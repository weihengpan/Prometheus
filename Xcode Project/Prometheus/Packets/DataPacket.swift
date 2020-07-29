//
//  DataPacket.swift
//  Prometheus
//
//  Created by 潘维恒 on 2020/7/9.
//  Copyright © 2020 PAN Weiheng. All rights reserved.
//

import CoreImage

struct DataPacket {
    
    let identifier: UInt32 = 0xAAAAAAAA // 0b10101010...
    var header: UInt32
    var payload: Data
    
    var flagBits: UInt8 {
        get { return UInt8(header >> 24) }
        set { header = UInt32(newValue) << 24 + frameIndex }
    }
    /// Only the last 24 bits are used
    var frameIndex: UInt32 {
        get { return UInt32(header & 0x00FFFFFF) }
        set { header = UInt32(flagBits) << 24 + newValue }
    }
    
    static var sizeExceptPayload: Int {
        return 2 * MemoryLayout<UInt32>.size
    }
    
    // MARK: - Initializers
    
    init(header: UInt32, payload: Data) {
        self.header = header
        self.payload = payload
    }
    
    init(flagBits: UInt8, frameIndex: UInt32, payload: Data) {
        self.payload = payload
        self.header = 0
        self.flagBits = flagBits
        self.frameIndex = frameIndex
    }
    
    init?(flagBits: UInt8, frameIndex: UInt32, message: String, encoding: String.Encoding = .utf8) {
        guard let payload = message.data(using: encoding) else { return nil }
        self.payload = payload
        self.header = 0
        self.flagBits = flagBits
        self.frameIndex = frameIndex
    }
    
    init?(archive: Data) {
        var bytesRead = 0
        
        let identifierByteCount = MemoryLayout<UInt32>.size
        let identifierData = archive[bytesRead..<bytesRead + identifierByteCount]
        let identifier = identifierData.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard identifier == self.identifier else { return nil }
        bytesRead += identifierByteCount
        
        let headerByteCount = MemoryLayout<UInt32>.size
        let headerData = archive[bytesRead..<bytesRead + headerByteCount]
        self.header = headerData.withUnsafeBytes { $0.load(as: UInt32.self) }
        bytesRead += headerByteCount
        
        self.payload = archive[bytesRead...]
    }
    
    // MARK: - Methods
    
    func archive() -> Data {
        var data = Data()
        
        var identifier = self.identifier
        data += Data(bytes: &identifier, count: MemoryLayout<UInt32>.size)
        
        var header = self.header
        data += Data(bytes: &header, count: MemoryLayout<UInt32>.size)
        
        data += payload
        
        return data
    }
    
}

