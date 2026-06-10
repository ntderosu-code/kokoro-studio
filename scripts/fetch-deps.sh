#!/bin/bash
# scripts/fetch-deps.sh — download sherpa-onnx libs + Kokoro model into vendor/ (gitignored)
set -euo pipefail
cd "$(dirname "$0")/.."

SHERPA_VERSION="1.13.2"
SHERPA_ARCHIVE="sherpa-onnx-v${SHERPA_VERSION}-osx-universal2-shared.tar.bz2"
MODEL_ARCHIVE="kokoro-multi-lang-v1_0.tar.bz2"

mkdir -p vendor

if [ ! -d "vendor/sherpa-onnx/lib" ]; then
  echo "Fetching sherpa-onnx v${SHERPA_VERSION}..."
  curl -L -o "vendor/${SHERPA_ARCHIVE}" \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/v${SHERPA_VERSION}/${SHERPA_ARCHIVE}"
  tar xf "vendor/${SHERPA_ARCHIVE}" -C vendor
  mv "vendor/sherpa-onnx-v${SHERPA_VERSION}-osx-universal2-shared" vendor/sherpa-onnx
  rm "vendor/${SHERPA_ARCHIVE}"
fi

if [ ! -d "vendor/model" ]; then
  echo "Fetching Kokoro model (~360MB compressed, be patient)..."
  curl -L -o "vendor/${MODEL_ARCHIVE}" \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${MODEL_ARCHIVE}"
  tar xf "vendor/${MODEL_ARCHIVE}" -C vendor
  mv vendor/kokoro-multi-lang-v1_0 vendor/model
  rm "vendor/${MODEL_ARCHIVE}"
fi

echo "Done. vendor/sherpa-onnx and vendor/model ready."
