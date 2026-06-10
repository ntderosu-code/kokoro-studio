import SwiftUI

struct PlayerBar: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var player: PlayerController

    private func timeString(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 16)
            }
            .keyboardShortcut("p", modifiers: .command)
            .help(player.isPlaying ? "Pause (⌘P)" : "Play (⌘P)")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Text(timeString(player.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Slider(value: Binding(get: { player.currentTime },
                                  set: { player.seek(to: $0) }),
                   in: 0...max(player.duration, 0.01)) {
                Text("Playback position")
            }
            .labelsHidden()

            Text(timeString(player.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("Export", systemImage: "square.and.arrow.down") {
                state.export()
            }
            .secondaryActionButtonStyle()
            .keyboardShortcut("s", modifiers: .command)
            .help("Export as \(state.exportFormat.label) (⌘S)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
