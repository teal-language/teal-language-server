
.PHONY: build
build: teal-types
	cyan check src/*.tl
	cyan build

teal-types:
	git clone https://github.com/teal-language/teal-types
