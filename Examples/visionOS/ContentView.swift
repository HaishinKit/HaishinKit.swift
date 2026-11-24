import HaishinKit
import RTMPHaishinKit
import SRTHaishinKit
import SwiftUI

struct ContentView: View {
    @State private var showingCodecs = false

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(String(localized: "Device codecs", table: "CodecSupport"), systemImage: "cpu") { showingCodecs = true }
            }.padding(.horizontal)
            PlaybackView()
        }
        .sheet(isPresented: $showingCodecs) { CodecSupportView() }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
