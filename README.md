# Clave

Clave is short for autoclave; it is a self-sterilizing, minimal Linux distribution that boots from a USB drive into RAM and wipes itself clean on reboot. There is no persistent root filesystem; the system is rebuilt from scratch every time it starts.

A disk partition can be mounted to `/home` to preserve files across reboots. Everything outside of `/home` is ephemeral: packages you install, configuration changes you make, and files you write anywhere else in the filesystem vanish the moment you reboot.

Under the hood, Clave is hand-rolled from source: a custom Linux kernel, BusyBox for userland utilities, musl libc, and TinyCC as an on-device C compiler. The kernel boots directly via EFI stub requiring no bootloader (no GRUB, no syslinux).

# Building

It is always a good idea to use a Docker container when working with Clave to avoid errors when building on your own computer. Any file paths listed in this README are assumed to be referenced from the container's point of view. By default, `/build` and `/kernel` exist solely in the container to avoid any contamination from the host file system. `/clave` is mounted to this current repository, so you can reference files like `/clave/src`.

`sh docker_init.sh` initializes the Alpine Linux Docker container.
`sh setup.sh` creates the `/build` directory in the container and installs project dependencies.
`sh /clave/src/build.sh` builds `clave.iso` and copies it to `/clave`for writing to flash drive.

# Additional features

## Persistent Files

By default, the /home directory is mounted to a disk partition to allow for persistent files. Set this disk partition in `/build/.env` or leave blank for no mounting. A recommended design pattern is to create a `userinit.sh` shell script in `/home` to easily handle any requirements on system initialization such as installing packages. 

### Preparing Partition

- If dual booting from Windows, create an unformatted partition on your disk.
- Once booted into Clave, use `cat /proc/partitions` to view your available disks and partitions.
- If you have not created a partition, use `fdisk /dev/<your_disk>` to create a partition.
- Run `mkfs.ext2 /dev/<your_disk_partition>` to create a file system. Make sure to select the right partition to avoid deleting data! 
- Inside of your Docker container, set `DISK` in `/build/.env` to your partition.
- Rebuild `clave.iso`. Your disk partition will automatically mount to `/home` on boot.

## Networking

Clave has a built-in system for WiFi connection. If using WiFi, ensure the proper firmware is installed.

`build/initramfs/etc/wpa_supplicant.conf` should be filled in with login credentials for WiFi access after building.
`src/wpa_install_mediatek_example.sh` shows what an example firmware installation may look like. This will likely not work on your computer, so modify it to fit your firmware needs.
`wifiinit` will quickly connect you to the WiFi network given you have the correct credentials and firmware.

## Package Management

The Clave Package Manager `cpm` is a lightweight tool to help handle packages.

By default, a package archive `pkgar` is created in the persistent `/home` directory. `cpm` allows you to download packages from the web and store them in the package archive. Then, you can load these packages into your system as you please, and they will be automatically removed on a system reboot. It is recommended to use a `userinit.sh` script to easily install certain packages on system boot to easily jump into things.

`cpm` currently has significant limitations which are exacerbated by the scale of Clave: there is no dependency resolution, no conflict detection, and no guarantee that a given package will work in Clave's minimal environment. Packages that rely on a traditional init system, shared libraries not present in the initramfs, or a writable root filesystem will likely fail.

# What's Next?
- `cpm` dependency and conflict resolution
- Kernel configuration tuning to reduce ISO size
- Broader package compatibility in the minimal initramfs environment

# Status

Clave is a work in progress. Large parts of it are incomplete, experimental, or outright broken. When in doubt, assume that any software you install will not work, as the environment is too minimal and too nonstandard for most packages to run without modification. If something does work, that is a pleasant surprise, not the expectation.
