# graphq — common tasks.
#   make run     build the .app bundle and launch it
#   make app     build build/graphq.app (release)
#   make install build and copy graphq.app to /Applications (then open it from Launchpad/Spotlight)
#   make dmg     build build/graphq.dmg (drag-to-Applications installer)
#   make test    run unit tests
#   make clean

# With Command Line Tools only (no Xcode), swift-testing lives outside the default search paths.
CLT_FW := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
HAS_XCODE := $(shell xcode-select -p 2>/dev/null | grep -q Xcode.app && echo 1)
TESTFLAGS := $(if $(HAS_XCODE),,$(if $(wildcard $(CLT_FW)/Testing.framework),-Xswiftc -F$(CLT_FW) -Xlinker -F$(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_FW) -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays,))

.PHONY: run app install dmg debug test clean

run: app
	open build/graphq.app

app:
	./scripts/bundle.sh release

install: app
	rm -rf /Applications/graphq.app
	cp -R build/graphq.app /Applications/graphq.app
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/graphq.app
	@echo "Installed /Applications/graphq.app"

dmg: app
	rm -rf build/dmg build/graphq.dmg
	mkdir -p build/dmg
	cp -R build/graphq.app build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname graphq -srcfolder build/dmg -ov -format UDZO build/graphq.dmg
	rm -rf build/dmg
	@echo "Built build/graphq.dmg"

debug:
	./scripts/bundle.sh debug && open build/graphq.app

test:
	swift test $(TESTFLAGS)

clean:
	rm -rf .build build
