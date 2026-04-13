APP_NAME   = ClaudeUsage
BUILD_DIR  = .build/release
APP_BUNDLE = build/$(APP_NAME).app

.PHONY: build install run clean

build:
	swift build -c release 2>&1
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	cp "Resources/Info.plist"       "$(APP_BUNDLE)/Contents/"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "Resources/AppIcon.icns"     "$(APP_BUNDLE)/Contents/Resources/"
	find "$(APP_BUNDLE)" -name "._*" -delete
	xattr -rc "$(APP_BUNDLE)"
	codesign --force --deep -s "Apple Development" "$(APP_BUNDLE)" 2>/dev/null || codesign --force --deep -s - "$(APP_BUNDLE)"
	@echo "✓ Built: $(APP_BUNDLE)"

run: build
	@pkill -x $(APP_NAME) 2>/dev/null || true
	open "$(APP_BUNDLE)"

install: build
	@pkill -x $(APP_NAME) 2>/dev/null || true
	cp -rf "$(APP_BUNDLE)" /Applications/
	@defaults write com.pua2.claudeusage repoPath "$$(pwd)"
	open /Applications/$(APP_NAME).app
	@echo "✓ Installed to /Applications/$(APP_NAME).app"

clean:
	rm -rf build .build
