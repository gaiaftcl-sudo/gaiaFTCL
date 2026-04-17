import Foundation

public enum SampleFormat: UInt8 {
    case complexInt16 = 0
    case complexFloat32 = 1
}

public struct ZMQHeader {
    public let sampleRateHz: UInt32
    public let sampleFormat: SampleFormat
    public let channelCount: UInt8
    public let reserved: Data // 10 bytes
    
    public init(sampleRateHz: UInt32, sampleFormat: SampleFormat, channelCount: UInt8) {
        self.sampleRateHz = sampleRateHz
        self.sampleFormat = sampleFormat
        self.channelCount = channelCount
        self.reserved = Data(count: 10)
    }
    
    public init?(data: Data) {
        guard data.count == 16 else { return nil }
        
        var sampleRateHz: UInt32 = 0
        var sampleFormatRaw: UInt8 = 0
        var channelCount: UInt8 = 0
        
        data.withUnsafeBytes { ptr in
            sampleRateHz = ptr.load(fromByteOffset: 0, as: UInt32.self)
            sampleFormatRaw = ptr.load(fromByteOffset: 4, as: UInt8.self)
            channelCount = ptr.load(fromByteOffset: 5, as: UInt8.self)
        }
        
        guard let format = SampleFormat(rawValue: sampleFormatRaw) else { return nil }
        
        self.sampleRateHz = UInt32(littleEndian: sampleRateHz)
        self.sampleFormat = format
        self.channelCount = channelCount
        self.reserved = data.subdata(in: 6..<16)
    }
    
    public func toData() -> Data {
        var data = Data(capacity: 16)
        var rate = sampleRateHz.littleEndian
        var format = sampleFormat.rawValue
        var channels = channelCount
        
        data.append(Data(bytes: &rate, count: MemoryLayout<UInt32>.size))
        data.append(Data(bytes: &format, count: MemoryLayout<UInt8>.size))
        data.append(Data(bytes: &channels, count: MemoryLayout<UInt8>.size))
        data.append(reserved)
        
        return data
    }
}
