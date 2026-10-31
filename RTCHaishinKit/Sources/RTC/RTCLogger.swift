import libdatachannel

/// Configures logging in the underlying libdatachannel library.
public actor RTCLogger {
    /// Defines the logging severity levels supported by `libdatachannel`.
    public enum Level {
        /// No logs will be emitted.
        case none
        /// Fatal errors.
        case fatal
        /// Recoverable errors.
        case error
        /// Potential issues that should be noted.
        case warning
        /// General informational messages.
        case info
        /// Debug messages for development and troubleshooting.
        case debug
        /// Verbose messages for detailed tracing.
        case verbose

        var cValue: rtcLogLevel {
            switch self {
            case .none:
                return RTC_LOG_NONE
            case .fatal:
                return RTC_LOG_FATAL
            case .error:
                return RTC_LOG_ERROR
            case .warning:
                return RTC_LOG_WARNING
            case .info:
                return RTC_LOG_INFO
            case .debug:
                return RTC_LOG_DEBUG
            case .verbose:
                return RTC_LOG_VERBOSE
            }
        }
    }

    /// The singleton logger instance.
    public static let shared = RTCLogger()

    /// The logger’s stored level.
    ///
    /// This property remains `.none`; `setLevel(_:)` configures the library without updating it.
    public private(set) var level: Level = .none

    /// Sets the logging level used by libdatachannel.
    ///
    /// - Parameter level: The severity level to pass to the library.
    public func setLevel(_ level: Level) {
        rtcInitLogger(level.cValue, nil)
    }
}
