import CoreMedia

struct FrameTracker {
    static let seconds = 1.0

    private(set) var frameRate: Int = 0
    private var count = 0
    private var rotated: CMTime = .zero

    init() {
    }

    mutating func update(_ time: CMTime) {
        count += 1
        if Self.seconds <= (time - rotated).seconds {
            rotated = time
            frameRate = count
            count = 0
        }
    }

    mutating func clear() {
        count = 0
        rotated = .zero
    }
}
