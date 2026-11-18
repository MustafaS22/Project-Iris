import AVFoundation
import CoreAudio
import CoreMedia
import Speech

/// Capture has no playback node and never changes system audio defaults. All
/// session changes and buffer appends are serialized on the same private queue.
final class VoiceCaptureSession: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.projectiris.voice-capture", qos: .userInitiated)
    private var session: AVCaptureSession?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var recordingURL: URL?
    private var activity: (@Sendable () -> Void)?
    private var writerStarted = false
    private var lastActivity = 0.0
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func start(request: SFSpeechAudioBufferRecognitionRequest, record: Bool = false, onActivity: (@Sendable () -> Void)? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let device = Self.microphone() else { throw IrisFailure.message("No microphone is available.") }
                    let session = AVCaptureSession()
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureAudioDataOutput()
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        throw IrisFailure.message("Iris couldn’t configure the microphone. Check your Mac’s sound input and try again.")
                    }
                    session.addInput(input)
                    session.addOutput(output)
                    self.activity=onActivity
                    if record {
                        let url=FileManager.default.temporaryDirectory.appendingPathComponent("IrisVoice-"+UUID().uuidString+".m4a")
                        let writer=try AVAssetWriter(outputURL:url,fileType:.m4a)
                        let input=AVAssetWriterInput(mediaType:.audio,outputSettings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:16000,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:32000])
                        input.expectsMediaDataInRealTime=true
                        guard writer.canAdd(input) else{throw IrisFailure.message("Couldn't prepare local voice recognition.")};writer.add(input)
                        self.writer=writer;self.writerInput=input;self.recordingURL=url;self.writerStarted=false
                    }
                    self.request = request
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    self.session = session
                    session.startRunning()
                    guard session.isRunning else {
                        self.finish()
                        throw IrisFailure.message("The microphone couldn’t start. Check your Mac’s sound input and try again.")
                    }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() { queue.async { self.finish() } }

    private func finish() {
        let pending = request
        request = nil
        if session?.isRunning == true { session?.stopRunning() }
        session = nil
        pending?.endAudio()
        activity=nil;writer?.cancelWriting();writer=nil;writerInput=nil;writerStarted=false
        if let url=recordingURL {try? FileManager.default.removeItem(at:url)};recordingURL=nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        request?.appendAudioSampleBuffer(sampleBuffer)
        let now=ProcessInfo.processInfo.systemUptime
        if connection.audioChannels.contains(where:{$0.averagePowerLevel > -38}),now-lastActivity>0.12 {lastActivity=now;activity?()}
        if let writer,let input=writerInput {
            if !writerStarted {
                guard writer.startWriting() else{return};writer.startSession(atSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer));writerStarted=true
            }
            if input.isReadyForMoreMediaData {input.append(sampleBuffer)}
        }
    }

    func finishRecording() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.request?.endAudio();self.request=nil;self.activity=nil
                if self.session?.isRunning == true{self.session?.stopRunning()};self.session=nil
                guard let writer=self.writer,let input=self.writerInput,let url=self.recordingURL,self.writerStarted else{self.finish();continuation.resume(throwing:IrisFailure.message("No microphone audio was captured."));return}
                self.writer=nil;self.writerInput=nil;self.recordingURL=nil;self.writerStarted=false
                input.markAsFinished()
                writer.finishWriting {
                    defer{try? FileManager.default.removeItem(at:url)}
                    do {guard writer.status == .completed else{throw IrisFailure.message("The voice recording couldn't be finished.")};continuation.resume(returning:try Data(contentsOf:url))}
                    catch{continuation.resume(throwing:error)}
                }
            }
        }
    }
    private static func microphone() -> AVCaptureDevice? {
        guard let selected = AVCaptureDevice.default(for: .audio) else { return nil }
        let transport = UInt32(bitPattern: selected.transportType)
        guard transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE else { return selected }
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
        func matches(_ device: AVCaptureDevice, _ type: UInt32) -> Bool {
            device.isConnected && UInt32(bitPattern: device.transportType) == type
        }
        return devices.first { matches($0, kAudioDeviceTransportTypeBuiltIn) }
            ?? devices.first { matches($0, kAudioDeviceTransportTypeUSB) }
            ?? selected
    }
}
