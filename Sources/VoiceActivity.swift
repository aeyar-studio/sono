import Foundation

/// Finds the speech inside a recorded buffer, and says when there is none.
///
/// Two jobs. Throw away recordings where nobody actually spoke, because a buffer
/// of pure room tone can still come back from the recogniser with a spurious
/// word. And trim the quiet off both ends, because the model is billed by audio
/// length and leading silence is time the user waits for nothing.
///
/// Deliberately not a neural VAD. Silero earns its keep on far-field or noisy
/// audio and for deciding when to *stop* recording unprompted. This runs on
/// close-mic push-to-talk, where the gap between speech and room tone is wide,
/// and it costs no model file, no download and no extra licence. `speechFrames`
/// is the seam: swapping in sherpa's SherpaOnnxVoiceActivityDetector later means
/// replacing that one function and nothing else.
enum VoiceActivity {
    /// 20 ms at 16 kHz. Long enough for a stable RMS, short enough to place the
    /// edges of a word to within a syllable.
    static let frameLength = 320

    /// Kept either side of the detected speech. Word onsets, especially plosives,
    /// start quieter than the vowel that follows, and clipping them costs the
    /// recogniser more than the extra audio does.
    static let padSeconds = 0.15

    /// Total voiced time below this is a click, a breath or a knock on the desk.
    static let minSpeechSeconds = 0.12

    /// A frame counts as speech only if it clears the room tone *and* this.
    /// Without the absolute term a silent recording has a tiny noise floor, and
    /// four times tiny is still tiny, so pure room tone reads as wall-to-wall
    /// speech and nothing ever gets rejected.
    static let absoluteFloor: Float = 0.006

    /// How far above the estimated noise floor a frame has to sit.
    static let overNoiseFloor: Float = 4

    /// The samples with silence trimmed off both ends, or nil when nobody spoke.
    static func trim(_ samples: [Float], sampleRate: Double = Recorder.sampleRate) -> [Float]? {
        guard let range = speechRange(samples, sampleRate: sampleRate) else { return nil }
        return Array(samples[range])
    }

    /// The span of `samples` worth transcribing, padded, or nil when nobody spoke.
    static func speechRange(_ samples: [Float],
                            sampleRate: Double = Recorder.sampleRate) -> Range<Int>? {
        let voiced = speechFrames(samples)
        guard let first = voiced.firstIndex(of: true),
              let last = voiced.lastIndex(of: true) else { return nil }

        // Measured on the voiced frames themselves, not on the padded span: with
        // padding included a single 20 ms blip would clear any sane threshold.
        let voicedSeconds = Double(voiced.filter { $0 }.count * frameLength) / sampleRate
        guard voicedSeconds >= minSpeechSeconds else { return nil }

        let pad = Int((padSeconds * sampleRate) / Double(frameLength))
        let start = max(0, first - pad) * frameLength
        let end = min(samples.count, min(voiced.count, last + 1 + pad) * frameLength)
        return start..<end
    }

    /// Per-frame speech decision. The whole detector lives here.
    private static func speechFrames(_ samples: [Float]) -> [Bool] {
        guard samples.count >= frameLength else { return [] }

        var energies: [Float] = []
        energies.reserveCapacity(samples.count / frameLength)
        var i = 0
        while i + frameLength <= samples.count {
            var sum: Float = 0
            for j in i..<(i + frameLength) { sum += samples[j] * samples[j] }
            energies.append((sum / Float(frameLength)).squareRoot())
            i += frameLength
        }

        // 20th percentile rather than the minimum: one unusually dead frame
        // should not define the floor, and a recording that is mostly speech
        // still has enough quiet frames down here to estimate from.
        let noiseFloor = percentile(energies, 0.2)
        let threshold = max(noiseFloor * overNoiseFloor, absoluteFloor)
        return energies.map { $0 > threshold }
    }

    private static func percentile(_ values: [Float], _ p: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[min(sorted.count - 1, max(0, index))]
    }

    #if DEBUG
    static func selfTest() {
        let rate = Recorder.sampleRate

        // Room tone, well under the absolute floor.
        func quiet(_ seconds: Double) -> [Float] {
            (0..<Int(seconds * rate)).map { _ in Float.random(in: -0.0006...0.0006) }
        }
        // ~300 Hz, in the range a voice actually occupies.
        func speech(_ seconds: Double, amplitude: Float = 0.2) -> [Float] {
            (0..<Int(seconds * rate)).map { amplitude * sin(Float($0) * 0.12) }
        }

        assert(trim([]) == nil, "an empty buffer is not speech")
        assert(trim(quiet(2.0)) == nil, "two seconds of room tone is not speech")
        assert(trim(speech(0.02)) == nil, "a 20 ms blip is a click, not a word")

        let recording = quiet(1.0) + speech(0.8) + quiet(1.0)
        guard let range = speechRange(recording) else {
            assertionFailure("missed obvious speech"); return
        }
        let start = Double(range.lowerBound) / rate
        let end = Double(range.upperBound) / rate
        assert(start > 0.5 && start <= 1.0, "start should sit just before the speech, got \(start)")
        assert(end >= 1.8 && end < 2.4, "end should sit just after the speech, got \(end)")

        let trimmed = trim(recording)!
        assert(trimmed.count < recording.count, "silence must actually come off")
        assert(trimmed.count > Int(0.8 * rate), "the speech itself must survive intact")

        // A quiet talker still registers: the floor is relative as well as absolute.
        assert(trim(quiet(0.5) + speech(0.5, amplitude: 0.03) + quiet(0.5)) != nil,
               "a soft voice is still a voice")
        print("VoiceActivity.selfTest ok")
    }
    #endif
}
