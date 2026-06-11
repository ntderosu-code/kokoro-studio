import SwiftUI

struct PlayerBar: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var player: PlayerController
    var onExport: () -> Void = {}
    var onRegenerate: () -> Void = {}

    @State private var peaks: [Float] = []
    @State private var markers: [HeadingMarker] = []

    private func rebuildWaveform() {
        guard let audio = state.lastAudio else {
            peaks = []
            markers = []
            return
        }
        peaks = WaveformBuilder.peaks(samples: audio.samples, buckets: 240)
        markers = WaveformBuilder.headingMarkers(cues: audio.cues,
                                                 script: audio.sourceScript)
    }

    private func timeString(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        HStack(spacing: 12) {
            if state.lastAudio?.isPreview == true {
                Text("PREVIEW")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
                    .help("This is the selected text only — Re-generate renders the full script")
            }

            Button("Re-generate") {
                onRegenerate()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(state.phase != .ready || !state.canGenerate)
            .help("Generate speech again (⌘↩)")

            if state.canPatch {
                Button("Patch") {
                    player.stop()
                    state.patchRegenerate()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .help("Re-render only the edited lines and splice them into the existing audio (⌥⌘↩)")
            }

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

            if peaks.isEmpty {
                Slider(value: Binding(get: { player.currentTime },
                                      set: { player.seek(to: $0) }),
                       in: 0...max(player.duration, 0.01)) {
                    Text("Playback position")
                }
                .labelsHidden()
            } else {
                WaveformView(peaks: peaks, markers: markers,
                             duration: player.duration,
                             currentTime: player.currentTime,
                             onSeek: { player.seek(to: $0) })
            }

            Text(timeString(player.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("Export", systemImage: "square.and.arrow.up") {
                onExport()
            }
            .buttonStyle(.bordered)
            .disabled(state.lastAudio?.isPreview == true)
            .help(state.lastAudio?.isPreview == true
                  ? "Previews can't be exported — Re-generate the full script first"
                  : "Export audio and captions (⌘S)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { rebuildWaveform() }
        .onChange(of: state.lastAudio?.previewWAV) { rebuildWaveform() }
    }
}
