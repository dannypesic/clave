#!/bin/sh
set -e

if [ ! -d /build ]; then
  echo "FATAL: /build does not exist. Rebuild the Docker image first."
  exit 1
fi

echo "Building project..."

ROOT="/build/initramfs"

mkdir -p $ROOT
mkdir $ROOT/bin
mkdir $ROOT/dev
mkdir $ROOT/etc
mkdir -p $ROOT/home/pkgar
mkdir $ROOT/lib
mkdir $ROOT/proc
mkdir $ROOT/sbin
mkdir $ROOT/sys
mkdir $ROOT/tmp
mkdir $ROOT/var
mkdir -p $ROOT/usr/bin
mkdir -p $ROOT/usr/include
mkdir -p $ROOT/usr/lib
mkdir -p $ROOT/usr/share
mkdir -p /build/iso/EFI/BOOT
mkdir /build/sysroot
mkdir /build/tcc-install
mkdir -p $ROOT/usr/lib/tcc
mkdir -p /build/external_src

echo "Installing musl libc..."

cd /build/external_src
wget https://musl.libc.org/releases/musl-1.2.5.tar.gz
tar xf musl-1.2.5.tar.gz
rm -f musl-1.2.5.tar.gz
cd musl-1.2.5

./configure \
  --prefix=/build/sysroot/usr \
  --disable-shared \
  --enable-wrapper=gcc

make -j$(nproc)
make install

cp -r /usr/include/linux       /build/sysroot/usr/include/
cp -r /usr/include/asm         /build/sysroot/usr/include/
cp -r /usr/include/asm-generic /build/sysroot/usr/include/
ar rcs /build/sysroot/usr/lib/libssp_nonshared.a

cd /build/external_src

# Install BusyBox
echo "Installing BusyBox..."
wget https://busybox.net/downloads/busybox-1.36.1.tar.bz2
tar xf busybox-1.36.1.tar.bz2
rm -f busybox-1.36.1.tar.bz2
cd busybox-1.36.1

make defconfig
sed -i '/CONFIG_STATIC/d' .config
echo 'CONFIG_STATIC=y' >> .config

sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' .config
sed -i 's/CONFIG_NANDWRITE=y/# CONFIG_NANDWRITE is not set/' .config
sed -i 's/CONFIG_NANDDUMP=y/# CONFIG_NANDDUMP is not set/' .config
sed -i 's/CONFIG_UBIATTACH=y/# CONFIG_UBIATTACH is not set/' .config
sed -i 's/CONFIG_UBIDETACH=y/# CONFIG_UBIDETACH is not set/' .config
sed -i 's/CONFIG_UBIMKVOL=y/# CONFIG_UBIMKVOL is not set/' .config
sed -i 's/CONFIG_UBIRMVOL=y/# CONFIG_UBIRMVOL is not set/' .config
sed -i 's/CONFIG_UBIRSVOL=y/# CONFIG_UBIRSVOL is not set/' .config
sed -i 's/CONFIG_UBIUPDATEVOL=y/# CONFIG_UBIUPDATEVOL is not set/' .config
sed -i 's/CONFIG_UBIRENAME=y/# CONFIG_UBIRENAME is not set/' .config
sed -i 's/CONFIG_FLASHCP=y/# CONFIG_FLASHCP is not set/' .config
sed -i 's/CONFIG_FLASH_LOCK=y/# CONFIG_FLASH_LOCK is not set/' .config
sed -i 's/CONFIG_FLASH_UNLOCK=y/# CONFIG_FLASH_UNLOCK is not set/' .config
sed -i 's/CONFIG_FLASH_ERASEALL=y/# CONFIG_FLASH_ERASEALL is not set/' .config
sed -i 's/CONFIG_POWERTOP=y/# CONFIG_POWERTOP is not set/' .config
sed -i 's/CONFIG_MODPROBE_SMALL=y/# CONFIG_MODPROBE_SMALL is not set/' .config
sed -i 's/CONFIG_DEPMOD=y/# CONFIG_DEPMOD is not set/' .config
sed -i 's/CONFIG_I2CGET=y/# CONFIG_I2CGET is not set/' .config
sed -i 's/CONFIG_I2CSET=y/# CONFIG_I2CSET is not set/' .config
sed -i 's/CONFIG_I2CDUMP=y/# CONFIG_I2CDUMP is not set/' .config
sed -i 's/CONFIG_I2CDETECT=y/# CONFIG_I2CDETECT is not set/' .config
sed -i 's/CONFIG_I2CTRANSFER=y/# CONFIG_I2CTRANSFER is not set/' .config
yes "" | make oldconfig
make -j$(nproc) CC=/build/sysroot/usr/bin/musl-gcc EXTRA_CFLAGS="-fno-pie" EXTRA_LDFLAGS="-no-pie"

cp busybox /build/initramfs/bin/busybox
ln -s busybox /build/initramfs/bin/sh

scanelf -e /build/initramfs/bin/busybox | grep -q 'ET_EXEC' || {
  echo "FATAL: /build/initramfs/bin/busybox was not linked as ET_EXEC"
  exit 1
}

cd /build/external_src

# Install TinyCC
echo "Installing TinyCC..."
git clone https://repo.or.cz/tinycc.git
cd tinycc

./configure \
  --prefix=/build/tcc-install \
  --cc=gcc \
  --extra-cflags="-static -fno-pie" \
  --extra-ldflags="-static -no-pie" \
  --config-musl \
  --sysroot=/build/sysroot \
  --crtprefix=/usr/lib/tcc \
  --libpaths=/usr/lib/tcc \
  --tccdir=/usr/lib/tcc

make -j$(nproc)
make install

cp /build/tcc-install/bin/tcc            /build/initramfs/usr/bin/tcc
cp /build/external_src/tinycc/libtcc1.a  /build/initramfs/usr/lib/tcc/
cp -r /build/external_src/tinycc/include/ /build/initramfs/usr/lib/tcc/include/

scanelf -e /build/initramfs/usr/bin/tcc | grep -q 'ET_EXEC' || {
  echo "FATAL: /build/initramfs/usr/bin/tcc was not linked as ET_EXEC"
  exit 1
}

cp /build/sysroot/usr/lib/libc.a  /build/initramfs/usr/lib/tcc/
cp /build/sysroot/usr/lib/crt1.o  /build/initramfs/usr/lib/tcc/
cp /build/sysroot/usr/lib/crti.o  /build/initramfs/usr/lib/tcc/
cp /build/sysroot/usr/lib/crtn.o  /build/initramfs/usr/lib/tcc/

echo "Adding the evil dot that broke everything..."
cp -r /build/sysroot/usr/include/. /build/initramfs/usr/include/

# Leave behind a forwarding wrapper so old instructions can't silently use a stale copied build script.
cat > /build/build.sh <<'EOF'
#!/bin/sh
echo "NOTICE: /build/build.sh is only a wrapper. Running /clave/src/build.sh instead."
exec /bin/sh /clave/src/build.sh "$@"
EOF
chmod +x /build/build.sh

# Compile init
echo "Compiling Init..."
CRTBEGIN=$(gcc -print-file-name=crtbegin.o)
CRTEND=$(gcc -print-file-name=crtend.o)

gcc -nostdlib -static -no-pie -fno-pie \
  -isystem /build/sysroot/usr/include \
  -o /build/initramfs/sbin/init \
  /build/sysroot/usr/lib/crt1.o \
  /build/sysroot/usr/lib/crti.o \
  "$CRTBEGIN" \
  /clave/src/init.c \
  -L/build/sysroot/usr/lib \
  -L"$(dirname "$CRTBEGIN")" \
  -lc -lgcc -lgcc_eh -lssp_nonshared \
  "$CRTEND" \
  /build/sysroot/usr/lib/crtn.o

scanelf -e /build/initramfs/sbin/init | grep -q 'ET_EXEC' || {
  echo "FATAL: /build/initramfs/sbin/init was not linked as ET_EXEC"
  exit 1
}
chmod +x /build/initramfs/sbin/init

cp /clave/src/.env.example /build/.env
cp /clave/src/wpa_supplicant_template.conf /build/initramfs/etc/wpa_supplicant.conf
cp /clave/src/default.script /build/initramfs/usr/share/default.script
chmod +x /build/initramfs/usr/share/default.script

echo "Project Setup Finished"
echo "Fill out these files:"
echo "/build/.env"
echo "/build/initramfs/etc/wpa_supplicant.conf (optional)"
echo ""
echo "Once finished, run sh /clave/src/build.sh to build iso"
