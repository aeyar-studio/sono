#!/usr/bin/env bash
# Downloads Sparkle's CLI tools (sign_update). Kept out of git for the same
# reason as the sherpa libraries: binaries do not belong in a source repo.
set -euo pipefail

VERSION="2.9.4"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Scripts/bin"

if [ -x "$DEST/sign_update" ]; then echo "sign_update already present"; exit 0; fi

mkdir -p "$DEST"
TMP="$(mktemp -d)"
curl -fL -o "$TMP/sparkle.tar.xz" \
  "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
tar xJf "$TMP/sparkle.tar.xz" -C "$TMP"
cp "$TMP/bin/sign_update" "$DEST/"
chmod +x "$DEST/sign_update"
rm -rf "$TMP"
echo "sign_update ready in Scripts/bin"
