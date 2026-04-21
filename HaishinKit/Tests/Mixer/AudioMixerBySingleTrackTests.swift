import AVFoundation
import Foundation
import Testing

@testable import HaishinKit

@Suite struct AudioMixerBySingleTrackTests {
    final class Result: AudioMixerDelegate {
        var outputs: [AVAudioPCMBuffer] = []

        func audioMixer(_ audioMixer: some AudioMixer, track: UInt8, didInput buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        }

        func audioMixer(_ audioMixer: some AudioMixer, didOutput audioFormat: AVAudioFormat) {
        }

        func audioMixer(_ audioMixer: some AudioMixer, didOutput audioBuffer: AVAudioPCMBuffer, when: AVAudioTime) {
            outputs.append(audioBuffer)
        }

        func audioMixer(_ audioMixer: some AudioMixer, errorOccurred error: AudioMixerError) {
        }
    }

    @Test func keep44100_1ch() {
        let mixer = AudioMixerBySingleTrack()
        mixer.settings = .init(
            sampleRate: 44100, channels: 1
        )
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(48000, numSamples: 1024, channels: 1)!)
        #expect(mixer.outputFormat?.sampleRate == 44100)
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(44100, numSamples: 1024, channels: 1)!)
        #expect(mixer.outputFormat?.sampleRate == 44100)
    }

    @Test func test44100to48000_1ch() {
        let mixer = AudioMixerBySingleTrack()
        mixer.settings = .init(
            sampleRate: 44100, channels: 1
        )
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(48000, numSamples: 1024, channels: 1)!)
        #expect(mixer.outputFormat?.sampleRate == 44100)
        mixer.settings = .init(
            sampleRate: 48000, channels: 1
        )
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(44100, numSamples: 1024, channels: 1)!)
        #expect(mixer.outputFormat?.sampleRate == 48000)
    }

    @Test func test44100to48000_4ch_2ch() {
        let result = Result()
        let mixer = AudioMixerBySingleTrack()
        mixer.delegate = result
        mixer.settings = .init(
            sampleRate: 44100, channels: 0
        )
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(48000, numSamples: 1024, channels: 4)!)
        #expect(mixer.outputFormat?.channelCount == 2)
        #expect(mixer.outputFormat?.sampleRate == 44100)
        mixer.settings = .init(
            sampleRate: 48000, channels: 0
        )
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(44100, numSamples: 1024, channels: 4)!)
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(44100, numSamples: 1024, channels: 4)!)
        #expect(mixer.outputFormat?.channelCount == 2)
        #expect(mixer.outputFormat?.sampleRate == 48000)
        #expect(result.outputs.count == 2)
    }

    @Test func test44100to48000_4ch() {
        let result = Result()
        let mixer = AudioMixerBySingleTrack()
        mixer.delegate = result
        mixer.settings = .init(
            sampleRate: 44100, channels: 0
        )
        mixer.settings.maximumNumberOfChannels = 4
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(48000, numSamples: 1024, channels: 4)!)
        #expect(mixer.outputFormat?.channelCount == 4)
        #expect(mixer.outputFormat?.sampleRate == 44100)
        mixer.settings = .init(
            sampleRate: 48000, channels: 0
        )
        mixer.settings.maximumNumberOfChannels = 4
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(44100, numSamples: 1024, channels: 4)!)
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(44100, numSamples: 1024, channels: 4)!)
        #expect(mixer.outputFormat?.channelCount == 4)
        #expect(mixer.outputFormat?.sampleRate == 48000)
        #expect(result.outputs.count == 2)
    }

    @Test func passthrough16000_48000() {
        let mixer = AudioMixerBySingleTrack()
        mixer.settings = .init(
            sampleRate: 0, channels: 1
        )
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(16000, numSamples: 1024, channels: 1)!)
        #expect(mixer.outputFormat?.sampleRate == 16000)
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(44100, numSamples: 1024, channels: 1)!)
        #expect(mixer.outputFormat?.sampleRate == 44100)
    }

    @Test func inputFormats() {
        let mixer = AudioMixerBySingleTrack()
        mixer.settings = .init(
            sampleRate: 44100, channels: 1
        )
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(48000, numSamples: 1024, channels: 1)!)
        let inputFormats = mixer.inputFormats
        #expect(inputFormats[0]?.sampleRate == 48000)
    }

    // Regression test for a bug where AudioMixerBySingleTrack.settings.didSet
    // fails to rebuild outputFormat when sampleRate/channels change. If even a
    // single input buffer arrives before the app configures its mixer settings,
    // outputFormat is locked to the raw input format for the life of the mixer.
    @Test func settingsChangeAfterFirstBuffer_rebuildsOutputFormat() {
        let mixer = AudioMixerBySingleTrack()
        // Starts with AudioMixerSettings.default: sampleRate=0, channels=0 (inherit input)

        // Simulates an external mic delivering buffers before the app has a
        // chance to configure the mixer.
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(48000, numSamples: 1024, channels: 2)!)
        #expect(mixer.outputFormat?.sampleRate == 48000)
        #expect(mixer.outputFormat?.channelCount == 2)

        // App now applies its intended mixer output format.
        mixer.settings = .init(sampleRate: 44100, channels: 1)

        // Mic continues delivering at its native format (same input format as before).
        mixer.append(0, buffer: CMAudioSampleBufferFactory.makeSinWave(48000, numSamples: 1024, channels: 2)!)

        // Expected: outputFormat follows the newly-assigned settings.
        #expect(mixer.outputFormat?.sampleRate == 44100)
        #expect(mixer.outputFormat?.channelCount == 1)
    }
}
