import AVFoundation
import CoreImage
import HaishinKit
import SwiftUI

private enum PreviewInput: Sendable {
    case tap(CGPoint)
    case begin(CGPoint, isPinch: Bool = false)
    case translate(CGPoint)
    case pinch(CGPoint, CGPoint, CGFloat)
    case scroll(CGPoint, CGFloat)
    case end
}

private enum OverlayKind: String, CaseIterable, Identifiable, Sendable {
    case text = "Text"
    case image = "Sample image"
    case video = "Sample video"

    var id: String { rawValue }
}

private struct PreviewSelection: Equatable, Sendable {
    let id: String
    let bounds: CGRect
}

private struct SelectionTask: Equatable {
    let id: String?
    let size: CGSize
}

private enum PreviewAction: Sendable {
    case none
    case add(CGPoint)
    case edit(String, String)
    case swipe(CGFloat)
}

@ScreenActor
private final class PreviewSceneEditor {
    nonisolated static let idPrefix = "example-overlay-"
    private let mixer: MediaMixer
    private var target: ScreenObject?
    private var editingBounds: CGRect?
    private var previous: CGPoint?
    private var gestureStart: CGPoint?
    private var resizeEdit: (id: String, rendered: CGRect, requested: CGRect)?

    nonisolated init(mixer: MediaMixer) {
        self.mixer = mixer
    }

    func handle(
        _ input: PreviewInput, size: CGSize, gravity: AVLayerVideoGravity, focus: String?
    ) async -> (String?, PreviewAction) {
        let screen = await mixer.screen
        let editor = ScreenObjectEditor(screen: screen)
        guard let coordinates = ScreenCoordinateTransform(screenSize: screen.size, previewSize: size, videoGravity: gravity) else {
            return (focus, .none)
        }
        switch input {
        case .scroll:
            break
        default:
            resizeEdit = nil
        }
        switch input {
        case .tap(let point):
            let position = coordinates.toScreen(point)
            guard CGRect(origin: .zero, size: screen.size).contains(position) else {
                return (nil, .none)
            }
            let object = hitTest(editor, position)
            if let text = object as? TextScreenObject {
                return (text.id, .edit(text.id, text.string))
            }
            return (object?.id, object == nil ? .add(position) : .none)
        case .begin(let point, let isPinch):
            let object = (isPinch ? target : nil) ?? hitTest(editor, coordinates.toScreen(point))
            editingBounds = isPinch && object === target ? editingBounds ?? object?.bounds : object?.bounds
            target = object
            previous = point
            gestureStart = isPinch ? nil : point
            return (object?.id ?? focus, .none)
        case .translate(let point):
            defer { previous = point }
            guard let target, let bounds = editingBounds, let previous else { return (focus, .none) }
            editingBounds = editor.transform(
                target, bounds: bounds, anchor: coordinates.toScreen(previous), destination: coordinates.toScreen(point)
            )
        case .pinch(let anchor, let destination, let scale):
            gestureStart = nil
            guard let target, let bounds = editingBounds else { return (focus, .none) }
            editingBounds = editor.transform(
                target, bounds: bounds, anchor: coordinates.toScreen(anchor),
                destination: coordinates.toScreen(destination), scale: scale
            )
        case .scroll(let location, let scale):
            let point = coordinates.toScreen(location)
            guard let object = hitTest(editor, point) else { return (focus, .none) }
            resize(object, with: editor, anchor: point, scale: scale)
            return (object.id, .none)
        case .end:
            defer {
                target = nil
                editingBounds = nil
                previous = nil
                gestureStart = nil
            }
            if target == nil, let start = gestureStart, let previous {
                let x = previous.x - start.x
                let y = previous.y - start.y
                if abs(x) >= 50, abs(x) > abs(y) {
                    return (focus, .swipe(x))
                }
            }
        }
        return (focus, .none)
    }

    #if os(macOS)
    func resize(id: String, scale: CGFloat) async {
        let screen = await mixer.screen
        guard let object = screen.findById(id), object.isVisible else { return }
        resize(object, with: ScreenObjectEditor(screen: screen), scale: scale)
    }
    #endif

    private func resize(
        _ object: ScreenObject,
        with editor: ScreenObjectEditor,
        anchor: CGPoint? = nil,
        scale: CGFloat
    ) {
        let rendered = object.bounds
        let bounds = if let resizeEdit, resizeEdit.id == object.id, resizeEdit.rendered == rendered {
            resizeEdit.requested
        } else {
            rendered
        }
        let point = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        if let requested = editor.transform(object, bounds: bounds, anchor: point, destination: point, scale: scale) {
            resizeEdit = (object.id, rendered, requested)
        }
    }

    func selection(id: String, size: CGSize, gravity: AVLayerVideoGravity) async -> PreviewSelection? {
        let screen = await mixer.screen
        guard let object = screen.findById(id), object.isVisible, object.parent != nil,
              let coordinates = ScreenCoordinateTransform(screenSize: screen.size, previewSize: size, videoGravity: gravity) else {
            return nil
        }
        let rect = coordinates.toPreview(target === object ? editingBounds ?? object.bounds : object.bounds)
        let visible = rect.intersection(CGRect(origin: .zero, size: size))
        return visible.isEmpty ? nil : PreviewSelection(id: id, bounds: visible)
    }

    func add(_ kind: OverlayKind, at position: CGPoint) async throws -> String {
        let screen = await mixer.screen
        let id = Self.idPrefix + UUID().uuidString
        let object: ScreenObject
        switch kind {
        case .text:
            let text = TextScreenObject(id: id)
            text.string = "New text"
            object = text
        case .image:
            let image = ImageScreenObject(id: id)
            guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
                  let sample = CIImage(contentsOf: url) else {
                throw CocoaError(.fileNoSuchFile)
            }
            image.ciImage = sample
            image.size = CGSize(width: 160, height: 160)
            object = image
        case .video:
            let video = AssetScreenObject(id: id)
            guard let url = Bundle.main.url(forResource: "SampleVideo_360x240_5mb", withExtension: "mp4") else {
                throw CocoaError(.fileNoSuchFile)
            }
            video.size = CGSize(width: 180, height: 120)
            video.isLooping = true
            try video.startReading(AVURLAsset(url: url))
            object = video
        }
        try screen.addChild(object)
        ScreenObjectEditor(screen: screen).move(
            object,
            to: CGPoint(x: position.x - object.size.width / 2, y: position.y - object.size.height / 2),
            size: object.size
        )
        return id
    }

    func updateText(id: String, value: String) async {
        let screen = await mixer.screen
        guard let text = screen.findById(id) as? TextScreenObject else { return }
        text.string = value
    }

    func remove(id: String) async {
        let screen = await mixer.screen
        guard let object = screen.findById(id) else { return }
        (object as? AssetScreenObject)?.cancelReading()
        screen.removeChild(object)
    }

    private func hitTest(_ editor: ScreenObjectEditor, _ point: CGPoint) -> ScreenObject? {
        editor.hitTest(point) { $0.id.hasPrefix(Self.idPrefix) }
    }
}

struct ScreenObjectEditingPreview<Preview: View>: View {
    @State private var editor: PreviewSceneEditor
    private let gravity: AVLayerVideoGravity
    private let onSwipe: (CGFloat) -> Void
    private let preview: Preview

    @State private var focus: String?
    @State private var selection: PreviewSelection?
    @State private var inputTask: Task<Void, Never>?
    @State private var insertionPoint: CGPoint?
    @State private var showAddMenu = false
    @State private var editingID: String?
    @State private var showEditor = false
    @State private var text = ""
    @State private var errorMessage = ""
    @State private var showError = false

    init(
        mixer: MediaMixer,
        gravity: AVLayerVideoGravity,
        onSwipe: @escaping (CGFloat) -> Void = { _ in },
        @ViewBuilder preview: () -> Preview
    ) {
        _editor = State(initialValue: PreviewSceneEditor(mixer: mixer))
        self.gravity = gravity
        self.onSwipe = onSwipe
        self.preview = preview()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                preview.frame(width: geometry.size.width, height: geometry.size.height)
                PreviewInputView { input in
                    enqueue {
                        let result = await editor.handle(input, size: geometry.size, gravity: gravity, focus: focus)
                        focus = result.0
                        switch result.1 {
                        case .none:
                            break
                        case .add(let position):
                            insertionPoint = position
                            showAddMenu = true
                        case .edit(let id, let value):
                            editingID = id
                            text = value
                            showEditor = true
                        case .swipe(let distance):
                            onSwipe(distance)
                        }
                    }
                }
                if let selection, selection.id == focus {
                    Rectangle()
                        .strokeBorder(.white, lineWidth: 2)
                        .frame(width: selection.bounds.width, height: selection.bounds.height)
                        .offset(x: selection.bounds.minX, y: selection.bounds.minY)
                        .allowsHitTesting(false)
                    Button {
                        let id = selection.id
                        enqueue {
                            await editor.remove(id: id)
                            if focus == id { focus = nil }
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.black, .white)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete object")
                    .position(
                        x: min(max(22, selection.bounds.maxX), max(22, geometry.size.width - 22)),
                        y: min(max(22, selection.bounds.minY), max(22, geometry.size.height - 22))
                    )
                    #if os(macOS)
                    HStack(spacing: 0) {
                        resizeButton("minus", label: "Shrink object", id: selection.id, scale: 1 / 1.2)
                        resizeButton("plus", label: "Enlarge object", id: selection.id, scale: 1.2)
                    }
                    .position(
                        x: min(max(44, selection.bounds.midX), max(44, geometry.size.width - 44)),
                        y: resizeControlsY(for: selection.bounds, height: geometry.size.height)
                    )
                    #endif
                }
            }
            .clipped()
            .task(id: SelectionTask(id: focus, size: geometry.size)) {
                guard let focus else {
                    selection = nil
                    return
                }
                while !Task.isCancelled {
                    let updated = await editor.selection(id: focus, size: geometry.size, gravity: gravity)
                    guard !Task.isCancelled else { return }
                    selection = updated
                    try? await Task.sleep(nanoseconds: 33_000_000)
                }
            }
        }
        .confirmationDialog("Add object", isPresented: $showAddMenu, titleVisibility: .visible) {
            ForEach(OverlayKind.allCases) { kind in
                Button(kind.rawValue) {
                    guard let position = insertionPoint else { return }
                    enqueue {
                        do {
                            focus = try await editor.add(kind, at: position)
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit text").font(.headline)
                TextEditor(text: $text)
                    .accessibilityLabel("Overlay text")
                    .frame(minWidth: 260, minHeight: 100)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { showEditor = false }
                    Button("Save") {
                        if let id = editingID {
                            let value = text
                            enqueue { await editor.updateText(id: id, value: value) }
                        }
                        showEditor = false
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
        }
        .alert("Could not add object", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onDisappear {
            inputTask?.cancel()
        }
    }

    #if os(macOS)
    private func resizeButton(_ symbol: String, label: String, id: String, scale: CGFloat) -> some View {
        Button {
            enqueue { await editor.resize(id: id, scale: scale) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func resizeControlsY(for bounds: CGRect, height: CGFloat) -> CGFloat {
        let below = bounds.maxY + 22
        if below <= height - 22 {
            return below
        }
        return max(22, bounds.minY - 44)
    }
    #endif

    private func enqueue(_ action: @escaping @MainActor () async -> Void) {
        let previous = inputTask
        inputTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}

#if os(iOS)
private struct PreviewInputView: UIViewRepresentable {
    let onInput: (PreviewInput) -> Void

    func makeUIView(context: Context) -> InputSurface {
        InputSurface()
    }

    func updateUIView(_ view: InputSurface, context: Context) {
        view.onInput = onInput
    }

    final class InputSurface: UIView, UIGestureRecognizerDelegate {
        var onInput: ((PreviewInput) -> Void)?
        private var pinchCenter: CGPoint?
        private var pinchTouchCount = 0

        init() {
            super.init(frame: .zero)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
            let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
            pinch.delegate = self
            tap.require(toFail: pan)
            tap.require(toFail: pinch)
            addGestureRecognizer(tap)
            addGestureRecognizer(pan)
            addGestureRecognizer(pinch)
        }

        required init?(coder: NSCoder) { nil }

        // A pinch can take over an in-progress one-finger pan.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
        }

        @objc private func tap(_ recognizer: UITapGestureRecognizer) {
            onInput?(.tap(recognizer.location(in: self)))
        }

        @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
            guard pinchCenter == nil else { return }
            let point = recognizer.location(in: self)
            switch recognizer.state {
            case .began:
                let delta = recognizer.translation(in: self)
                onInput?(.begin(CGPoint(x: point.x - delta.x, y: point.y - delta.y)))
                onInput?(.translate(point))
            case .changed:
                onInput?(.translate(point))
            case .ended:
                onInput?(.translate(point))
                onInput?(.end)
            case .cancelled, .failed:
                onInput?(.end)
            default:
                break
            }
        }

        @objc private func pinch(_ recognizer: UIPinchGestureRecognizer) {
            let center = recognizer.location(in: self)
            switch recognizer.state {
            case .began:
                pinchCenter = center
                pinchTouchCount = recognizer.numberOfTouches
                recognizer.scale = 1
                onInput?(.begin(center, isPinch: true))
            case .changed:
                if let previous = pinchCenter, pinchTouchCount == recognizer.numberOfTouches, pinchTouchCount >= 2 {
                    onInput?(.pinch(previous, center, recognizer.scale))
                }
                pinchCenter = center
                pinchTouchCount = recognizer.numberOfTouches
                recognizer.scale = 1
            case .ended, .cancelled, .failed:
                pinchCenter = nil
                onInput?(.end)
            default:
                break
            }
        }
    }
}
#elseif os(macOS)
private struct PreviewInputView: NSViewRepresentable {
    let onInput: (PreviewInput) -> Void

    func makeNSView(context: Context) -> InputSurface {
        InputSurface()
    }

    func updateNSView(_ view: InputSurface, context: Context) {
        view.onInput = onInput
    }

    final class InputSurface: NSView {
        var onInput: ((PreviewInput) -> Void)?
        override var isFlipped: Bool { true }
        private var down: CGPoint?
        private var dragging = false

        override func mouseDown(with event: NSEvent) {
            down = point(event)
            dragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let down else { return }
            let location = point(event)
            if !dragging {
                guard hypot(location.x - down.x, location.y - down.y) >= 3 else { return }
                dragging = true
                onInput?(.begin(down))
            }
            onInput?(.translate(location))
        }

        override func mouseUp(with event: NSEvent) {
            defer { down = nil }
            if dragging {
                onInput?(.translate(point(event)))
                onInput?(.end)
            } else if let down, bounds.contains(point(event)) {
                onInput?(.tap(down))
            }
        }

        override func scrollWheel(with event: NSEvent) {
            let delta = event.scrollingDeltaY
            guard delta != 0 else { return }
            let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.12
            onInput?(.scroll(point(event), exp(min(2, max(-2, delta * sensitivity)))))
        }

        override func magnify(with event: NSEvent) {
            onInput?(.scroll(point(event), 1 + event.magnification))
        }

        private func point(_ event: NSEvent) -> CGPoint {
            convert(event.locationInWindow, from: nil)
        }
    }
}
#endif
