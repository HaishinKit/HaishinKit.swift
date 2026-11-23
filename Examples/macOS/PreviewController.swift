import AppKit
import AVFoundation
import HaishinKit
import SwiftUI

/// A stable output keeps renderer changes independent of capture and connection lifetimes.
@MainActor
final class PreviewController: NSObject, ObservableObject, NSWindowDelegate, MediaMixerOutput, StreamOutput {
    enum Renderer: String, CaseIterable { case metal = "MTHKView", pip = "PiPView" }
    @Published var renderer: Renderer = .metal {
        didSet {
            guard renderer != oldValue else { return }
            updateFloatingRenderer()
        }
    }
    @Published private(set) var isFloating = false
    var dynamicRangeMode: DynamicRangeMode = .sdr {
        didSet {
            (inlineView as? MTHKView)?.setDynamicRangeMode(dynamicRangeMode)
            (floatingView as? MTHKView)?.setDynamicRangeMode(dynamicRangeMode)
        }
    }
    var videoTrackId: UInt8? { UInt8.max }
    var audioTrackId: UInt8? { nil }
    private var inlineView: NSView?
    private var panel: NSPanel?
    private var floatingView: NSView?

    func install(_ view: NSView) {
        inlineView = view
        (view as? MTHKView)?.setDynamicRangeMode(dynamicRangeMode)
    }

    func toggleFloatingPreview() {
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
        let view = makeView(renderer: renderer, frame: .init(x: 0, y: 0, width: 480, height: 270))
        panel.contentView = view
        floatingView = view
        self.panel = panel
        isFloating = true
        panel.center()
        panel.orderFrontRegardless()
    }

    fileprivate func makeView(renderer: Renderer, frame: CGRect) -> NSView {
        let view: NSView
        switch renderer {
        case .metal:
            let metal = MTHKView(frame: frame)
            metal.videoGravity = .resizeAspect
            metal.setDynamicRangeMode(dynamicRangeMode)
            view = metal
        case .pip:
            let pip = PiPHKView(frame: frame)
            pip.videoGravity = .resizeAspect
            view = pip
        }
        view.autoresizingMask = [.width, .height]
        return view
    }

    private func updateFloatingRenderer() {
        guard let panel else { return }
        let size = panel.contentView?.bounds.size ?? CGSize(width: 480, height: 270)
        let view = makeView(renderer: renderer, frame: CGRect(origin: .zero, size: size))
        panel.contentView = view
        floatingView = view
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
            (self.floatingView as? any MediaMixerOutput)?.mixer(mixer, didOutput: sampleBuffer)
        }
    }
    nonisolated func stream(_ stream: some StreamConvertible, didOutput video: CMSampleBuffer) {
        Task { @MainActor in
            (self.inlineView as? any StreamOutput)?.stream(stream, didOutput: video)
            (self.floatingView as? any StreamOutput)?.stream(stream, didOutput: video)
        }
    }
}

struct StudioPreviewSurface: NSViewRepresentable {
    let controller: PreviewController
    let renderer: PreviewController.Renderer
    func makeNSView(context: Context) -> NSView {
        let view = controller.makeView(renderer: renderer, frame: .zero)
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
