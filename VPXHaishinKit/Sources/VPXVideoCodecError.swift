import CoreMedia

/// A standalone codec failure. Unsupported configurations never select another codec.
public enum VPXVideoCodecError: Swift.Error {
    /// A setting is out of range or an update changes an immutable setting.
    case invalidSettings
    /// The input sample, pixel format, or decoded output is unsupported.
    case unsupportedFormat
    /// An encoder timestamp is nonnumeric, nonzero-epoch, or not strictly increasing.
    case invalidTimestamp
    /// The codec was invalidated, or encoding was attempted after finishing.
    case invalidSession
    /// A native libvpx operation failed with its returned status code.
    case codec(Int32)
    /// A Core Media, Core Video, or VideoToolbox operation failed with its status code.
    case coreMedia(OSStatus)
}
