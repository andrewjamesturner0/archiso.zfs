# ArchISO with ZFS (DKMS)

Automated build system for creating Arch Linux installer ISOs with built-in ZFS support. The ISO boots with ZFS modules pre-compiled and ready to use.

## Environment Setup

This build system is designed to run on **Arch Linux** host environments. It has been tested and optimized for:
- **Native Arch Linux**: Standard bare-metal or VM installations.
- **Arch Linux on WSL2**: Fully supported. Automated path handling (in `/var/tmp`) ensures high performance on Windows-mounted filesystems.
- **Vagrant Boxes**: Works with `archlinux/archlinux` or similar boxes.

If you are starting on a fresh environment, use the automated setup script:

```bash
# Must run as root
sudo ./setup-vm.sh
```

This script will:
1. Install all necessary host dependencies (`archiso`, `devtools`, etc.)
2. Configure `sudoers` for the build environment
3. Create a dedicated `builder` user
4. Import OpenZFS GPG signing keys
5. Initialize a customized ArchISO profile (based on `releng`)
6. Configure the local ZFS repository and `linux-lts` kernel settings

## Quick Start

After setup, run the main build script as the `builder` user:

```bash
su - builder
cd path/to/repo
./build.sh
```

The build will:
1. Check if kernel or ZFS versions have changed since last build
2. Skip the build if versions are unchanged (idempotent)
3. Build `zfs-utils` and `zfs-dkms` from AUR in a clean chroot
4. Build the ISO with ZFS modules pre-compiled via DKMS
5. Store version hash to enable future skip detection

Output ISOs are written to `out/` (keeps the last 3 builds).

---

## How It Works

### Build Flow

```
build.sh (orchestrator)
    │
    ├─► get-build-versions.sh
    │       └─► Queries pacman repos + AUR API for latest versions
    │
    ├─► Compares version hash with previous build
    │       └─► Exits early if unchanged
    │
    ├─► build-aur.sh (runs as user)
    │       ├─► Creates/updates clean chroot via mkarchroot
    │       ├─► Clones zfs-utils and zfs-dkms from AUR
    │       ├─► Builds packages via extra-x86_64-build
    │       └─► Copies .pkg.tar.zst to repo/ and updates database
    │
    └─► build-iso.sh (runs as root)
            ├─► Bind mounts repo/ to /repo
            ├─► Runs mkarchiso with custom profile
            ├─► DKMS compiles ZFS modules during build
            └─► Rotates old ISOs, keeping last 3
```

### Key Design Decisions

- **DKMS approach**: ZFS modules are compiled during ISO build, not at boot time.
- **linux-lts kernel**: Stable kernel for better ZFS compatibility.
- **Clean chroot builds**: Ensures reproducible AUR package builds.
- **Local pacman repo**: Custom packages exposed to `mkarchiso` via bind mount at `/repo`.
- **Version-based skip**: Only rebuilds when kernel or ZFS versions change.
- **WSL/Mount performance**: Ephemeral build directories are located in `/var/tmp` to avoid slow Windows filesystem performance and permission issues.

---

## Scripts Reference

### `setup-vm.sh` - Initial Provisioning
Prepares a fresh system for building. Installs dependencies, creates the build user, and initializes the ISO profile. MUST run as root.
- **WSL Tip**: On WSL, ensure you are running an Arch-based distribution.
- **Vagrant Tip**: Run this once inside your Vagrant guest to provision the build environment.

### `cleanup.sh` - Repository Reset
Restores the repository to a pristine state by removing all build artifacts, temporary directories, and generated profiles.

### `build.sh` - Main Orchestrator
Entry point for all builds. Handles version checking, logging, and coordination.
- File locking (`flock`) prevents concurrent builds.
- Logs all output to `state/build.log`.
- Compares MD5 hash of versions to detect changes.

### `scripts/build-aur.sh` - AUR Package Builder
Builds ZFS packages from AUR in a clean chroot environment.
- **Must NOT run as root**.
- Handles CRLF to LF conversion for Windows filesystem compatibility.
- Builds via `extra-x86_64-build`.

### `scripts/build-iso.sh` - ISO Builder
Creates the bootable ISO using `mkarchiso`.
- **Must run as root**.
- Bind mounts `repo/` to `/repo`.
- Rotates old ISOs (keeps last 3).

### `scripts/common.env` - Shared Configuration
Defines paths and shared variables used by all scripts.

| Variable | Path | Description |
|----------|------|-------------|
| `REPODIR` | `repo/` | Local pacman repository |
| `PROFILE` | `profile/` | ArchISO profile |
| `OUTDIR` | `out/` | Final ISOs |
| `STATEDIR` | `state/` | Build state and logs |
| `BUILD_ROOT`| `/var/tmp/archiso-zfs` | Base for ephemeral build data |
| `WORKDIR` | `$BUILD_ROOT/work` | mkarchiso workdir |
| `CHROOTDIR` | `$BUILD_ROOT/chroot`| Clean build chroot |

---

## Cron Automation

### Setup

1. **Install sudoers configuration:**
   ```bash
   sudo cp sudoers.d/archiso-zfs /etc/sudoers.d/
   sudo chmod 440 /etc/sudoers.d/archiso-zfs
   sudo visudo -c  # Validate syntax
   ```

2. **Add cron job:**
   ```bash
   crontab -e
   ```
   ```
   # Daily at 3am
   0 3 * * * /home/builder/Dev/archiso.zfs/cron-build.sh
   ```

### `cron-build.sh`
Wrapper script that sets up the environment and executes `build.sh`. All output goes to `state/build.log`.

---

## Directory Structure

```
archiso.zfs/
├── setup-vm.sh              # Environment setup (run first)
├── build.sh                 # Main orchestrator
├── cleanup.sh               # Reset environment
├── cron-build.sh            # Cron wrapper
├── scripts/
│   ├── common.env           # Shared configuration
│   ├── build-aur.sh         # AUR package builder
│   ├── build-iso.sh         # ISO builder
│   └── get-build-versions.sh
├── profile/                 # Generated ArchISO profile
├── repo/                    # Local pacman repo
├── state/                   # Build state and logs
└── out/                     # Output ISOs
```

> [!NOTE]
> Ephemeral build directories (`_chroot`, `_aurbuild`, `work`) are located in `/var/tmp/archiso-zfs` to ensure compatibility and performance.

---

## Credits & Caveats

This project was developed with the assistance of **Antigravity**, a powerful agentic AI coding assistant from Google DeepMind.

> [!WARNING]
> While this build system aims for robustness and idempotency, it was generated and refined by an AI. Standard "AI-generated code" caveats apply:
> - **Verify before use**: Always review script logic and sudoers configurations before running on production systems.
> - **Edge cases**: There may be edge cases or specific hardware configurations not fully accounted for.
> - **Security**: Ensure GPG keys and package sources match your security requirements.

### CRLF Errors
The scripts automatically handle CRLF conversion, but if you encounter issues manually:
```bash
dos2unix scripts/*.sh scripts/*.env *.sh
```

### Force Rebuild
```bash
rm state/last-build.hash
./build.sh
```

### Check Build Lock
```bash
# See if lock is held
fuser state/build.lock

# Remove stale lock (only if no build running)
rm state/build.lock
```

---

## Validation

After booting the ISO:
```bash
uname -r              # Should show linux-lts kernel version
modprobe zfs          # Should load without errors
zfs version           # Should display ZFS version
```
