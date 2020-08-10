//
//  BinaryArchiver.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/8/8.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import Foundation

/// A class for archiving variables into binary data serially.
class BinaryArchiver {
    
    private var archive = Data()
    
    /// Archives the given object into binary data.
    ///
    /// Only simple types are supported, as `class` types will not work and `struct` types are not guaranteed to work.
    /// Currently, endianness is not specified, so it is platform-dependent. On iOS, little endian is being used for most of the time.
    /// - Parameter object: The object to archive.
    func archive<T>(_ object: T) {
        var object = object
        archive += Data(bytes: &object, count: MemoryLayout<T>.size)
    }
    
    /// Appends the given data to the archive.
    /// - Parameter data: The data to append.
    func archive(_ data: Data) {
        archive += data
    }
    
    /// Returns the archive and resets the archiver's state.
    ///
    /// You may start to archive another object immediately after calling this method.
    func collectArchive() -> Data {
        let data = archive
        reset()
        return data
    }
    
    /// Resets the archiver's state.
    func reset() {
        archive = Data()
    }
    
}
