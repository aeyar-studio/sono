#!/usr/bin/env bash
# Downloads the sherpa-onnx C API libraries and headers that Sono links against.
# Kept out of git: 103 MB of binaries would bloat every clone.
set -euo pipefail

VERSION="v1.13.2"
ARCHIVE="sherpa-onnx-${VERSION}-onnxruntime-1.24.4-osx-arm64-shared.tar.bz2"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/${VERSION}/${ARCHIVE}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/Vendor"

if [ -f "${DEST}/sherpa/lib/libsherpa-onnx-c-api.dylib" ]; then
  echo "sherpa-onnx already present"; exit 0
fi

mkdir -p "${DEST}"
cd "${DEST}"
echo "Downloading ${ARCHIVE}…"
curl -fL -o sherpa.tar.bz2 "${URL}"
tar xjf sherpa.tar.bz2
rm sherpa.tar.bz2
mv sherpa-onnx-* sherpa

# Module map so Swift can import the C API.
cat > sherpa/module.modulemap <<'MODULEMAP'
module CSherpaOnnx {
    header "include/sherpa-onnx/c-api/c-api.h"
    export *
}
MODULEMAP

echo "sherpa-onnx ready in Vendor/sherpa"
