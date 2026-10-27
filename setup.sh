#!/bin/sh
set -e

JOBS=${JOBS:-$(nproc)}

echo "Installing build dependencies..."
apk add --no-cache \
    gcc make musl-dev flex bison perl bash cpio \
    xorriso dosfstools mtools bc linux-headers \
    elfutils-dev openssl-dev curl tar xz wget git wpa_supplicant pax-utils

echo "Downloading kernel source..."
mkdir -p /kernel
curl -L https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.22.tar.xz \
    -o /tmp/linux.tar.xz
tar xf /tmp/linux.tar.xz -C /kernel
rm /tmp/linux.tar.xz

echo "Building toolchain..."

mkdir -p /build/sysroot
mkdir -p /build/tcc-install
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

make -j"$JOBS"
make install

cp -r /usr/include/linux       /build/sysroot/usr/include/
cp -r /usr/include/asm         /build/sysroot/usr/include/
cp -r /usr/include/asm-generic /build/sysroot/usr/include/
ar rcs /build/sysroot/usr/lib/libssp_nonshared.a

cd /build/external_src

echo "Building BusyBox..."
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
make -j"$JOBS" CC=/build/sysroot/usr/bin/musl-gcc EXTRA_CFLAGS="-fno-pie" EXTRA_LDFLAGS="-no-pie"

# busybox stays here; build.sh copies it into the initramfs on each build
scanelf -e busybox | grep -q 'ET_EXEC' || {
  echo "FATAL: busybox was not linked as ET_EXEC"
  exit 1
}

cd /build/external_src

echo "Building TinyCC..."
# Retry the upstream download, then use the mob-branch mirror if TLS keeps failing.
attempt=1
while ! git -c http.version=HTTP/1.1 clone --depth 1 https://repo.or.cz/tinycc.git tinycc; do
  rm -rf /build/external_src/tinycc
  if [ "$attempt" -ge 3 ]; then
    echo "TinyCC upstream download failed; trying the GitHub mirror..."
    git -c http.version=HTTP/1.1 clone --depth 1 --branch mob \
      https://github.com/TinyCC/tinycc.git tinycc
    break
  fi
  attempt=$((attempt + 1))
  echo "Retrying TinyCC download (attempt $attempt of 3)..."
done
cd tinycc

# Configure paths for the booted system; /build is only an installation workspace.
./configure \
  --prefix=/build/tcc-install \
  --cc=gcc \
  --extra-cflags="-static -fno-pie" \
  --extra-ldflags="-static -no-pie" \
  --config-musl \
  --sysroot= \
  --sysincludepaths='{B}/include:/usr/include' \
  --crtprefix=/usr/lib/tcc \
  --libpaths=/usr/lib/tcc \
  --tccdir=/usr/lib/tcc

make -j"$JOBS"
make install

scanelf -e /build/tcc-install/bin/tcc | grep -q 'ET_EXEC' || {
  echo "FATAL: tcc was not linked as ET_EXEC"
  exit 1
}

# Personal inputs persist on the host; build copies stay inside this container.
cp /private-inputs/build.env /build/.env
cp /private-inputs/wpa_supplicant.conf /build/wpa_supplicant.conf

echo "Toolchain ready."
