#!/usr/bin/env bash

for d in ./test/target/*/; do
	cp ./hooks/* "${d}/.git/hooks/"
done
