#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
umask 077
mkdir -p local/firmware
if [ ! -e local/build.env ]; then
    cp src/.env.example local/build.env
    echo "Created local/build.env (gitignored)"
fi
if [ ! -e local/wpa_supplicant.conf ]; then
    cp src/wpa_supplicant_template.conf local/wpa_supplicant.conf
    echo "Created local/wpa_supplicant.conf (gitignored)"
fi
