APP_NAME = ClaudeDash
BUILD_DIR = $(shell xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')
INSTALL_DIR = /Applications

.PHONY: build install run clean

build:
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Release build

install: build
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@sleep 0.5
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(BUILD_DIR)/$(APP_NAME).app" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"
	@open "$(INSTALL_DIR)/$(APP_NAME).app"

run: build
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@sleep 0.5
	@open "$(BUILD_DIR)/$(APP_NAME).app"

clean:
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) clean
