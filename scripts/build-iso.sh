#!/usr/bin/env bash
# Build Arch Linux ISO with ZFS support
# Idempotent: cleans work dir before build, manages bind mount safely
set -euo pipefail

source "$(dirname "$0")/common.env"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: build-iso.sh must run as root" >&2
    exit 1
fi

KEEP=3
MOUNTPOINT="/repo"

# Cleanup function for trap (idempotent unmount)
cleanup() {
    if mountpoint -q "$MOUNTPOINT"; then
        echo "==> Unmounting $MOUNTPOINT"
        umount "$MOUNTPOINT"
    fi
}
trap cleanup EXIT

echo "==> Cleaning previous build artifacts"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR" "$OUTDIR"

echo "==> Setting up local repo bind mount"
mkdir -p "$MOUNTPOINT"
# Unmount if already mounted (idempotent)
if mountpoint -q "$MOUNTPOINT"; then
    umount "$MOUNTPOINT"
fi
mount --bind "$REPODIR" "$MOUNTPOINT"

echo "==> Building ISO"
mkarchiso -v -w "$WORKDIR" -o "$OUTDIR" "$PROFILE"

echo "==> Rotating old ISOs (keeping $KEEP)"
mapfile -t ISOS < <(ls -1t "$OUTDIR"/*.iso 2>/dev/null || true)
if (( ${#ISOS[@]} > KEEP )); then
    for iso in "${ISOS[@]:KEEP}"; do
        echo "    Removing old ISO: $iso"
        rm -f "$iso"
    done
fi

echo "==> Cleaning work directory"
rm -rf "$WORKDIR"

echo "==> ISO build complete"
ls -lh "$OUTDIR"/*.iso 2>/dev/null || echo "    No ISOs found in $OUTDIR"