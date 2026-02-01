#!/usr/bin/env bash
# Setup script for a fresh Arch Linux VM or WSL environment
# Installs necessary dependencies for building Archiso ZFS

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Updating system and installing dependencies..."
pacman -Syu --noconfirm --needed base-devel archiso git curl devtools pacman-contrib dos2unix

echo "==> Configuring sudoers for build user..."
if [[ -f "$SCRIPT_DIR/sudoers.d/archiso-zfs" ]]; then
    # Replace {{SCRIPT_DIR}} with actual path
    sed "s|{{SCRIPT_DIR}}|$SCRIPT_DIR|g" "$SCRIPT_DIR/sudoers.d/archiso-zfs" > /etc/sudoers.d/archiso-zfs
    chmod 440 /etc/sudoers.d/archiso-zfs
    echo "    Installed /etc/sudoers.d/archiso-zfs with path: $SCRIPT_DIR"
else
    echo "WARNING: sudoers.d/archiso-zfs not found in script directory"
fi

echo "==> Setting up build user..."
BUILD_USER="builder"
if ! id "$BUILD_USER" &>/dev/null; then
    echo "    Creating user '$BUILD_USER'..."
    useradd -m -G wheel -s /bin/bash "$BUILD_USER"
    echo "$BUILD_USER:$BUILD_USER" | chpasswd
    echo "    User '$BUILD_USER' created with password '$BUILD_USER'"
else
    echo "    User '$BUILD_USER' already exists"
fi

echo "==> Importing ZFS signing keys..."
# Import OpenZFS key for verification
# Key ID: 6AD860EED4598027
# Owner:  Tony Hutter (GPG key for signing ZFS releases) <hutter2@llnl.gov>
KEY_ID="6AD860EED4598027"
if ! su - "$BUILD_USER" -c "gpg --list-keys $KEY_ID" &>/dev/null; then
    echo "    Importing key $KEY_ID..."
    su - "$BUILD_USER" -c "gpg --recv-keys $KEY_ID" || echo "WARNING: Failed to import GPG key."
else
    echo "    Key $KEY_ID already exists."
fi

echo "==> Fixing project directory permissions..."
# Ensure the build user owns the project directory so they can build
# Skip hidden/build directories to avoid issues with mounted filesystems or many small files
find "$(dirname "$SCRIPT_DIR")" -maxdepth 1 ! -name "_*" -exec chown -R "$BUILD_USER:$BUILD_USER" {} + || true

echo "==> Setup complete."
echo "    Please log in as '$BUILD_USER' (password: $BUILD_USER) to run the build:"
echo "    su - $BUILD_USER"
echo "    cd $(dirname "$SCRIPT_DIR")"
echo "    ./build.sh"

echo "==> Setting up archiso profile..."
# Copy standard releng profile if it doesn't exist
PROFILE_DIR="$SCRIPT_DIR/profile"
if [[ ! -d "$PROFILE_DIR" ]]; then
    echo "    Copying releng profile to $PROFILE_DIR..."
    cp -r /usr/share/archiso/configs/releng "$PROFILE_DIR"
    
    # Customizations
    echo "    Applying ZFS and Kernel customizations..."
    
    # pacman.conf: Add customzfs repo and enable ParallelDownloads
    cat >> "$PROFILE_DIR/pacman.conf" <<EOF

[customzfs]
SigLevel = Optional TrustAll
Server = file:///repo
EOF
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' "$PROFILE_DIR/pacman.conf"

    # packages.x86_64: Replace linux with linux-lts, broadcom-wl with dkms variant, add ZFS packages
    sed -i 's/^linux$/linux-lts\nlinux-lts-headers/' "$PROFILE_DIR/packages.x86_64"
    sed -i 's/^broadcom-wl$/broadcom-wl-dkms/' "$PROFILE_DIR/packages.x86_64"
    cat >> "$PROFILE_DIR/packages.x86_64" <<EOF
zfs-utils
zfs-dkms
EOF

    # mkinitcpio preset: rename linux -> linux-lts and fix paths
    mv "$PROFILE_DIR/airootfs/etc/mkinitcpio.d/linux.preset" \
       "$PROFILE_DIR/airootfs/etc/mkinitcpio.d/linux-lts.preset"
    sed -i "s|vmlinuz-linux|vmlinuz-linux-lts|g; s|initramfs-linux\.img|initramfs-linux-lts.img|g" \
        "$PROFILE_DIR/airootfs/etc/mkinitcpio.d/linux-lts.preset"

    # mkinitcpio hooks: add zfs hook before filesystems
    sed -i 's/ filesystems/ zfs filesystems/' \
        "$PROFILE_DIR/airootfs/etc/mkinitcpio.conf.d/archiso.conf"

    # Bootloader configs: update kernel/initramfs filenames for linux-lts
    find "$PROFILE_DIR" \( -path '*/efiboot/*' -o -path '*/grub/*' -o -path '*/syslinux/*' \) \
        -type f -exec sed -i 's/vmlinuz-linux/vmlinuz-linux-lts/g; s/initramfs-linux\.img/initramfs-linux-lts.img/g' {} +

    # profiledef.sh: rename ISO to archlinux.zfs and add timestamp to version
    sed -i 's/^iso_name="archlinux"$/iso_name="archlinux.zfs"/' "$PROFILE_DIR/profiledef.sh"
    sed -i 's/+%Y\.%m\.%d)/+%Y.%m.%d-%H%M%S)/' "$PROFILE_DIR/profiledef.sh"

    # Fix permissions for the build user
    chown -R "$BUILD_USER:$BUILD_USER" "$PROFILE_DIR"
    echo "    Profile setup complete."
else
    echo "    Profile directory already exists, skipping generation."
fi
