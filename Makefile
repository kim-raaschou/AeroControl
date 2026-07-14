APP_NAME = AeroControl
BUILD_DIR = .build/release
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR = /Applications

.PHONY: build bundle install run clean test release

run:
	swift build --product AeroControl && swift run AeroControl $(ARGS)

build:
	swift build -c release --product AeroControl

# Assemble a proper .app bundle (accessory agent, LSUIElement) around the release
# binary, with a stable bundle identifier so the Accessibility grant sticks, then
# ad-hoc codesign it.
bundle: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Packaging/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --sign - "$(APP_BUNDLE)"
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

test:
	swift test

