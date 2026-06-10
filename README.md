# Kokoro Studio

A small, fully offline macOS app for generating speech from text with the
[Kokoro](https://huggingface.co/hexgrad/Kokoro-82M) TTS model, running
natively via [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx). No Python,
no network, no install steps — one self-contained `.app`.

- Script editor with word/character count
- Two engines: **Kokoro** (53 voices) and **Pocket TTS** (clone any voice
  from a 5–15s audio sample)
- Settings sidebar: engine, voice, speed, pause control
  (paragraph/punctuation), pronunciation dictionary, output format and folder
- In-app playback with scrubbing
- Export to WAV (lossless) or M4A (AAC)
- Keyboard shortcuts: ⌘↩ generate, ⌘P play/pause, ⌘S export

## Requirements

- macOS 14 (Sonoma) or later
- ~750MB disk for the app (both models are bundled inside)

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

## Acknowledgements

Kokoro Studio is a thin GUI over excellent open source work:

- **[Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M)** by hexgrad — the
  TTS model itself (Apache-2.0). The bundled `kokoro-multi-lang-v1_0` ONNX
  conversion is published by the sherpa-onnx project.
- **[Pocket TTS](https://github.com/kyutai-labs/pocket-tts)** by Kyutai — the
  voice-cloning engine (model weights CC-BY-4.0; ONNX export by
  [KevinAHM](https://huggingface.co/KevinAHM/pocket-tts-onnx)).
- **[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)** by k2-fsa /
  next-gen Kaldi — the on-device inference runtime (Apache-2.0).
- **[ONNX Runtime](https://github.com/microsoft/onnxruntime)** by Microsoft —
  the underlying inference engine (MIT).
- **[eSpeak NG](https://github.com/espeak-ng/espeak-ng)** — phonemization data
  bundled with the model (GPL-3.0).

License texts for the bundled model ship inside the app at
`Contents/Resources/model/LICENSE`.
