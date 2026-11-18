import AVFoundation

/// Plays PCM as it arrives; the engine is independent from microphone capture.
@MainActor final class StreamingSpeechPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let speed = AVAudioUnitTimePitch()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private var decoder = PCM16Stream()
    private var generation = UUID()
    private var scheduled = 0
    private var pendingSamples: [Float] = []
    private var finished = false
    var onPlaying: ((Bool) -> Void)?
    init() {
        engine.attach(player); engine.attach(speed)
        engine.connect(player, to: speed, format: format)
        engine.connect(speed, to: engine.mainMixerNode, format: format)
    }
    func enqueue(_ bytes: Data, rate: Double, flush: Bool = false) throws {
        pendingSamples += decoder.append(bytes)
        // A 100 ms jitter buffer smooths small network packets without waiting for a whole clip.
        guard pendingSamples.count >= 2400 || flush && !pendingSamples.isEmpty else { return }
        let samples = pendingSamples; pendingSamples.removeAll(keepingCapacity: true)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)), let channel = buffer.floatChannelData?[0] else { throw IrisFailure.message("Couldn't prepare streaming audio playback.") }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in channel.update(from: source.baseAddress!, count: samples.count) }
        speed.rate = Float(min(1.4, max(0.75, rate)))
        if !engine.isRunning { try engine.start() }
        scheduled += 1
        let token = generation
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.generation == token else { return }
                self.scheduled -= 1
                if self.scheduled == 0 {
                    self.onPlaying?(false)
                    if self.finished { self.player.stop(); self.engine.stop() }
                }
            }
        }
        if !player.isPlaying { player.play() }
        onPlaying?(true)
    }
    func flush(rate: Double) throws { try enqueue(Data(), rate: rate, flush: true) }
    func finish() {
        finished = true
        if scheduled == 0 { player.stop(); engine.stop(); onPlaying?(false) }
    }
    func stop() {
        generation = UUID(); scheduled = 0; pendingSamples = []; finished = true; decoder = PCM16Stream()
        player.stop(); engine.stop(); onPlaying?(false)
    }
}
