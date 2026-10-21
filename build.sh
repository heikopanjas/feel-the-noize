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
DIST=.build/dist
VERSION=$(awk -F'"' '/MARKETING_VERSION/ { print $2 }' project.yml)
ZIP="$DIST/FeelTheNoize-$VERSION.zip"

# Release-only signing, passed on the command line; project.yml keeps automatic development signing.
TEAM_ID=${TEAM_ID:-8J2G689FCZ}
DEVELOPER_ID=${DEVELOPER_ID:-"Developer ID Application: Heiko Panjas ($TEAM_ID)"}
# Shared by all Developer ID apps of the team. Create once with an App Store Connect API key:
# xcrun notarytool store-credentials developer-id-notary --key AuthKey_<id>.p8 --key-id <id> --issuer <uuid>
NOTARY_PROFILE=${NOTARY_PROFILE:-developer-id-notary}

usage() {
    cat <<EOF
Usage: ./build.sh [command ...]

  gen        generate the Xcode project with XcodeGen
  build      gen, then Debug build (default)
  run        build, then launch the Debug app
  test       gen, then run the unit tests
  format     swift-format in place
  lint       swift-format lint --strict
  diagrams   render Docs/diagrams/*.puml to SVG
  icon       re-render the app icon
  release    test, then Developer ID signed build zipped to $ZIP
  notarize   submit $ZIP, staple, Gatekeeper check, re-zip
  clean      remove .build

Environment overrides: TEAM_ID, DEVELOPER_ID, NOTARY_PROFILE.
EOF
}

xcb() {
    xcodebuild -scheme "$SCHEME" -destination 'platform=macOS' "$@" | xcbeautify
}

# Zips the given app to $ZIP.
zip_app() {
    mkdir -p "$DIST"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$1" "$ZIP"
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
    plantuml -tsvg Docs/diagrams/*.puml
}

cmd_icon() {
    swift Scripts/render-icon.swift Sources/FeelTheNoize/Resources/Assets.xcassets/AppIcon.appiconset
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
    zip_app "$APP_RELEASE"
}

# Uploads $ZIP to Apple's notary service, staples the ticket to the app inside it, and re-zips the stapled app.
# Staples a copy unpacked from the zip, not $APP_RELEASE: the ticket belongs to the submitted build, and the
# release app may have been moved or rebuilt since `release`.
cmd_notarize() {
    if [ ! -f "$ZIP" ]; then
        echo "$ZIP not found, run ./build.sh release first" >&2
        exit 1
    fi
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    STAGING=$(mktemp -d)
    trap 'rm -rf "$STAGING"' EXIT
    ditto -x -k "$ZIP" "$STAGING"
    local app="$STAGING/$APP_NAME.app"
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
    codesign --verify --strict --deep --verbose=2 "$app"
    zip_app "$app"
}

cmd_clean() {
    rm -rf .build
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
