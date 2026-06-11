import SwiftUI

struct AuditionTarget: Identifiable {
    let text: String
    var id: String { text }
}

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var player = PlayerController()
    @StateObject private var highlighter = FollowAlongHighlighter()
    @State private var quickAddWord: String?
    @State private var showingLinter = false
    @State private var hasEditorSelection = false

    private var pronunciationSuspects: [String] {
        ScriptLinter.acronymSuspects(
            in: state.script,
            coveredBy: PronunciationDictionary.parse(state.pronunciationRulesText))
    }
    @State private var showingExportSheet = false
    @State private var showingSaveProfile = false
    @State private var newProfileName = ""
    @State private var profileNames = ProfileStore.list()

    /// Reads the current selection from the focused text view (the script
    /// editor). SwiftUI's TextEditor exposes no selection binding on macOS,
    /// so we go through the responder chain.
    private func selectedEditorText() -> String? {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return nil
        }
        let range = textView.selectedRange()
        guard range.length > 0 else { return nil }
        let selection = (textView.string as NSString).substring(with: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return selection.isEmpty ? nil : selection
    }

    private func importDocument(at url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let converted = try ScriptImporter.importFile(at: url)
            guard !converted.isEmpty else {
                state.errorMessage = "Nothing readable found in that document."
                return
            }
            state.importedText = converted
        } catch {
            state.errorMessage = "Could not import: \(error.localizedDescription)"
        }
    }

    private func showFindAndReplace() {
        guard let textView = EditorTextAccess.focusTextView(in: NSApp.keyWindow)
        else { return }
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        let action = NSMenuItem()
        action.tag = NSTextFinder.Action.showReplaceInterface.rawValue
        textView.performTextFinderAction(action)
    }

    var body: some View {
        // Standard macOS architecture: NavigationSplitView's sidebar gets the
        // system Liquid Glass floating-slab treatment on macOS 26 for free.
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 340)
        } detail: {
            editorPane
                .background(Color(nsColor: .windowBackgroundColor),
                            ignoresSafeAreaEdges: .bottom)
        }
    }

    private var editorPane: some View {
        VStack(spacing: 6) {
            EditorView()
                // Glass floats over the page so the script scrolls beneath
                // it — that gives Liquid Glass something to refract.
                .overlay(alignment: .bottom) {
                    BarGlassContainer(spacing: 10) {
                        VStack(spacing: 10) {
                            if state.lastAudio != nil {
                                PlayerBar(player: player,
                                          onExport: { showingExportSheet = true },
                                          onRegenerate: {
                                              player.stop()
                                              state.generate()
                                          })
                                    .barGlass()
                            }
                            // Only present while it has content: the first
                            // Generate, or status/Stop during generation.
                            if state.lastAudio == nil || state.isGenerating {
                                actionBar
                                    .barGlass()
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 16)
                    }
                    .animation(.spring(duration: 0.35),
                               value: state.lastAudio?.previewWAV)
                }
            scriptInfoRow
        }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(minWidth: 380, maxWidth: .infinity,
                   minHeight: 200, maxHeight: .infinity)
        .toolbar(id: "main") {
            ToolbarItem(id: "profile", placement: .navigation) {
                Menu {
                    Picker("Profile", selection: $state.currentProfileName) {
                        Text("Custom").tag("")
                        ForEach(profileNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Save Current As…") {
                        newProfileName = state.currentProfileName
                        showingSaveProfile = true
                    }
                    if !state.currentProfileName.isEmpty {
                        Button("Delete \"\(state.currentProfileName)\"",
                               role: .destructive) {
                            ProfileStore.delete(name: state.currentProfileName)
                            profileNames = ProfileStore.list()
                            state.currentProfileName = ""
                        }
                    }
                } label: {
                    Label(state.currentProfileName.isEmpty
                          ? "Profile" : state.currentProfileName,
                          systemImage: "square.stack")
                }
                .help("Apply, save, or delete settings profiles")
                .onChange(of: state.currentProfileName) { _, name in
                    if !name.isEmpty, let profile = ProfileStore.load(name: name) {
                        state.apply(profile)
                    }
                }
            }

            // Selection actions
            ToolbarItem(id: "selection") {
                ControlGroup {
                    Button("Preview Selection",
                           systemImage: "waveform.and.magnifyingglass") {
                        if let selection = selectedEditorText() {
                            player.stop()
                            state.generate(textOverride: selection)
                        }
                    }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(state.phase != .ready || !hasEditorSelection)
                    .help(hasEditorSelection
                          ? "Generate only the selected text (⇧⌘↩)"
                          : "Select part of the script to preview it (⇧⌘↩)")

                    Button("Add to Dictionary", systemImage: "character.book.closed") {
                        if let selection = selectedEditorText() {
                            quickAddWord = selection
                        }
                    }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(!hasEditorSelection)
                    .help(hasEditorSelection
                          ? "Add selected word to pronunciation dictionary (⌘D)"
                          : "Select a word to add it to the dictionary (⌘D)")

                    Button("Compare Voices", systemImage: "person.2.wave.2") {
                        let text = selectedEditorText()
                            ?? AuditionSupport.defaultText(from: state.script)
                        guard !text.isEmpty else { return }
                        player.stop()
                        state.auditionText = text
                    }
                    .disabled(state.phase != .ready
                              || (state.script.trimmingCharacters(
                                    in: .whitespacesAndNewlines).isEmpty
                                  && !hasEditorSelection))
                    .help("Hear the selection (or first sentence) in two voices side by side")
                }
            }

            // Text-editing tools
            ToolbarItem(id: "editing") {
                ControlGroup {
                    Button("Find & Replace", systemImage: "magnifyingglass") {
                        showFindAndReplace()
                    }
                    .help("Find and replace in the script (⌘F)")

                    if #available(macOS 15.2, *) {
                        WritingToolsToolbarButton()
                            .help("Proofread or rewrite the selection with Apple Intelligence")
                    }
                }
            }

            // Output action anchors the trailing edge
            ToolbarItem(id: "export") {
                Button("Export", systemImage: "square.and.arrow.up") {
                    showingExportSheet = true
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(state.lastAudio == nil || state.lastAudio?.isPreview == true)
                .help(state.lastAudio?.isPreview == true
                      ? "Previews can't be exported — Re-generate the full script first"
                      : "Export audio and captions (⌘S)")
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportSheet()
        }
        .alert("Save Profile", isPresented: $showingSaveProfile) {
            TextField("Profile name", text: $newProfileName)
            Button("Save") {
                let name = newProfileName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                try? ProfileStore.save(state.currentProfile(), name: name)
                profileNames = ProfileStore.list()
                state.currentProfileName = name
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves engine, voice, speed, pauses, dictionary, and output settings under one name.")
        }
        .sheet(item: Binding(
            get: { quickAddWord.map(QuickAddTarget.init) },
            set: { quickAddWord = $0?.word })) { target in
            QuickAddDictionaryView(word: target.word,
                                   rulesText: $state.pronunciationRulesText)
        }
        .sheet(item: Binding(
            get: { state.auditionText.map(AuditionTarget.init) },
            set: { state.auditionText = $0?.text })) { target in
            VoiceAuditionView(text: target.text)
        }
        .sheet(item: Binding(
            get: { state.importedText.map(AuditionTarget.init) },
            set: { state.importedText = $0?.text })) { target in
            ImportPreviewView(text: target.text)
        }
        .fileImporter(isPresented: $state.showingImportPanel,
                      allowedContentTypes: ScriptImporter.importableTypes) { result in
            if case .success(let url) = result { importDocument(at: url) }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url,
                      ScriptImporter.importableExtensions
                          .contains(url.pathExtension.lowercased()) else { return }
                Task { @MainActor in importDocument(at: url) }
            }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSTextView.didChangeSelectionNotification)) { _ in
            hasEditorSelection = selectedEditorText() != nil
            // Click-to-seek: only while playing, so ordinary caret
            // placement during editing never jumps the audio.
            if player.isPlaying, state.followAlongHighlight,
               let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
               textView.selectedRange().length == 0,
               let target = highlighter.seekTarget(
                   forCharacterAt: textView.selectedRange().location) {
                player.seek(to: target)
            }
        }
        .onChange(of: state.lastAudio?.previewWAV) { _, url in
            highlighter.prepare(audio: state.lastAudio, script: state.script)
            if let url {
                player.load(url: url)
                if state.autoplayAfterGenerate {
                    player.togglePlayPause()
                }
            }
        }
        .onChange(of: state.script) {
            // Re-checks staleness; prepare bails fast on mismatch and
            // clears any now-misaligned highlight.
            highlighter.prepare(audio: state.lastAudio, script: state.script)
        }
        .onReceive(player.$currentTime) { time in
            if state.followAlongHighlight, player.isPlaying {
                highlighter.update(time: time)
            }
        }
        .onChange(of: player.isPlaying) { _, playing in
            if !playing { highlighter.clearHighlight() }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { state.errorMessage != nil },
                                    set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    private var scriptSummary: String {
        let words = DurationEstimator.wordCount(of: state.script)
        guard words > 0 else { return "" }
        let estimate = DurationEstimator.estimate(
            script: state.script, pauses: state.pauseSettings,
            wordsPerSecond: state.calibratedWordsPerSecond, speed: state.speed)
        return "\(words) words · estimated \(DurationEstimator.formatted(estimate))"
    }

    /// Word/duration count and pronunciation flags — outside the page card,
    /// anchored under the text area (#18).
    private var scriptInfoRow: some View {
        HStack(spacing: 14) {
            if !scriptSummary.isEmpty {
                Text(scriptSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .help("Estimated audio length — calibrates from your actual generations")
            }
            if !pronunciationSuspects.isEmpty {
                Button {
                    showingLinter = true
                } label: {
                    Label("\(pronunciationSuspects.count) pronunciation flags",
                          systemImage: "exclamationmark.bubble")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .help("Acronyms that may be mispronounced — click to review")
                .popover(isPresented: $showingLinter, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Possible pronunciation issues")
                            .font(.headline)
                        Text("ALL-CAPS terms with no dictionary rule. Add @letters to spell them out, or @word to silence the flag.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(pronunciationSuspects, id: \.self) { token in
                            HStack {
                                Text(token).font(.body.monospaced())
                                Spacer()
                                Button("Add…") {
                                    showingLinter = false
                                    quickAddWord = token
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(14)
                    .frame(width: 320)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            statusView
            Spacer()
            if state.isGenerating {
                Button("Stop") {
                    state.cancelGeneration()
                }
                .secondaryActionButtonStyle()
                .controlSize(.large)
                .help("Stop generation")
            } else {
                // Once audio exists, Re-generate lives in the player bar
                // next to Play (#17); this bar keeps the first Generate.
                if state.lastAudio == nil {
                    Button("Generate") {
                        player.stop()
                        state.generate()
                    }
                    .prominentActionButtonStyle()
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!state.canGenerate)
                    .help("Generate speech (⌘↩)")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusView: some View {
        switch state.phase {
        case .loadingModel:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading model…")
            }
        case .generating(let progress):
            ProgressView(value: Double(progress))
                .frame(width: 140)
                .help("Generating: \(Int(progress * 100))%")
        case .failed(let message):
            Label("Model failed to load", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help(message)
        case .ready:
            EmptyView()
        }
    }
}

struct EditorView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TextEditor(text: $state.script)
            .font(.system(size: state.editorFontSize))
            .lineSpacing(4)
            .scrollContentBackground(.hidden)
            .editorWritingTools()
            // Overlay on the TextEditor itself so the placeholder shares its
            // coordinate space: 5pt = NSTextView's line fragment padding,
            // which is exactly where the caret sits.
            .overlay(alignment: .topLeading) {
                if state.script.isEmpty {
                    Text("Type or paste your script here…")
                        .foregroundStyle(.secondary)
                        .font(.system(size: state.editorFontSize))
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(8)
            // Keep the last lines reachable above the floating glass bars.
            .contentMargins(.bottom, 120, for: .scrollContent)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary)
        )
        .shadow(color: .black.opacity(0.10), radius: 10, y: 2)
    }
}
