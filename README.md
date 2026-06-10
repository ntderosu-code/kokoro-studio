# Kokoro Studio

A small, fully offline macOS app for generating speech from text with the
[Kokoro](https://huggingface.co/hexgrad/Kokoro-82M) TTS model, running
natively via [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx). No Python,
no network, no install steps — one self-contained `.app`.

- Script editor with word/character count
- Settings sidebar: voice (all 53 Kokoro 1.0 voices), speed, output format,
  output folder
- In-app playback with scrubbing
- Export to WAV (lossless) or M4A (AAC)
- Keyboard shortcuts: ⌘↩ generate, ⌘P play/pause, ⌘S export

## Requirements

- macOS 14 (Sonoma) or later
- ~500MB disk for the app (the Kokoro model is bundled inside)

## Building from source

```bash
./scripts/fetch-deps.sh   # downloads sherpa-onnx dylibs + Kokoro model (~400MB) into vendor/
./scripts/build-app.sh    # builds release binary and assembles build/Kokoro Studio.app
open "build/Kokoro Studio.app"
```

Run the tests (the engine test loads the real model):

```bash
DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test
```

## Distributing

The app is ad-hoc codesigned. On another Mac, Gatekeeper will block a plain
double-click the first time: **right-click the app → Open → Open**. To remove
the quarantine flag instead: `xattr -dr com.apple.quarantine "Kokoro Studio.app"`.
For wider distribution, sign with a Developer ID certificate and notarize.

Zip it for sharing:

```bash
ditto -c -k --keepParent "build/Kokoro Studio.app" KokoroStudio.zip
```

## Voices

The bundled model is `kokoro-multi-lang-v1_0` (53 speakers, 24kHz). English
voices use the `af_`/`am_` (American) and `bf_`/`bm_` (British) prefixes —
e.g. `af_heart`, `af_bella`, `am_adam`, `bm_george`. The remaining voices
cover Spanish, French, Hindi, Italian, Japanese, Portuguese, and Chinese.

## Licenses

- Kokoro model weights: Apache-2.0
- sherpa-onnx: Apache-2.0
