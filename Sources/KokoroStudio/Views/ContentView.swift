import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var player = PlayerController()
    @State private var sidebarVisible = true

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                EditorView()
                    .frame(minWidth: 380, maxWidth: .infinity,
                           minHeight: 200, maxHeight: .infinity)
                if sidebarVisible {
                    SidebarView()
                        .frame(minWidth: 230, idealWidth: 270, maxWidth: 340)
                }
            }
            if state.lastAudio != nil {
                Divider()
                PlayerBar(player: player)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                statusView
                if state.isGenerating {
                    Button("Stop", systemImage: "stop.fill") {
                        state.cancelGeneration()
                    }
                    .help("Stop generation")
                } else {
                    Button("Generate", systemImage: "waveform") {
                        player.stop()
                        state.generate()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!state.canGenerate)
                    .help("Generate speech (⌘↩)")
                }
                Button("Settings", systemImage: "sidebar.right") {
                    withAnimation { sidebarVisible.toggle() }
                }
                .help("Toggle settings sidebar")
            }
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
    }
}
