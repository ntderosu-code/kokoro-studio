# Script Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the sidebar Scripts list with document tabs fused to the editor card, move the library to a toolbar "Scripts" dropdown, and collapse export into a split Export button with Batch Export… / Export Open Tabs.

**Architecture:** Pure tab-list transition logic in a caseless `enum ScriptTabs` (unit-tested), thin AppState integration (`openTabIDs` persisted as JSON via `@AppStorage`, active tab = existing `currentDocumentID`), and a new `ScriptTabBar` SwiftUI view hosted above `EditorView`. Spec: `docs/superpowers/specs/2026-06-12-script-tabs-design.md`.

**Tech Stack:** Swift / SwiftUI (macOS 14+), SwiftPM, XCTest.

---

## Conventions

- Build: `swift build`
- Tests: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter <ClassName>`
- `documents` in AppState is recency-ordered (index 0 = newest); "most recent library script" = `documents.first`.

## File Structure

**Create:**
- `Sources/KokoroStudio/ScriptTabs.swift` — pure tab-list transitions (open/close/close-others/reconcile).
- `Sources/KokoroStudio/Views/ScriptTabBar.swift` — tab strip view + rename/delete dialog plumbing.
- `Tests/KokoroStudioTests/ScriptTabsTests.swift`

**Modify:**
- `Sources/KokoroStudio/AppState.swift` — `openTabIDs` storage + `openTab`/`closeTab`/`closeOtherTabs`/`nextTab`/`previousTab`; reconcile in `loadLibrary()`; tab upkeep in `createDocument`/`duplicateDocument`/`deleteDocument`.
- `Sources/KokoroStudio/Views/ContentView.swift` — host tab bar in `editorPane`; leading "Scripts" toolbar menu; export split button.
- `Sources/KokoroStudio/Views/SidebarView.swift` — delete the Scripts section and its plumbing.
- `Sources/KokoroStudio/KokoroStudioApp.swift` — ⌘T / ⇧⌘W / ⌃Tab commands.

---

## Task 1: ScriptTabs pure logic

**Files:**
- Create: `Sources/KokoroStudio/ScriptTabs.swift`
- Test: `Tests/KokoroStudioTests/ScriptTabsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/KokoroStudioTests/ScriptTabsTests.swift`:

```swift
import XCTest
@testable import KokoroStudio

final class ScriptTabsTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    func testOpenNewAppendsAndActivates() {
        let state = ScriptTabs.open(c, in: .init(openIDs: [a, b], activeID: a))
        XCTAssertEqual(state, .init(openIDs: [a, b, c], activeID: c))
    }

    func testOpenExistingJustActivates() {
        let state = ScriptTabs.open(b, in: .init(openIDs: [a, b], activeID: a))
        XCTAssertEqual(state, .init(openIDs: [a, b], activeID: b))
    }

    func testCloseInactiveKeepsActive() {
        let state = ScriptTabs.close(a, in: .init(openIDs: [a, b, c], activeID: b),
                                     library: [a, b, c])
        XCTAssertEqual(state, .init(openIDs: [b, c], activeID: b))
    }

    func testCloseActiveSelectsRightNeighborThenLeft() {
        let mid = ScriptTabs.close(b, in: .init(openIDs: [a, b, c], activeID: b),
                                   library: [a, b, c])
        XCTAssertEqual(mid, .init(openIDs: [a, c], activeID: c))
        let last = ScriptTabs.close(c, in: .init(openIDs: [a, c], activeID: c),
                                    library: [a, b, c])
        XCTAssertEqual(last, .init(openIDs: [a], activeID: a))
    }

    func testCloseLastTabFallsBackToMostRecentLibraryScript() {
        let state = ScriptTabs.close(a, in: .init(openIDs: [a], activeID: a),
                                     library: [d, a, b])
        XCTAssertEqual(state, .init(openIDs: [d], activeID: d))
    }

    func testCloseLastTabWithEmptyLibraryGoesEmpty() {
        let state = ScriptTabs.close(a, in: .init(openIDs: [a], activeID: a),
                                     library: [])
        XCTAssertEqual(state, .init(openIDs: [], activeID: nil))
    }

    func testCloseOthers() {
        let state = ScriptTabs.closeOthers(keeping: b,
                                           in: .init(openIDs: [a, b, c], activeID: a))
        XCTAssertEqual(state, .init(openIDs: [b], activeID: b))
    }

    func testReconcileDropsMissingAndFixesActive() {
        let state = ScriptTabs.reconcile(.init(openIDs: [a, b, c], activeID: c),
                                         library: [a, b, d])
        XCTAssertEqual(state, .init(openIDs: [a, b], activeID: a))
    }

    func testReconcileEmptyOpenSeedsFromLibrary() {
        let state = ScriptTabs.reconcile(.init(openIDs: [], activeID: nil),
                                         library: [d, a])
        XCTAssertEqual(state, .init(openIDs: [d], activeID: d))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter ScriptTabsTests`
Expected: FAIL — `cannot find 'ScriptTabs' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/KokoroStudio/ScriptTabs.swift`:

```swift
import Foundation

/// Transitions for the open-tab list. Pure logic: AppState feeds in the
/// current state and the recency-ordered library, and applies the result.
enum ScriptTabs {
    struct State: Equatable {
        var openIDs: [UUID]
        var activeID: UUID?
    }

    /// Open (or re-activate) a script as a tab.
    static func open(_ id: UUID, in state: State) -> State {
        var openIDs = state.openIDs
        if !openIDs.contains(id) { openIDs.append(id) }
        return State(openIDs: openIDs, activeID: id)
    }

    /// Close a tab. The script stays in the library. Closing the active tab
    /// selects its right neighbor (else left); closing the last tab falls
    /// back to the most recent library script, or empty if none exist.
    static func close(_ id: UUID, in state: State, library: [UUID]) -> State {
        guard let index = state.openIDs.firstIndex(of: id) else { return state }
        var openIDs = state.openIDs
        openIDs.remove(at: index)

        if openIDs.isEmpty {
            guard let fallback = library.first(where: { $0 != id }) ?? library.first,
                  fallback != id
            else { return State(openIDs: [], activeID: nil) }
            return State(openIDs: [fallback], activeID: fallback)
        }
        guard state.activeID == id else {
            return State(openIDs: openIDs, activeID: state.activeID)
        }
        let neighbor = openIDs[min(index, openIDs.count - 1)]
        return State(openIDs: openIDs, activeID: neighbor)
    }

    static func closeOthers(keeping id: UUID, in state: State) -> State {
        guard state.openIDs.contains(id) else { return state }
        return State(openIDs: [id], activeID: id)
    }

    /// Launch-time cleanup: drop tabs whose documents vanished, seed from the
    /// library when empty, and force the active tab into the open set.
    static func reconcile(_ state: State, library: [UUID]) -> State {
        var openIDs = state.openIDs.filter(library.contains)
        if openIDs.isEmpty, let first = library.first { openIDs = [first] }
        let activeID = state.activeID.flatMap { openIDs.contains($0) ? $0 : nil }
            ?? openIDs.first
        return State(openIDs: openIDs, activeID: activeID)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter ScriptTabsTests`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/KokoroStudio/ScriptTabs.swift Tests/KokoroStudioTests/ScriptTabsTests.swift
git commit -m "feat: ScriptTabs pure open/close/reconcile transitions"
```

---

## Task 2: AppState integration

**Files:**
- Modify: `Sources/KokoroStudio/AppState.swift` (library section, ~lines 309–425)

- [ ] **Step 1: Add persisted open-tab storage**

Below `currentDocumentID` (ends ~line 321), add:

```swift
    @AppStorage("openTabIDs") private var openTabIDsJSON = ""

    /// Open script tabs, in display order. Persisted across launches.
    var openTabIDs: [UUID] {
        get {
            guard let data = openTabIDsJSON.data(using: .utf8),
                  let strings = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return strings.compactMap(UUID.init(uuidString:))
        }
        set {
            if let data = try? JSONEncoder().encode(newValue.map(\.uuidString)) {
                openTabIDsJSON = String(data: data, encoding: .utf8) ?? ""
            }
        }
    }

    private var tabState: ScriptTabs.State {
        ScriptTabs.State(openIDs: openTabIDs, activeID: currentDocumentID)
    }

    /// Applies a ScriptTabs transition result: persists the open set and
    /// switches documents if the active tab changed.
    private func applyTabState(_ state: ScriptTabs.State) {
        openTabIDs = state.openIDs
        if let active = state.activeID, active != currentDocumentID {
            selectDocument(active)
        } else if state.activeID == nil {
            createDocument()
        }
    }
```

- [ ] **Step 2: Add the tab actions**

After `applyTabState`, add:

```swift
    func openTab(_ id: UUID) {
        applyTabState(ScriptTabs.open(id, in: tabState))
    }

    func closeTab(_ id: UUID) {
        applyTabState(ScriptTabs.close(id, in: tabState,
                                       library: documents.map(\.id)))
    }

    func closeOtherTabs(keeping id: UUID) {
        applyTabState(ScriptTabs.closeOthers(keeping: id, in: tabState))
    }

    func nextTab() { cycleTab(by: 1) }
    func previousTab() { cycleTab(by: -1) }

    private func cycleTab(by offset: Int) {
        let ids = openTabIDs
        guard ids.count > 1, let current = currentDocumentID,
              let index = ids.firstIndex(of: current) else { return }
        selectDocument(ids[(index + offset + ids.count) % ids.count])
    }
```

- [ ] **Step 3: Reconcile at launch**

In `loadLibrary()`, after the existing `if/else` chain (after line 334, before `startAutosave()`), add:

```swift
        applyTabState(ScriptTabs.reconcile(tabState, library: documents.map(\.id)))
```

- [ ] **Step 4: Tab upkeep in document CRUD**

In `createDocument`, after `currentDocumentID = meta.id` add:

```swift
        openTabIDs = ScriptTabs.open(meta.id, in: tabState).openIDs
```

In `duplicateDocument`, after `documents.insert(copy, at: 0)` add:

```swift
        openTab(copy.id)
```

Replace the body of `deleteDocument` with:

```swift
    /// Removes the library entry only — exported audio is never touched.
    func deleteDocument(_ id: UUID) {
        let next = ScriptTabs.close(id, in: tabState,
                                    library: documents.map(\.id))
        DocumentStore.delete(id: id)
        documents.removeAll { $0.id == id }
        if currentDocumentID == id {
            currentDocumentID = nil // force reload in selectDocument
        }
        applyTabState(next)
    }
```

(`ScriptTabs.close`'s library fallback already excludes the closed id, so the
deleted document can't be re-selected.)

- [ ] **Step 5: Build and run full test suite**

Run: `swift build && DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test`
Expected: builds; all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/KokoroStudio/AppState.swift
git commit -m "feat: AppState open-tab persistence and tab actions"
```

---

## Task 3: ScriptTabBar view

**Files:**
- Create: `Sources/KokoroStudio/Views/ScriptTabBar.swift`
- Modify: `Sources/KokoroStudio/Views/ContentView.swift` (`editorPane`, ~line 79)

- [ ] **Step 1: Create the tab bar view**

Create `Sources/KokoroStudio/Views/ScriptTabBar.swift`:

```swift
import SwiftUI

/// Document tabs fused to the editor card's top edge. One tab per open
/// script; the script library lives in the toolbar Scripts menu.
struct ScriptTabBar: View {
    @EnvironmentObject private var state: AppState
    @State private var renameTarget: ScriptDocumentMeta?
    @State private var renameText = ""
    @State private var deleteTarget: ScriptDocumentMeta?

    private var openDocuments: [ScriptDocumentMeta] {
        state.openTabIDs.compactMap { id in
            state.documents.first(where: { $0.id == id })
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(openDocuments) { doc in
                        tab(for: doc)
                            .id(doc.id)
                    }
                    Button {
                        state.createDocument()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 26, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("New script (⌘T)")
                }
                .padding(.horizontal, 6)
            }
            .onChange(of: state.currentDocumentID) { _, id in
                if let id { withAnimation { proxy.scrollTo(id) } }
            }
        }
        .alert("Rename Script", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                if let doc = renameTarget {
                    state.renameDocument(doc.id, to: renameText)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog(
            "Delete \"\(deleteTarget?.title ?? "")\"?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ), titleVisibility: .visible
        ) {
            Button("Delete Script", role: .destructive) {
                if let doc = deleteTarget { state.deleteDocument(doc.id) }
                deleteTarget = nil
            }
        } message: {
            Text("Removes it from the library. Exported audio is not affected.")
        }
    }

    private func tab(for doc: ScriptDocumentMeta) -> some View {
        let isActive = doc.id == state.currentDocumentID
        return HStack(spacing: 4) {
            Button {
                state.closeTab(doc.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0.4)
            .help("Close tab (⇧⌘W)")
            Text(doc.title)
                .lineLimit(1)
                .font(.callout)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: 180)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8)
                .fill(isActive
                      ? Color(nsColor: .textBackgroundColor)
                      : Color(nsColor: .windowBackgroundColor).opacity(0.6))
        )
        .contentShape(Rectangle())
        .onTapGesture { state.selectDocument(doc.id) }
        .contextMenu {
            Button("Rename…") {
                renameText = doc.title
                renameTarget = doc
            }
            Button("Duplicate") { state.duplicateDocument(doc.id) }
            Divider()
            Button("Close Tab") { state.closeTab(doc.id) }
            Button("Close Other Tabs") { state.closeOtherTabs(keeping: doc.id) }
            Divider()
            Button("Delete…", role: .destructive) { deleteTarget = doc }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Script tab: \(doc.title)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
```

- [ ] **Step 2: Host it above the editor and square the card's top corners**

In `ContentView.editorPane` (~line 80), put the tab bar directly above `EditorView()` with zero spacing so they fuse:

```swift
    private var editorPane: some View {
        VStack(spacing: 6) {
            VStack(spacing: 0) {
                ScriptTabBar()
                EditorView()
                    // ... existing .overlay(alignment: .bottom) glass bars unchanged
            }
            scriptInfoRow
        }
        // ... existing padding/frame/toolbar modifiers unchanged
    }
```

(Keep the existing `.overlay` chain attached to `EditorView()` exactly as it is — only wrap the two views in the inner `VStack(spacing: 0)`.)

In `EditorView.body`, square the card's top corners so tabs sit flush. Replace:

```swift
        .clipShape(RoundedRectangle(cornerRadius: GlassMetrics.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: GlassMetrics.cornerRadius)
                .strokeBorder(.quaternary)
        )
```

with:

```swift
        .clipShape(UnevenRoundedRectangle(
            bottomLeadingRadius: GlassMetrics.cornerRadius,
            bottomTrailingRadius: GlassMetrics.cornerRadius))
        .overlay(
            UnevenRoundedRectangle(
                bottomLeadingRadius: GlassMetrics.cornerRadius,
                bottomTrailingRadius: GlassMetrics.cornerRadius)
                .strokeBorder(.quaternary)
        )
```

- [ ] **Step 3: Build and verify manually**

Run: `swift build && ./scripts/build-app.sh && open "build/Kokoro Studio.app"`
Verify: tabs render above the editor; click switches scripts; ✕ closes (script stays in library); + creates; context menu renames/duplicates/closes/deletes; tabs persist across relaunch.

- [ ] **Step 4: Commit**

```bash
git add Sources/KokoroStudio/Views/ScriptTabBar.swift Sources/KokoroStudio/Views/ContentView.swift
git commit -m "feat: document tab bar fused to the editor card"
```

---

## Task 4: Scripts toolbar menu + sidebar cleanup

**Files:**
- Modify: `Sources/KokoroStudio/Views/ContentView.swift` (toolbar, before the `"profile"` item ~line 119)
- Modify: `Sources/KokoroStudio/Views/SidebarView.swift` (Scripts section lines 62–105 + its plumbing)

- [ ] **Step 1: Add the Scripts menu**

Inside `.toolbar(id: "main")`, before the `"profile"` `ToolbarItem`, add:

```swift
            ToolbarItem(id: "scripts", placement: .navigation) {
                Menu {
                    ForEach(state.documents) { doc in
                        Button {
                            state.openTab(doc.id)
                        } label: {
                            if state.openTabIDs.contains(doc.id) {
                                Label(doc.title, systemImage: "checkmark")
                            } else {
                                Text(doc.title)
                            }
                        }
                    }
                    Divider()
                    Button("New Script", systemImage: "plus") {
                        state.createDocument()
                    }
                    // ⌘T shortcut lives on the File-menu command (Task 5);
                    // registering it twice would double-fire.
                    Button("Import Document…", systemImage: "square.and.arrow.down") {
                        state.showingImportPanel = true
                    }
                } label: {
                    Label("Scripts", systemImage: "doc.text")
                }
                .help("Open a script from the library")
            }
```

- [ ] **Step 2: Remove the sidebar Scripts section**

In `SidebarView.swift`:
- Delete the whole `Section("Scripts") { ... }` block (lines 62–105).
- Delete the now-unused `@State` vars `scriptSearch`, `renameTarget`, `renameText`, `deleteTarget` and the `filteredDocuments` computed property (top of the struct).
- Delete the `.alert("Rename Script", ...)` and the delete `.confirmationDialog`/`.alert` modifiers attached to the `Form` that referenced `renameTarget`/`deleteTarget` (they moved into `ScriptTabBar`).

- [ ] **Step 3: Build and verify manually**

Run: `swift build && ./scripts/build-app.sh && open "build/Kokoro Studio.app"`
Verify: sidebar starts at Engine; Scripts toolbar menu lists all scripts with checkmarks on open ones, opens/activates tabs, creates and imports.

- [ ] **Step 4: Commit**

```bash
git add Sources/KokoroStudio/Views/ContentView.swift Sources/KokoroStudio/Views/SidebarView.swift
git commit -m "feat: scripts library toolbar menu replaces sidebar list"
```

---

## Task 5: Export split button + keyboard commands

**Files:**
- Modify: `Sources/KokoroStudio/Views/ContentView.swift` (the `"export"` `ToolbarItem`)
- Modify: `Sources/KokoroStudio/KokoroStudioApp.swift` (`CommandGroup(after: .newItem)`, ~line 54)

- [ ] **Step 1: Replace the Export button with a split button**

Replace the existing `ToolbarItem(id: "export") { Button("Export", ...) ... }` with:

```swift
            ToolbarItem(id: "export") {
                Menu {
                    Button("Batch Export…", systemImage: "square.stack.3d.up") {
                        state.showingBatchSheet = true
                    }
                    .disabled(state.phase != .ready && !state.batchRunning)
                    Button("Export Open Tabs",
                           systemImage: "square.and.arrow.up.on.square") {
                        state.saveCurrentDocumentNow()
                        state.startBatch(documentIDs: state.openTabIDs)
                        state.showingBatchSheet = true
                    }
                    .disabled(state.phase != .ready || state.openTabIDs.isEmpty)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                } primaryAction: {
                    guard state.lastAudio != nil,
                          state.lastAudio?.isPreview != true else { return }
                    showingExportSheet = true
                }
                .keyboardShortcut("s", modifiers: .command)
                .help(state.lastAudio == nil || state.lastAudio?.isPreview == true
                      ? "Generate audio first to export — or open the menu for batch export"
                      : "Export audio and captions (⌘S); batch options in the menu")
            }
```

Note: the menu stays enabled even when the current script has no exportable
audio — batch export must remain reachable — so the primary action guards
instead of using `.disabled`. "Export Open Tabs" also opens the batch sheet so
progress is visible (the queue is already running; `BatchQueueView` shows it).

Check `startBatch`'s behavior in `AppState` when called with the sheet closed —
it is the same call `BatchQueueView` makes, so no changes needed there.

- [ ] **Step 2: Add keyboard commands**

In `KokoroStudioApp.swift`, extend `CommandGroup(after: .newItem)`:

```swift
            CommandGroup(after: .newItem) {
                Button("New Script") {
                    state.createDocument()
                }
                .keyboardShortcut("t", modifiers: .command)
                Button("Close Tab") {
                    if let id = state.currentDocumentID { state.closeTab(id) }
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                Divider()
                Button("Show Next Tab") { state.nextTab() }
                    .keyboardShortcut(.tab, modifiers: .control)
                Button("Show Previous Tab") { state.previousTab() }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])
                Divider()
                Button("Import Document…") {
                    state.showingImportPanel = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
```

(⌘T is registered only here; the toolbar Scripts menu's New Script button
intentionally carries no shortcut.)

- [ ] **Step 3: Build and verify manually**

Run: `swift build && ./scripts/build-app.sh && open "build/Kokoro Studio.app"`
Verify: Export button exports current script on click (⌘S works); the ▾ menu offers Batch Export… (sheet) and Export Open Tabs (queues open tabs, sheet shows progress); ⌘T, ⇧⌘W, ⌃Tab, ⌃⇧Tab all work; File menu shows the new items.

- [ ] **Step 4: Commit**

```bash
git add Sources/KokoroStudio/Views/ContentView.swift Sources/KokoroStudio/KokoroStudioApp.swift
git commit -m "feat: split Export button and tab keyboard commands"
```

---

## Final verification

- [ ] Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test` — all pass.
- [ ] Run: `./scripts/build-app.sh && open "build/Kokoro Studio.app"` — full manual pass: tabs (open/close/persist/cycle), Scripts menu, sidebar settings-only, split Export, batch flows, delete-open-script edge case, Services "New Kokoro Studio Script" still lands in a new tab.

## Notes for the implementer

- `selectDocument` drops `lastAudio` on switch by design (stale audio invites exporting the wrong lesson) — do not "fix" this while wiring tabs.
- `applyTabState`'s `createDocument()` fallback covers the empty-library case only; normal closes always resolve to a tab via `ScriptTabs.close`.
- YAGNI: no drag-reorder, no per-tab state, no dirty indicators, no NSWindow tabs.
