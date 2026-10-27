# Clave

Clave is short for autoclave; it is a self-sterilizing, minimal Linux distribution that boots from a USB drive into RAM and wipes itself clean on reboot. There is no persistent root filesystem: the system is rebuilt from scratch every time it starts.

A disk partition can be mounted to `/home` to preserve files across reboots. Everything outside of `/home` is ephemeral: packages you install, configuration changes you make, and files you write anywhere else in the filesystem vanish the moment you reboot.

Under the hood, Clave is built from source: the Linux kernel, BusyBox for utilities, musl libc, and TinyCC as an on-device C compiler. The kernel boots directly via EFI stub requiring no bootloader.

# Building

Start Docker Desktop, then run these commands from the repository on your Mac:

```sh
make config
# Edit local/build.env and local/wpa_supplicant.conf as needed.
make firmware  # Downloads the original MediaTek example firmware list once.
make build
make flash-help
```

`make build` runs the existing setup and image-building scripts in a fresh
`docker run --rm --platform linux/amd64` Alpine container and writes `clave.iso`
to the repository. All dependencies, kernel sources, and compiled intermediates
stay in the container and disappear on exit. There are no build volumes or
compiled caches. `make build JOBS=4` limits parallel compilation.

`local/` and `clave.iso` are gitignored. Existing local files are never replaced
by `make config`. Source and private inputs are mounted read-only during builds;
only the finished ISO is copied to the host. A failed build leaves a previous
ISO intact. `make flash-help` prints the macOS flashing commands without writing
to a USB drive. `sh docker_init.sh` is a shortcut for `make build`.

# Additional features

## Persistent Files

By default, the /home directory is mounted to a disk partition to allow for persistent files. Set this disk partition in `local/build.env` or leave blank for no mounting. A recommended design pattern is to create a `userinit.sh` shell script in `/home` to easily handle any requirements on system initialization such as installing packages. 

### Preparing Partition

- If dual booting from Windows, create an unformatted partition on your disk.
- Once booted into Clave, use `cat /proc/partitions` to view your available disks and partitions.
- If you have not created a partition, use `fdisk /dev/<your_disk>` to create a partition.
- Run `mkfs.ext2 /dev/<your_disk_partition>` to create a file system. Make sure to select the right partition to avoid deleting data! 
- On your Mac, set `DISK` in `local/build.env` to your partition.
- Rebuild `clave.iso`. Your disk partition will automatically mount to `/home` on boot.

## Networking

Clave has a built-in system for WiFi connection. If using WiFi, ensure the proper firmware is installed.

Fill in `local/wpa_supplicant.conf` with your WiFi credentials before building.
`make firmware` uses `src/wpa_install_mediatek_example.sh` to download the same
five MediaTek filenames as the original installer into `local/firmware/mediatek/`.
It keeps existing nonempty blobs. If an upstream download fails, it reports the
filename and retains the other files; place any missing blobs there manually.
For other hardware, add your firmware to `local/firmware/`, retaining its Linux
firmware subdirectories. The build copies these saved blobs and runs the
original WiFi library-installation steps after staging the initramfs.
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
