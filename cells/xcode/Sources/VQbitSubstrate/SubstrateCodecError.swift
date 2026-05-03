import Foundation

public enum SubstrateCodecError: Error, Sendable {
    case invalidLength(expected: Int, actual: Int)
    case unsupportedProtocolVersion(found: UInt8, expected: UInt8)
    case malformedUUID(offset: Int)
    case invalidMagic
    case truncatedHeader
}
