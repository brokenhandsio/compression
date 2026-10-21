#!/usr/bin/env bash
#
# vendor-zstd.sh
# Downloads and vendors zstd source into Sources/CZstd
# so it can be built as a Swift-PM C target.
#
# Usage:
#   ./Scripts/vendor-zstd.sh          # uses default version
#   ./Scripts/vendor-zstd.sh 1.5.7    # specify version
#
set -euo pipefail

ZSTD_VERSION="${1:-1.5.7}"
ZSTD_URL="https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CZSTD_DIR="${PROJECT_ROOT}/Sources/CZstd"
WORK_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "==> Vendoring zstd ${ZSTD_VERSION}"
echo "    URL: ${ZSTD_URL}"
echo "    Destination: ${CZSTD_DIR}"

# ---------------------------------------------------------------------------
# 1. Download, extract
# ---------------------------------------------------------------------------
echo "==> Downloading zstd ${ZSTD_VERSION}..."
curl -fsSL "${ZSTD_URL}" -o "${WORK_DIR}/zstd.tar.gz"

echo "==> Extracting..."
tar xzf "${WORK_DIR}/zstd.tar.gz" -C "${WORK_DIR}"

ZSTD_SRC="${WORK_DIR}/zstd-${ZSTD_VERSION}"
if [[ ! -d "${ZSTD_SRC}" ]]; then
    echo "Error: Expected source directory ${ZSTD_SRC} not found." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Prepare destination (preserving any hand-maintained umbrella header)
# ---------------------------------------------------------------------------
echo "==> Preparing ${CZSTD_DIR}..."
if [[ ! -f "${CZSTD_DIR}/include/CZstd.h" ]]; then
    echo "Error: ${CZSTD_DIR}/include/CZstd.h is missing." >&2
    echo "       It is written by hand and cannot be regenerated; restore it from git first." >&2
    exit 1
fi
rm -rf "${CZSTD_DIR}/lib"
mkdir -p "${CZSTD_DIR}/lib"

ZSTD_FOLDERS=(
    common
    compress
    decompress
)

ZSTD_PUBLIC_HEADERS=(
    zstd.h
    zstd_errors.h
)

# ---------------------------------------------------------------------------
# 3. Copy source files
# ---------------------------------------------------------------------------
echo "==> Copying source files..."
for f in "${ZSTD_FOLDERS[@]}"; do
    cp -r "${ZSTD_SRC}/lib/${f}" "${CZSTD_DIR}/lib/${f}"
done

for f in "${ZSTD_PUBLIC_HEADERS[@]}"; do
    cp "${ZSTD_SRC}/lib/${f}" "${CZSTD_DIR}/lib/${f}"
done

echo ""
echo "==> zstd ${ZSTD_VERSION} vendored successfully into ${CZSTD_DIR}"
