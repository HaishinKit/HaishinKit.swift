import Foundation
import HaishinKit
import Testing
@testable import RTCHaishinKit

@Suite struct RTCWrapperTests {
    @Test func remoteCandidateIsPubliclyConstructible() throws {
        let candidate = RTCIceCandidate(candidate: "candidate:1 1 UDP 2122260223 127.0.0.1 50000 typ host", mid: "0")
        #expect(candidate.mid == "0")
        let peer = try RTCPeerConnection(RTCConfiguration(isAutoNegotionEnabled: false))
        // libdatachannel requires a remote description before accepting candidates.
        #expect(throws: RTCError.self) { try peer.addRemoteCandidate(candidate) }
        peer.close()
    }

    @Test func generatedDescriptionAndRemoteTrackAreDelivered() async throws {
        let sender = try RTCPeerConnection(RTCConfiguration(isAutoNegotionEnabled: false))
        let receiver = try RTCPeerConnection(RTCConfiguration(isAutoNegotionEnabled: false))
        let events = PeerEvents()
        sender.delegate = events
        receiver.delegate = events
        let stream = RTCStream()
        try sender.addTrack(AudioStreamTrack(.init(format: .opus)), stream: stream)
        try sender.setLocalDesciption(.offer)
        #expect(!sender.localDescription.isEmpty)
        #expect(events.description == sender.localDescription)
        #expect(events.type == .offer)
        try receiver.setRemoteDesciption(sender.localDescription, type: .offer)
        events.track = nil
        let remoteTrack = try #require(events.weakTrack)
        let playback = RTCStream()
        await remoteTrack.setStream(playback)
        #expect(await playback.tracks.count == 1)
        #expect(await playback.tracks.first === remoteTrack)
        await playback.close()
        sender.close()
        receiver.close()
        await stream.close()
    }
}

private final class PeerEvents: RTCPeerConnectionDelegate {
    var description = ""
    var type: SDPSessionDescriptionType?
    var track: RTCMediaTrack?
    weak var weakTrack: RTCMediaTrack?

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerateLocalDescription sdp: String, type: SDPSessionDescriptionType) {
        description = sdp
        self.type = type
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen track: RTCMediaTrack) {
        self.track = track
        weakTrack = track
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, connectionStateChanged connectionState: RTCPeerConnection.ConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, iceGatheringStateChanged iceGatheringState: RTCPeerConnection.IceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, iceConnectionStateChanged iceConnectionState: RTCPeerConnection.IceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, signalingStateChanged signalingState: RTCPeerConnection.SignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, gotIceCandidate candidated: RTCIceCandidate) {}
}
