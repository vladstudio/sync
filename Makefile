APP_NAME = Sync
BUILD_DIR = .build
APP_BUNDLE = build/$(APP_NAME).app
BINARY = $(BUILD_DIR)/release/$(APP_NAME)

build:
	swift build -c release

package: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BINARY) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	cp Resources/MenuBarIcon.png $(APP_BUNDLE)/Contents/Resources/
	cp "Resources/MenuBarIcon@2x.png" $(APP_BUNDLE)/Contents/Resources/
	for bundle in $(BUILD_DIR)/release/*.bundle; do \
		[ -e "$$bundle" ] || continue; \
		cp -R "$$bundle" $(APP_BUNDLE)/Contents/Resources/; \
	done

install: package
	cp -r $(APP_BUNDLE) /Applications/

clean:
	swift package clean
	rm -rf build/

.PHONY: build package install clean
