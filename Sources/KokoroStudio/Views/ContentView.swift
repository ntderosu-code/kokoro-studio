import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var player = PlayerController()
    @State private var quickAddWord: String?
    @State private var showingSyntaxHelp = false
    @State private var showingLinter = false

    private var pronunciationSuspects: [String] {
        ScriptLinter.acronymSuspects(
            in: state.script,
            coveredBy: PronunciationDictionary.parse(state.pronunciationRulesText))
    }
    @State private var showingExportSheet = false
    @State private var showingSaveProfile = false
    @State private var newProfileName = ""
    @State private var profileNames = ProfileStore.list()
    @State private var selectedProfile = ""

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
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Menu {
                    Picker("Profile", selection: $selectedProfile) {
                        Text("Custom").tag("")
                        ForEach(profileNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Save Current As…") {
                        newProfileName = selectedProfile
                        showingSaveProfile = true
                    }
                    if !selectedProfile.isEmpty {
                        Button("Delete \"\(selectedProfile)\"", role: .destructive) {
                            ProfileStore.delete(name: selectedProfile)
                            profileNames = ProfileStore.list()
                            selectedProfile = ""
                        }
                    }
                } label: {
                    Label(selectedProfile.isEmpty ? "Profile" : selectedProfile,
                          systemImage: "square.stack")
                }
                .help("Apply, save, or delete settings profiles")
                .onChange(of: selectedProfile) { _, name in
                    if !name.isEmpty, let profile = ProfileStore.load(name: name) {
                        state.apply(profile)
                    }
                }
            }

            ToolbarItemGroup {
                Button("Preview Selection", systemImage: "waveform.and.magnifyingglass") {
                    if let selection = selectedEditorText() {
                        player.stop()
                        state.generate(textOverride: selection)
                    } else {
                        state.errorMessage =
                            "Select part of the script first — Preview generates just the selection."
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(state.phase != .ready)
                .help("Generate only the selected text (⇧⌘↩)")

                Button("Find & Replace", systemImage: "magnifyingglass") {
                    showFindAndReplace()
                }
                .help("Find and replace in the script (⌘F)")

                if #available(macOS 15.2, *) {
                    WritingToolsToolbarButton()
                        .help("Proofread or rewrite the selection with Apple Intelligence")
                }

                Button("Export", systemImage: "square.and.arrow.up") {
                    showingExportSheet = true
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(state.lastAudio == nil || state.lastAudio?.isPreview == true)
                .help(state.lastAudio?.isPreview == true
                      ? "Previews can't be exported — Re-generate the full script first"
                      : "Export audio and captions (⌘S)")

                Button("Add to Dictionary", systemImage: "character.book.closed") {
                    if let selection = selectedEditorText() {
                        quickAddWord = selection
                    } else {
                        state.errorMessage =
                            "Select a word or phrase in the editor first, then press ⌘D."
                    }
                }
                .keyboardShortcut("d", modifiers: .command)
                .help("Add selected word to pronunciation dictionary (⌘D)")

                Button("Script Syntax", systemImage: "questionmark.circle") {
                    showingSyntaxHelp = true
                }
                .help("Script syntax: pauses, speakers, headings, pronunciation")
                .popover(isPresented: $showingSyntaxHelp, arrowEdge: .bottom) {
                    SyntaxCheatSheet()
                }

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Preferences: voices, editor, playback, export (⌘,)")
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
                selectedProfile = name
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
        .onChange(of: state.lastAudio?.previewWAV) { _, url in
            if let url {
                player.load(url: url)
                if state.autoplayAfterGenerate {
                    player.togglePlayPause()
                }
            }
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
        return "\(words) words · est. \(DurationEstimator.formatted(estimate))"
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
