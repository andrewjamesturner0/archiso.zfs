#!/usr/bin/env bash
# Cron wrapper for archiso-zfs build
# Idempotent: just calls build.sh which handles all idempotency
#
# Example crontab entry (daily at 3am):
#   0 3 * * * /path/to/archiso.zfs/cron-build.sh
#
# Prerequisites:
#   - Passwordless sudo configured for the build user
#   - All build dependencies installed (archiso, devtools, base-devel, git)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Ensure PATH includes necessary tools
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# Run the build
exec ./build.sh
