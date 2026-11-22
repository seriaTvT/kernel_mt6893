#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
set -euo pipefail

config=$1
mode=$2
shift 2

case "$mode" in
    bakasu)
        options=(-e KSU_MANUAL_HOOK -d KSU_SUSFS)
        required=('CONFIG_KSU_MANUAL_HOOK=y' '# CONFIG_KSU_SUSFS is not set')
        ;;
    susfs)
        options=(-d KSU_MANUAL_HOOK -e KSU_SUSFS -e KSU_SUSFS_PRIORITY_UID_FILTER)
        required=('# CONFIG_KSU_MANUAL_HOOK is not set' 'CONFIG_KSU_SUSFS=y'
                  'CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER=y')
        ;;
    *)
        printf 'Unsupported BakaSU build mode: %s\n' "$mode" >&2
        exit 2
        ;;
esac

scripts/config --file "$config" -e KALLSYMS -e KALLSYMS_ALL -e KSU "${options[@]}"
"$@" olddefconfig

for setting in CONFIG_KALLSYMS=y CONFIG_KALLSYMS_ALL=y CONFIG_KSU=y "${required[@]}"; do
    if ! grep -Fxq -- "$setting" "$config"; then
        printf 'Missing required kernel configuration: %s\n' "$setting" >&2
        exit 1
    fi
done
