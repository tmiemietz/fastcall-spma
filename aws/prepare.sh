#!/bin/bash

# Prepare the instance by installing packages and cloning this repository.

set -euo pipefail

# Install the required packages. Designed for Debian Bullseye.
install_packages() {
	sudo apt-get update
	sudo apt-get install --yes \
		git make gcc flex bison libelf-dev libssl-dev bc python3 kmod lz4 cmake \
		g++ libboost-dev libboost-program-options1.74-dev
}

# Clone this repository at the specified commit/branch.
clone() {
	git init fastcall-spma
	cd fastcall-spma
	git remote add origin 'https://github.com/tmiemietz/fastcall-spma'
	git fetch origin "$GIT_CHECKOUT"
	git checkout FETCH_HEAD
	git config user.name fastcall
	git config user.email fastcall@example.com
	cd - >/dev/null
}

install_packages
clone
