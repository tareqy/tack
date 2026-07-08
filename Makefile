# xcode-select on this machine points at Command Line Tools; xcodebuild needs full Xcode
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

ARCH := $(shell uname -m)
DEST := platform=macOS,arch=$(ARCH)

.PHONY: gen build unit ui test build-tests unit-nobuild ui-nobuild

gen:
	xcodegen generate

build:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData build

unit:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData -only-testing:TackTests test

ui:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData -only-testing:TackUITests -parallel-testing-enabled NO -resultBundlePath .build/results/ui-$$(date +%s).xcresult test

test: unit ui

# Compile app + both test bundles ONCE; then iterate with the *-nobuild targets below.
# After ANY source change (app or tests), run build-tests again — test-without-building
# runs whatever was last compiled.
build-tests:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData build-for-testing

unit-nobuild:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData -only-testing:TackTests test-without-building

ui-nobuild:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData -only-testing:TackUITests -parallel-testing-enabled NO -resultBundlePath .build/results/ui-$$(date +%s).xcresult test-without-building
