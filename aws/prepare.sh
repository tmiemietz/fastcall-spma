#!/bin/bash

set -euo pipefail

install_packages() {
	sudo apt-get update
	sudo apt-get --yes install \
		git make gcc flex bison libelf-dev libssl-dev bc python3 kmod cmake g++ \
		libboost-dev libboost-program-options1.74-dev
}

clone() {
	git init fastcall-spma
	cd fastcall-spma
	git remote add origin 'https://github.com/tmiemietz/fastcall-spma'
	git fetch origin "$GIT_CHECKOUT"
	git checkout FETCH_HEAD
	cd - >/dev/null
}

install_packages
clone
