import SwiftUI

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
            // Replace the default (empty) help viewer with something useful.
            CommandGroup(replacing: .help) {
                Link("Kokoro Studio Help",
                     destination: URL(string: "https://github.com/ntderosu-code/kokoro-studio#readme")!)
                Link("Report an Issue…",
                     destination: URL(string: "https://github.com/ntderosu-code/kokoro-studio/issues")!)
            }
        }
    }
}
