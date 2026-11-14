import CoreMedia
import Foundation
import Testing
import VideoToolbox

@testable import HaishinKit

@Suite struct VideoCodecFactoryTests {
    @Test func standardCodecsDoNotRequireRegistration() async {
        let factory = VideoCodecFactory()
        #expect(await factory.supportedFormats(for: .compression) == [.h264, .hevc])
        #expect(await factory.supportedFormats(for: .decompression) == [.h264, .hevc])
    }

    @Test func unregisteredCodecsFailInBothDirections() throws {
        let factory = VideoCodecFactory()
        var description: CMFormatDescription?
        #expect(CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: VideoCodecSettings.Format.vp8.codecType, width: 64, height: 48, extensions: nil, formatDescriptionOut: &description) == noErr)
        let input = try #require(description)
        #expect(throws: VideoCodecFactory.Error.self) {
            try factory.makeSession(mode: .compression, settings: .init(format: .vp8), inputFormat: input)
        }
        #expect(throws: VideoCodecFactory.Error.self) {
            try factory.makeSession(mode: .decompression, settings: .default, inputFormat: input)
        }
    }

    @Test func explicitCodecAndLegacyProfileSelection() throws {
        let hevc = VideoCodecSettings(profileLevel: kVTProfileLevel_HEVC_Main_AutoLevel as String)
        #expect(hevc.format == .hevc)
        #expect(VideoCodecSettings(format: .hevc).profileLevel.contains("HEVC"))
        var switched = VideoCodecSettings(format: .hevc)
        switched.format = .h264
        #expect(switched.profileLevel.contains("H264"))
        var vp9 = VideoCodecSettings(format: .vp9)
        vp9.profileLevel = kVTProfileLevel_HEVC_Main_AutoLevel as String
        #expect(vp9.format == .vp9)
        #expect(vp9.invalidateSession(.init(format: .vp8)))
        let decoded = try JSONDecoder().decode(VideoCodecSettings.self, from: JSONEncoder().encode(vp9))
        #expect(decoded.format == .vp9)
    }
}
