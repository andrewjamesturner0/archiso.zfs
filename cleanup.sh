#!/usr/bin/env bash
# Cleanup script to restore repo to fresh state
# Removes all build artifacts, generated profiles, and temporary directories.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.env"

echo "==> Cleaning up build artifacts..."

# Function to remove directory with checking
remove_dir() {
    if [[ -d "$1" ]]; then
        echo "    Removing $1..."
        # Use sudo if we don't own the directory (e.g. created by root/builder in chroot)
        if [[ -w "$1" ]]; then
            rm -rf "$1"
        else
            sudo rm -rf "$1"
        fi
    fi
}

# 1. Remove project-local artifacts
remove_dir "$OUTDIR"
remove_dir "$REPODIR"
remove_dir "$PROFILE"
remove_dir "$STATEDIR"

# 2. Remove old legacy build dirs (if they exist from before the fix)
remove_dir "$PROJECT_ROOT/work"
remove_dir "$PROJECT_ROOT/_chroot"
remove_dir "$PROJECT_ROOT/_aurbuild"

# 3. Remove new external build dirs (in /var/tmp)
# Defined in common.env as BUILD_ROOT
if [[ -n "${BUILD_ROOT:-}" && "$BUILD_ROOT" != "/" ]]; then
    remove_dir "$BUILD_ROOT"
fi

echo "==> Cleanup complete."
echo "    To restart from scratch, run:"
echo "    ./setup-vm.sh"
echo "    ./build.sh"
