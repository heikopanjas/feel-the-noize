# Manopola build entry points. Agents: use these instead of hand-rolled xcodebuild calls.
SHELL := /bin/bash

SCHEME := Manopola
# Build products land in .build/Products/<Configuration>, verified by inspecting where `build` writes Manopola.app.
APP_DEBUG   := .build/Products/Debug/Manopola.app
APP_RELEASE := .build/Products/Release/Manopola.app
DIST    := build/dist
VERSION := $(shell awk -F'"' '/MARKETING_VERSION/ { print $$2 }' project.yml)
ZIP     := $(DIST)/Manopola-$(VERSION).zip

# Release-only signing, passed on the command line; project.yml keeps automatic development signing.
TEAM_ID        ?= 8J2G689FCZ
DEVELOPER_ID   ?= Developer ID Application: Heiko Panjas ($(TEAM_ID))
# Create once with: xcrun notarytool store-credentials manopola-notary --apple-id <id> --team-id 8J2G689FCZ
NOTARY_PROFILE ?= manopola-notary

XCB := xcodebuild -scheme $(SCHEME) -destination 'platform=macOS'

.PHONY: all gen build run test format lint diagrams icon release notarize clean

all: build

gen:
	xcodegen generate --quiet

build: gen
	set -o pipefail && $(XCB) -configuration Debug build | xcbeautify

run: build
	open $(APP_DEBUG)

test: gen
	set -o pipefail && $(XCB) test | xcbeautify

format:
	xcrun swift-format format --in-place --recursive Sources Tests

lint:
	xcrun swift-format lint --strict --recursive Sources Tests

diagrams:
	plantuml -tsvg docs/diagrams/*.puml

icon:
	swift scripts/render-icon.swift Sources/Manopola/Resources/Assets.xcassets/AppIcon.appiconset

# Developer ID signed, hardened, secure timestamp, no get-task-allow. Produces $(ZIP), ready for `make notarize`.
release: test
	set -o pipefail && $(XCB) -configuration Release \
	  CODE_SIGN_STYLE=Manual \
	  CODE_SIGN_IDENTITY="$(DEVELOPER_ID)" \
	  DEVELOPMENT_TEAM=$(TEAM_ID) \
	  OTHER_CODE_SIGN_FLAGS="--timestamp" \
	  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
	  clean build | xcbeautify
	codesign --verify --strict --deep --verbose=2 $(APP_RELEASE)
	@# Notarization rejects the debugging entitlement Xcode injects into plain builds.
	@! codesign -d --entitlements - $(APP_RELEASE) 2>/dev/null | grep -q get-task-allow || \
	  (echo "get-task-allow entitlement present, notarization would fail"; exit 1)
	mkdir -p $(DIST)
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP_RELEASE) $(ZIP)

# Uploads to Apple's notary service, staples the ticket, and re-zips the stapled app.
notarize:
	xcrun notarytool submit $(ZIP) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(APP_RELEASE)
	spctl --assess --type execute --verbose=2 $(APP_RELEASE)
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP_RELEASE) $(ZIP)

clean:
	rm -rf build .build
