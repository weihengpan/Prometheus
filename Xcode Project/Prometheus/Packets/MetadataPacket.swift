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
    var frameRate: UInt32 = 0
    var fileSize: UInt32 = 0
    private var fileNameData = Data()
    
    var flagString: String {
        switch flagBits {
        case Flag.void:
            return "void"
        case Flag.request:
            return "request"
        case Flag.ready:
            return "ready"
        default:
            return "unknown"
        }
    }
    var fileName: String? {
        return String(bytes: fileNameData, encoding: MetadataPacket.fileNameEncoding)
    }
    
    
    private let archiver = BinaryArchiver()
    private let unarchiver = BinaryUnarchiver()
    
    // MARK: - Initializers
    
    init(flagBits: UInt32, numberOfFrames: UInt32, frameRate: UInt32, fileSize: UInt32, fileNameData: Data) {
        self.flagBits = flagBits
        self.numberOfFrames = numberOfFrames
        self.frameRate = frameRate
        self.fileSize = fileSize
        self.fileNameData = fileNameData
    }
    
    init?(flagBits: UInt32, numberOfFrames: UInt32, frameRate: UInt32, fileSize: UInt32, fileName: String) {
        self.flagBits = flagBits
        self.numberOfFrames = numberOfFrames
        self.frameRate = frameRate
        self.fileSize = fileSize
        guard let fileNameData = fileName.data(using: MetadataPacket.fileNameEncoding) else { return nil }
        self.fileNameData = fileNameData
    }
    
    init?(archive: Data) {
        
        unarchiver.loadArchive(from: archive)
        unarchiver.unarchive(to: &identifier)
        unarchiver.unarchive(to: &flagBits)
        unarchiver.unarchive(to: &numberOfFrames)
        unarchiver.unarchive(to: &frameRate)
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
        archiver.archive(frameRate)
        archiver.archive(fileSize)
        archiver.archive(fileNameData)
        let archive = archiver.collectArchive()
        return archive
    }
    
    // MARK: - Flag Constants
    
    /*
     
     The flags listed below are used during calibration in duplex mode.
     These values should be put in the `flagBits` property of the packet.
     Here, a "reply" is a quick flash emitted by the receiver.
     
     */
    
    enum Flag {
        /// This flag carries no meaning, and should be ignored.
        static let void: UInt32 =    0x00000000
        
        /// Use this flag to inform the receiver to reply this frame.
        static let request: UInt32 =   0xAAAAAAAA  // 0b10101010...
        
        /// Use this flag to inform the receiver that the sender has collected
        /// enough information, and will start sending the data packets soon.
        static let ready: UInt32 =   0x55555555  // 0b01010101...
        
        /// There is no use for this value yet.
        //static let noReply: UInt32 = 0xFFFFFFFF  // 0b11111111...
    }
}
