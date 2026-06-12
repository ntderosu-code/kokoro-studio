# Kokoro Studio

A fully offline macOS app for turning scripts into natural speech. Native
SwiftUI with Liquid Glass on macOS 26, powered by the
[Kokoro](https://huggingface.co/hexgrad/Kokoro-82M) TTS model and
[Pocket TTS](https://github.com/kyutai-labs/pocket-tts) voice cloning via
[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx). No Python, no network,
no subscription — one self-contained `.app`.

![Kokoro Studio](docs/screenshot.png)

## Download

Grab the latest signed & notarized build from
[**Releases**](https://github.com/ntderosu-code/kokoro-studio/releases) —
unzip, drag to Applications, double-click. macOS 14+ (Apple Silicon & Intel).

## Features

**Voices**
- **Kokoro engine** — 53 voices: American & British English plus Spanish,
  French, Hindi, Italian, Japanese, Portuguese, and Chinese
- **Pocket TTS engine** — clone any voice from a 5–15 second audio sample
- Multi-speaker dialogue: tag lines `@Maya:` / `@Sam:` and map each speaker
  to a voice
- **Compare Voices**: hear the same line in two voices side by side, then
  adopt the winner with one click

**Narration control** (built for instructional content)
- Pause control by type: paragraph, sentence (`. ! ?`), clause (`, ; :`),
  and heading (`#` lines) — plus inline `[pause:800]` markers
- `*emphasis*` markers: a breath before and after, slightly slower delivery
- Per-speaker voice **and speed** for dialogue (`@Maya:` lines)
- Pronunciation dictionary with acronym modes (`APA = @letters`,
  `NASA = @word`, `IEP = @letters-first`) plus one-off inline overrides:
  `{Roush|rowsh}`
- Pronunciation linter flags unknown acronyms with one-click dictionary add
- Number & symbol normalization: `$5.50`, `25%`, `1–2`, `v1.2`, `x²`, `°C`,
  dates, times, URLs and emails read naturally
- Named profiles lock a whole course to one consistent sound

**Output**
- WAV (lossless) or M4A (AAC) export
- Synced **VTT/SRT captions** with sample-accurate sentence cues
- **Module splitting**: `## file: lesson-2` markers export one audio +
  caption file per section from a single document
- Loudness normalization: silence trim, −1 dBFS leveling, anti-click fades
- **Loudness presets**: −16 LUFS podcast, −14 LUFS streaming, or a custom
  integrated-loudness target (BS.1770) at export
- **Batch export**: queue several scripts and walk away — each renders
  with its own profile, honors module splitting, and notifies when done
- Lead-in/lead-out silence padding for LMS players that clip
- Live estimated audio length that calibrates from your actual generations

**Editor**
- **Script library**: every lesson lives in the sidebar with autosave —
  each script remembers its profile
- **Document import** (⌘O or drag-and-drop): `.docx`, `.md`, `.txt`,
  `.rtf` — headings and bold convert to script syntax, with a preview
  before anything touches your editor
- **Patch re-render** (⌥⌘↩): edit a sentence after generating and splice
  just that re-rendered block into the existing audio and captions
- **Follow-along highlight**: the spoken sentence lights up during
  playback; click any sentence to jump the audio there
- **Waveform scrubber** with heading tick marks in the player bar
- Pronunciation dictionary **CSV import/export** for course teams
- **macOS Services**: right-click selected text in any app to speak it or
  start a new script from it
- Find & replace (native find bar, ⌘F / ⌥⌘F)
- Apple Intelligence **Writing Tools** in the toolbar (macOS 15.2+)
- **Preview Selection** (⇧⌘↩): audition just the selected sentence
- Quick-add to dictionary: select a word, press ⌘D
- Script syntax cheat sheet (? in the toolbar)
- First-run sample script: a spoken tour of every syntax feature
- In-app playback with scrubbing

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Generate / Re-generate | ⌘↩ |
| Patch re-render edited lines | ⌥⌘↩ |
| Preview selection | ⇧⌘↩ |
| Export | ⌘S |
| Import document | ⌘O |
| Play / Pause | ⌘P |
| Add selection to dictionary | ⌘D |
| Find / Find & Replace | ⌘F / ⌥⌘F |

## Building from source

```bash
./scripts/fetch-deps.sh   # sherpa-onnx dylibs + both models (~500MB) into vendor/
./scripts/build-app.sh    # assembles build/Kokoro Studio.app (ad-hoc signed)
open "build/Kokoro Studio.app"
```

Run the tests (engine tests load the real models):

```bash
DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test
```

Release builds (`./scripts/build-app.sh --release`) sign with Developer ID
and notarize; see the script header for the required keychain profile.

### Sparkle updates

Kokoro Studio uses [Sparkle](https://sparkle-project.org/) for installed-app
update checks. The updater starts only when the assembled app bundle includes
both a Sparkle appcast URL and EdDSA public key:

```bash
SPARKLE_PUBLIC_ED_KEY="..." \
./scripts/build-app.sh --release
```

By default, release builds use the GitHub Pages appcast at
`https://ntderosu-code.github.io/kokoro-studio/appcast.xml`. Override it with
`SPARKLE_FEED_URL` only if the feed moves.

Generate the key once with Sparkle's `generate_keys` tool, keep the private key
safe, and publish signed archives/appcasts with `generate_appcast`. Optional
release settings are `SPARKLE_ENABLE_AUTOMATIC_CHECKS` and
`SPARKLE_AUTOMATICALLY_UPDATE`; leave them unset to use Sparkle's consent
prompt/defaults. `SPARKLE_VERIFY_BEFORE_EXTRACTION` defaults to `true`.

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

## License

Source code is MIT (see [LICENSE](LICENSE)). The distributed app bundles
components under their own terms — see [NOTICE.md](NOTICE.md), in particular
the eSpeak NG GPL-3.0 note for anyone forking this into a closed product.
