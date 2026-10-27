#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
repo=$(pwd -P)
docker=${DOCKER:-docker}
image=${IMAGE:-alpine:3.22.2}

# All compilation and dependency installation use the disposable Linux filesystem.
# Only the finished ISO is exported; personal inputs are mounted read-only.
umask 077
output=$(mktemp -d "$repo/local/.output.XXXXXX")
trap 'rm -rf "$output"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"$docker" run --rm --platform linux/amd64 \
    --mount "type=bind,source=$repo,target=/clave,readonly" \
    --mount "type=bind,source=$repo/local,target=/private-inputs,readonly" \
    --mount "type=bind,source=$output,target=/output" \
    --env "JOBS=${JOBS:-}" \
    "$image" sh -c 'sh /clave/setup.sh && sh /clave/src/build.sh'

mv "$output/clave.iso" "$repo/clave.iso"
printf '\nCreated %s/clave.iso\nRun make flash-help for macOS USB instructions.\n' "$repo"
