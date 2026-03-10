#!/usr/bin/env bash
# Rebuild a package using mock for EL10

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
    cat <<EOF
Usage: $0 <package-name> <arch>

Build an RPM package using mock for AlmaLinux 10.

Arguments:
    package-name  - Package name matching directory in packages/ (e.g., gnome-shell)
    arch          - Target architecture (x86_64, x86_64_v2, aarch64)

Examples:
    $0 gnome-shell x86_64_v2
    $0 morewaita-icon-theme x86_64

Environment variables:
    MOCK_CONFIG   - Mock configuration (default: almalinux-10-<arch>)
    OUTPUT_DIR    - Build output directory (default: ./build-output)
    BUILDROOT     - Mock buildroot directory (default: /var/lib/mock)
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
MOCK_CONFIG="${MOCK_CONFIG:-almalinux-10-${ARCH}}"

# Verify package exists
if [ ! -f "${PACKAGE_YAML}" ]; then
    echo "Error: Package not found: ${PACKAGE_NAME}" >&2
    echo "  Expected: ${PACKAGE_YAML}" >&2
    exit 1
fi

echo "Building package: ${PACKAGE_NAME}"
echo "  Architecture: ${ARCH}"
echo "  Mock config: ${MOCK_CONFIG}"
echo "  Package dir: ${PACKAGE_DIR}"
echo

# Parse package.yaml (requires yq or python with pyyaml)
if command -v yq &>/dev/null; then
    SOURCE_TYPE=$(yq eval '.source.type' "${PACKAGE_YAML}")
    SOURCE_URL=$(yq eval '.source.url' "${PACKAGE_YAML}")
    PKG_VERSION=$(yq eval '.version' "${PACKAGE_YAML}")
    PKG_RELEASE=$(yq eval '.release' "${PACKAGE_YAML}")
elif python3 -c "import yaml" 2>/dev/null; then
    eval "$(python3 <<EOF
import yaml
with open('${PACKAGE_YAML}') as f:
    data = yaml.safe_load(f)
    print(f"SOURCE_TYPE='{data['source']['type']}'")
    print(f"SOURCE_URL='{data['source']['url']}'")
    print(f"PKG_VERSION='{data['version']}'")
    print(f"PKG_RELEASE='{data['release']}'")
EOF
)"
else
    echo "Error: Neither yq nor python with pyyaml found" >&2
    echo "Please install one of them to parse package.yaml" >&2
    exit 1
fi

echo "  Source type: ${SOURCE_TYPE}"
echo "  Source URL: ${SOURCE_URL}"
echo "  Version: ${PKG_VERSION}-${PKG_RELEASE}"
echo

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Download source
SOURCES_DIR="${OUTPUT_DIR}/SOURCES"
mkdir -p "${SOURCES_DIR}"

case "${SOURCE_TYPE}" in
    srpm)
        echo "Downloading SRPM..."
        SRPM_FILE="${SOURCES_DIR}/$(basename "${SOURCE_URL}")"
        curl -L -o "${SRPM_FILE}" "${SOURCE_URL}"
        echo "✓ Downloaded: ${SRPM_FILE}"
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
        
        # TODO: For git sources, we'd need to create an SRPM
        # This requires a spec file, which should be in the package directory
        echo "Warning: Git source builds require a spec file - not fully implemented yet" >&2
        SRPM_FILE="${TARBALL}"  # Placeholder
        ;;
    *)
        echo "Error: Unsupported source type: ${SOURCE_TYPE}" >&2
        exit 1
        ;;
esac

# Configure mock for x86_64_v2 if needed
if [ "${ARCH}" = "x86_64_v2" ]; then
    echo "Configuring mock for x86_64_v2 build..."
    MOCK_CONFIG_FILE="/etc/mock/${MOCK_CONFIG}.cfg"
    
    # Create custom mock config if it doesn't exist
    if [ ! -f "${MOCK_CONFIG_FILE}" ]; then
        sudo cp "/etc/mock/almalinux-10-x86_64.cfg" "${MOCK_CONFIG_FILE}" || true
        sudo tee -a "${MOCK_CONFIG_FILE}" >/dev/null <<'EOF'

# x86_64_v2 optimizations
config_opts['target_arch'] = 'x86_64'
config_opts['macros']['%optflags'] = '-O2 -g -march=x86-64-v2 -mtune=generic'
config_opts['macros']['%_arch'] = 'x86_64'
EOF
    fi
fi

# Build with mock
echo
echo "Building RPM with mock..."
echo "  Config: ${MOCK_CONFIG}"
echo "  SRPM: ${SRPM_FILE}"
echo

if [ "${SOURCE_TYPE}" = "srpm" ]; then
    mock -r "${MOCK_CONFIG}" --rebuild "${SRPM_FILE}" \
        --resultdir="${OUTPUT_DIR}/RPMS" \
        --verbose
    
    echo
    echo "✓ Build complete"
    echo "  Output directory: ${OUTPUT_DIR}/RPMS"
    ls -lh "${OUTPUT_DIR}/RPMS/"*.rpm 2>/dev/null || echo "  No RPMs found"
else
    echo "Skipping mock build for non-SRPM source (not yet implemented)"
fi

# Find built RPM
BUILT_RPM=$(find "${OUTPUT_DIR}/RPMS" -name "${PACKAGE_NAME}-*.rpm" -type f ! -name "*.src.rpm" | head -n1)

if [ -n "${BUILT_RPM}" ] && [ -f "${BUILT_RPM}" ]; then
    echo
    echo "✓ Built RPM: ${BUILT_RPM}"
    rpm -qip "${BUILT_RPM}" 2>/dev/null || true
    
    # Return path for use in CI
    echo "${BUILT_RPM}"
else
    echo "Error: No RPM built" >&2
    exit 1
fi
