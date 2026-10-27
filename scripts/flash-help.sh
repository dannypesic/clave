#!/bin/sh
cat <<'EOF'
From the Clave repository directory:

  diskutil list

Identify your USB drive's whole-disk identifier (for example, disk4).
Replace N below with that number. Writing the ISO erases the selected USB drive.

  diskutil unmountDisk /dev/diskN
  sudo dd if=clave.iso of=/dev/rdiskN bs=4m
  sync
  diskutil eject /dev/diskN

Press Control-T during dd to show progress. Boot the USB drive in UEFI mode.
EOF
