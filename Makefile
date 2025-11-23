SHELL := /bin/bash

.PHONY: default all build run tests setup-scripts

default: build

all: build tests

build:
	./scripts/build.sh

run:
	@echo "Run the built artifact (if exists)"
	if [ -f build/dummy ]; then ./build/dummy; else echo "Artifact not found, run 'make build' first"; fi

tests:
	@echo "No unit tests yet. Add tests under tests/ and use ctest or pytest for execution."

setup-scripts:
	chmod +x scripts/*.sh || true
	@echo "Scripts made executable: scripts/*.sh"
