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
    }
}
