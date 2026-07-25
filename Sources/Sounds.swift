import AVFoundation

/// Two short cues — a perfect fifth rising when dictation starts, the same
/// interval falling when it stops. Low-mid (C3/G3): the fundamental sits near
/// 130 Hz, well under the old bell register. At that pitch the sub-octave is
/// trimmed (it would land near 65 Hz, where laptop speakers only flap) and a
/// second harmonic carries audibility instead. Rendered to WAV once on first use,
/// then played through `afplay`.
///
/// The detour worth remembering: playing these through our own AVAudioEngine went
/// silent, because starting the mic engine a moment later reconfigures the audio
/// device and cuts any in-process playback mid-tone. A separate process can't be
/// interrupted that way, so the tone survives — same sound, reliably audible.
@MainActor
enum Sounds {
    private static let startURL = write(notes: [130.81, 196.00], name: "sono-start")   // C3 → G3
    private static let stopURL = write(notes: [196.00, 130.81], name: "sono-stop")     // G3 → C3

    static func playStart() { play(startURL) }
    static func playStop() { play(stopURL) }

    private static func play(_ url: URL?) {
        guard Settings.soundsEnabled, let url else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = [url.path]
        try? process.run()      // fire and forget; never block dictation on a chime
    }

    /// Render the tone and stash it in the temp directory. Returns nil if
    /// anything fails, which just means no chime.
    private static func write(notes: [Double], name: String) -> URL? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = render(notes: notes, format: format) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).wav")
        do {
            // Re-render each launch: cheap, and avoids serving a stale file if the
            // tone is ever retuned.
            try? FileManager.default.removeItem(at: url)
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return url
        } catch {
            return nil
        }
    }

    /// Fundamental + sub-octave for body + a touch of third harmonic for
    /// definition; soft attack, exponential decay. Notes overlap slightly so the
    /// pair reads as one gesture. Peak checked at 0.63 — loud, no clipping.
    private static func render(notes: [Double], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let noteLength = 0.10           // seconds of attack+body per note
        let tail = 0.24                 // decay allowed to ring past the last note
        let total = noteLength * Double(notes.count - 1) + tail
        let frames = AVAudioFrameCount(total * rate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames

        for i in 0..<Int(frames) { samples[i] = 0 }

        for (index, frequency) in notes.enumerated() {
            let offset = Int(Double(index) * noteLength * rate)
            let voiceFrames = Int(min(Double(frames) - Double(offset), tail * rate))
            guard voiceFrames > 0 else { continue }

            for n in 0..<voiceFrames {
                let t = Double(n) / rate
                let attack = min(1, t / 0.012)                 // 12 ms: a tone, not a tick
                let decay = exp(-t * 9)                        // slower than a bell
                let phase = 2 * Double.pi * frequency * t
                let value = (sin(phase)
                             + 0.18 * sin(phase * 0.5)         // just a hint of sub-octave
                             + 0.30 * sin(phase * 2)           // keeps it audible on small speakers
                             + 0.12 * sin(phase * 3))          // a little definition
                            * attack * decay * 0.50
                samples[offset + n] += Float(value)
            }
        }
        return buffer
    }
}
