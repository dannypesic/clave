#!/bin/sh

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

echo "Ensuring firmware..."
if [ ! -f "/build/initramfs/lib/firmware/mediatek/WIFI_RAM_CODE_MT7902_1.bin" ]; then
    wget -P /build/initramfs/lib/firmware/mediatek/ https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/WIFI_RAM_CODE_MT7902_1.bin
fi

if [ ! -f "/build/initramfs/lib/firmware/mediatek/WIFI_RAM_CODE_MT7961_1a.bin" ]; then
    wget -P /build/initramfs/lib/firmware/mediatek/ https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/WIFI_RAM_CODE_MT7961_1a.bin
fi

if [ ! -f "/build/initramfs/lib/firmware/mediatek/WIFI_MT7961_patch_mcu_1_2_hdr.bin" ]; then
    wget -P /build/initramfs/lib/firmware/mediatek/ https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/WIFI_MT7961_patch_mcu_1_2_hdr.bin
fi

if [ ! -f "/build/initramfs/lib/firmware/mediatek/WIFI_RAM_CODE_MT7922_1.bin" ]; then
    mkdir -p /build/initramfs/lib/firmware/mediatek
    wget -P /build/initramfs/lib/firmware/mediatek/ https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/WIFI_RAM_CODE_MT7922_1.bin
fi

if [ ! -f "/build/initramfs/lib/firmware/mediatek/WIFI_MT7922_patch_mcu_1_1_hdr.bin" ]; then
    wget -P /build/initramfs/lib/firmware/mediatek/ https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/WIFI_MT7922_patch_mcu_1_1_hdr.bin
fi

echo "WiFi functionality succesfuly installed."