import Foundation

/// Everything needed to re-render one edited block and splice it into
/// existing audio (#11).
struct PatchPlan: Equatable {
    /// New text to synthesize, including a speaker-context line when the
    /// edit sits inside dialogue.
    let replacementText: String
    /// Sample range of the existing audio to remove.
    let cutSampleRange: Range<Int>
    /// Indices into the old cue array being replaced (may be empty for
    /// pure insertions).
    let replacedCueRange: Range<Int>
    /// Silence to append after the new chunk; 0 when the patch reaches
    /// the end of the audio.
    let trailingPauseMs: Int
}

/// Computes what to re-render after an edit, by diffing the script the
/// audio was generated from against the current script and mapping the
/// changed block onto cue/sample boundaries via CueAlignment. Pure logic
/// — synthesis and splicing orchestration live in AppState.
enum ScriptPatcher {
    /// Line-level diff via common prefix/suffix. nil when equal.
    static func changedLineRange(old: [String], new: [String])
        -> (old: Range<Int>, new: Range<Int>)? {
        guard old != new else { return nil }
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }
        return (prefix..<(old.count - suffix), prefix..<(new.count - suffix))
    }

    static func plan(oldScript: String, newScript: String,
                     cues: [CaptionCue], sampleRate: Int, totalSamples: Int,
                     pauses: PauseSettings) -> PatchPlan? {
        let oldLines = oldScript.components(separatedBy: "\n")
        let newLines = newScript.components(separatedBy: "\n")
        guard let changed = changedLineRange(old: oldLines, new: newLines),
              !cues.isEmpty else { return nil }

        // A wholesale rewrite patches worse than it regenerates.
        if newLines.count > 2,
           changed.new.count * 2 > newLines.count { return nil }

        // Char span (UTF-16, matching CueAlignment's NSRanges) of the
        // changed old lines.
        var offsets: [Int] = [0]
        for line in oldLines {
            offsets.append(offsets.last! + (line as NSString).length + 1)
        }
        let changedStart = offsets[changed.old.lowerBound]
        let changedEnd = changed.old.isEmpty
            ? changedStart
            : offsets[changed.old.upperBound] - 1 // exclude the newline

        let aligned = CueAlignment.align(cues: cues.map(\.text),
                                         script: oldScript)

        // Cues whose aligned range intersects the changed span.
        var intersecting: [Int] = []
        for (index, range) in aligned.enumerated() {
            guard let range else { continue }
            let rangeEnd = range.location + range.length
            if range.location < changedEnd, rangeEnd > changedStart {
                intersecting.append(index)
            }
        }

        let replacedCueRange: Range<Int>
        if let first = intersecting.first, let last = intersecting.last {
            replacedCueRange = first..<(last + 1)
        } else {
            // Pure insertion (or change in non-audible lines): splice at
            // the first cue that starts after the change.
            let insertIndex = aligned.enumerated().first { _, range in
                guard let range else { return false }
                return range.location >= changedStart
            }?.offset ?? cues.count
            replacedCueRange = insertIndex..<insertIndex
        }

        // Unaligned cues at the boundaries mean the cut points can't be
        // trusted — bail to full regeneration.
        let guardLow = max(0, replacedCueRange.lowerBound - 1)
        let guardHigh = min(cues.count, replacedCueRange.upperBound + 1)
        for index in guardLow..<guardHigh where aligned[index] == nil {
            return nil
        }

        let cutStart = replacedCueRange.lowerBound < cues.count
            ? sampleIndex(cues[replacedCueRange.lowerBound].start,
                          rate: sampleRate)
            : totalSamples
        let cutEnd = replacedCueRange.upperBound < cues.count
            ? sampleIndex(cues[replacedCueRange.upperBound].start,
                          rate: sampleRate)
            : totalSamples
        guard cutStart <= cutEnd, cutEnd <= totalSamples else { return nil }

        // Speaker context: an edit inside dialogue must keep its voice,
        // so prepend the speaker active at the start of the change.
        var replacement = newLines[changed.new].joined(separator: "\n")
        let changedHasOwnTag = newLines[changed.new].first?
            .trimmingCharacters(in: .whitespaces).hasPrefix("@") ?? false
        if !changedHasOwnTag, !replacement.isEmpty,
           let speaker = activeSpeaker(inLinesBefore: changed.new.lowerBound,
                                       of: newLines) {
            replacement = "@\(speaker):\n" + replacement
        }

        // The cut removed the old trailing pause; the new chunk re-adds
        // one sized by its own last line — unless the patch runs to the
        // end of the audio, where generation never pauses either.
        let trailingPauseMs: Int
        if replacedCueRange.upperBound < cues.count {
            let lastLine = newLines[changed.new]
                .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            trailingPauseMs = (lastLine?.trimmingCharacters(in: .whitespaces)
                .hasPrefix("#") ?? false) ? pauses.headingMs : pauses.paragraphMs
        } else {
            trailingPauseMs = 0
        }

        return PatchPlan(replacementText: replacement,
                         cutSampleRange: cutStart..<cutEnd,
                         replacedCueRange: replacedCueRange,
                         trailingPauseMs: trailingPauseMs)
    }

    static func splice(old: [Float], cut: Range<Int>,
                       replacement: [Float]) -> [Float] {
        Array(old[..<cut.lowerBound]) + replacement + Array(old[cut.upperBound...])
    }

    /// Old cues before the patch, the new chunk's cues shifted to the
    /// splice point, and the old cues after shifted by the length delta.
    static func rebuildCues(old: [CaptionCue], replacedRange: Range<Int>,
                            newCues: [CaptionCue], insertAt: Double,
                            timeDelta: Double,
                            totalDuration: Double) -> [CaptionCue] {
        let before = Array(old[..<replacedRange.lowerBound])
        let inserted = newCues.map {
            CaptionCue(start: $0.start + insertAt, end: $0.end + insertAt,
                       text: $0.text)
        }
        let after = old[replacedRange.upperBound...].map {
            CaptionCue(start: $0.start + timeDelta,
                       end: min(totalDuration, $0.end + timeDelta),
                       text: $0.text)
        }
        return (before + inserted + after).filter { $0.end > $0.start }
    }

    private static func sampleIndex(_ seconds: Double, rate: Int) -> Int {
        Int((seconds * Double(rate)).rounded())
    }

    /// Last `@Name:` tag in the lines before `index` (segmenter carries
    /// speakers forward the same way).
    private static func activeSpeaker(inLinesBefore index: Int,
                                      of lines: [String]) -> String? {
        for line in lines[..<index].reversed() {
            if let match = line.trimmingCharacters(in: .whitespaces)
                .firstMatch(of: #/^@([\w ]+):/#) {
                return String(match.1).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
