#!/usr/bin/env bash
# Main build orchestrator for archiso-zfs
# Idempotent: checks versions before building, uses lock file, safe to run repeatedly
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.env"

# Ensure state directory exists (idempotent)
mkdir -p "$STATEDIR"

# Setup logging
exec > >(tee -a "$LOGFILE") 2>&1
echo "==== $(date '+%Y-%m-%d %H:%M:%S') ===="

# Lock file for cron safety (prevents concurrent builds)
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo "ERROR: Another build is already running (lock file: $LOCKFILE)"
    exit 1
fi

# Get current versions from repos
echo "==> Checking package versions"
CURRENT=$("$SCRIPT_DIR/scripts/get-build-versions.sh")
CURRENT_HASH=$(echo "$CURRENT" | md5sum | awk '{print $1}')

echo "$CURRENT"

# Compare with last build
LAST_HASH_FILE="$STATEDIR/last-build.hash"
if [[ -f "$LAST_HASH_FILE" ]]; then
    LAST_HASH=$(cat "$LAST_HASH_FILE")
    if [[ "$CURRENT_HASH" == "$LAST_HASH" ]]; then
        echo "==> No kernel/ZFS changes detected - skipping build"
        exit 0
    fi
    echo "==> Version changes detected"
else
    echo "==> First build (no previous hash found)"
fi

echo "==> Starting build"

# Build AUR packages (must NOT run as root)
"$SCRIPT_DIR/scripts/build-aur.sh"

# Build ISO (requires root)
sudo "$SCRIPT_DIR/scripts/build-iso.sh"

# Store hash of current versions (only after successful build)
echo "$CURRENT_HASH" > "$LAST_HASH_FILE"

echo "==== BUILD COMPLETE $(date '+%Y-%m-%d %H:%M:%S') ===="