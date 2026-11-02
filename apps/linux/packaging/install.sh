#!/bin/sh
# Installs the latest AppImage for the current user; no root.
set -eu

repo=${CADEX_REPO:-c4duZ/cadex}
version=${CADEX_VERSION:-latest}
url=${CADEX_APPIMAGE_URL:-https://github.com/$repo/releases/$version/download/Cadex-linux-x86_64.AppImage}
bin_dir=${CADEX_BIN_DIR:-$HOME/.local/bin}
data_dir=${CADEX_DATA_DIR:-$HOME/.local/share}
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

echo "Downloading $url"
curl -fL --progress-bar -o "$tmp" "$url"
if [ -n "${CADEX_SHA256:-}" ]; then
    echo "$CADEX_SHA256  $tmp" | sha256sum -c -
fi
mkdir -p "$bin_dir" "$data_dir/applications" "$data_dir/icons/hicolor/scalable/apps" "$data_dir/icons/hicolor/256x256/apps"
install -m 755 "$tmp" "$bin_dir/cadex"
here=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)
raw=${CADEX_RAW_BASE:-https://raw.githubusercontent.com/$repo/main/apps/linux/packaging}
if [ -f "$here/cadex.desktop" ]; then
    install -m 644 "$here/cadex.desktop" "$data_dir/applications/cadex.desktop"
    install -m 644 "$here/cadex.svg" "$data_dir/icons/hicolor/scalable/apps/cadex.svg"
    install -m 644 "$here/cadex.png" "$data_dir/icons/hicolor/256x256/apps/cadex.png"
else
    curl -fsSL -o "$data_dir/applications/cadex.desktop" "$raw/cadex.desktop" || true
    mkdir -p "$data_dir/icons/hicolor/scalable/apps" "$data_dir/icons/hicolor/256x256/apps"
    curl -fsSL -o "$data_dir/icons/hicolor/scalable/apps/cadex.svg" "$raw/cadex.svg" || true
    curl -fsSL -o "$data_dir/icons/hicolor/256x256/apps/cadex.png" "$raw/cadex.png" || true
fi
echo "Installed $bin_dir/cadex"
echo "Make sure $bin_dir is in PATH."
