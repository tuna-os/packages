#!/usr/bin/env bash
# Push RPM to GHCR as ORAS artifact with metadata

set -euo pipefail

# Configuration
REGISTRY="${REGISTRY:-ghcr.io}"
REPOSITORY="${REPOSITORY:-tuna-os/packages}"

usage() {
    cat <<EOF
Usage: $0 <rpm-file>

Push an RPM file to GHCR as an ORAS artifact.

Example:
    $0 gnome-shell-48.0-1.el10.x86_64_v2.rpm

Environment variables:
    REGISTRY    - Container registry (default: ghcr.io)
    REPOSITORY  - Repository path (default: tuna-os/packages)
    GITHUB_TOKEN - Authentication token for GHCR
EOF
    exit 1
}

# Check arguments
if [ $# -ne 1 ]; then
    usage
fi

RPM_FILE="$1"

if [ ! -f "${RPM_FILE}" ]; then
    echo "Error: RPM file not found: ${RPM_FILE}" >&2
    exit 1
fi

# Extract RPM metadata
PKG_NAME=$(rpm -qp "${RPM_FILE}" --queryformat='%{NAME}' 2>/dev/null)
PKG_VERSION=$(rpm -qp "${RPM_FILE}" --queryformat='%{VERSION}' 2>/dev/null)
PKG_RELEASE=$(rpm -qp "${RPM_FILE}" --queryformat='%{RELEASE}' 2>/dev/null)
PKG_ARCH=$(rpm -qp "${RPM_FILE}" --queryformat='%{ARCH}' 2>/dev/null)
PKG_SUMMARY=$(rpm -qp "${RPM_FILE}" --queryformat='%{SUMMARY}' 2>/dev/null)
PKG_LICENSE=$(rpm -qp "${RPM_FILE}" --queryformat='%{LICENSE}' 2>/dev/null)

# Construct OCI tag
TAG="${PKG_VERSION}-${PKG_RELEASE}-${PKG_ARCH}-el10"
FULL_REF="${REGISTRY}/${REPOSITORY}/${PKG_NAME}:${TAG}"

echo "Pushing RPM to GHCR..."
echo "  Package: ${PKG_NAME}"
echo "  Version: ${PKG_VERSION}-${PKG_RELEASE}"
echo "  Architecture: ${PKG_ARCH}"
echo "  Tag: ${TAG}"
echo "  Reference: ${FULL_REF}"
echo

# Login to GHCR if token available
if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "${GITHUB_TOKEN}" | oras login "${REGISTRY}" --username "${GITHUB_ACTOR:-tuna-os}" --password-stdin
fi

# Push with ORAS including annotations
oras push "${FULL_REF}" \
    "${RPM_FILE}:application/x-rpm" \
    --annotation "org.opencontainers.image.title=${PKG_NAME}" \
    --annotation "org.opencontainers.image.version=${PKG_VERSION}-${PKG_RELEASE}" \
    --annotation "org.opencontainers.image.description=${PKG_SUMMARY}" \
    --annotation "org.opencontainers.image.licenses=${PKG_LICENSE}" \
    --annotation "com.tunaos.package.name=${PKG_NAME}" \
    --annotation "com.tunaos.package.version=${PKG_VERSION}" \
    --annotation "com.tunaos.package.release=${PKG_RELEASE}" \
    --annotation "com.tunaos.package.arch=${PKG_ARCH}" \
    --annotation "com.tunaos.package.el_version=10"

echo
echo "✓ Successfully pushed: ${FULL_REF}"

# Also tag as 'latest' for this arch
LATEST_REF="${REGISTRY}/${REPOSITORY}/${PKG_NAME}:latest-${PKG_ARCH}-el10"
echo
echo "Tagging as latest for architecture..."
oras tag "${FULL_REF}" "latest-${PKG_ARCH}-el10"
echo "✓ Tagged: ${LATEST_REF}"
