#!/usr/bin/env bash
#
# fetch-silesia.sh
# Downloads the Silesia corpus into a destination directory.
# Skips the download if the requested files are already present.
#
# Usage:
#   scripts/fetch-silesia.sh <dest> [file ...]
#
# With no file list, extracts the full corpus. Otherwise extracts just the named files.
#
# Examples:
#   scripts/fetch-silesia.sh Tests/Fixtures/Silesia
#   scripts/fetch-silesia.sh Benchmarks/Fixtures dickens mozilla x-ray
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <dest> [file ...]" >&2
    exit 1
fi

DEST="$1"
shift
FILES=("$@")
URL="https://sun.aei.polsl.pl//~sdeor/corpus/silesia.zip"

# Skip if everything we'd extract is already there. For the full-corpus case,
# `dickens` stands in for "we ran a full extract": unzip is all-or-nothing.
needs_download=0
if [[ ${#FILES[@]} -eq 0 ]]; then
    [[ -f "${DEST}/dickens" ]] || needs_download=1
else
    for f in "${FILES[@]}"; do
        [[ -f "${DEST}/${f}" ]] || { needs_download=1; break; }
    done
fi

if [[ ${needs_download} -eq 0 ]]; then
    echo "==> Silesia corpus already present at ${DEST}, skipping."
    exit 0
fi

echo "==> Downloading Silesia corpus from ${URL}"
mkdir -p "${DEST}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# Install curl if no HTTP client is present (stripped CI containers).
if ! command -v curl >/dev/null 2>&1 \
    && ! command -v fetch >/dev/null 2>&1 \
    && ! command -v wget >/dev/null 2>&1; then
    echo "==> No HTTP client on PATH; installing curl..."
    SUDO=""
    if [[ "$(id -u)" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    fi
    if command -v apt-get >/dev/null 2>&1; then
        ${SUDO} apt-get update -qq
        ${SUDO} apt-get install -y --no-install-recommends curl ca-certificates
    elif command -v pkg >/dev/null 2>&1; then
        ${SUDO} pkg install -y curl
    elif command -v dnf >/dev/null 2>&1; then
        ${SUDO} dnf install -y curl
    elif command -v apk >/dev/null 2>&1; then
        ${SUDO} apk add --no-cache curl ca-certificates
    elif command -v brew >/dev/null 2>&1; then
        brew install curl
    else
        echo "error: no known package manager to install curl" >&2
        exit 1
    fi
fi

# curl on Linux/macOS, fetch on FreeBSD, wget as a backstop.
if command -v curl >/dev/null 2>&1; then
    curl --fail --silent --show-error --location \
        --retry 3 --retry-delay 5 --connect-timeout 30 \
        -o "${TMP}/silesia.zip" "${URL}"
elif command -v fetch >/dev/null 2>&1; then
    fetch -q -T 30 -o "${TMP}/silesia.zip" "${URL}"
elif command -v wget >/dev/null 2>&1; then
    wget --quiet --tries=3 --timeout=30 -O "${TMP}/silesia.zip" "${URL}"
else
    echo "error: HTTP client install reported success but none found on PATH" >&2
    exit 1
fi

echo "==> Extracting into ${DEST}"
if [[ ${#FILES[@]} -eq 0 ]]; then
    unzip -q "${TMP}/silesia.zip" -d "${DEST}"
else
    unzip -q "${TMP}/silesia.zip" "${FILES[@]}" -d "${DEST}"
fi

echo "==> Silesia corpus ready."
