#!/bin/sh

cmd="$1"
shift
pkg_name="$1"

PKG_DIR="/home/pkgar"

case "$cmd" in
  get)
    shift
    url="$1"
    if [ -z "$pkg_name" ] || [ -z "$url" ]; then
      echo "Usage: cpm get <name> <url>"
      exit 1
    fi

    echo "Getting $pkg_name from $url..."

    tmp_file="/tmp/${pkg_name}.download"
    wget -O "$tmp_file" "$url" || { echo "Error: download failed"; rm -f "$tmp_file"; exit 1; }

    case "$url" in
      *.tar.gz|*.tgz)   format="tar.gz" ;;
      *.tar.bz2|*.tbz2) format="tar.bz2" ;;
      *.tar.xz|*.txz)   format="tar.xz" ;;
      *)
        echo "Error: unsupported format (expected tar.gz, tar.bz2, or tar.xz)"
        rm -f "$tmp_file"
        exit 1
        ;;
    esac

    mkdir -p "$PKG_DIR/$pkg_name"
    mv "$tmp_file" "$PKG_DIR/$pkg_name/$pkg_name.$format"

    cat > "$PKG_DIR/$pkg_name/manifest.txt" << EOF
url: $url
format: $format
dependencies: ""
conflicts: ""
version:
EOF

    echo "Done: $pkg_name archived."
    echo "Edit $PKG_DIR/$pkg_name/manifest.txt to fill in dependencies/conflicts."
    ;;

  install)
    shift  # move past pkg_name

    # parse flags
    force=0
    case "$1" in
      -f|--force) force=1 ;;
    esac

    # read format from manifest
    manifest="$PKG_DIR/$pkg_name/manifest.txt"
    if [ ! -f "$manifest" ]; then
      echo "Error: $pkg_name not in package archive. Run cpm get first."
      exit 1
    fi
    format=$(grep '^format:' "$manifest" | cut -d' ' -f2)
    archive="$PKG_DIR/$pkg_name/$pkg_name.$format"

    if [ ! -f "$archive" ]; then
      echo "Error: archive not found: $archive"
      exit 1
    fi

    echo "Installing $pkg_name..."

    tmp_dir="/tmp/$pkg_name"
    mkdir -p "$tmp_dir"
    if ! tar -xaf "$archive" -C "$tmp_dir"; then
      rm -rf "$tmp_dir"
      echo "Error: $pkg_name failed to extract"
      exit 1
    fi

    if [ "$force" -eq 1 ]; then
      for d in $tmp_dir/*/*; do
        [ -d "$d" ] || continue
        base=$(basename "$d")
        mkdir -p "/usr/$base"
        tar -C "$d" -cf - . | tar -C "/usr/$base" -xpf -
      done
    else
      # dependency/conflict checks go here later
      for d in $tmp_dir/*/*; do
        [ -d "$d" ] || continue
        base=$(basename "$d")
        mkdir -p "/usr/$base"
        tar -C "$d" -cf - . | tar -C "/usr/$base" -xpf -
      done
    fi

    rm -rf "$tmp_dir"
    echo "Done: $pkg_name installed."
    ;;

  rm)
    if [ -z "$pkg_name" ]; then
      echo "Usage: cpm rm <name>"
      exit 1
    fi
    echo "Permanently removing $pkg_name from package archive..."
    rm -r "$PKG_DIR/$pkg_name"
    echo "Done: $pkg_name permanently removed."
    ;;

  help)
    echo "Manual:"
    echo ""
    echo "cpm get <name> <url>: gets package from download url and saves to $PKG_DIR/<name>"
    echo ""
    echo "cpm install <name> [-f]: installs package from $PKG_DIR/<name> to system instance"
    echo "-f    ignore all dependency or conflict issues"
    echo ""
    echo "cpm rm <name>: permanently deletes package from pkgar"
    ;;

  *)
    echo "Unknown command: $cmd. Run cpm help for manual."
    exit 1
    ;;
esac
