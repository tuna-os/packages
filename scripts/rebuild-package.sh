#!/usr/bin/env bash
# Rebuild a package for EL10 using rpmbuild

set -euo pipefail

# Redirect all diagnostic output to stderr.
# The RPM path is written to fd3 (original stdout) at the very end.
exec 3>&1 1>&2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
    cat <<EOF
Usage: $0 <package-name> <arch>

Build an RPM package for AlmaLinux 10-compatible systems.

Arguments:
    package-name  - Package name matching directory in packages/ (e.g., gnome-shell)
    arch          - Target architecture (x86_64, x86_64_v2, aarch64)

Examples:
    $0 gnome-shell x86_64_v2
    $0 morewaita-icon-theme x86_64

Environment variables:
    OUTPUT_DIR    - Build output directory (default: ./build-output)
EOF
    exit 1
}

# Check arguments
if [ $# -ne 2 ]; then
    usage
fi

PACKAGE_NAME="$1"
ARCH="$2"

PACKAGE_DIR="${REPO_ROOT}/packages/${PACKAGE_NAME}"
PACKAGE_YAML="${PACKAGE_DIR}/package.yaml"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/build-output}"
LOCAL_SPEC_FILE="${PACKAGE_DIR}/${PACKAGE_NAME}.spec"

# Verify package exists
if [ ! -f "${PACKAGE_YAML}" ]; then
    echo "Error: Package not found: ${PACKAGE_NAME}" >&2
    echo "  Expected: ${PACKAGE_YAML}" >&2
    exit 1
fi

echo "Building package: ${PACKAGE_NAME}"
echo "  Architecture: ${ARCH}"
echo "  Package dir: ${PACKAGE_DIR}"
echo

# Parse package.yaml (requires yq or python with pyyaml)
if command -v yq &>/dev/null; then
    SOURCE_TYPE=$(yq eval '.source.type' "${PACKAGE_YAML}")
    SOURCE_URL=$(yq eval '.source.url' "${PACKAGE_YAML}")
    PKG_VERSION=$(yq eval '.version' "${PACKAGE_YAML}")
    PKG_RELEASE=$(yq eval '.release' "${PACKAGE_YAML}")
    SPEC_SOURCE_URL=$(yq eval '.spec_source.url // ""' "${PACKAGE_YAML}")
elif python3 -c "import yaml" 2>/dev/null; then
    eval "$(python3 <<EOF
import yaml
with open('${PACKAGE_YAML}') as f:
    data = yaml.safe_load(f)
    print(f"SOURCE_TYPE='{data['source']['type']}'")
    print(f"SOURCE_URL='{data['source']['url']}'")
    print(f"PKG_VERSION='{data['version']}'")
    print(f"PKG_RELEASE='{data['release']}'")
    spec = data.get('spec_source', {}) or {}
    print(f"SPEC_SOURCE_URL='{spec.get('url', '')}'")
EOF
)"
else
    echo "Error: Neither yq nor python with pyyaml found" >&2
    echo "Please install one of them to parse package.yaml" >&2
    exit 1
fi

echo "  Source type: ${SOURCE_TYPE}"
echo "  Source URL: ${SOURCE_URL}"
if [ -f "${LOCAL_SPEC_FILE}" ]; then
    echo "  Local spec override: ${LOCAL_SPEC_FILE}"
fi
if [ -n "${SPEC_SOURCE_URL}" ]; then
    echo "  Spec override: ${SPEC_SOURCE_URL}"
fi
echo "  Version: ${PKG_VERSION}-${PKG_RELEASE}"
echo

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Download source
SOURCES_DIR="${OUTPUT_DIR}/SOURCES"
mkdir -p "${SOURCES_DIR}"

# For COPR type: use dnf download inside a container to fetch pre-built RPMs
if [ "${SOURCE_TYPE}" = "copr" ]; then
    if command -v yq &>/dev/null; then
        COPR_REPO=$(yq eval '.source.copr' "${PACKAGE_YAML}")
    else
        COPR_REPO=$(python3 -c "import yaml; d=yaml.safe_load(open('${PACKAGE_YAML}')); print(d['source']['copr'])")
    fi

    RPM_ARCH="${ARCH}"
    if [ "${RPM_ARCH}" = "x86_64_v2" ]; then
        RPM_ARCH="x86_64"
    fi

    echo "Downloading from COPR: ${COPR_REPO} (arch: ${RPM_ARCH})..."

    # Run dnf download inside an EL10 container so we get the correct binaries
    podman run --rm \
        --arch="${RPM_ARCH}" \
        -v "${OUTPUT_DIR}:/output:Z" \
        quay.io/almalinuxorg/almalinux-bootc:10 \
        /bin/bash -exc "
            dnf -y install 'dnf-command(copr)' &>/dev/null
            dnf -y copr enable '${COPR_REPO}'
            dnf -y download --arch '${RPM_ARCH}' --destdir /output/SOURCES '${PACKAGE_NAME}'
        "

    DOWNLOADED_RPM=$(find "${SOURCES_DIR}" -name "${PACKAGE_NAME}-*.rpm" -not -name "*.src.rpm" | head -n1)
    if [ -z "${DOWNLOADED_RPM}" ]; then
        echo "Error: dnf download failed to produce an RPM for ${PACKAGE_NAME}" >&2
        exit 1
    fi

    echo "✓ Downloaded: ${DOWNLOADED_RPM}" >&2
    echo "${DOWNLOADED_RPM}" >&3
    exit 0
fi

case "${SOURCE_TYPE}" in
    srpm)
        echo "Downloading SRPM..."
        SRPM_FILE="${SOURCES_DIR}/$(basename "${SOURCE_URL}")"
        curl -L -o "${SRPM_FILE}" "${SOURCE_URL}"
        echo "✓ Downloaded: ${SRPM_FILE}"
        ;;
    rpm)
        echo "Downloading binary RPM..."
        RPM_ARCH="${ARCH}"
        if [ "${RPM_ARCH}" = "x86_64_v2" ]; then
            # Tailscale and other upstream repos publish x86_64, not x86_64_v2.
            RPM_ARCH="x86_64"
        fi
        RPM_URL="${SOURCE_URL//\{arch\}/${RPM_ARCH}}"
        DOWNLOADED_RPM="${SOURCES_DIR}/$(basename "${RPM_URL}")"
        curl -L -o "${DOWNLOADED_RPM}" "${RPM_URL}"
        echo "✓ Downloaded: ${DOWNLOADED_RPM}"
        ;;
    git)
        echo "Cloning git repository..."
        GIT_TAG=$(yq eval '.source.tag' "${PACKAGE_YAML}" 2>/dev/null || echo "main")
        GIT_DIR="${SOURCES_DIR}/${PACKAGE_NAME}-git"
        rm -rf "${GIT_DIR}"
        git clone --depth 1 --branch "${GIT_TAG}" "${SOURCE_URL}" "${GIT_DIR}"
        
        # Create tarball from git checkout
        TARBALL="${SOURCES_DIR}/${PACKAGE_NAME}-${PKG_VERSION}.tar.gz"
        tar czf "${TARBALL}" -C "$(dirname "${GIT_DIR}")" "$(basename "${GIT_DIR}")"
        echo "✓ Created tarball: ${TARBALL}"
        
        # Build directly from generated spec for simple git-backed packages.
        ;;
    *)
        echo "Error: Unsupported source type: ${SOURCE_TYPE}" >&2
        exit 1
        ;;
esac

# Build with rpmbuild
echo
echo "Building RPM with rpmbuild..."
echo

RPMBUILD_TOPDIR="${OUTPUT_DIR}/rpmbuild"
mkdir -p "${RPMBUILD_TOPDIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

TARGET_ARCH="${ARCH}"
OPTFLAGS="-O2 -g"
if [ "${ARCH}" = "x86_64_v2" ]; then
    # rpmbuild doesn't know x86_64_v2 as an RPM arch; build x86_64 with v2 flags.
    TARGET_ARCH="x86_64"
    OPTFLAGS="-O2 -g -march=x86-64-v2 -mtune=generic"
fi

if [ "${SOURCE_TYPE}" = "rpm" ]; then
    mkdir -p "${RPMBUILD_TOPDIR}/RPMS/${TARGET_ARCH}"
    cp -f "${DOWNLOADED_RPM}" "${RPMBUILD_TOPDIR}/RPMS/${TARGET_ARCH}/"
elif [ "${SOURCE_TYPE}" = "srpm" ]; then
    if [ -f "${LOCAL_SPEC_FILE}" ] || [ -n "${SPEC_SOURCE_URL}" ]; then
        # For forked spec workflows (Pagure), unpack SRPM, replace spec, then build.
        rpm -ivh --define "_topdir ${RPMBUILD_TOPDIR}" "${SRPM_FILE}" >/dev/null

        SPEC_FILE="${RPMBUILD_TOPDIR}/SPECS/${PACKAGE_NAME}.spec"

        if [ -f "${LOCAL_SPEC_FILE}" ]; then
            echo "Using local spec override..."
            cp -f "${LOCAL_SPEC_FILE}" "${SPEC_FILE}"
        else
            echo "Downloading spec override..."
            curl -L -o "${SPEC_FILE}" "${SPEC_SOURCE_URL}"
        fi

        rpmbuild \
            -ba "${SPEC_FILE}" \
            --target "${TARGET_ARCH}" \
            --define "_topdir ${RPMBUILD_TOPDIR}" \
            --define "optflags ${OPTFLAGS}" \
            --define "_disable_source_fetch 0"
    else
        rpmbuild \
            --rebuild "${SRPM_FILE}" \
            --target "${TARGET_ARCH}" \
            --define "_topdir ${RPMBUILD_TOPDIR}" \
            --define "optflags ${OPTFLAGS}" \
            --define "_disable_source_fetch 0"
    fi
else
    # Generic, minimal packaging path for git source packages like MoreWaita.
    SPEC_FILE="${RPMBUILD_TOPDIR}/SPECS/${PACKAGE_NAME}.spec"
    cp "${TARBALL}" "${RPMBUILD_TOPDIR}/SOURCES/"

    cat > "${SPEC_FILE}" <<EOF
Name:           ${PACKAGE_NAME}
Version:        ${PKG_VERSION}
Release:        ${PKG_RELEASE}%{?dist}
Summary:        ${PACKAGE_NAME} packaged for TunaOS
License:        GPL-3.0-or-later
BuildArch:      noarch
Source0:        $(basename "${TARBALL}")

%description
${PACKAGE_NAME} package built by TunaOS packages automation.

%prep
%autosetup -n ${PACKAGE_NAME}-git

%build

%install
mkdir -p %{buildroot}/usr/share/${PACKAGE_NAME}
cp -a . %{buildroot}/usr/share/${PACKAGE_NAME}/

%files
/usr/share/${PACKAGE_NAME}

%changelog
* Tue Mar 10 2026 TunaOS Automation <noreply@tunaos.local> - ${PKG_VERSION}-${PKG_RELEASE}
- Automated package build
EOF

    rpmbuild \
        -ba "${SPEC_FILE}" \
        --define "_topdir ${RPMBUILD_TOPDIR}"
fi

echo
echo "✓ Build complete"
echo "  Output directory: ${RPMBUILD_TOPDIR}/RPMS"
find "${RPMBUILD_TOPDIR}/RPMS" -name "*.rpm" -type f -print -exec ls -lh {} \; | head -n 20 || echo "  No RPMs found"

# Find built RPM
BUILT_RPM=$(find "${RPMBUILD_TOPDIR}/RPMS" -name "${PACKAGE_NAME}[-_]*.rpm" -type f ! -name "*.src.rpm" | head -n1)

if [ -n "${BUILT_RPM}" ] && [ -f "${BUILT_RPM}" ]; then
    echo
    echo "✓ Built RPM: ${BUILT_RPM}"
    rpm -qip "${BUILT_RPM}" 2>/dev/null || true
    
    # Return path for use in CI
    echo "${BUILT_RPM}" >&3
else
    echo "Error: No RPM built" >&2
    exit 1
fi
