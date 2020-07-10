//
//  MetadataPacket.swift
//  Prometheus
//
//  Created by 潘维恒 on 2020/7/9.
//  Copyright © 2020 PAN Weiheng. All rights reserved.
//

import Foundation

struct MetadataPacket {
    
    let identifier: UInt32 = 0x55555555 // 0b01010101...
    var flagBits: UInt32 // reserved
    var numberOfFrames: UInt32
    var fileSize: UInt32 // in bytes
    var fileNameData: Data // encoded in UTF-8
    
    // MARK: - Initializers
    
    init(flagBits: UInt32, numberOfFrames: UInt32, fileSize: UInt32, fileNameData: Data) {
        self.flagBits = flagBits
        self.numberOfFrames = numberOfFrames
        self.fileSize = fileSize
        self.fileNameData = fileNameData
    }
    
    init?(flagBits: UInt32, numberOfFrames: UInt32, fileSize: UInt32, fileName: String) {
        self.flagBits = flagBits
        self.numberOfFrames = numberOfFrames
        self.fileSize = fileSize
        guard let fileNameData = fileName.data(using: .utf8) else { return nil }
        self.fileNameData = fileNameData
    }
    
    init?(archive: Data) {
        var bytesRead = 0
        
        let identifierByteCount = MemoryLayout<UInt32>.size
        let identifierData = archive[bytesRead..<bytesRead + identifierByteCount]
        let identifier = identifierData.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard identifier == self.identifier else { return nil }
        bytesRead += identifierByteCount
        
        let flagBitsByteCount = MemoryLayout<UInt32>.size
        let flagBitsData = archive[bytesRead..<bytesRead + flagBitsByteCount]
        self.flagBits = flagBitsData.withUnsafeBytes { $0.load(as: UInt32.self) }
        bytesRead += flagBitsByteCount
        
        let numberOfFramesByteCount = MemoryLayout<UInt32>.size
        let numberOfFramesData = archive[bytesRead..<bytesRead + numberOfFramesByteCount]
        self.numberOfFrames = numberOfFramesData.withUnsafeBytes { $0.load(as: UInt32.self) }
        bytesRead += numberOfFramesByteCount
        
        let fileSizeByteCount = MemoryLayout<UInt32>.size
        let fileSizeData = archive[bytesRead..<bytesRead + fileSizeByteCount]
        self.fileSize = fileSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }
        bytesRead += fileSizeByteCount
        
        self.fileNameData = archive[bytesRead...]
    }
    
    // MARK: - Methods
    
    func archive() -> Data {
        
        var data = Data()
        
        var identifier = self.identifier
        data += Data(bytes: &identifier, count: MemoryLayout<UInt32>.size)
        
        var flagBits = self.flagBits
        data += Data(bytes: &flagBits, count: MemoryLayout<UInt32>.size)
        
        var numberOfFrames = self.numberOfFrames
        data += Data(bytes: &numberOfFrames, count: MemoryLayout<UInt32>.size)
        
        var fileSize = self.fileSize
        data += Data(bytes: &fileSize, count: MemoryLayout<UInt32>.size)
        
        data += fileNameData
        
        return data
    }
}
