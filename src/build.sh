#!/bin/sh
set -e

# /build is internal to the container to avoid Mac filesystem limitations (case-sensitivity, mknod)
SRC_INITRAMFS=/build/initramfs
INITRAMFS_CPIO=/kernel/initramfs.cpio
KERNEL_SRC=/kernel/linux-6.18.22
ISO_DIR=/build/iso
ESP_IMG=/build/esp.img
ISO_OUT=/build/clave.iso
FINAL_ISO=/clave/clave.iso

echo "Cleaning stale build artifacts..."
rm -f "$INITRAMFS_CPIO"
rm -f "$KERNEL_SRC/usr/initramfs_inc_data"
rm -f "$SRC_INITRAMFS/sbin/init" "$SRC_INITRAMFS/init"
rm -f "$SRC_INITRAMFS/sbin/sysinit"
rm -f "$SRC_INITRAMFS/etc/passwd" "$SRC_INITRAMFS/etc/group"
find "$SRC_INITRAMFS" -name '.DS_Store' -delete
find "$SRC_INITRAMFS" -name '.ash_history' -delete

echo "Ensuring initramfs directories..."
mkdir -p "$SRC_INITRAMFS"/dev
mknod "$SRC_INITRAMFS/dev/console" c 5 1 2>/dev/null || true
mknod "$SRC_INITRAMFS/dev/null"    c 1 3 2>/dev/null || true
mknod "$SRC_INITRAMFS/dev/urandom" c 1 9 2>/dev/null || true
chmod 600 "$SRC_INITRAMFS/dev/console" 2>/dev/null || true
chmod 666 "$SRC_INITRAMFS/dev/null"    2>/dev/null || true
chmod 666 "$SRC_INITRAMFS/dev/urandom" 2>/dev/null || true
mkdir -p "$SRC_INITRAMFS"/tmp
mkdir -p "$SRC_INITRAMFS"/bin
mkdir -p "$SRC_INITRAMFS"/sbin
mkdir -p "$SRC_INITRAMFS"/etc
mkdir -p "$SRC_INITRAMFS"/var/run/wpa_supplicant
mkdir -p "$SRC_INITRAMFS"/home
mkdir -p "$SRC_INITRAMFS"/home/pkgar

echo "Injecting environment..."
if [ ! -f /build/.env ]; then
  echo "FATAL: /build/.env not found. Copy src/.env.example to /build/.env and fill it in."
  exit 1
fi
. /build/.env
sed "s|__DISK__|${DISK:-}|g" "/clave/src/sysinit.template" > "$SRC_INITRAMFS/sbin/sysinit"
chmod +x "$SRC_INITRAMFS/sbin/sysinit"

if [ ! -f "$SRC_INITRAMFS/etc/wpa_supplicant.conf" ]; then
  cp /clave/src/wpa_supplicant_template.conf "$SRC_INITRAMFS/etc/wpa_supplicant.conf"
else
  sed -i 's|^interface=.*$|ctrl_interface=/var/run/wpa_supplicant|' \
    "$SRC_INITRAMFS/etc/wpa_supplicant.conf"
fi

echo "Setting kernel config..."
cd "$KERNEL_SRC"
make ARCH=x86_64 x86_64_defconfig
# Booting
./scripts/config --enable EFI
./scripts/config --enable EFI_STUB
./scripts/config --enable BLK_DEV_INITRD
./scripts/config --set-str INITRAMFS_SOURCE "/kernel/initramfs.cpio"
./scripts/config --enable RD_GZIP
./scripts/config --enable DEVTMPFS
./scripts/config --enable DEVTMPFS_MOUNT
./scripts/config --enable PROC_FS
./scripts/config --enable SYSFS
./scripts/config --enable EARLY_PRINTK
./scripts/config --enable FB
./scripts/config --enable FB_EFI
# Console
./scripts/config --enable FRAMEBUFFER_CONSOLE
./scripts/config --enable VT
./scripts/config --enable VT_CONSOLE
./scripts/config --enable CMDLINE_BOOL
./scripts/config --set-str CMDLINE "console=tty0 rdinit=/sbin/init loglevel=7"
# Persistent drives
./scripts/config --enable EXT4_FS
./scripts/config --enable EXT2_FS
./scripts/config --enable USB_STORAGE
./scripts/config --enable BLK_DEV_NVME
./scripts/config --enable SATA_AHCI
# Networking
./scripts/config --enable NET
./scripts/config --enable INET
./scripts/config --enable PACKET
./scripts/config --enable UNIX
./scripts/config --enable NETDEVICES
./scripts/config --enable ETHERNET
./scripts/config --enable MII
./scripts/config --enable E1000E
./scripts/config --enable R8169
./scripts/config --enable VIRTIO_NET
# WiFi
./scripts/config --enable CFG80211
./scripts/config --enable MAC80211
./scripts/config --enable RFKILL
./scripts/config --enable FW_LOADER
./scripts/config --enable IWLWIFI
./scripts/config --enable IWLDVM
./scripts/config --enable IWLMVM
./scripts/config --enable ATH9K
./scripts/config --enable ATH10K
./scripts/config --enable RTW88
./scripts/config --enable BRCMFMAC
# MediaTek wifi
./scripts/config --enable MT76_CORE
./scripts/config --enable MT76_CONNAC_LIB
./scripts/config --enable MT7921_COMMON
./scripts/config --enable MT7921E

make ARCH=x86_64 olddefconfig

echo "Compiling binaries..."
# musl-gcc inherits Alpine's default PIE toolchain, so link init explicitly as ET_EXEC.
CRTBEGIN=$(gcc -print-file-name=crtbegin.o)
CRTEND=$(gcc -print-file-name=crtend.o)

gcc -nostdlib -static -no-pie -fno-pie \
  -isystem /build/sysroot/usr/include \
  -o "$SRC_INITRAMFS/sbin/init" \
  /build/sysroot/usr/lib/crt1.o \
  /build/sysroot/usr/lib/crti.o \
  "$CRTBEGIN" \
  /clave/src/init.c \
  -L/build/sysroot/usr/lib \
  -L"$(dirname "$CRTBEGIN")" \
  -lc -lgcc -lgcc_eh -lssp_nonshared \
  "$CRTEND" \
  /build/sysroot/usr/lib/crtn.o

scanelf -e "$SRC_INITRAMFS/sbin/init" | grep -q 'ET_EXEC' || {
  echo "FATAL: $SRC_INITRAMFS/sbin/init was not linked as ET_EXEC"
  exit 1
}

scanelf -e "$SRC_INITRAMFS/bin/busybox" | grep -q 'ET_EXEC' || {
  echo "FATAL: $SRC_INITRAMFS/bin/busybox is still PIE-shaped (ET_DYN). Rebuild userland with /clave/setup.sh first."
  exit 1
}

echo "Managing system resources"
cp /clave/src/cpm.sh $SRC_INITRAMFS/usr/bin/cpm
cp /clave/src/wifiinit.sh $SRC_INITRAMFS/usr/bin/wifiinit
chmod +x $SRC_INITRAMFS/usr/bin/cpm
chmod +x $SRC_INITRAMFS/usr/bin/wifiinit
mkdir -p $SRC_INITRAMFS/usr/share/udhcpc
cp /clave/src/default.script $SRC_INITRAMFS/usr/share/udhcpc/default.script
chmod +x $SRC_INITRAMFS/usr/share/udhcpc/default.script

echo "Packing initramfs cpio..."
cd "$SRC_INITRAMFS"
find . -print0 | cpio --null -o --format=newc > "$INITRAMFS_CPIO"
echo "    cpio size: $(du -sh "$INITRAMFS_CPIO" | cut -f1)"

test -s "$INITRAMFS_CPIO" || { echo "FATAL: cpio is empty!"; exit 1; }
cpio -tv < "$INITRAMFS_CPIO" | grep -q 'sbin/init' || { echo "FATAL: /sbin/init missing from cpio!"; exit 1; }

echo "==> Building kernel..."
cd "$KERNEL_SRC"
make ARCH=x86_64 -j"$(nproc)" bzImage

echo "Copying bzImage to ISO dir..."
cp arch/x86/boot/bzImage "$ISO_DIR/EFI/BOOT/BOOTX64.EFI"

echo "Creating EFI System Partition image..."
cd /
dd if=/dev/zero of="$ESP_IMG" bs=1M count=80
mkfs.vfat "$ESP_IMG"
mmd -i "$ESP_IMG" ::/EFI
mmd -i "$ESP_IMG" ::/EFI/BOOT
mcopy -i "$ESP_IMG" "$ISO_DIR/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI

echo "Copying esp.img into ISO dir..."
cp "$ESP_IMG" "$ISO_DIR/esp.img"

echo "Building ISO..."
cd /
xorriso -as mkisofs -o "$ISO_OUT" -e esp.img -no-emul-boot -append_partition 2 0xef "$ESP_IMG" "$ISO_DIR"
rm -f "$ESP_IMG" "$ISO_DIR/esp.img"

echo "Copying ISO to host mount..."
cp "$ISO_OUT" "$FINAL_ISO"

echo ""
echo "Done! ISO is at $FINAL_ISO"
