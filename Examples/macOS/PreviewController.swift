import AppKit
import AVFoundation
import HaishinKit
import SwiftUI

/// A stable output keeps renderer changes independent of capture and connection lifetimes.
@MainActor
final class PreviewController: NSObject, ObservableObject, NSWindowDelegate, MediaMixerOutput, StreamOutput {
    enum Renderer: String, CaseIterable { case metal = "MTHKView", pip = "PiPView" }
    @Published var renderer: Renderer = .metal {
        didSet { if renderer != .pip { closeFloatingPreview() } }
    }
    @Published private(set) var isFloating = false
    var dynamicRangeMode: DynamicRangeMode = .sdr {
        didSet { (inlineView as? MTHKView)?.setDynamicRangeMode(dynamicRangeMode) }
    }
    var videoTrackId: UInt8? { UInt8.max }
    var audioTrackId: UInt8? { nil }
    private var inlineView: NSView?
    private var panel: NSPanel?
    private var floatingView: PiPHKView?

    func install(_ view: NSView) {
        inlineView = view
        (view as? MTHKView)?.setDynamicRangeMode(dynamicRangeMode)
    }

    func toggleFloatingPreview() {
        guard renderer == .pip else { return }
        if isFloating { closeFloatingPreview(); return }
        let panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 480, height: 270),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = String(localized: "Floating preview")
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentMinSize = .init(width: 240, height: 135)
        panel.delegate = self
        let view = PiPHKView(frame: .init(x: 0, y: 0, width: 480, height: 270))
        view.videoGravity = .resizeAspect
        panel.contentView = view
        floatingView = view
        self.panel = panel
        isFloating = true
        panel.center()
        panel.orderFrontRegardless()
    }

    func closeFloatingPreview() {
        panel?.delegate = nil
        panel?.close()
        panel = nil
        floatingView = nil
        isFloating = false
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        floatingView = nil
        isFloating = false
    }

    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async {}
    nonisolated func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {}
    nonisolated func stream(_ stream: some StreamConvertible, didOutput audio: AVAudioBuffer, when: AVAudioTime) {}
    nonisolated func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {
        Task { @MainActor in
            (self.inlineView as? any MediaMixerOutput)?.mixer(mixer, didOutput: sampleBuffer)
            self.floatingView?.mixer(mixer, didOutput: sampleBuffer)
        }
    }
    nonisolated func stream(_ stream: some StreamConvertible, didOutput video: CMSampleBuffer) {
        Task { @MainActor in
            (self.inlineView as? any StreamOutput)?.stream(stream, didOutput: video)
            self.floatingView?.stream(stream, didOutput: video)
        }
    }
}

struct StudioPreviewSurface: NSViewRepresentable {
    let controller: PreviewController
    let renderer: PreviewController.Renderer
    func makeNSView(context: Context) -> NSView {
        let view: NSView = renderer == .metal ? MTHKView(frame: .zero) : PiPHKView(frame: .zero)
        controller.install(view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct PreviewControls: View {
    @ObservedObject var controller: PreviewController
    var body: some View {
        HStack {
            Picker(String(localized: "Preview renderer"), selection: $controller.renderer) {
                ForEach(PreviewController.Renderer.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden().fixedSize().accessibilityLabel(String(localized: "Preview renderer"))
            if controller.renderer == .pip {
                Button {
                    controller.toggleFloatingPreview()
                } label: {
                    Label(controller.isFloating ? String(localized: "Close floating preview") : String(localized: "Open floating preview"),
                          systemImage: controller.isFloating ? "pip.exit" : "pip.enter")
                }
                .help(String(localized: "Show video in an always-on-top window."))
            }
        }
    }
}
