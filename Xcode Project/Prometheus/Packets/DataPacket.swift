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
    private var flagBitsFrameIndexUnion: UInt32 = 0
    var payload = Data()
    
    var flagBits: UInt8 {
        get { return UInt8(flagBitsFrameIndexUnion >> 24) }
        set { flagBitsFrameIndexUnion = UInt32(newValue) << 24 + frameIndex }
    }
    /// Only the last 24 bits are used
    var frameIndex: UInt32 {
        get { return UInt32(flagBitsFrameIndexUnion & 0x00FFFFFF) }
        set { flagBitsFrameIndexUnion = UInt32(flagBits) << 24 + newValue }
    }
    
    private let archiver = BinaryArchiver()
    private let unarchiver = BinaryUnarchiver()
    
    // MARK: - Initializers
    
    init(header: UInt32, payload: Data) {
        self.flagBitsFrameIndexUnion = header
        self.payload = payload
    }
    
    init(flagBits: UInt8, frameIndex: UInt32, payload: Data) {
        self.payload = payload
        self.flagBitsFrameIndexUnion = 0
        self.flagBits = flagBits
        self.frameIndex = frameIndex
    }
    
    init?(flagBits: UInt8, frameIndex: UInt32, message: String, encoding: String.Encoding = .utf8) {
        guard let payload = message.data(using: encoding) else { return nil }
        self.payload = payload
        self.flagBitsFrameIndexUnion = 0
        self.flagBits = flagBits
        self.frameIndex = frameIndex
    }
    
    init?(archive: Data) {
        
        unarchiver.loadArchive(from: archive)
        unarchiver.unarchive(to: &identifier)
        unarchiver.unarchive(to: &flagBitsFrameIndexUnion)
        unarchiver.unarchive(to: &payload)
        
        // Verify identifier
        guard identifier == DataPacket.identifierConstant else { return nil }
    }
    
    // MARK: - Methods
    
    func archive() -> Data {
        
        archiver.archive(identifier)
        archiver.archive(flagBitsFrameIndexUnion)
        archiver.archive(payload)
        let archive = archiver.collectArchive()
        return archive

    }
        
}

