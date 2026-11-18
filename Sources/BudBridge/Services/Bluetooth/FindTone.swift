import AVFoundation
import Observation

/// Plays the "find earbuds" sound.
protocol FindTonePlaying: AnyObject {
    var isPlaying: Bool { get }
    func toggle()
}

/// "Find earbuds": the earbuds have no locator command, so, like the phone app, play a loud
/// repeating chirp through the current audio output (the earbuds, when they're connected).
@Observable
final class FindTone: FindTonePlaying {
    private(set) var isPlaying = false

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var source: AVAudioSourceNode?

    func toggle() {
        if isPlaying { stop() } else { start() }
    }

    func start() {
        guard !isPlaying else { return }
        let format = engine.outputNode.inputFormat(forBus: 0)
        let node = Self.makeChirp(sampleRate: format.sampleRate)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1))
        engine.mainMixerNode.outputVolume = 0.6
        do {
            try engine.start()
            source = node
            isPlaying = true
        } catch {
            engine.detach(node)
        }
    }

    func stop() {
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
        isPlaying = false
    }

    /// Two alternating tones, 120 ms each, then 400 ms of silence. Renders on the audio thread.
    nonisolated private static func makeChirp(sampleRate: Double) -> AVAudioSourceNode {
        var phase = 0.0
        var sample = 0
        let period = Int(sampleRate * 0.64)
        return AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frameCount) {
                let t = sample % period
                let frequency: Double? = switch t {
                case ..<Int(sampleRate * 0.12): 2_700
                case ..<Int(sampleRate * 0.24): 3_400
                default: nil
                }
                var value: Float = 0
                if let frequency {
                    phase += 2 * .pi * frequency / sampleRate
                    if phase > 2 * .pi { phase -= 2 * .pi }
                    value = Float(sin(phase)) * 0.8
                }
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
                sample += 1
            }
            return noErr
        }
    }
}
