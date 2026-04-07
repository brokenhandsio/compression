#!/bin/bash
# Downloads the Silesia compression corpus for benchmarks.
# https://sun.aei.polsl.pl/~sdeor/index.php?page=silesia

set -euo pipefail

FIXTURES_DIR="$(dirname "$0")/../Fixtures"
mkdir -p "$FIXTURES_DIR"

if [ -f "$FIXTURES_DIR/dickens" ] && [ -f "$FIXTURES_DIR/mozilla" ] && [ -f "$FIXTURES_DIR/x-ray" ]; then
    echo "Silesia fixtures already present."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Silesia corpus..."
curl -L -o "$TMP/silesia.zip" "https://sun.aei.polsl.pl//~sdeor/corpus/silesia.zip"
unzip -o "$TMP/silesia.zip" mozilla dickens x-ray -d "$FIXTURES_DIR"
echo "Done. Fixtures saved to $FIXTURES_DIR"
