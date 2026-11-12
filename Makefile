APP := build/Linkhop.app
DEST := /Applications/Linkhop.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: build bundle install default icon clean

# Regenerate Resources/AppIcon.icns from scripts/make-icon.swift.
icon:
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/Linkhop $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	codesign --force --sign - $(APP)

# Build, install to /Applications, register with LaunchServices, and (re)start.
install: bundle
	-pkill -x Linkhop
	rm -rf $(DEST)
	cp -R $(APP) $(DEST)
	touch $(DEST)
	$(LSREGISTER) -f $(DEST)
	open $(DEST)

# Ask macOS to make Linkhop the default browser (shows a system confirmation dialog).
default:
	-pkill -x Linkhop
	open $(DEST) --args --make-default

clean:
	rm -rf .build build
