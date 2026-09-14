APP_NAME = AeroControl
BUILD_DIR = .build/release
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR = /Applications

# Command Line Tools 27 ship a macOS 27 SDK in which SwiftUI's @State is a macro whose
# plugin only comes with Xcode. Build against the bundled macOS 26 SDK when it exists
# (Package.swift targets macOS 26 anyway). Override with SDKROOT=... if needed.
SDK26 := /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
ifneq ($(wildcard $(SDK26)),)
export SDKROOT ?= $(SDK26)
endif

.PHONY: build bundle install run clean test release

run:
	swift build --product AeroControl && swift run AeroControl $(ARGS)

build:
	swift build -c release --product AeroControl

# Sign with a stable identity when one exists: macOS ties privacy grants (Screen
# Recording for previews) to the code signature, and an ad-hoc signature changes with
# every build, which silently revokes the grant. Create it once (self-signed, no
# trust needed): see README "Build from source". Falls back to ad-hoc.
SIGN_IDENTITY ?= $(shell security find-identity -p codesigning 2>/dev/null | grep -q '"AeroControl Dev"' && echo "AeroControl Dev" || echo "-")

# Assemble a proper .app bundle (accessory agent, LSUIElement) around the release
# binary, with a stable bundle identifier, then codesign it (see SIGN_IDENTITY).
bundle: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Packaging/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --sign "$(SIGN_IDENTITY)" "$(APP_BUNDLE)"
	@echo "Signed with identity: $(SIGN_IDENTITY)"
	@echo "Built $(APP_BUNDLE)"

# Build the bundle and install it to /Applications.
install: bundle
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed $(INSTALL_DIR)/$(APP_NAME).app"

clean:
	swift package clean
	rm -rf .build

# Build a versioned, distributable release + Homebrew cask into .release/.
# Usage: make release VERSION=0.1.0-Beta   (add PUBLISH=1 to cut the GitHub Release)
release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=x.y.z[-Beta] [PUBLISH=1]"; exit 2; }
	script/release.sh "$(VERSION)" $(if $(PUBLISH),--publish,)

# Swift Testing's macro plugin must be pointed at explicitly when building against a
# different SDK than the toolchain's own (see SDKROOT above).
TESTING_PLUGINS := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
test:
	swift test $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS),)

