#!/usr/bin/env bash
# Pull RPM from GHCR ORAS artifact

set -euo pipefail

# Configuration
REGISTRY="${REGISTRY:-ghcr.io}"
REPOSITORY="${REPOSITORY:-tuna-os/packages}"
OUTPUT_DIR="${OUTPUT_DIR:-./downloaded-packages}"

usage() {
    cat <<EOF
Usage: $0 <package-name> <version-release> <arch>

Pull an RPM artifact from GHCR using ORAS.

Arguments:
    package-name     - Name of the package (e.g., gnome-shell)
    version-release  - Version-release (e.g., 48.0-1 or 'latest')
    arch             - Architecture (x86_64, x86_64_v2, aarch64)

Examples:
    $0 gnome-shell 48.0-1 x86_64_v2
    $0 morewaita-icon-theme latest x86_64

Environment variables:
    REGISTRY     - Container registry (default: ghcr.io)
    REPOSITORY   - Repository path (default: tuna-os/packages)
    OUTPUT_DIR   - Download destination (default: ./downloaded-packages)
    GITHUB_TOKEN - Authentication token for GHCR (if needed)
EOF
    exit 1
}

# Check arguments
if [ $# -ne 3 ]; then
    usage
fi

PACKAGE_NAME="$1"
VERSION_RELEASE="$2"
ARCH="$3"

# Construct reference
if [ "${VERSION_RELEASE}" = "latest" ]; then
    TAG="latest-${ARCH}-el10"
else
    TAG="${VERSION_RELEASE}-${ARCH}-el10"
fi

FULL_REF="${REGISTRY}/${REPOSITORY}/${PACKAGE_NAME}:${TAG}"

# Create output directory
mkdir -p "${OUTPUT_DIR}"

echo "Pulling RPM from GHCR..."
echo "  Package: ${PACKAGE_NAME}"
echo "  Version: ${VERSION_RELEASE}"
echo "  Architecture: ${ARCH}"
echo "  Reference: ${FULL_REF}"
echo "  Output: ${OUTPUT_DIR}"
echo

# Login to GHCR if token available (may be needed for private repos)
if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "${GITHUB_TOKEN}" | oras login "${REGISTRY}" --username "${GITHUB_ACTOR:-tuna-os}" --password-stdin 2>/dev/null || true
fi

# Pull artifact
cd "${OUTPUT_DIR}"
if oras pull "${FULL_REF}"; then
    echo
    echo "✓ Successfully pulled package"
    
    # Find the downloaded RPM
    RPM_FILE=$(find . -maxdepth 1 -name "*.rpm" -type f | head -n1)
    if [ -n "${RPM_FILE}" ]; then
        echo "  Downloaded: ${RPM_FILE}"
        rpm -qip "${RPM_FILE}" 2>/dev/null || true
    fi
else
    echo "✗ Failed to pull package: ${FULL_REF}" >&2
    exit 1
fi
