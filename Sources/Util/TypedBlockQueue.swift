import CoreMedia
import Foundation

final class TypedBlockQueue<T: AnyObject> {
    private let queue: CMBufferQueue
    private let capacity: CMItemCount

    @inlinable @inline(__always) var head: T? {
        guard let head = queue.head else {
            return nil
        }
        return (head as! T)
    }

    @inlinable @inline(__always) var isEmpty: Bool {
        queue.isEmpty
    }

    @inlinable @inline(__always) var duration: CMTime {
        queue.duration
    }

    init(capacity: CMItemCount, handlers: CMBufferQueue.Handlers) throws {
        self.capacity = capacity
        self.queue = try CMBufferQueue(capacity: capacity, handlers: handlers)
    }

    @inlinable
    @inline(__always)
    func enqueue(_ buffer: T) throws {
        try queue.enqueue(buffer)
    }

    @inlinable
    @inline(__always)
    func dequeue() -> T? {
        guard let value = queue.dequeue() else {
            return nil
        }
        return (value as! T)
    }

    @inlinable
    @inline(__always)
    func reset() throws {
        try queue.reset()
    }
}

extension TypedBlockQueue where T == CMSampleBuffer {
    func dequeue(_ presentationTimeStamp: CMTime) -> CMSampleBuffer? {
        var result: CMSampleBuffer?
        while !queue.isEmpty {
            guard let head else {
                break
            }
            if head.presentationTimeStamp <= presentationTimeStamp {
                result = dequeue()
            } else {
                return result
            }
        }
        return result
    }
}
