import Foundation

/// Compile with the sample endpoint builder and RTMPURL.swift; no Apple headset is required.
@main
struct VisionStudioEndpointChecks {
    static func main() {
        func make(_ server: String, _ key: String = "stream") -> URL? {
            VisionStudioEndpoint.make(server: server, streamName: key)
        }
        for scheme in ["rtmp", "rtmps", "srt"] {
            for port in ["0", "65536", "999999999999999999999", "-1", "bad"] {
                precondition(make("\(scheme)://example.test:\(port)/live") == nil, "accepted \(scheme) port \(port)")
            }
        }
        for port in [1, 65535] {
            precondition(make("rtmp://example.test:\(port)/live")?.port == port)
        }
        for scheme in ["RTMP", "RtMpS"] {
            let url = make("\(scheme)://example.test/live/", "stream?token=abc&expires=123")!
            precondition(url.scheme == scheme.lowercased())
            let rtmp = RTMPURL(url: url)
            precondition(rtmp.command == "\(scheme.lowercased())://example.test/live")
            precondition(rtmp.streamName == "stream?token=abc&expires=123")
        }
        let signed = RTMPURL(url: make("rtmps://example.test/live", "stream?sig=a%2Fb%3D")!)
        precondition(signed.command == "rtmps://example.test/live")
        precondition(signed.streamName == "stream?sig=a%2Fb%3D")
        let hostCollision = RTMPURL(url: make("rtmp://live.example.test/app", "live")!)
        precondition(hostCollision.command == "rtmp://live.example.test/app")
        precondition(hostCollision.streamName == "live")
        let secret = make("srt://example.test:9710?passphrase=0123456789==&streamid=publish:abc=xyz")!
        precondition(secret.absoluteString == "srt://example.test:9710?passphrase=0123456789==&streamid=publish:abc=xyz&mode=caller")
        let combined = RTMPURL(url: make("rtmp://example.test/live?auth=one", "stream?token=two")!)
        precondition(combined.command == "rtmp://example.test/live")
        precondition(combined.streamName == "stream?auth=one&token=two")
        for value in ["", "?", "?mode=caller", "?mode=client", "?streamid=publish:signal"] {
            let srt = make("SRT://example.test:9710\(value)")!
            precondition(srt.scheme == "srt")
            precondition(srt.query?.contains("mode=") == true)
            // The transport parser's question-mark split must always have two components.
            precondition(srt.absoluteString.split(separator: "?").count == 2)
        }
        for query in ["mode=listener", "mode=server", "mode=rendezvous", "adapter=127.0.0.1", "mode=caller&mode=listener", "mode=unknown", "mode="] {
            precondition(make("srt://example.test:9710?\(query)") == nil)
        }
        for server in ["rtmp://example.test", "https://example.test/live", "srt://example.test", "rtmp://example.test/live#fragment", "not a URL"] {
            precondition(make(server) == nil)
        }
        precondition(make("rtmp://example.test/live", "") == nil)
        precondition(make("rtmp://example.test/live", "stream#fragment") == nil)
        print("Vision studio endpoint checks passed: ports, schemes, signed RTMP keys, SRT caller normalization and invalid input.")
    }
}
