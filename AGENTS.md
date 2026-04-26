# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this project is

`Clave` is a hand-rolled minimal Linux distribution that boots from a USB via UEFI. It is built from source components: a custom Linux kernel, BusyBox for userland, musl libc, and TinyCC as an on-device compiler. A custom PID 1 (`init`, written in C) mounts the virtual filesystems and execs a shell. There is no bootloader — the kernel is booted directly via EFI stub as `BOOTX64.EFI`.

## Build workflow

All builds happen inside a Docker container (Alpine + toolchain). The Mac filesystem is case-insensitive and does not support Linux device nodes, which causes critical failures if the build workspace is on a bind-mount.

**Crucially, the entire build workspace (`/build/`) and the kernel source (`/kernel/`) live inside the container's internal filesystem, not on the Mac host.**

```sh
# outside the container (on Mac):
sh docker_init.sh

# inside the container, to initialize (musl, busybox, tcc):
sh /clave/setup.sh

# inside the container, to build the ISO:
sh /clave/src/build.sh
```

`src/build.sh` drives the entire pipeline: cleans stale artifacts, configures the kernel, compiles `init.c`, packs the initramfs into a cpio, builds `bzImage`, builds an EFI System Partition FAT image, and wraps everything in `build/clave.iso`. It then copies the finished ISO back to `/clave/clave.iso` on the host.

**Important:** run `build.sh` directly from `/clave/src/build.sh`, not from a copy. Setup used to copy it to `/build/build.sh`, but that copy goes stale whenever `src/build.sh` changes. The script writes all artifacts to `/build/` regardless of where it is run from.

## Paths at a glance

| Purpose | Path (Inside Container) |
| --- | --- |
| Source code (mounted from Mac) | `/clave/` |
| Kernel source (internal to container) | `/kernel/linux-6.18.22/` |
| Build workspace (internal to container) | `/build/` |
| Initramfs staging | `/build/initramfs/` |
| Output ISO (copied to host) | `/clave/clave.iso` |

## Architecture

### Boot flow

1. UEFI firmware loads `BOOTX64.EFI` (the `bzImage`) via the EFI stub — no GRUB.
2. Kernel unpacks the embedded initramfs into RAM. The cpio is embedded at kernel build time via `CONFIG_INITRAMFS_SOURCE` pointing to `/kernel/initramfs.cpio`.
3. `CONFIG_DEVTMPFS_MOUNT=y` causes the kernel to mount devtmpfs on `/dev` before executing init.
4. Kernel exec's `/sbin/init` (as specified by `rdinit=/sbin/init` in the embedded `CMDLINE`).
5. `init.c` mounts `/proc`, `/sys`, wires stdin/stdout/stderr to `/dev/console`, then `execve`s `/sbin/sysinit`.

### Userland toolchain provenance

The toolchain inside the initramfs is deliberately layered:

- **musl libc** (built from source into `/build/sysroot`) — provides headers, `libc.a`, and crt objects.
- **BusyBox** — built statically against musl.
- **TinyCC** — built with paths pointing to the internal `/usr/lib/tcc` layout of the booted system.

## Gotchas learned the hard way

- **Do not use the Mac filesystem for building.** APFS/HFS+ is case-insensitive (breaks kernel build) and doesn't support `mknod` (breaks `/dev/console` in initramfs). Use the internal `/build` directory.
