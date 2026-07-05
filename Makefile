ARCH := $(shell uname -m)
DEST := platform=macOS,arch=$(ARCH)

.PHONY: gen build unit ui test

gen:
	xcodegen generate

build:
	xcodebuild -project Kanban.xcodeproj -scheme Kanban -destination '$(DEST)' -derivedDataPath .build/DerivedData build

unit:
	xcodebuild -project Kanban.xcodeproj -scheme Kanban -destination '$(DEST)' -derivedDataPath .build/DerivedData -only-testing:KanbanTests test

ui:
	xcodebuild -project Kanban.xcodeproj -scheme Kanban -destination '$(DEST)' -derivedDataPath .build/DerivedData -only-testing:KanbanUITests -parallel-testing-enabled NO -resultBundlePath .build/results/ui-$$(date +%s).xcresult test

test: unit ui
