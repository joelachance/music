APP_NAME := MiniSpotify
APP_DIR := .build/$(APP_NAME).app
EXECUTABLE := .build/release/$(APP_NAME)

.PHONY: build bundle run run-track run-track-paused test spotify-check stop clean

build:
	swift build -c release

bundle: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	cp "$(EXECUTABLE)" "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	printf "APPL????" > "$(APP_DIR)/Contents/PkgInfo"
	codesign --force --sign - "$(APP_DIR)" >/dev/null 2>&1 || true

run: bundle
	open "$(APP_DIR)"

run-track: bundle
	@test -n "$(TRACK_URI)" || (echo 'Usage: make run-track TRACK_URI=spotify:track:2IClzYyvgwrsmVVipYsx5T' && exit 1)
	open -n "$(APP_DIR)" --args --track-uri "$(TRACK_URI)" $(if $(CONTEXT_URI),--context-uri "$(CONTEXT_URI)",)

run-track-paused: bundle
	@test -n "$(TRACK_URI)" || (echo 'Usage: make run-track-paused TRACK_URI=spotify:track:2IClzYyvgwrsmVVipYsx5T' && exit 1)
	open -n "$(APP_DIR)" --args --track-uri "$(TRACK_URI)" --start-paused $(if $(CONTEXT_URI),--context-uri "$(CONTEXT_URI)",)

test:
	swift run MiniSpotifyChecks

spotify-check:
	osascript scripts/spotify-check.applescript

stop:
	pkill -x "$(APP_NAME)" 2>/dev/null || true

clean:
	rm -rf .build
