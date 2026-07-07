# xcode-select on this machine points at Command Line Tools; xcodebuild needs full Xcode
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

ARCH := $(shell uname -m)
DEST := platform=macOS,arch=$(ARCH)

.PHONY: gen build unit ui test

gen:
	xcodegen generate

build:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData build

unit:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData -only-testing:TackTests test

ui:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData -only-testing:TackUITests -parallel-testing-enabled NO -resultBundlePath .build/results/ui-$$(date +%s).xcresult test

test: unit ui
