#!/bin/sh
set -e

JOBS=${JOBS:-$(nproc)}

# /build is internal to the container to avoid Mac filesystem limitations (case-sensitivity, mknod)
SRC_INITRAMFS=/build/initramfs
INITRAMFS_CPIO=/kernel/initramfs.cpio
KERNEL_SRC=/kernel/linux-6.18.22
ISO_DIR=/build/iso
ESP_IMG=/build/esp.img
ISO_OUT=/build/clave.iso
FINAL_ISO=/output/clave.iso

echo "Checking prerequisites..."
test -f /build/external_src/busybox-1.36.1/busybox || {
  echo "FATAL: busybox not found at /build/external_src/busybox-1.36.1/busybox. Run setup.sh first."
  exit 1
}
test -f /build/tcc-install/bin/tcc || {
  echo "FATAL: tcc not found at /build/tcc-install/bin/tcc. Run setup.sh first."
  exit 1
}
test -f /build/.env || {
  echo "FATAL: /build/.env not found. Copy /clave/src/.env.example to /build/.env and fill it in."
  exit 1
}

echo "Staging initramfs..."
rm -rf "$SRC_INITRAMFS"
mkdir -p "$SRC_INITRAMFS/bin"
mkdir -p "$SRC_INITRAMFS/dev"
mkdir -p "$SRC_INITRAMFS/etc"
mkdir -p "$SRC_INITRAMFS/home/pkgar"
mkdir -p "$SRC_INITRAMFS/lib"
mkdir -p "$SRC_INITRAMFS/proc"
mkdir -p "$SRC_INITRAMFS/sbin"
mkdir -p "$SRC_INITRAMFS/sys"
mkdir -p "$SRC_INITRAMFS/tmp"
mkdir -p "$SRC_INITRAMFS/var/run/wpa_supplicant"
mkdir -p "$SRC_INITRAMFS/usr/bin"
mkdir -p "$SRC_INITRAMFS/usr/include"
mkdir -p "$SRC_INITRAMFS/usr/lib/tcc"
mkdir -p "$SRC_INITRAMFS/usr/share/udhcpc"
mkdir -p "$ISO_DIR/EFI/BOOT"

mknod "$SRC_INITRAMFS/dev/console" c 5 1
mknod "$SRC_INITRAMFS/dev/null"    c 1 3
mknod "$SRC_INITRAMFS/dev/urandom" c 1 9
chmod 600 "$SRC_INITRAMFS/dev/console"
chmod 666 "$SRC_INITRAMFS/dev/null"
chmod 666 "$SRC_INITRAMFS/dev/urandom"

echo "Copying BusyBox..."
cp /build/external_src/busybox-1.36.1/busybox "$SRC_INITRAMFS/bin/busybox"
ln -s busybox "$SRC_INITRAMFS/bin/sh"

echo "Copying TinyCC..."
cp /build/tcc-install/bin/tcc              "$SRC_INITRAMFS/usr/bin/tcc"
# Include installed support objects (runmain.o, bt-*.o, bcheck*.o) and headers.
cp -r /usr/lib/tcc/.                      "$SRC_INITRAMFS/usr/lib/tcc/"
# musl's compatibility archives provide names such as libm.a and libpthread.a.
cp /build/sysroot/usr/lib/*.a             "$SRC_INITRAMFS/usr/lib/tcc/"
cp /build/sysroot/usr/lib/crt1.o           "$SRC_INITRAMFS/usr/lib/tcc/"
cp /build/sysroot/usr/lib/crti.o           "$SRC_INITRAMFS/usr/lib/tcc/"
cp /build/sysroot/usr/lib/crtn.o           "$SRC_INITRAMFS/usr/lib/tcc/"
cp -r /build/sysroot/usr/include/. "$SRC_INITRAMFS/usr/include/"

echo "Compiling init..."
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

chmod +x "$SRC_INITRAMFS/sbin/init"

echo "Copying userland scripts..."
cp /clave/src/cpm.sh         "$SRC_INITRAMFS/usr/bin/cpm"
cp /clave/src/wifiinit.sh    "$SRC_INITRAMFS/usr/bin/wifiinit"
cp /clave/src/default.script "$SRC_INITRAMFS/usr/share/udhcpc/default.script"
chmod +x "$SRC_INITRAMFS/usr/bin/cpm"
chmod +x "$SRC_INITRAMFS/usr/bin/wifiinit"
chmod +x "$SRC_INITRAMFS/usr/share/udhcpc/default.script"

echo "Injecting config..."
. /build/.env
sed "s|__DISK__|${DISK:-}|g" /clave/src/sysinit.template > "$SRC_INITRAMFS/sbin/sysinit"
chmod +x "$SRC_INITRAMFS/sbin/sysinit"

if [ -f /build/wpa_supplicant.conf ]; then
  cp /build/wpa_supplicant.conf "$SRC_INITRAMFS/etc/wpa_supplicant.conf"
else
  cp /clave/src/wpa_supplicant_template.conf "$SRC_INITRAMFS/etc/wpa_supplicant.conf"
fi

# ── custom additions ────────────────────────────────────────────────────────
# Add extra files to the initramfs here before the image is packed.
# Use the target path relative to $SRC_INITRAMFS, e.g.:
#   cp /clave/src/mytool "$SRC_INITRAMFS/usr/bin/mytool"
. /clave/src/wpa_install_mediatek_example.sh
# ───────────────────────────────────────────────────────────────────────────

echo "Verifying initramfs..."
scanelf -e "$SRC_INITRAMFS/sbin/init"   | grep -q 'ET_EXEC' || { echo "FATAL: sbin/init is not ET_EXEC";   exit 1; }
scanelf -e "$SRC_INITRAMFS/bin/busybox" | grep -q 'ET_EXEC' || { echo "FATAL: bin/busybox is not ET_EXEC"; exit 1; }
scanelf -e "$SRC_INITRAMFS/usr/bin/tcc" | grep -q 'ET_EXEC' || { echo "FATAL: usr/bin/tcc is not ET_EXEC"; exit 1; }
test -c "$SRC_INITRAMFS/dev/console"   || { echo "FATAL: dev/console missing or not a char device";  exit 1; }
test -c "$SRC_INITRAMFS/dev/null"      || { echo "FATAL: dev/null missing or not a char device";     exit 1; }
test -c "$SRC_INITRAMFS/dev/urandom"   || { echo "FATAL: dev/urandom missing or not a char device";  exit 1; }
grep -q '^ctrl_interface=' "$SRC_INITRAMFS/etc/wpa_supplicant.conf" || {
  echo "FATAL: wpa_supplicant.conf is missing ctrl_interface line"
  exit 1
}
if find "$SRC_INITRAMFS" \( -name '.DS_Store' -o -name '.ash_history' \) | grep -q .; then
  echo "FATAL: host-leak files found in initramfs"
  exit 1
fi

echo "Packing initramfs cpio..."
cd "$SRC_INITRAMFS"
find . -print0 | cpio --null -o --format=newc > "$INITRAMFS_CPIO"
echo "    cpio size: $(du -sh "$INITRAMFS_CPIO" | cut -f1)"

test -s "$INITRAMFS_CPIO" || { echo "FATAL: cpio is empty!"; exit 1; }
cpio -tv < "$INITRAMFS_CPIO" | grep -q 'sbin/init' || { echo "FATAL: /sbin/init missing from cpio!"; exit 1; }

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
./scripts/config --set-str CMDLINE "console=tty0 rdinit=/sbin/init loglevel=7" # replace 'loglevel=7' with 'quiet loglevel=0' for a clean init screen
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

echo "==> Building kernel..."
make ARCH=x86_64 -j"$JOBS" bzImage

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
echo "Run make flash-help on the host for macOS USB instructions."
