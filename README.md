# TunaOS Package Repository

RPM package builds for TunaOS, targeting CentOS Stream / AlmaLinux 10 (EL10). Packages are built via GitHub Actions and published to GitHub Container Registry (GHCR) as ORAS artifacts.

## Packages

The `packages/` directory contains one subdirectory per package, each with a `package.yaml` metadata file:

| Package | Description |
|---------|-------------|
| `gnome-shell` | GNOME Shell for EL10 |
| `mutter` | GNOME compositor/window manager |
| `gdm` | GNOME Display Manager |
| `gtk4` | GTK 4 toolkit |
| `libadwaita` | GNOME HIG widget library |
| `mutter` | GNOME compositor |
| `gnome-control-center` | GNOME Settings |
| `gnome-session` | GNOME session manager |
| `gnome-settings-daemon` | GNOME settings daemon |
| `gnome-initial-setup` | First-run wizard |
| `gsettings-desktop-schemas` | GSettings schemas |
| `xdg-desktop-portal` | Desktop portal |
| `xdg-desktop-portal-gnome` | GNOME desktop portal backend |
| `pango` | Text layout library |
| `poppler` | PDF rendering library |
| `libcupsfilters` | CUPS filters library |
| `tecla` | On-screen keyboard |
| `glib2` | GLib core library |
| `morewaita-icon-theme` | MoreWaita icon theme |
| `tailscale` | Tailscale mesh VPN client |

## Package Metadata Format

Each `package.yaml` defines how to fetch and build the package:

```yaml
name: gnome-shell
version: "48.3"
release: "7.el10"
source:
  # Source type: copr | srpm | rpm | git
  type: copr
  copr: jreilly1821/c10s-gnome    # For copr type: enable this COPR and dnf download
arches:
  - x86_64
  - x86_64_v2
  - aarch64
el_version: 10
```

### Source types

| Type | Behaviour |
|------|-----------|
| `copr` | Enables the specified COPR repo inside an EL10 container and runs `dnf download` to fetch the pre-built RPM |
| `srpm` | Downloads a source RPM and rebuilds it with `rpmbuild` |
| `rpm` | Downloads a pre-built binary RPM directly (e.g. Tailscale upstream) |
| `git` | Clones a git repo, creates a tarball, and builds a minimal spec |

An optional `spec_source` block overrides the spec file used during an SRPM rebuild:

```yaml
spec_source:
  type: local                      # 'local' = spec file checked in to this repo
  repo: https://src.fedoraproject.org/forks/jreilly1821/rpms/gnome-shell.git
  branch: rawhide-el10+-no-x11
```

## Architecture Support

| Arch | Notes |
|------|-------|
| `x86_64` | Standard x86_64 |
| `x86_64_v2` | Optimized for AlmaLinux Kitten / newer CPUs (`-march=x86-64-v2`) |
| `aarch64` | ARM64, runs on `ubuntu-24.04-arm` runners |

## ORAS Artifact Naming

Built RPMs are published to GHCR with the format:

```
ghcr.io/tuna-os/packages/PACKAGE:VERSION-RELEASE-ARCH-el10
```

Example:
```
ghcr.io/tuna-os/packages/gnome-shell:48.3-7.el10-x86_64_v2-el10
```

## Workflows

| Workflow | Trigger | Description |
|----------|---------|-------------|
| `build-gnome48.yml` | Push to `packages/**` or manual | Builds all GNOME packages |
| `build-morewaita.yml` | Push to `packages/morewaita-icon-theme/**` or manual | Builds MoreWaita icon theme |
| `build-tailscale.yml` | Push to `packages/tailscale/**` or manual | Builds Tailscale RPM |
| `rebuild-all.yml` | Scheduled / manual | Rebuilds every package |
| `reusable-build-package.yml` | Called by other workflows | Core build logic |

Trigger a manual build:

```bash
gh workflow run build-gnome48.yml
gh workflow run rebuild-all.yml
```

## Local Development

### Prerequisites

- `podman` (for `copr` source type builds)
- `rpmbuild` (for `srpm`/`git` source type builds)
- `yq` or Python 3 with `pyyaml`
- `oras` CLI (for pushing to GHCR)

### Build a package locally

```bash
./scripts/rebuild-package.sh <package-name> <arch>

# Examples:
./scripts/rebuild-package.sh gnome-shell x86_64_v2
./scripts/rebuild-package.sh morewaita-icon-theme x86_64
./scripts/rebuild-package.sh tailscale aarch64
```

The script writes the built RPM path to stdout (fd3) and logs to stderr. Output lands in `./build-output/` by default; override with `OUTPUT_DIR=`.

### Push to GHCR

```bash
export GITHUB_TOKEN=<your_token>
./scripts/oras-push.sh path/to/package.rpm
```

### Pull from GHCR

```bash
./scripts/oras-pull.sh <package-name> <version-tag>
```

## Adding a New Package

1. Create `packages/<package-name>/package.yaml`:

   ```yaml
   name: my-package
   version: "1.0"
   release: "1"
   source:
     type: srpm
     url: https://kojipkgs.fedoraproject.org/.../my-package-1.0-1.fc42.src.rpm
   arches:
     - x86_64
     - x86_64_v2
     - aarch64
   el_version: 10
   ```

2. If the package needs a spec override, add `<package-name>.spec` alongside `package.yaml`.

3. Add the package path to the appropriate workflow trigger in `.github/workflows/`.

4. Open a PR — CI will build and publish the RPM on merge.
