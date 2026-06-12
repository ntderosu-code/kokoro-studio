import SwiftUI

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Link("Kokoro Studio Help",
                 destination: URL(string: "https://github.com/ntderosu-code/kokoro-studio#readme")!)
            Button("Script Syntax Reference") {
                openWindow(id: "syntax-reference")
            }
            Button("Restore Sample Script") {
                state.requestRestoreSampleScript()
            }
            Divider()
            Link("Report an Issue…",
                 destination: URL(string: "https://github.com/ntderosu-code/kokoro-studio/issues")!)
        }
    }
}

@main
struct KokoroStudioApp: App {
    @StateObject private var state = AppState()
    private let appUpdater = AppUpdater()

    var body: some Scene {
        WindowGroup("Kokoro Studio") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 720, minHeight: 480)
                .task {
                    state.loadModel()
                    state.seedSampleScriptIfFirstRun()
                    state.loadLibrary()
                    ServiceProvider.shared.state = state
                    NSApp.servicesProvider = ServiceProvider.shared
                    NSUpdateDynamicServices()
                }
        }
        .defaultSize(width: 940, height: 620)
        .commands {
            // System Find / Find & Replace menu items (⌘F, ⌥⌘F) wired to the
            // focused text view's native find bar.
            TextEditingCommands()
            HelpCommands(state: state)
            CommandGroup(after: .appInfo) {
                if let updater = appUpdater.updater {
                    CheckForUpdatesView(updater: updater)
                }
            }
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
        }

        Window("Script Syntax", id: "syntax-reference") {
            SyntaxCheatSheet()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}
