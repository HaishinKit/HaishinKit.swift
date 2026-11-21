import Foundation
import XCTest
import libdatachannel
@testable import RTCHaishinKit

final class RTCDataChannelTests: XCTestCase {
    func testTextMessagesAndClosedState() throws {
        let sender = try RTCPeerConnection(RTCConfiguration(isAutoNegotionEnabled: false))
        let receiver = try RTCPeerConnection(RTCConfiguration(isAutoNegotionEnabled: false))
        let channel = try sender.createDataChannel("text")
        let opened = expectation(description: "channel open")
        let received = expectation(description: "UTF-8 and empty text received")
        received.expectedFulfillmentCount = 2
        let closed = expectation(description: "channel closed")
        let events = LoopbackEvents(opened: opened, received: received, closed: closed)
        sender.delegate = events
        receiver.delegate = events
        channel.delegate = events
        events.sender = sender
        events.receiver = receiver
        defer {
            sender.close()
            receiver.close()
        }
        try sender.setLocalDesciption(.offer)
        try receiver.setRemoteDesciption(sender.localDescription, type: .offer)
        try receiver.setLocalDesciption(.answer)
        try sender.setRemoteDesciption(receiver.localDescription, type: .answer)
        events.flushCandidates()
        wait(for: [opened], timeout: 10)
        try channel.send("日本語🌏")
        try channel.send("")
        wait(for: [received], timeout: 10)
        XCTAssertEqual(events.messages, ["日本語🌏", ""])
        try RTCError.check(rtcClose(channel.id))
        wait(for: [closed], timeout: 10)
        XCTAssertEqual(channel.readyState, .closed)
    }
}

private final class LoopbackEvents: RTCPeerConnectionDelegate, RTCDataChannelDelegate {
    let opened: XCTestExpectation
    let received: XCTestExpectation
    let closed: XCTestExpectation
    weak var sender: RTCPeerConnection?
    weak var receiver: RTCPeerConnection?
    var remoteChannel: RTCDataChannel?
    var messages: [String] = []
    private let candidateLock = NSLock()
    private var pendingCandidates: [(Bool, RTCIceCandidate)] = []
    private var descriptionsReady = false

    func flushCandidates() {
        candidateLock.lock()
        descriptionsReady = true
        let pending = pendingCandidates
        pendingCandidates.removeAll()
        candidateLock.unlock()
        for (fromSender, candidate) in pending {
            apply(candidate, fromSender: fromSender)
        }
    }

    private func apply(_ candidate: RTCIceCandidate, fromSender: Bool) {
        do {
            try (fromSender ? receiver : sender)?.addRemoteCandidate(candidate)
        } catch {
            XCTFail("Failed to add ICE candidate: \(error)")
        }
    }

    init(opened: XCTestExpectation, received: XCTestExpectation, closed: XCTestExpectation) {
        self.opened = opened
        self.received = received
        self.closed = closed
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        remoteChannel = dataChannel
        dataChannel.delegate = self
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, gotIceCandidate candidate: RTCIceCandidate) {
        candidateLock.lock()
        if !descriptionsReady {
            pendingCandidates.append((peerConnection === sender, candidate))
            candidateLock.unlock()
            return
        }
        candidateLock.unlock()
        apply(candidate, fromSender: peerConnection === sender)
    }
    func dataChannel(_ dataChannel: RTCDataChannel, readyStateChanged readyState: RTCDataChannel.ReadyState) {
        guard dataChannel !== remoteChannel else { return }
        if readyState == .open { opened.fulfill() }
        if readyState == .closed { closed.fulfill() }
    }
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessage message: String) {
        messages.append(message)
        received.fulfill()
    }
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessage message: Data) {
        XCTFail("Expected a text message")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, connectionStateChanged connectionState: RTCPeerConnection.ConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, iceGatheringStateChanged iceGatheringState: RTCPeerConnection.IceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, iceConnectionStateChanged iceConnectionState: RTCPeerConnection.IceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, signalingStateChanged signalingState: RTCPeerConnection.SignalingState) {}
}
