//
//  MetadataPacket.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/7/9.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import Foundation

struct MetadataPacket {
    
    static let identifierConstant: UInt32 = 0x55555555 // 0b01010101...
    static let fileNameEncoding: String.Encoding = .utf8
    
    var identifier: UInt32 = MetadataPacket.identifierConstant
    var flagBits: UInt32 = 0
    var numberOfFrames: UInt32 = 0
    var fileSize: UInt32 = 0
    
    private var fileNameData = Data()
    var fileName: String? {
        return String(bytes: fileNameData, encoding: MetadataPacket.fileNameEncoding)
    }
    
    private let archiver = BinaryArchiver()
    private let unarchiver = BinaryUnarchiver()
    
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
        guard let fileNameData = fileName.data(using: MetadataPacket.fileNameEncoding) else { return nil }
        self.fileNameData = fileNameData
    }
    
    init?(archive: Data) {
        
        unarchiver.loadArchive(from: archive)
        unarchiver.unarchive(to: &identifier)
        unarchiver.unarchive(to: &flagBits)
        unarchiver.unarchive(to: &numberOfFrames)
        unarchiver.unarchive(to: &fileSize)
        unarchiver.unarchive(to: &fileNameData)
        
        // Verify identifier
        guard identifier == MetadataPacket.identifierConstant else { return nil }
    }
    
    // MARK: - Methods
    
    func archive() -> Data {
        
        archiver.archive(identifier)
        archiver.archive(flagBits)
        archiver.archive(numberOfFrames)
        archiver.archive(fileSize)
        archiver.archive(fileNameData)
        let archive = archiver.collectArchive()
        return archive
    }
}
