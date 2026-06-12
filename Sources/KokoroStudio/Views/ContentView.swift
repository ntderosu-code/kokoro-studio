import SwiftUI

struct AuditionTarget: Identifiable {
    let text: String
    var id: String { text }
}

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var player = PlayerController()
    @StateObject private var highlighter = FollowAlongHighlighter()
    @Namespace private var glassNamespace
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
            VStack(spacing: 0) {
            ScriptTabBar()
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
                                    .barGlassID("player-bar", in: glassNamespace)
                            }
                            // Only present while it has content: the first
                            // Generate, or status/Stop during generation.
                            if state.lastAudio == nil || state.isGenerating {
                                actionBar
                                    .barGlass()
                                    .barGlassID("action-bar", in: glassNamespace)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 16)
                    }
                    .animation(.spring(duration: 0.35),
                               value: state.lastAudio?.previewWAV)
                }
            }
            scriptInfoRow
        }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(minWidth: 380, maxWidth: .infinity,
                   minHeight: 200, maxHeight: .infinity)
        .toolbar(id: "main") {
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
                    // ⌘T lives on the File-menu command; registering it twice
                    // would double-fire.
                    Button("Import Document…", systemImage: "square.and.arrow.down") {
                        state.showingImportPanel = true
                    }
                } label: {
                    Label("Scripts", systemImage: "doc.text")
                }
                .help("Open a script from the library")
            }

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

            ToolbarItem(id: "margin-speakers") {
                Button {
                    state.marginSpeakerMode.toggle()
                } label: {
                    Label("Speaker Margins",
                          systemImage: state.marginSpeakerMode
                              ? "person.crop.rectangle.badge.plus.fill"
                              : "person.crop.rectangle.badge.plus")
                }
                .help(state.marginSpeakerMode
                      ? "Hide the speaker margin"
                      : "Show speaker icons in the margin to assign voices per paragraph")
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
        .sheet(isPresented: $state.showingBatchSheet) {
            BatchQueueView()
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
                .buttonStyle(.bordered)
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
                    .buttonStyle(.borderedProminent)
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
    @State private var pendingPickerParagraph: Int?

    private func refreshChips() {
        SpeakerChipRenderer.apply(
            enabled: state.marginSpeakerMode,
            script: state.script,
            colorOverrides: state.speakerColors,
            symbolOverrides: state.speakerSymbols,
            in: EditorTextAccess.findTextView(in: NSApp.keyWindow))
    }

    private func handleParagraphTap(_ paragraphIndex: Int) {
        pendingPickerParagraph = paragraphIndex
    }

    /// Script speakers in document order, then mapped voices not in the script.
    private var knownSpeakers: [String] {
        var names = ScriptSegmenter.speakerNames(in: state.script)
        for name in state.speakerVoices.keys.sorted() where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    private func currentSpeaker(forParagraph index: Int) -> String {
        let spans = ParagraphSpeakers.resolve(script: state.script)
        guard spans.indices.contains(index) else { return ParagraphSpeakers.narratorName }
        return spans[index].speaker
    }

    /// Applies a SpeakerTagEditor edit through the text view so the change
    /// lands on the native undo stack as a single step.
    private func assignSpeaker(_ speaker: String, toParagraph index: Int) {
        guard let edit = SpeakerTagEditor.assign(
                script: state.script, paragraphIndex: index, to: speaker),
              let textView = EditorTextAccess.focusTextView(in: NSApp.keyWindow)
        else { return }
        if textView.shouldChangeText(in: edit.range,
                                     replacementString: edit.replacement) {
            textView.textStorage?.replaceCharacters(in: edit.range,
                                                    with: edit.replacement)
            textView.didChangeText()
        }
        state.script = textView.string   // keep the binding in sync
        refreshChips()
        // Gutter refresh happens via the script change driving SpeakerGutterHost.
    }

    /// Persists a new speaker's voice and visual identity, then tags the
    /// paragraph with it.
    private func createSpeaker(name: String, voiceID: Int,
                               colorIndex: Int, symbolIndex: Int,
                               forParagraph index: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != SpeakerIdentity.narratorName else { return }
        var voices = state.speakerVoices; voices[trimmed] = voiceID
        state.speakerVoices = voices
        var colors = state.speakerColors; colors[trimmed] = colorIndex
        state.speakerColors = colors
        var symbols = state.speakerSymbols; symbols[trimmed] = symbolIndex
        state.speakerSymbols = symbols
        assignSpeaker(trimmed, toParagraph: index)
    }

    private struct PickerTarget: Identifiable { let id: Int }

    var body: some View {
        HStack(spacing: 0) {
            if state.marginSpeakerMode {
                SpeakerGutterHost(script: state.script,
                                  colorOverrides: state.speakerColors,
                                  symbolOverrides: state.speakerSymbols,
                                  paragraphTapped: handleParagraphTap)
                    .frame(width: 34)
                    .popover(item: Binding(
                        get: { pendingPickerParagraph.map(PickerTarget.init) },
                        set: { pendingPickerParagraph = $0?.id }
                    ), arrowEdge: .leading) { target in
                        SpeakerPickerPopover(
                            knownSpeakers: knownSpeakers,
                            currentSpeaker: currentSpeaker(forParagraph: target.id),
                            colorOverrides: state.speakerColors,
                            symbolOverrides: state.speakerSymbols,
                            voiceGroups: state.visibleVoiceGroups,
                            defaultVoiceID: state.voiceID,
                            onPick: { name in
                                assignSpeaker(name, toParagraph: target.id)
                                pendingPickerParagraph = nil
                            },
                            onCreate: { name, voiceID, colorIndex, symbolIndex in
                                createSpeaker(name: name, voiceID: voiceID,
                                              colorIndex: colorIndex,
                                              symbolIndex: symbolIndex,
                                              forParagraph: target.id)
                                pendingPickerParagraph = nil
                            })
                    }
            }
            editorCore
        }
        .background(Color(nsColor: .textBackgroundColor))
        // Top corners are square so the tab strip fuses to the card.
        .clipShape(UnevenRoundedRectangle(
            bottomLeadingRadius: GlassMetrics.cornerRadius,
            bottomTrailingRadius: GlassMetrics.cornerRadius))
        .overlay(
            UnevenRoundedRectangle(
                bottomLeadingRadius: GlassMetrics.cornerRadius,
                bottomTrailingRadius: GlassMetrics.cornerRadius)
                .strokeBorder(.quaternary)
        )
        .shadow(color: .black.opacity(0.10), radius: 10, y: 2)
        .onAppear { refreshChips() }
        .onChange(of: state.script) { _, _ in refreshChips() }
        .onChange(of: state.marginSpeakerMode) { _, _ in refreshChips() }
    }

    private var editorCore: some View {
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
    }
}
