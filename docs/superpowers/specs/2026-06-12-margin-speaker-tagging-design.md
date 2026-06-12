# Margin Speaker Tagging — Design

**Date:** 2026-06-12
**Status:** Approved (brainstorming), pending implementation plan
**Component:** Kokoro Studio editor (SwiftUI / AppKit, macOS 14+)

## Summary

Add a toggleable **margin speaker-tagging** mode to the script editor. When on, a thin
left gutter shows one clickable icon per paragraph indicating that paragraph's effective
speaker (color + symbol), and `@Speaker:` lines render as colored chips. Clicking a gutter
icon opens a Liquid-Glass popover to assign a speaker, which edits the underlying
`@Speaker:` text for you.

The mode is a **visual front-end to the existing `@Speaker:` syntax**, not a new data
model. The script text remains the single source of truth; the text→audio pipeline,
`ScriptSegmenter`, `ScriptPatcher`, profiles, and `speakerVoices` are unchanged.

## Decisions (from brainstorming)

| # | Decision | Choice |
|---|----------|--------|
| Source of truth | Margin is a view onto `@Speaker:` lines vs a separate tagging layer | **A — view onto the text.** Margin reads/writes `@Speaker:`; hand-typed tags still work. |
| Line treatment | How a speaker change renders in the editor | **A — colored chip** (target), with **B — tinted raw tag + dot** as fallback. |
| Tagging unit | Paragraph vs finer pause-split segment | **Paragraph** (blank-line-separated block). One gutter icon per paragraph. |
| Click behavior | What assignment writes to the text | **A — smart insert/clean.** Insert `@Name:` only when it differs from the inherited speaker; remove a redundant tag; reset to Narrator. |
| Color/symbol | Auto vs user-chosen | **B — auto from palette, user-overridable.** |
| New speaker | Name only vs name + voice | **D — name + inline voice pick**, writing into `speakerVoices`. |

## Architecture

### Data model (new, on `AppState`)

Two new `@AppStorage` JSON maps, mirroring the existing `speakerVoices` accessor pattern:

- `speakerColors: [String: Int]` — speaker name → palette color index.
- `speakerSymbols: [String: Int]` — speaker name → SF Symbol index.
- A mode flag: `@AppStorage("marginSpeakerMode") var marginSpeakerMode = false`.

Override (Decision B) writes into `speakerColors` / `speakerSymbols`. Voice continues to
live in `speakerVoices`; "New speaker…" (Decision D) writes name + voice there.

### Speaker identity (`SpeakerIdentity` enum namespace)

Caseless `enum` owning the visual palette:

- A fixed palette of ~8 colors, each paired with an SF Symbol.
- Narrator is fixed: gray, `paragraph`/`¶`.
- `autoAssign(name:existing:) -> (colorIndex, symbolIndex)` — deterministically hands the
  next free slot to a new speaker so identity is stable per name and collisions are
  minimized.
- `color(for:)` / `symbol(for:)` resolve a speaker to its current identity, honoring
  overrides in the maps and falling back to auto-assignment.

### Pure logic core (UI-free, TDD'd)

Matches the repo's "domain logic in caseless enum namespaces" convention
(`ScriptSegmenter`, `CueAlignment`, …). Both are fully testable without models or AppKit.

**`ParagraphSpeakers`**
- `resolve(script:) -> [ParagraphSpan]`
- `ParagraphSpan` = character range of the paragraph + the **effective speaker** (sticky:
  inherited from the nearest preceding `@Name:` tag, Narrator when none).
- Drives gutter icon placement and chip ranges.

**`SpeakerTagEditor`**
- `assign(script:, paragraphIndex:, speaker:) -> EditResult`
- Implements smart insert/clean (Decision A):
  - Picked speaker ≠ inherited → insert `@Name:` line at the paragraph start.
  - Picked speaker == inherited and the paragraph carries a literal redundant tag → remove it.
  - Picked Narrator → reset (insert/remove as needed to make the effective speaker Narrator).
- Returns an explicit **range replacement** (range + replacement string) so the editor can
  apply it through `NSTextView` and preserve native undo, rather than wholesale-replacing
  `state.script`.

### Editor rendering

**Gutter overlay**
- Thin (~34pt) AppKit layer aligned to the editor's scroll/coordinate space via
  `EditorTextAccess` + the layout manager's bounding rect for each paragraph's first glyph.
- One icon per `ParagraphSpan`. Assigned paragraphs show color + symbol; Narrator/unassigned
  show a faint neutral icon.
- Re-synced on scroll, text change, and font-size change.

**Chip rendering (Decision A — target)**
- A custom `NSLayoutManager` subclass draws a rounded, tinted background behind each
  `@Name:` range, with a foreground tint. Tag text stays `@Name:` inside the pill.
- **Fallback B:** if glyph/background work proves fragile, render via temp attributes
  (tint + leading color dot), no custom layout manager.
- **Constraint:** must coexist with follow-along highlighting, which also uses
  temp attributes / the layout manager. Verified as a design constraint, not an afterthought.

### Interaction flow

1. Toolbar button toggles `marginSpeakerMode`. Off = today's plain editor; on = gutter + chips.
2. Click a gutter icon → Liquid-Glass popover (`#available(macOS 26.0, *)`, material fallback,
   per `Views/GlassStyle.swift`):
   - Narrator (reset), each known speaker (swatch + voice + ✓ on the current one),
     and "New speaker…".
3. Pick a speaker → `SpeakerTagEditor.assign` → apply the range edit through the text view →
   gutter + chips refresh from a re-resolved `ParagraphSpeakers`.
4. "New speaker…" sub-flow: name field + voice picker + auto color/symbol (overridable swatch
   row). Writes `speakerVoices`, and `speakerColors` / `speakerSymbols` if overridden.

## Risks

1. **Gutter alignment (highest).** macOS `TextEditor` exposes no layout API; alignment rides
   `EditorTextAccess` + layout-manager rects and must re-sync on scroll/resize/edit.
   **Prototype this first.** If jittery, fall back to looser per-paragraph anchoring.
2. **Chip layout manager (second).** Fallback B already defined.

Both risks are isolated to rendering. The pure-logic core and data model are unaffected, so
the feature degrades gracefully.

## Out of scope (YAGNI)

- Drag-to-reassign paragraphs.
- Per-paragraph voice (voice stays per-speaker).
- Multi-select paragraph assignment.
- Gutter in export/caption/waveform views.

## Testing

- `ParagraphSpeakersTests` — sticky inheritance, Narrator default, multi-tag scripts,
  empty/whitespace paragraphs, tags mid-document.
- `SpeakerTagEditorTests` — insert when differing, clean redundant tags, Narrator reset,
  idempotence, boundary paragraphs (first/last), undo-friendly range output.
- `SpeakerIdentityTests` — deterministic auto-assignment, override precedence, Narrator fixed.
- Rendering (gutter/chip) verified manually in the assembled `.app`.
