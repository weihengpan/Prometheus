//
//  DataPacket.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/7/9.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import CoreImage

struct DataPacket {
    
    static let identifierConstant: UInt32 = 0xAAAAAAAA // 0b10101010...
    static var headerSize: Int {
        return 2 * MemoryLayout<UInt32>.size
    }
    
    var identifier: UInt32 = DataPacket.identifierConstant
    private var flagAndFrameNumberUnion: UInt32 = 0
    var payload = Data()
    
    var flag: UInt8 {
        get { return UInt8(flagAndFrameNumberUnion >> 24) }
        set { flagAndFrameNumberUnion = UInt32(newValue) << 24 + frameNumber }
    }
    
    /// 24 bits only.
    var frameNumber: UInt32 {
        get { return UInt32(flagAndFrameNumberUnion & 0x00FFFFFF) }
        set { flagAndFrameNumberUnion = UInt32(flag) << 24 + newValue }
    }
    
    private let archiver = BinaryArchiver()
    private let unarchiver = BinaryUnarchiver()
    
    // MARK: - Initializers
    
    init(header: UInt32, payload: Data) {
        self.flagAndFrameNumberUnion = header
        self.payload = payload
    }
    
    init(flag: UInt8, frameNumber: UInt32, payload: Data) {
        self.payload = payload
        self.flagAndFrameNumberUnion = 0
        self.flag = flag
        self.frameNumber = frameNumber
    }
    
    init?(flag: UInt8, frameNumber: UInt32, message: String, encoding: String.Encoding = .utf8) {
        guard let payload = message.data(using: encoding) else { return nil }
        self.payload = payload
        self.flagAndFrameNumberUnion = 0
        self.flag = flag
        self.frameNumber = frameNumber
    }
    
    init?(archive: Data) {
        
        unarchiver.loadArchive(from: archive)
        unarchiver.unarchive(to: &identifier)
        unarchiver.unarchive(to: &flagAndFrameNumberUnion)
        unarchiver.unarchive(to: &payload)
        
        // Verify identifier
        guard identifier == DataPacket.identifierConstant else { return nil }
    }
    
    // MARK: - Methods
    
    func archive() -> Data {
        
        archiver.archive(identifier)
        archiver.archive(flagAndFrameNumberUnion)
        archiver.archive(payload)
        let archive = archiver.collectArchive()
        return archive

    }
        
    // MARK: - Flag constants
    
    /*
     
     The flags listed below have no use yet.
     These values should be put in the `flag` property of the packet.
     Note that each flag is only 8-bit.
     
     */
    
    enum Flag {
        
        static let void: UInt8 = 0x00
        
    }
}

