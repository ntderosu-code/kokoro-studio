import SwiftUI

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Link("Kokoro Studio Help",
                 destination: URL(string: "https://github.com/ntderosu-code/kokoro-studio#readme")!)
            Button("Script Syntax Reference") {
                openWindow(id: "syntax-reference")
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

    var body: some Scene {
        WindowGroup("Kokoro Studio") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 720, minHeight: 480)
                .task { state.loadModel() }
        }
        .defaultSize(width: 940, height: 620)
        .commands {
            // System Find / Find & Replace menu items (⌘F, ⌥⌘F) wired to the
            // focused text view's native find bar.
            TextEditingCommands()
            HelpCommands()
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
