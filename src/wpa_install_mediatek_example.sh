#!/bin/sh
set -e

# On macOS: make firmware downloads the original list into gitignored local/.
if [ "${1:-}" = "--download" ]; then
    cd "$(dirname "$0")/.."
    umask 077
    firmware_dir="$(pwd -P)/local/firmware/mediatek"
    mkdir -p "$firmware_dir"
    base=https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek
    failed=0
    partial=
    trap 'if [ -n "$partial" ]; then rm -f "$partial"; fi' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    for name in \
        WIFI_RAM_CODE_MT7902_1.bin \
        WIFI_RAM_CODE_MT7961_1a.bin \
        WIFI_MT7961_patch_mcu_1_2_hdr.bin \
        WIFI_RAM_CODE_MT7922_1.bin \
        WIFI_MT7922_patch_mcu_1_1_hdr.bin
    do
        target="$firmware_dir/$name"
        if [ -s "$target" ]; then
            printf 'Keeping %s\n' "$name"
            continue
        fi
        partial=$(mktemp "$firmware_dir/.download.XXXXXX")
        if curl --fail --location --retry 3 "$base/$name" -o "$partial"; then
            # Some upstream servers return an HTML challenge instead of a blob.
            if LC_ALL=C head -c 512 "$partial" | grep -qiE '<!doctype html|<html'; then
                printf 'No firmware received for %s (upstream returned HTML).\n' "$name" >&2
                failed=1
            elif [ -s "$partial" ]; then
                mv "$partial" "$target"
                partial=
                continue
            else
                printf 'No firmware received for %s (empty download).\n' "$name" >&2
                failed=1
            fi
        else
            printf 'Could not download %s; existing blobs are untouched.\n' "$name" >&2
            failed=1
        fi
        rm -f "$partial"
        partial=
    done
    exit "$failed"
fi

# Inside the build container, after build.sh has recreated the initramfs.
apk add wpa_supplicant

ROOT="/build/initramfs"
echo "Installing libraries..."
cp /lib/ld-musl-x86_64.so.1 $ROOT/lib
cp /usr/lib/libnl-3.so.200 $ROOT/usr/lib/libnl-3.so.200
cp /usr/lib/libnl-genl-3.so.200 $ROOT/usr/lib/libnl-genl-3.so.200 
cp /usr/lib/libpcsclite.so.1 $ROOT/usr/lib/libpcsclite.so.1
cp /usr/lib/libssl.so.3 $ROOT/usr/lib/libssl.so.3
cp /usr/lib/libcrypto.so.3 $ROOT/usr/lib/libcrypto.so.3
cp /usr/lib/libdbus-1.so.3 $ROOT/usr/lib/libdbus-1.so.3
cp /lib/ld-musl-x86_64.so.1 $ROOT/lib/ld-musl-x86_64.so.1
cp /sbin/wpa_supplicant $ROOT/usr/bin/

echo "Adding saved firmware..."
mkdir -p "$ROOT/lib/firmware"
cp -R /private-inputs/firmware/. "$ROOT/lib/firmware/"
find "$ROOT/lib/firmware" -name '.DS_Store' -delete
