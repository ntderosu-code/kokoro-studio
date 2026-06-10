import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var player = PlayerController()
    @State private var sidebarVisible = true
    @State private var quickAddWord: String?
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

    var body: some View {
        EditorView()
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .frame(minWidth: 380, maxWidth: .infinity,
                   minHeight: 200, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
            BarGlassContainer(spacing: 10) {
                VStack(spacing: 10) {
                    if state.lastAudio != nil {
                        PlayerBar(player: player,
                                  onExport: { showingExportSheet = true })
                            .barGlass()
                    }
                    actionBar
                        .barGlass()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.top, 4)
            }
            .animation(.spring(duration: 0.35),
                       value: state.lastAudio?.previewWAV)
        }
        // The "desk" the page card and glass controls sit on. Standard window
        // background — lighter than underPageBackground, and the titlebar
        // keeps its system material.
        .background(Color(nsColor: .windowBackgroundColor),
                    ignoresSafeAreaEdges: .bottom)
        .inspector(isPresented: $sidebarVisible) {
            SidebarView()
                .inspectorColumnWidth(min: 240, ideal: 290, max: 360)
        }
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
                Button("Export", systemImage: "square.and.arrow.up") {
                    showingExportSheet = true
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(state.lastAudio == nil)
                .help("Export audio and captions (⌘S)")

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

                Button("Settings", systemImage: "sidebar.right") {
                    withAnimation { sidebarVisible.toggle() }
                }
                .help("Toggle settings sidebar")
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
            if let url { player.load(url: url) }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { state.errorMessage != nil },
                                    set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
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
                Button(state.lastAudio == nil ? "Generate" : "Re-generate") {
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

    private var wordCount: Int {
        state.script.split { $0.isWhitespace || $0.isNewline }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $state.script)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                if state.script.isEmpty {
                    Text("Type or paste your script here…")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                        .padding(.top, 16)
                        .padding(.leading, 13)
                        .allowsHitTesting(false)
                }
            }
            Divider()
            HStack {
                Text("\(wordCount) words · \(state.script.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary)
        )
        .shadow(color: .black.opacity(0.10), radius: 10, y: 2)
    }
}
