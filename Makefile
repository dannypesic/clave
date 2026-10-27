.DEFAULT_GOAL := build
DOCKER ?= docker
IMAGE ?= alpine:3.22.2
JOBS ?=
export DOCKER IMAGE JOBS

.PHONY: help build config firmware flash-help
help:
	@printf '%s\n' \
	  'Clave build instructions (run from this directory on your Mac)' \
	  '' \
	  '1. Start Docker Desktop.' \
	  '2. make config       Create missing private configuration files.' \
	  '   Edit local/wpa_supplicant.conf for Wi-Fi.' \
	  '   Edit local/build.env for an optional /home partition.' \
	  '3. make firmware     Download the MediaTek example firmware, if needed.' \
	  '   Other firmware goes in local/firmware/ with its subfolders.' \
	  '4. make build        Build ./clave.iso in a disposable container.' \
	  '5. make flash-help   Show macOS USB flashing instructions.' \
	  '' \
	  'Optional: make build JOBS=4 to limit parallel compilation.' \
	  'local/ and clave.iso are gitignored.'

build: config
	@sh scripts/build.sh

config:
	@sh scripts/config.sh

firmware: config
	@sh src/wpa_install_mediatek_example.sh --download

flash-help:
	@sh scripts/flash-help.sh
