#!/usr/bin/env bash
#
# vendor-zlib.sh
# Downloads and vendors zlib source into Sources/Compression/CZlib
# so it can be built as a Swift-PM C target.
#
# Usage:
#   ./Scripts/vendor-zlib.sh          # uses default version
#   ./Scripts/vendor-zlib.sh 1.3.1    # specify version
#
set -euo pipefail

ZLIB_VERSION="${1:-1.3.1}"
ZLIB_URL="https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz"

PREFIX_LC="czlib_z_"
PREFIX_UC="CZLIB_Z_"
PREFIX_ZLIB="CZLIB_ZLIB_"
HEADER_PREFIX="czlib-"  # for renamed header filenames

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CZLIB_DIR="${PROJECT_ROOT}/Sources/CZlib"
WORK_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# Portable in-place sed
sed_inplace() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

echo "==> Vendoring zlib ${ZLIB_VERSION}"
echo "    URL: ${ZLIB_URL}"
echo "    Destination: ${CZLIB_DIR}"

# ---------------------------------------------------------------------------
# 1. Download, extract
# ---------------------------------------------------------------------------
echo "==> Downloading zlib ${ZLIB_VERSION}..."
curl -fsSL "${ZLIB_URL}" -o "${WORK_DIR}/zlib.tar.gz"

echo "==> Extracting..."
tar xzf "${WORK_DIR}/zlib.tar.gz" -C "${WORK_DIR}"

ZLIB_SRC="${WORK_DIR}/zlib-${ZLIB_VERSION}"

if [[ ! -d "${ZLIB_SRC}" ]]; then
    echo "Error: Expected source directory ${ZLIB_SRC} not found." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Prepare destination (preserving any hand-maintained umbrella header)
# ---------------------------------------------------------------------------
echo "==> Preparing ${CZLIB_DIR}..."
PRESERVED_UMBRELLA=""
if [[ -f "${CZLIB_DIR}/include/CZlib.h" ]]; then
    PRESERVED_UMBRELLA="$(cat "${CZLIB_DIR}/include/CZlib.h")"
fi
rm -rf "${CZLIB_DIR}"
mkdir -p "${CZLIB_DIR}/include"
mkdir -p "${CZLIB_DIR}/src"

# ---------------------------------------------------------------------------
# 3. Define file lists
# ---------------------------------------------------------------------------
# Streaming + one-shot compress/uncompress. No gzip FILE* I/O (gz*.c)
# and no callback-inflate (infback.c) — add back if you need them.
ZLIB_C_FILES=(
    adler32.c
    compress.c
    crc32.c
    deflate.c
    inffast.c
    inflate.c
    inftrees.c
    trees.c
    uncompr.c
    zutil.c
)

ZLIB_PRIVATE_HEADERS=(
    crc32.h
    deflate.h
    gzguts.h
    inffast.h
    inffixed.h
    inflate.h
    inftrees.h
    trees.h
    zutil.h
)

ZLIB_PUBLIC_HEADERS=(
    zlib.h
    zconf.h
)

# ---------------------------------------------------------------------------
# 4. Copy source files
# ---------------------------------------------------------------------------
echo "==> Copying source files..."
for f in "${ZLIB_C_FILES[@]}"; do
    cp "${ZLIB_SRC}/${f}" "${CZLIB_DIR}/src/${f}"
done

for h in "${ZLIB_PRIVATE_HEADERS[@]}"; do
    if [[ -f "${ZLIB_SRC}/${h}" ]]; then
        cp "${ZLIB_SRC}/${h}" "${CZLIB_DIR}/src/${HEADER_PREFIX}${h}"
    fi
done

for h in "${ZLIB_PUBLIC_HEADERS[@]}"; do
    cp "${ZLIB_SRC}/${h}" "${CZLIB_DIR}/include/${HEADER_PREFIX}${h}"
done

# ---------------------------------------------------------------------------
# 5. Build list of all vendored files (used by sed sweeps)
# ---------------------------------------------------------------------------
ALL_VENDORED_FILES=()
for f in "${ZLIB_C_FILES[@]}"; do
    ALL_VENDORED_FILES+=("${CZLIB_DIR}/src/${f}")
done
for h in "${ZLIB_PRIVATE_HEADERS[@]}"; do
    if [[ -f "${CZLIB_DIR}/src/${HEADER_PREFIX}${h}" ]]; then
        ALL_VENDORED_FILES+=("${CZLIB_DIR}/src/${HEADER_PREFIX}${h}")
    fi
done
for h in "${ZLIB_PUBLIC_HEADERS[@]}"; do
    ALL_VENDORED_FILES+=("${CZLIB_DIR}/include/${HEADER_PREFIX}${h}")
done

# ---------------------------------------------------------------------------
# 6. Rewrite #include directives for renamed headers
# ---------------------------------------------------------------------------
echo "==> Rewriting #include directives..."
ALL_HEADERS=("${ZLIB_PUBLIC_HEADERS[@]}" "${ZLIB_PRIVATE_HEADERS[@]}")
for h in "${ALL_HEADERS[@]}"; do
    sed_inplace "s|\"${h}\"|\"${HEADER_PREFIX}${h}\"|g" "${ALL_VENDORED_FILES[@]}"
    sed_inplace "s|<${h}>|<${HEADER_PREFIX}${h}>|g" "${ALL_VENDORED_FILES[@]}"
done

# ---------------------------------------------------------------------------
# 7. Activate Z_PREFIX block in zconf.h
# ---------------------------------------------------------------------------
echo "==> Activating Z_PREFIX block..."
sed_inplace "s|^#ifdef Z_PREFIX.*$|#if 1 /* Z_PREFIX - ${PREFIX_LC} */|" \
    "${CZLIB_DIR}/include/${HEADER_PREFIX}zconf.h"

# ---------------------------------------------------------------------------
# 8. Apply prefix to all identifiers
# ---------------------------------------------------------------------------
echo "==> Applying ${PREFIX_LC} prefix..."

# z_  -> czlib_z_   (z_deflate, z_streamp, z_const, z_size_t, etc.)
sed_inplace -E "s/(^|[^a-zA-Z_])z_/\1${PREFIX_LC}/g" "${ALL_VENDORED_FILES[@]}"

# Z_  -> CZLIB_Z_   (Z_OK, Z_FINISH, Z_PREFIX, etc.)
sed_inplace -E "s/(^|[^a-zA-Z_])Z_/\1${PREFIX_UC}/g" "${ALL_VENDORED_FILES[@]}"

# ZLIB_ -> CZLIB_ZLIB_  (ZLIB_VERSION, ZLIB_INTERNAL, ZLIB_H guard)
sed_inplace -E "s/(^|[^a-zA-Z_])ZLIB_/\1${PREFIX_ZLIB}/g" "${ALL_VENDORED_FILES[@]}"

# ZCONF_H guard isn't caught above
sed_inplace "s/ZCONF_H/CZLIB_ZCONF_H/g" \
    "${CZLIB_DIR}/include/${HEADER_PREFIX}zconf.h"

# ---------------------------------------------------------------------------
# 9. Create modulemap and umbrella shim
# ---------------------------------------------------------------------------
echo "==> Creating module.modulemap and umbrella header..."
if [[ -n "${PRESERVED_UMBRELLA}" ]]; then
    echo "    Restoring existing CZlib.h"
    printf '%s' "${PRESERVED_UMBRELLA}" > "${CZLIB_DIR}/include/CZlib.h"
else
    echo "    Generating minimal CZlib.h"
    cat > "${CZLIB_DIR}/include/CZlib.h" <<SHIM
#ifndef CZLIB_UMBRELLA_H
#define CZLIB_UMBRELLA_H

#include "${HEADER_PREFIX}zlib.h"

#endif
SHIM
fi

cat > "${CZLIB_DIR}/include/module.modulemap" <<'MODULEMAP'
module CZlib {
    header "CZlib.h"
    export *
}
MODULEMAP

# ---------------------------------------------------------------------------
# 10. Add LICENSE and version stamp
# ---------------------------------------------------------------------------
cp "${ZLIB_SRC}/LICENSE" "${CZLIB_DIR}/LICENSE" 2>/dev/null \
    || cp "${ZLIB_SRC}/README" "${CZLIB_DIR}/LICENSE" 2>/dev/null \
    || true

echo "${ZLIB_VERSION}" > "${CZLIB_DIR}/ZLIB_VERSION"

# ---------------------------------------------------------------------------
# 11. Validate: compile each .c and confirm every defined-text symbol is prefixed
# ---------------------------------------------------------------------------
echo "==> Validating symbol prefixes with clang + nm..."
TMP_OBJ_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}" "${TMP_OBJ_DIR}"' EXIT

validation_failed=0
for f in "${ZLIB_C_FILES[@]}"; do
    if ! clang -c \
        -I"${CZLIB_DIR}/include" \
        -I"${CZLIB_DIR}/src" \
        "${CZLIB_DIR}/src/${f}" \
        -o "${TMP_OBJ_DIR}/${f}.o" 2>"${TMP_OBJ_DIR}/${f}.log"
    then
        echo "ERROR: failed to compile ${f}:" >&2
        cat "${TMP_OBJ_DIR}/${f}.log" >&2
        validation_failed=1
        continue
    fi

    # ' T ' = global text symbol (defined function). Anything not prefixed
    # is a symbol that escaped the rename.
    bad="$(nm "${TMP_OBJ_DIR}/${f}.o" 2>/dev/null \
        | awk '$2 == "T" { print $3 }' \
        | grep -v "^_\?${PREFIX_LC}" || true)"
    if [[ -n "${bad}" ]]; then
        echo "ERROR: ${f} has unprefixed public symbols:" >&2
        echo "${bad}" >&2
        validation_failed=1
    fi
done

if [[ ${validation_failed} -ne 0 ]]; then
    echo "Validation FAILED." >&2
    exit 1
fi

echo ""
echo "==> zlib ${ZLIB_VERSION} vendored successfully into ${CZLIB_DIR}"
echo "    All public symbols carry the ${PREFIX_LC} prefix."
