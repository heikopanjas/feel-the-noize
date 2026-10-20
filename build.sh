#!/bin/bash
# Feel the Noize build entry point. Agents: use this instead of hand-rolled xcodebuild calls.
# Usage: ./build.sh [command ...], see usage below. Runs `build` without a command.
set -euo pipefail

cd "$(dirname "$0")"

SCHEME=FeelTheNoize
# Build products land in .build/Products/<Configuration>, verified by inspecting where `build` writes the app.
APP_NAME="Feel the Noize"
APP_DEBUG=".build/Products/Debug/$APP_NAME.app"
APP_RELEASE=".build/Products/Release/$APP_NAME.app"
DIST=build/dist
VERSION=$(awk -F'"' '/MARKETING_VERSION/ { print $2 }' project.yml)
ZIP="$DIST/FeelTheNoize-$VERSION.zip"

# Release-only signing, passed on the command line; project.yml keeps automatic development signing.
TEAM_ID=${TEAM_ID:-8J2G689FCZ}
DEVELOPER_ID=${DEVELOPER_ID:-"Developer ID Application: Heiko Panjas ($TEAM_ID)"}
# Create once with: xcrun notarytool store-credentials feelthenoize-notary --apple-id <id> --team-id 8J2G689FCZ
NOTARY_PROFILE=${NOTARY_PROFILE:-feelthenoize-notary}

usage() {
    cat <<EOF
Usage: ./build.sh [command ...]

  gen        generate the Xcode project with XcodeGen
  build      gen, then Debug build (default)
  run        build, then launch the Debug app
  test       gen, then run the unit tests
  format     swift-format in place
  lint       swift-format lint --strict
  diagrams   render docs/diagrams/*.puml to SVG
  icon       re-render the app icon
  release    test, then Developer ID signed build zipped to $ZIP
  notarize   submit $ZIP, staple, Gatekeeper check, re-zip
  clean      remove build and .build

Environment overrides: TEAM_ID, DEVELOPER_ID, NOTARY_PROFILE.
EOF
}

xcb() {
    xcodebuild -scheme "$SCHEME" -destination 'platform=macOS' "$@" | xcbeautify
}

zip_app() {
    mkdir -p "$DIST"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP_RELEASE" "$ZIP"
}

cmd_gen() {
    xcodegen generate --quiet
}

cmd_build() {
    cmd_gen
    xcb -configuration Debug build
}

cmd_run() {
    cmd_build
    open "$APP_DEBUG"
}

cmd_test() {
    cmd_gen
    xcb test
}

cmd_format() {
    xcrun swift-format format --in-place --recursive Sources Tests
}

cmd_lint() {
    xcrun swift-format lint --strict --recursive Sources Tests
}

cmd_diagrams() {
    plantuml -tsvg docs/diagrams/*.puml
}

cmd_icon() {
    swift scripts/render-icon.swift Sources/FeelTheNoize/Resources/Assets.xcassets/AppIcon.appiconset
}

# Developer ID signed, hardened, secure timestamp, no get-task-allow. Produces $ZIP, ready for `notarize`.
cmd_release() {
    cmd_test
    xcb -configuration Release \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        OTHER_CODE_SIGN_FLAGS="--timestamp" \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
        clean build
    codesign --verify --strict --deep --verbose=2 "$APP_RELEASE"
    # Notarization rejects the debugging entitlement Xcode injects into plain builds.
    if codesign -d --entitlements - "$APP_RELEASE" 2>/dev/null | grep -q get-task-allow; then
        echo "get-task-allow entitlement present, notarization would fail" >&2
        exit 1
    fi
    zip_app
}

# Uploads to Apple's notary service, staples the ticket, and re-zips the stapled app.
cmd_notarize() {
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_RELEASE"
    spctl --assess --type execute --verbose=2 "$APP_RELEASE"
    zip_app
}

cmd_clean() {
    rm -rf build .build
}

if [ $# -eq 0 ]; then
    set -- build
fi

# Validate every command first, so a typo in the second one does not surface after a long first one.
for command in "$@"; do
    case "$command" in
        gen | build | run | test | format | lint | diagrams | icon | release | notarize | clean) ;;
        help | -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown command: $command" >&2
            usage >&2
            exit 2
            ;;
    esac
done

for command in "$@"; do
    "cmd_$command"
done
