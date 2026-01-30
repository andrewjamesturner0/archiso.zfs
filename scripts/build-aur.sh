#!/usr/bin/env bash
# Build ZFS AUR packages into local repo
# Idempotent: can be run multiple times safely, rebuilds packages each run
set -euo pipefail

source "$(dirname "$0")/common.env"

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: build-aur.sh must not run as root" >&2
    exit 1
fi

echo "==> Building AUR packages"

# Ensure directories exist (idempotent)
mkdir -p "$REPODIR" "$AUR_BUILDDIR" "$CHROOTDIR"

# Create or update clean chroot (idempotent)
if [[ ! -d "$CHROOTDIR/root" ]]; then
    echo "==> Creating clean chroot"
    sudo /usr/bin/mkarchroot "$CHROOTDIR/root" base-devel
else
    echo "==> Updating existing chroot"
    sudo /usr/bin/arch-nspawn "$CHROOTDIR/root" pacman -Syu --noconfirm
fi

build_pkg() {
    local pkg="$1"
    local dir="$AUR_BUILDDIR/$pkg"

    echo "==> Building $pkg"

    # Clean previous build (idempotent)
    rm -rf "$dir"
    
    # Clone without CRLF conversion
    git -c core.autocrlf=false clone "https://aur.archlinux.org/$pkg.git" "$dir"
    
    # Convert ALL text files from CRLF to LF
    find "$dir" -type f -exec sed -i 's/\r$//' {} +

    # Update checksums to match actual downloaded sources
    echo "updating checksums"
    (cd "$dir" && updpkgsums)
    echo "updating checksums - done"

    echo "running makechrootpkg"
    (cd "$dir" && makechrootpkg -c -r "$CHROOTDIR")
    echo "makechrootpkg done"

    # Copy built packages to repo
    find "$dir" -name '*.pkg.tar.zst' -exec cp -f {} "$REPODIR/" \;
}

build_pkg zfs-utils
build_pkg zfs-dkms

echo "==> Updating repo database"
repo-add "$REPODIR/customzfs.db.tar.gz" "$REPODIR"/*.pkg.tar.zst

# Clean transient build output
rm -rf "$AUR_BUILDDIR"

echo "==> AUR build complete"