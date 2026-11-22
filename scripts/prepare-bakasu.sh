#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
set -eu

cd "$(dirname "$0")/.."
patch="$PWD/patches/bakasu-susfs-v2.4.0.patch"
git submodule update --init -- KernelSU

if git -C KernelSU apply --reverse --check "$patch" 2>/dev/null; then
	exit 0
fi

git -C KernelSU apply --check "$patch"
git -C KernelSU apply "$patch"
