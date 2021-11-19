.PHONY: test clean clean_test

test:
	./test/test.sh

all: test

clean_test:
	rm -rf test/target/*

clean: clean_test
