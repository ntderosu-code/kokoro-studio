import SwiftUI

/// Clickable waveform scrubber with heading tick marks (#36). PlayerBar
/// falls back to its Slider when peaks are empty.
struct WaveformView: View {
    let peaks: [Float]
    let markers: [HeadingMarker]
    let duration: Double
    let currentTime: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let count = peaks.count
                    guard count > 0 else { return }
                    let barWidth = size.width / CGFloat(count)
                    let playedX = duration > 0
                        ? size.width * CGFloat(currentTime / duration) : 0
                    for (index, peak) in peaks.enumerated() {
                        let x = CGFloat(index) * barWidth
                        let barHeight = max(1.5, size.height * CGFloat(peak))
                        let rect = CGRect(x: x,
                                          y: (size.height - barHeight) / 2,
                                          width: max(1, barWidth - 1),
                                          height: barHeight)
                        let played = x + barWidth / 2 <= playedX
                        context.fill(Path(roundedRect: rect, cornerRadius: 0.5),
                                     with: .color(played
                                                  ? Color.accentColor
                                                  : Color.secondary.opacity(0.45)))
                    }
                }

                // Heading ticks with hover titles.
                ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
                    let x = duration > 0
                        ? width * CGFloat(marker.time / duration) : 0
                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 1.5, height: height)
                        .offset(x: x)
                        .help(marker.title)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in seek(at: value.location.x, width: width) }
                    .onEnded { value in seek(at: value.location.x, width: width) })
        }
        .frame(height: 26)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int(currentTime)) of \(Int(duration)) seconds")
        .accessibilityAdjustableAction { direction in
            let step = max(1, duration / 20)
            onSeek(direction == .increment
                   ? min(duration, currentTime + step)
                   : max(0, currentTime - step))
        }
    }

    private func seek(at x: CGFloat, width: CGFloat) {
        guard duration > 0, width > 0 else { return }
        let fraction = min(max(x / width, 0), 1)
        onSeek(Double(fraction) * duration)
    }
}
