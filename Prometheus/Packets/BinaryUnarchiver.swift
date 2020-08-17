//
//  BinaryUnarchiver.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/8/8.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import Foundation

/// A class for serially unarchiving content from binary data.
class BinaryUnarchiver {
    
    private var archive: Data!
    private var bytesRead: Int = 0
    
    /// Loads the given archive.
    ///
    /// This method also resets the unarchiver's state before loading.
    /// - Parameter data: The archive to load.
    func loadArchive(from data: Data) {
        bytesRead = 0
        archive = data
    }
    
    /// Unarchives part of the archive data and writes it into a variable.
    ///
    /// The size of `object` is automatically determined from its type.
    /// Only simple types are supported, as `class` types will not work and `struct` types are not guaranteed to work.
    /// Currently, endianness is not specified, so it is platform-dependent. On iOS, little endian is being used for most of the time.
    /// - Parameter object: The variable to write to.
    func unarchive<T>(to object: inout T) {
        
        let objectByteCount = MemoryLayout<T>.size
        let objectData = archive[bytesRead..<bytesRead + objectByteCount]
        object = objectData.withUnsafeBytes { $0.load(as: T.self) }
        bytesRead += objectByteCount
    }
    
    /// Unarchives part of the archive data and directly writes it into a `Data` variable.
    /// - Parameters:
    ///   - data: The variable to write to.
    ///   - dataSize: The size of the data to unarchive. If `nil` is specified, the rest of the archive (that are not read) will be all written into `data`.
    func unarchive(to data: inout Data, dataSize: Int? = nil) {
        if let size = dataSize {
            data = archive[bytesRead..<bytesRead + size]
            bytesRead += size
        } else {
            data = archive[bytesRead...]
            bytesRead = archive.count
        }
    }

    
    /// Resets the unarchiver to its freshly initialized state.
    func reset() {
        archive = nil
        bytesRead = 0
    }
}
