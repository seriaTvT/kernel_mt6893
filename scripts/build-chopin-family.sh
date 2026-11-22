#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
set -euo pipefail

if [[ $# != 3 ]]; then
    printf 'Usage: %s {chopin|ares} {stock|bakasu|susfs} OUTPUT_DIR\n' "$0" >&2
    exit 2
fi

device=$1
mode=$2
output=$(realpath -m "$3")
case "$device" in
    chopin|ares) ;;
    *) printf 'Unsupported device: %s\n' "$device" >&2; exit 2 ;;
esac
case "$mode" in
    stock|bakasu|susfs) ;;
    *) printf 'Unsupported build mode: %s\n' "$mode" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."
# Opt-in builds share the BakaSU checkout under .bakasu.
exec 9> .build.lock
flock 9

unset KBUILD_KSU
bakasu_commit=none
if [[ "$mode" != stock ]]; then
    sh scripts/prepare-bakasu.sh
    export KBUILD_KSU=1
    bakasu_commit=$(git -C drivers/kernelsu rev-parse HEAD)
fi

mkdir -p "$output"
kmake=(make O="$output" ARCH=arm64 CC=clang LD=ld.lld
       CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-android-
       CROSS_COMPILE_ARM32=arm-linux-androideabi- CROSS_COMPILE_COMPAT=arm-linux-androideabi-)
"${kmake[@]}" "${device}_defconfig"
if [[ "$mode" == stock ]]; then
    if grep -Eq '^CONFIG_KSU(_[A-Z0-9_]+)?=[ym]$' "$output/.config"; then
        printf 'Stock config unexpectedly enables BakaSU\n' >&2
        exit 1
    fi
else
    bash scripts/configure-bakasu.sh "$output/.config" "$mode" "${kmake[@]}"
fi

jobs=${BUILD_JOBS:-$(nproc)}
# Generate SELinux and init headers before compiling the rest of the tree.
"${kmake[@]}" -j"$jobs" security/selinux/ init/
"${kmake[@]}" -j"$jobs" Image.gz-dtb
test -s "$output/arch/arm64/boot/Image.gz-dtb"
printf 'device=%s\nmode=%s\nkernel_commit=%s\nbakasu_commit=%s\n' \
    "$device" "$mode" "$(git rev-parse HEAD)" "$bakasu_commit" > "$output/build-info.txt"
