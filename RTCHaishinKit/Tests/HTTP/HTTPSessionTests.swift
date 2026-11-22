import Foundation
import HaishinKit
import Testing

@testable import RTCHaishinKit

@Suite struct HTTPSessionTests {
    @Test func playbackRetainsBothReceiveTracksUntilOfferIsCreated() async throws {
        let session = HTTPSession(uri: try #require(URL(string: "http://localhost/live/whep")), mode: .playback, configuration: nil)
        let offer = try await session.makeOffer()
        try await session.close()
        #expect(offer.contains("a=ice-ufrag:"))
        #expect(offer.contains("a=candidate:"))
        #expect(offer.contains("m=audio"))
        #expect(offer.contains("m=video"))
        #expect(offer.components(separatedBy: "a=recvonly").count == 3)
    }

    @Test(arguments:
 ["http:/localhost/whep", "https:/localhost/whep", "whep:/localhost/live", "https://", "https:///whep"])
    func rejectsMalformedURL(_ value: String) async throws {
        let uri = try #require(URL(string: value))
        for mode in [StreamSessionMode.publish, .playback] {
            let session = HTTPSessionFactory().make(uri, mode: mode, configuration: nil)
            await #expect {
                try await session.connect { }
            } throws: { error in
                (error as? URLError)?.code == .badURL
            }
            #expect(await session.connected == false)
            var states = await session.readyState.makeAsyncIterator()
            #expect(await states.next() == .closed)
        }
    }
}
