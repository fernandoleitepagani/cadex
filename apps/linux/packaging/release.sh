#!/bin/sh
# The Linux release step. Publishing is still a manual GitHub release.
set -eu

if [ "${CADEX_LINUX:-0}" != "1" ]; then
    echo "Set CADEX_LINUX=1 to build and checksum the Linux release." >&2
    exit 1
fi

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app=$(dirname "$here")
repo=$(CDPATH= cd -- "$app/../.." && pwd)
out=${CADEX_OUT:-$app/dist}

"$here/build.sh"

echo
echo "Artifacts in $out:"
sha256sum "$out"/Cadex-linux-x86_64.* 2>/dev/null || true
echo
echo "Upload them to the GitHub release and add the linux-x86_64 entry to latest.json."
echo "The .deb/.rpm only notify about updates; the AppImage is the self-update target."
