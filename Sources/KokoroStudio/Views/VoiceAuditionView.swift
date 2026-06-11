import SwiftUI

/// Side-by-side comparison of two voices speaking the same text (#32).
/// Renders are cached for the session, so alternating playback is instant
/// after the first listen on each side.
struct VoiceAuditionView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let text: String

    @State private var voiceA: AuditionVoice = .kokoro(3)
    @State private var voiceB: AuditionVoice = .kokoro(2)

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compare Voices").font(.headline)
                Text("“\(text)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            HStack(spacing: 0) {
                column(title: "Voice A", selection: $voiceA)
                Divider()
                column(title: "Voice B", selection: $voiceB)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 320)
        .onAppear {
            // A starts as whatever the script currently uses; B starts on
            // a different recommended voice so play-play comparison works
            // immediately.
            voiceA = state.engineKind == .pocket
                ? .pocket : .kokoro(state.voiceID)
            if voiceA == voiceB {
                voiceB = .kokoro(state.voiceID == 2 ? 3 : 2)
            }
        }
        .onDisappear { state.stopAudition() }
    }

    @ViewBuilder
    private func column(title: String,
                        selection: Binding<AuditionVoice>) -> some View {
        VStack(spacing: 14) {
            Picker(title, selection: selection) {
                ForEach(state.visibleVoiceGroups, id: \.label) { group in
                    Section(group.label) {
                        ForEach(group.voices) { voice in
                            Text(voice.displayName)
                                .tag(AuditionVoice.kokoro(voice.id))
                        }
                    }
                }
                if state.engineKind == .pocket || !state.pocketVoicePath.isEmpty {
                    Text("Pocket (cloned sample)").tag(AuditionVoice.pocket)
                }
            }
            .labelsHidden()

            Button {
                state.toggleAudition(text: text, voice: selection.wrappedValue)
            } label: {
                if state.auditionRendering == selection.wrappedValue {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 34, height: 34)
                } else {
                    Image(systemName: state.auditionPlaying == selection.wrappedValue
                          ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                }
            }
            .buttonStyle(.plain)
            .disabled(state.auditionRendering != nil)
            .accessibilityLabel("Play \(selection.wrappedValue.label)")

            Button("Use This Voice") {
                state.useAuditionVoice(selection.wrappedValue)
                dismiss()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
