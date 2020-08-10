//
//  DataPacketImage.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/8/10.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import CoreImage

/// An immutable class for storing the code image of a `DataPacket` while making its frame number remain accessible.
class DataPacketImage {
    
    let image: CIImage
    let frameNumber: UInt32
    
    init(image: CIImage, frameNumber: UInt32) {
        self.image = image
        self.frameNumber = frameNumber
    }
}
