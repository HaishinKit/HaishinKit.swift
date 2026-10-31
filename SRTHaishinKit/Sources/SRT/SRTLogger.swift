import Foundation
import libsrt

/// Configures logging levels and functional areas in the SRT library.
public actor SRTLogger {
    /// The singleton logger instance.
    public static let shared = SRTLogger()

    /// The severity levels supported by the SRT logger.
    public enum Level: Sendable {
        /// Detailed diagnostic messages.
        case debug
        /// Informational messages.
        case notice
        /// Potential problems or unusual behavior.
        case warning
        /// Errors encountered during operation.
        case error
        /// Critical errors that make the current socket unusable.
        case crit

        var value: Int32 {
            switch self {
            case .debug:
                return LOG_DEBUG
            case .notice:
                return LOG_NOTICE
            case .warning:
                return LOG_WARNING
            case .error:
                return LOG_ERR
            case .crit:
                return LOG_CRIT
            }
        }
    }

    /// The SRT subsystems whose logging can be enabled.
    public enum FunctionalArea: Int32, Sendable {
        /// Serious issues that do not belong to a specific subsystem.
        case general = 0
        /// Socket creation, opening, closing, and configuration.
        case bstats = 1
        /// Connection establishment and handshakes.
        case control = 2
        /// Timer checks and related activity.
        case data = 3
        /// Timestamp-based packet delivery.
        case tsbpd = 4
        /// System resource allocation and management.
        case rsrc = 5
        /// The HaiCrypt encryption module.
        case haicrypt = 6
        /// Congestion control.
        case congest = 7
        /// Packet filtering.
        case pfilter = 8
        /// Application logging.
        case applog
        /// Socket and library management API calls.
        case apiCtrl = 11
        /// Queue control.
        case queCtrl = 13
        /// Internal epoll updates.
        case epollUpd = 16
        /// Receive API calls.
        case apiRecv = 21
        /// Receive buffers.
        case bufRecv = 22
        /// Receive queues.
        case queRecv = 23
        /// Receive channels.
        case chanRecv = 24
        /// Receive groups.
        case grpRecv = 25
        /// Send API calls.
        case apiSend = 31
        /// Send buffers.
        case bufSend = 32
        /// Send queues.
        case queSend = 33
        /// Send channels.
        case chnSend = 34
        /// Send groups.
        case grpSend = 35
        /// Internal activity not associated with a specific socket.
        case `internal` = 41
        /// Queue management.
        case queMgmt = 43
        /// Channel management.
        case chnMgmt = 44
        /// Group management.
        case grpMgmt = 45
        /// Epoll API calls.
        case epollApi = 46

        func addLogFA() {
            srt_addlogfa(rawValue)
        }

        func delLogFA() {
            srt_dellogfa(rawValue)
        }
    }

    private init() {
        srt_setloglevel(level.value)
    }

    /// The current logging level.
    public private(set) var level: Level = .notice {
        didSet {
            guard level != oldValue else {
                return
            }
            srt_setloglevel(level.value)
        }
    }

    /// The functional areas managed by this logger.
    ///
    /// Changing this set adds newly selected areas and removes previously selected areas
    /// from the library’s logging configuration.
    public private(set) var functionalAreas: Set<FunctionalArea> = [] {
        didSet {
            for area in oldValue.subtracting(functionalAreas) {
                area.delLogFA()
            }
            for area in functionalAreas.subtracting(oldValue) {
                area.addLogFA()
            }
        }
    }

    /// Sets the severity level used by the SRT library.
    public func setLevel(_ level: Level) {
        self.level = level
    }

    /// Updates the set of functional areas managed by this logger.
    public func setFunctionalAreas(_ functionalAreas: Set<FunctionalArea>) {
        self.functionalAreas = functionalAreas
    }
}
