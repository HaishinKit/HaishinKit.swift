import AVFoundation
import Foundation

#if os(iOS) || os(tvOS) || os(macOS)
/// Configuration calback block for an AudioDeviceUnit
@available(tvOS 17.0, *)
public typealias AudioDeviceConfigurationBlock = @Sendable (AudioDeviceUnit) throws -> Void

/// An object that provides the interface to control the AVCaptureDevice's transport behavior.
@available(tvOS 17.0, *)
public final class AudioDeviceUnit: DeviceUnit {
    /// The output type that this capture audio data output..
    public typealias Output = AVCaptureAudioDataOutput

    /// The track number.
    public let track: UInt8
    /// The input data to a cupture session.
    public private(set) var input: AVCaptureInput?
    /// The current audio device object.
    public private(set) var device: AVCaptureDevice?
    /// The output data to a sample buffers.
    public private(set) var output: Output? {
        didSet {
            oldValue?.setSampleBufferDelegate(nil, queue: nil)
        }
    }
    /// The connection from a capture input to a capture output.
    public private(set) var connection: AVCaptureConnection?
    private var dataOutput: AudioDeviceUnitDataOutput?

    init(_ track: UInt8, device: AVCaptureDevice) throws {
        input = try AVCaptureDeviceInput(device: device)
        self.track = track
        self.device = device
        output = AVCaptureAudioDataOutput()
        if let input, let output {
            connection = AVCaptureConnection(inputPorts: input.ports, output: output)
        }
    }

    func setSampleBufferDelegate(_ audioUnit: AudioCaptureUnit?) {
        dataOutput = audioUnit?.makeDataOutput(track)
        output?.setSampleBufferDelegate(dataOutput, queue: audioUnit?.lockQueue)
    }
}

@available(tvOS 17.0, *)
final class AudioDeviceUnitDataOutput: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let track: UInt8
    private let audioMixer: any AudioMixer

    init(track: UInt8, audioMixer: any AudioMixer) {
        self.track = track
        self.audioMixer = audioMixer
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        audioMixer.append(track, buffer: sampleBuffer)
    }
}

#else
final class AudioDeviceUnit: DeviceUnit {
    var output: AVCaptureOutput?
    var track: UInt8
    var input: AVCaptureInput?
    var device: AVCaptureDevice?
    var connection: AVCaptureConnection?

    init(_ track: UInt8, device: AVCaptureDevice) throws {
        self.track = track
    }
}
#endif
