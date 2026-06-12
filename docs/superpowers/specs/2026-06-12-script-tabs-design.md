# Script Tabs — Multi-Document UI Design

**Goal:** Replace the sidebar Scripts list with document tabs above the editor (standard multi-document UI). The script library moves to a toolbar dropdown, the sidebar becomes purely settings, and Batch Export moves into a split Export toolbar button.

**Decisions made during brainstorming:**
- Tabs only in the main UI; full library behind a toolbar "Scripts" dropdown (chosen over a sidebar library or all-scripts-as-tabs).
- Open tabs and the active tab persist across launches.
- Batch export keeps its picker sheet as the default, with a one-click "Export Open Tabs" alternative.
- Export controls collapse into one split button (`Menu` with `primaryAction`).
- Tab style: document tabs fused to the editor card's top edge (over floating pills or a full-width segmented strip).

## UX Behavior

### Tab bar
- One tab per *open* script: title, hover-visible close (✕), and a trailing `+` tab that creates a new script.
- Click activates the tab (existing `selectDocument`).
- Context menu per tab: Rename…, Duplicate, Close Tab, Close Other Tabs, Delete… — the same actions the sidebar list offers today.
- Closing a tab never deletes the script; it remains in the library. Closing the last tab keeps one tab open — the app always has a current document, as today.
- Overflow: the strip scrolls horizontally; the active tab is auto-scrolled into view. No drag-reorder in v1.
- Keyboard: ⌘T new script, ⇧⌘W close tab (⌘W remains close-window), ⌃Tab / ⌃⇧Tab cycle tabs. Shortcuts appear in menus/tooltips for discoverability.

### Scripts dropdown (toolbar, leading edge)
- Lists every library script; open scripts get a checkmark. Selecting opens it as a tab (or activates the existing tab).
- Below a divider: New Script (⌘T) and Import… (existing importer flow).

### Sidebar
- The Scripts section and the Batch Export… button are removed.
- Engine, Voice, Pauses, and Pronunciation sections remain — the sidebar becomes purely settings.

### Export split button (toolbar, trailing edge)
- Main part: Export current script — unchanged behavior, ⌘S, same disabled states (no audio / preview-only).
- Menu part:
  - **Batch Export…** — opens the existing picker sheet (choose any library scripts, queue).
  - **Export Open Tabs** — queues exactly the open tabs via the existing batch pipeline, skipping the sheet.

## Technical Design

### Data model (AppState)
- `@AppStorage("openTabIDs")` JSON string + typed `openTabIDs: [UUID]` accessor, mirroring the `speakerVoices` JSON-map pattern.
- Active tab is the existing `currentDocumentID` — no new concept.
- New methods:
  - `openTab(_ id:)` — append to `openTabIDs` if missing, then select.
  - `closeTab(_ id:)` — remove from `openTabIDs`; if it was active, select a neighbor; if the set empties, fall back to the most recent library script (creating one if the library is empty).
- Launch-time reconciliation in `loadDocuments()`: drop open-tab IDs whose documents no longer exist; ensure `currentDocumentID` is in the open set.
- `deleteDocument`, `duplicateDocument`, and `newDocument` get one-line tab upkeep (delete closes its tab; new/duplicate opens one).

### Pure logic: `ScriptTabs`
Caseless `enum ScriptTabs` holding the tab-list transition logic: given `(openIDs, activeID, libraryIDs, action)` return the new `(openIDs, activeID)`. Covers open, close, close-others, active-fallback on close/delete, and launch reconciliation. UI-free and unit-testable, matching the repo's domain-logic convention.

### Views
- **`ScriptTabBar.swift`** (new) — horizontal `ScrollView` of tab buttons fused to the editor card: top corners rounded with `GlassMetrics.cornerRadius`, square bottoms, active tab matches the card background. Hosted in the main column directly above `EditorView`; the editor card squares its top corners while the tab bar is visible. Plain materials only — the Liquid Glass policy keeps glass on floating bars.
- **`ContentView`** — toolbar gains the leading `Menu("Scripts")`; the Export `ToolbarItem` becomes a `Menu(primaryAction:)` split button (⌘S stays on the primary action). The sidebar's Scripts `Section` and batch button are deleted; the rename/delete alert plumbing moves to the tab bar.
- **`BatchQueueView`** — unchanged. "Export Open Tabs" calls the existing `startBatch(documentIDs:)` with `openTabIDs`.

### Edge cases
- Deleting a script that is open (from the dropdown or a tab's context menu) closes its tab through the existing `deleteDocument` path, which already selects a neighbor.
- macOS Services `newScriptFromText` flows through `newDocument` and therefore gets a tab automatically.
- Generation/playback state on tab switch keeps today's sidebar-switch semantics — untouched; the `GeneratedAudio.sourceScript` staleness guard already covers script/audio mismatch.

### Testing
- XCTest suite for `ScriptTabs` (~8 cases: open new, open existing, close inactive, close active selects neighbor, close last falls back, close others, reconcile missing IDs, empty library fallback).
- UI verified manually in the assembled app.

## Non-Goals
- Drag-reordering tabs.
- Per-tab window or playback state.
- Dirty indicators (scripts auto-save).
- Native `NSWindow` tabs.
