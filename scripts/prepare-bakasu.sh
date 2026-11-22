#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
set -eu

cd "$(dirname "$0")/.."
state="$PWD/.bakasu"
cache="$state/upstream.git"
patch="$PWD/patches/bakasu-susfs-v2.4.0.patch"
ref=${BAKASU_REF:-refs/heads/main}
upstream=https://github.com/Baka-SU/BakaSU.git

# BakaSU Kbuild derives its version from Git history and tags.
if [ ! -d "$cache/objects" ]; then
	git init --bare --quiet "$cache"
fi
if ! git --git-dir="$cache" fetch --force --tags -- "$upstream" "$ref"; then
	echo "Failed to fetch BakaSU ref $ref" >&2
	exit 1
fi
commit=$(git --git-dir="$cache" rev-parse --verify 'FETCH_HEAD^{commit}')
printf 'BakaSU %s resolved to %s\n' "$ref" "$commit"

candidate=$(mktemp -d "$state/source.XXXXXXXX")
cleanup()
{
	if [ "$(readlink "$state/KernelSU" || true)" != "${candidate##*/}" ]; then
		git --git-dir="$cache" worktree remove --force "$candidate" 2>/dev/null || rmdir "$candidate"
	fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

git --git-dir="$cache" worktree add --quiet --detach "$candidate" "$commit"
if git -C "$candidate" apply --reverse --check "$patch" 2>/dev/null; then
	echo "BakaSU already contains the SUSFS compatibility patch"
elif git -C "$candidate" apply --check "$patch"; then
	git -C "$candidate" apply "$patch"
else
	echo "BakaSU $commit is incompatible with the SUSFS patch. Update the patch or set BAKASU_REF to a compatible commit." >&2
	exit 1
fi

# Publish only a checkout that passed the compatibility check.
previous=$(readlink "$state/KernelSU" || true)
ln -s "${candidate##*/}" "$candidate/checkout-link"
mv -Tf "$candidate/checkout-link" "$state/KernelSU"
case "$previous" in
	source.*) git --git-dir="$cache" worktree remove --force "$state/$previous" ;;
esac
