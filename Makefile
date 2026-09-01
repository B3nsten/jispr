APP_NAME   := Jispr
CONFIG     ?= release
BUILD_DIR  := build
APP        := $(BUILD_DIR)/$(APP_NAME).app
BIN        := .build/$(CONFIG)/$(APP_NAME)
CERT_NAME  := Jispr Local Signing
# Use the local self-signed certificate when it exists (see: make cert),
# otherwise sign ad-hoc. Override with SIGN_IDENTITY=... if you have a real one.
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q '"$(CERT_NAME)"' && echo "$(CERT_NAME)" || echo "-")

.PHONY: build bundle run install cert check clean

build:
	swift build -c $(CONFIG)

bundle: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BIN)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	printf "APPL????" > "$(APP)/Contents/PkgInfo"
	codesign --force --sign "$(SIGN_IDENTITY)" "$(APP)"
	@echo "Built $(APP) (signed with: $(SIGN_IDENTITY))"

run: bundle
	-pkill -x $(APP_NAME)
	@i=0; while pgrep -x $(APP_NAME) >/dev/null && [ $$i -lt 50 ]; do sleep 0.1; i=$$((i+1)); done
	open "$(APP)"

install: bundle
	-pkill -x $(APP_NAME)
	@i=0; while pgrep -x $(APP_NAME) >/dev/null && [ $$i -lt 50 ]; do sleep 0.1; i=$$((i+1)); done
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" /Applications/
	@echo "Installed /Applications/$(APP_NAME).app"

# Run the JisprCore checks.
check:
	swift run -c $(CONFIG) JisprCoreChecks

# One-time: create a local self-signed signing certificate.
cert:
	sh scripts/make-signing-cert.sh "$(CERT_NAME)"

clean:
	rm -rf .build "$(BUILD_DIR)"
