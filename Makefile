# Omnomnom: every command a contributor, an agent and CI run. The targets follow the build
# contract the j23n apps share (j23n/apple-ci); .apple-ci/apple.mk is a copy of its rules
# (`make update-apple-ci` refreshes it).

SHELL := /bin/bash
PYTHON ?= python3

PROJECT_SPEC := project.yml
XCODEPROJ := Omnomnom.xcodeproj
SCHEME := Omnomnom
PLATFORMS := ios

include .apple-ci/apple.mk

.PHONY: help bootstrap test test-fooddb fooddb ci-linux ci-macos clean

help:
	@echo "make bootstrap   XcodeGen and the Xcode project (then make fooddb, once you have the sources)"
	@echo "make test        the food database pipeline's tests (macOS and Linux)"
	@echo "make build       the app for the iOS Simulator, unsigned"
	@echo "make test-app    the app's tests in the iOS Simulator"
	@echo "make fooddb ARGS='--ciqual … --bls …'   builds Omnomnom/Resources/foods.sqlite (Tools/fooddb/README.md)"
	@echo "make ci-linux | ci-macos   what CI runs"

bootstrap: tools project

test: test-fooddb

test-fooddb:
	cd Tools/fooddb && $(PYTHON) -m unittest

# The bundled database, from the sources Tools/fooddb/README.md lists; not in git.
fooddb:
	cd Tools/fooddb && $(PYTHON) -m fooddb build $(ARGS)

ci-linux: test

ci-macos: test build test-app

clean:
	rm -rf $(XCODEPROJ) .build
