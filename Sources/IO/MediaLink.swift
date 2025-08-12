import AVFoundation

#if canImport(SwiftPMSupport)
import SwiftPMSupport
#endif

protocol MediaLinkDelegate: AnyObject {
    func mediaLink(_ mediaLink: MediaLink<Self>, dequeue sampleBuffer: CMSampleBuffer)
    func mediaLink(_ mediaLink: MediaLink<Self>, didBufferingChanged: Bool)
}

private let kMediaLink_bufferTime = 0.2
private let kMediaLink_bufferingTime = 0.0

final class MediaLink<T: MediaLinkDelegate> {
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else {
                return
            }
            choreographer.isPaused = isPaused
            nstry({
                if self.isPaused {
                    self.playerNode.pause()
                } else {
                    self.playerNode.play()
                }
            }, { exeption in
                logger.warn(exeption)
            })
        }
    }
    var hasVideo = false
    var bufferTime = kMediaLink_bufferTime
    weak var delegate: T?
    private(set) lazy var playerNode = AVAudioPlayerNode()
    private(set) var isRunning: Atomic<Bool> = .init(false)
    private var isBuffering = true {
        didSet {
            if !isBuffering {
                bufferingTime = 0.0
            }
            isPaused = isBuffering
            delegate?.mediaLink(self, didBufferingChanged: isBuffering)
        }
    }
    private var bufferingTime = kMediaLink_bufferingTime
    private lazy var choreographer: DisplayLinkChoreographer = {
        var choreographer = DisplayLinkChoreographer()
        choreographer.delegate = self
        return choreographer
    }()
    private var bufferQueue: TypedBlockQueue<CMSampleBuffer>?
    private var scheduledAudioBuffers: Atomic<Int> = .init(0)
    private var presentationTimeStampOrigin: CMTime = .invalid
    private var audioTime = IOAudioTime()
    private var duration: TimeInterval = 0.0

    func enqueue(_ buffer: CMSampleBuffer) {
        guard buffer.presentationTimeStamp != .invalid else {
            return
        }
        if presentationTimeStampOrigin == .invalid {
            presentationTimeStampOrigin = buffer.presentationTimeStamp
        }
        if buffer.presentationTimeStamp == presentationTimeStampOrigin {
            delegate?.mediaLink(self, dequeue: buffer)
            return
        }
        try? bufferQueue?.enqueue(buffer)
        if isBuffering {
            bufferingTime = bufferQueue?.duration.seconds ?? 0
            if bufferTime <= bufferingTime {
                isBuffering = false
            }
        }
    }

    func enqueue(_ audioBuffer: AVAudioBuffer, when: AVAudioTime) {
        guard let audioBuffer = audioBuffer as? AVAudioPCMBuffer else {
            return
        }
        if !audioTime.hasAnchor {
            audioTime.anchor(playerNode.lastRenderTime ?? AVAudioTime(hostTime: 0))
        }
        nstry({
            self.scheduledAudioBuffers.mutate { $0 += 1 }
            Task {
                await self.playerNode.scheduleBuffer(audioBuffer, at: self.audioTime.at)
                self.scheduledAudioBuffers.mutate {
                    $0 -= 1
                    if $0 == 0 {
                        self.isBuffering = true
                    }
                }
            }
            self.audioTime.advanced(Int64(audioBuffer.frameLength))
            if !self.isPaused && !self.playerNode.isPlaying && 10 <= self.scheduledAudioBuffers.value {
                self.playerNode.play()
            }
        }, { exeption in
            logger.warn(exeption)
        })
    }

    private func duration(_ timestamp: Double) -> Double {
        defer {
            duration += timestamp
        }
        if playerNode.isPlaying {
            guard let nodeTime = playerNode.lastRenderTime, let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
                return 0.0
            }
            return TimeInterval(playerTime.sampleTime) / playerTime.sampleRate
        }
        return duration
    }

    private func makeBufferkQueue() {
        do {
            self.bufferQueue = .init(try .init(capacity: 256, handlers: .outputPTSSortedSampleBuffers))
        } catch {
            logger.error(error)
        }
    }
}

extension MediaLink: ChoreographerDelegate {
    // MARK: ChoreographerDelegate
    func choreographer(_ choreographer: some Choreographer, didFrame timestamp: TimeInterval, targetTimestamp: TimeInterval) {
        guard let bufferQueue else {
            return
        }
        let duration = self.duration(targetTimestamp - timestamp)
        var frameCount = 0
        while !bufferQueue.isEmpty {
            guard let first = bufferQueue.head else {
                break
            }
            if first.presentationTimeStamp.seconds - presentationTimeStampOrigin.seconds <= duration {
                delegate?.mediaLink(self, dequeue: first)
                frameCount += 1
                _ = bufferQueue.dequeue()
            } else {
                if 2 < frameCount {
                    logger.info("droppedFrame: \(frameCount)")
                }
                return
            }
        }
        isBuffering = true
    }
}

extension MediaLink: Running {
    // MARK: Running
    func startRunning() {
        guard !isRunning.value else {
            return
        }
        scheduledAudioBuffers.mutate { $0 = 0 }
        hasVideo = false
        bufferingTime = kMediaLink_bufferingTime
        isBuffering = true
        duration = 0.0
        choreographer.startRunning()
        makeBufferkQueue()
        isRunning.mutate { $0 = true }
    }

    func stopRunning() {
        guard isRunning.value else {
            return
        }
        choreographer.stopRunning()
        if playerNode.isPlaying {
            playerNode.stop()
            playerNode.reset()
        }
        bufferQueue = nil
        audioTime.reset()
        presentationTimeStampOrigin = .invalid
        isRunning.mutate { $0 = false }
    }
}
