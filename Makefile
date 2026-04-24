.PHONY: build install run clean

build:
	swift build -c release

install: build
	cp .build/release/Waxpad /usr/local/bin/waxpad

run:
	swift run

clean:
	swift package clean
