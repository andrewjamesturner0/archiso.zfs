#!/usr/bin/env bash
# Get current versions of kernel and ZFS from repos
# Idempotent: read-only operation, no side effects
set -euo pipefail

# Get latest available versions from official repos
KERNEL_VER=$(pacman -Si linux-lts 2>/dev/null | awk '/^Version/ {print $3}') || KERNEL_VER="unknown"

# Get ZFS version from AUR API
ZFS_VER=$(curl -sf "https://aur.archlinux.org/rpc/?v=5&type=info&arg=zfs-dkms" | \
    grep -oP '"Version":"\K[^"]+') || ZFS_VER="unknown"

# Output in sourceable format
echo "KERNEL_VER=${KERNEL_VER}"
echo "ZFS_VER=${ZFS_VER}"