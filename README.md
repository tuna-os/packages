# TunaOS Package Repository

Custom package repository for TunaOS that provides GNOME 48 packages and MoreWaita icon theme as ORAS artifacts in GHCR. Replaces COPR dependencies with full control over package builds and versions.

## Overview

This repository builds RPM packages from upstream sources (Fedora SRPMs/Git) and publishes them to GitHub Container Registry (GHCR) as ORAS artifacts. Supports multi-architecture builds including x86_64_v2 for AlmaLinux Kitten.

**Packages provided:**
- GNOME 48 stack (gnome-shell, mutter, and dependencies)
- MoreWaita icon theme

**Architecture support:**
- x86_64 (standard)
- x86_64_v2 (optimized for AlmaLinux Kitten)
- aarch64 (ARM64)

## Repository Structure

```
packages/
├── gnome-shell/
│   └── package.yaml          # Package metadata and source configuration
├── mutter/
│   └── package.yaml
├── morewaita-icon-theme/
│   └── package.yaml
└── ...

scripts/
├── oras-push.sh              # Push RPM to GHCR with ORAS
├── oras-pull.sh              # Pull RPM from GHCR
└── rebuild-package.sh        # Orchestrate mock build

.github/workflows/
├── reusable-build-package.yml  # Core package build workflow
├── build-gnome48.yml          # GNOME 48 packages
└── build-morewaita.yml        # MoreWaita icon theme
```

## Package Metadata Format

Each package directory contains a `package.yaml` file:

```yaml
name: gnome-shell
version: "48.0"
release: "1"
source:
  type: srpm  # or 'git', 'tarball'
  url: https://kojipkgs.fedoraproject.org/packages/gnome-shell/48.0/1.fc42/src/gnome-shell-48.0-1.fc42.src.rpm
arches:
  - x86_64
  - x86_64_v2
  - aarch64
el_version: 10  # Target EL version for rebuild
```

## ORAS Artifact Naming

Artifacts are published to GHCR with the format:

```
ghcr.io/tuna-os/packages/PACKAGE:VERSION-RELEASE-ARCH-el10
```

Examples:
- `ghcr.io/tuna-os/packages/gnome-shell:48.0-1-x86_64_v2-el10`
- `ghcr.io/tuna-os/packages/morewaita-icon-theme:46-1-x86_64-el10`

## Usage in TunaOS Builds

The tunaOS main repository includes a download script that pulls packages during build:

```bash
# In tunaOS build_scripts/
./download-tuna-packages.sh
```

Packages are cached locally and installed during the build process.

## Triggering Builds

### Automatic (Renovate)
Renovate monitors upstream sources and creates PRs when new versions are available. After merge, workflows automatically rebuild packages.

### Manual
Trigger builds via GitHub Actions:
```bash
gh workflow run build-gnome48.yml
gh workflow run build-morewaita.yml
```

### Rebuild All
Weekly scheduled rebuilds ensure packages stay current with security updates:
```bash
gh workflow run rebuild-all.yml
```

## Development Workflow

1. **Add a new package:**
   ```bash
   mkdir -p packages/package-name
   cat > packages/package-name/package.yaml <<EOF
   name: package-name
   version: "1.0"
   release: "1"
   source:
     type: srpm
     url: https://...
   arches: [x86_64, x86_64_v2, aarch64]
   el_version: 10
   EOF
   ```

2. **Test build locally:**
   ```bash
   ./scripts/rebuild-package.sh package-name x86_64_v2
   ```

3. **Push to GHCR:**
   ```bash
   ./scripts/oras-push.sh package-name-1.0-1.el10.x86_64_v2.rpm
   ```

## Architecture-Specific Builds

### x86_64_v2 Support
Packages built for x86_64_v2 use optimized compiler flags in mock:

```bash
config_opts['target_arch'] = 'x86_64'
config_opts['macros']['%optflags'] = '-O2 -g -march=x86-64-v2'
```

This provides ~10-20% performance improvement on newer CPUs while maintaining compatibility with AlmaLinux 10.

## Signing

All RPMs are signed with the TunaOS GPG key before being pushed to GHCR:

```bash
rpm --addsign package.rpm
```

ORAS artifacts include cosign signatures for verification:

```bash
cosign verify ghcr.io/tuna-os/packages/gnome-shell:48.0-1-x86_64_v2-el10
```

## Renovate Configuration

See `renovate.json5` for automated dependency tracking. Custom datasources:
- **Fedora Koji**: Monitors GNOME packages in Fedora builds
- **GitHub Releases**: Tracks MoreWaita upstream releases

## Initial Setup

### Prerequisites
- GitHub repository created at `tuna-os/packages`
- GHCR write permission (via `GITHUB_TOKEN`)
- GPG signing key configured in repository secrets
- `oras` CLI installed (available in GitHub Actions runners by default)

### First-Time Setup
1. Clone this repository
2. Configure GitHub secrets:
   - `COSIGN_PRIVATE_KEY` - for signing artifacts
   - `GPG_PRIVATE_KEY` - for signing RPMs
   - `GPG_PASSPHRASE` - GPG key passphrase
3. Run initial package population:
   ```bash
   gh workflow run build-gnome48.yml
   gh workflow run build-morewaita.yml
   ```

## Integration with TunaOS

See the main [tunaOS repository](https://github.com/tuna-os/tunaOS) for integration details. The `build_scripts/download-tuna-packages.sh` script automatically pulls packages during OS image builds.

## License

Same as TunaOS main repository - see LICENSE file.

## Contributing

This is an internal package repository for TunaOS. For package requests or issues, please file them in the main [tunaOS repository](https://github.com/tuna-os/tunaOS/issues).
