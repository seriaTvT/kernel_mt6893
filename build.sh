#!/bin/bash
#
# Compile script for Hydrogen kernel
# Brought to you by rio004
#

set -e

# Date/Time
SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')

# Device
DEVICE="${1:-agate}"
DEFCONFIG="${DEVICE}_defconfig"
ZIPNAME="HydrogenKernel-${DEVICE}-${DATE}.zip"

echo -e "Building for: $DEVICE\n"

# Both build variants share the output directory.
exec 9> .build.lock
flock 9

# Ensure the toolchain is available
TC_DIR="$HOME/toolchains/proton-clang"
CURRENT_DIR=$(pwd)
if [ ! -d "$TC_DIR" ]; then
    mkdir -p "$HOME/toolchains"
    cd "$HOME/toolchains"
    git clone --depth=1 https://gitlab.com/LeCmnGend/proton-clang.git -b clang-15 proton-clang
    cd "$CURRENT_DIR"
fi
export PATH="$TC_DIR/bin:$PATH"

# Process options
CLEAN_BUILD=false
INCLUDE_KSU=false
for arg in "$@"; do
    case $arg in
        -c) CLEAN_BUILD=true ;;
        -ksu) INCLUDE_KSU=true
             ZIPNAME="HydrogenKernel-KSU-${DEVICE}-${DATE}.zip"
             ;;
    esac
done

if [ "$CLEAN_BUILD" = true ]; then
    rm -rf out
fi
unset KBUILD_KSU
if [ "$INCLUDE_KSU" = true ]; then
    # BAKASU_REF can select a specific branch, tag, or commit instead of main.
    sh scripts/prepare-bakasu.sh
    export KBUILD_KSU=1
fi

# Compilation process
mkdir -p out
make O=out ARCH=arm64 "$DEFCONFIG"
if [ "$INCLUDE_KSU" = true ]; then
    if [ "$DEVICE" = chopin ]; then
        scripts/config --file out/.config -e KALLSYMS -e KALLSYMS_ALL \
            -e KSU -d KSU_MANUAL_HOOK -e KSU_SUSFS \
            -e KSU_SUSFS_PRIORITY_UID_FILTER
    else
        scripts/config --file out/.config -e KALLSYMS -e KALLSYMS_ALL \
            -e KSU -e KSU_MANUAL_HOOK -d KSU_SUSFS
    fi
    make O=out ARCH=arm64 olddefconfig

    required_config='CONFIG_KSU=y'
    if [ "$DEVICE" = chopin ]; then
        required_config="$required_config
# CONFIG_KSU_MANUAL_HOOK is not set
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER=y"
    else
        required_config="$required_config
CONFIG_KSU_MANUAL_HOOK=y
# CONFIG_KSU_SUSFS is not set"
    fi
    while IFS= read -r setting; do
        if ! grep -Fxq -- "$setting" out/.config; then
            printf 'Missing required kernel configuration: %s\n' "$setting" >&2
            exit 1
        fi
    done <<< "$required_config"
fi

echo -e "\nStarting compilation...\n"
if make -j$(nproc --all) O=out ARCH=arm64 CC="ccache clang" LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- Image.gz; then
    echo -e "\nKernel compiled successfully! Zipping up...\n"
    git clone -q --depth=1 https://github.com/rio004/AnyKernel3 AnyKernel3
    cp out/arch/arm64/boot/Image.gz AnyKernel3
    rm -rf *zip out/arch/arm64/boot
    (cd AnyKernel3 && zip -r9 "../$ZIPNAME" * -x '*.git*' README.md *placeholder)
    rm -rf AnyKernel3
    echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!"
    echo "Zip: $ZIPNAME"
else
    echo -e "\nCompilation failed!" >&2
    exit 1
fi
