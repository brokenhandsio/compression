#!/usr/bin/env bash
# Thin wrapper around scripts/fetch-silesia.sh — pulls just the three files
# the benchmarks use into Benchmarks/Fixtures/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/../../scripts/fetch-silesia.sh" \
    "${SCRIPT_DIR}/../Fixtures" \
    dickens mozilla x-ray
