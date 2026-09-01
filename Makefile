APP_NAME   := Jispr
CONFIG     ?= release
BUILD_DIR  := build
APP        := $(BUILD_DIR)/$(APP_NAME).app
BIN        := .build/$(CONFIG)/$(APP_NAME)
# Ad-hoc signing by default. Set SIGN_IDENTITY to a real certificate to keep
# Accessibility permission across rebuilds.
SIGN_IDENTITY ?= -

.PHONY: build bundle run install clean

build:
	swift build -c $(CONFIG)

bundle: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BIN)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	printf "APPL????" > "$(APP)/Contents/PkgInfo"
	codesign --force --sign "$(SIGN_IDENTITY)" "$(APP)"
	@echo "Built $(APP)"

run: bundle
	-pkill -x $(APP_NAME)
	open "$(APP)"

install: bundle
	-pkill -x $(APP_NAME)
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" /Applications/
	@echo "Installed /Applications/$(APP_NAME).app"

clean:
	rm -rf .build "$(BUILD_DIR)"
