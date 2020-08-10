//
//  NestedQRCodeGenerator.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/7/8.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import CoreImage

class NestedQRCodeGenerator {
    
    typealias ErrorCorrectionLevel = QRCodeInformation.ErrorCorrectionLevel
    
    private let filter = CIFilter(name: "CIQRCodeGenerator")!
    private let ciContext = CIContext()
    
    // MARK: - Methods
    
    /// Generates code images for the given data by splitting it into segments of appropriate sizes so that they may be displayed in a nested configuration.
    /// - Parameters:
    ///   - data: The input data.
    ///   - largerCodeMaxPacketSize: The maximum packet size of the larger codes.
    ///   - smallerCodeMaxPacketSize: The maximum packet size of the smaller codes.
    /// - Returns: The generated code images, arranged in the following order: [larger, smaller, larger, smaller, ...]. The images are unit-sized, so you will need to scale and composite them to display them properly.
    func generateDataPacketImagesForNestedDisplay(for data: Data, largerCodeCorrectionLevel: ErrorCorrectionLevel, largerCodeMaxPacketSize: Int, smallerCodeCorrectionLevel: ErrorCorrectionLevel, smallerCodeMaxPacketSize: Int) -> [DataPacketImage] {
        
        let headerSize = DataPacket.headerSize
        let largerCodeMaxPayloadSize = largerCodeMaxPacketSize - headerSize
        let smallerCodeMaxPayloadSize = smallerCodeMaxPacketSize - headerSize
        let dataSize = data.count
        
        // Generate images
        var dataPacketImages = [DataPacketImage]()
        var frameNumber: UInt32 = 0
        var bytesSplit = 0
        while bytesSplit < dataSize {
            
            let maxPayloadSize = (frameNumber % 2 == 0) ? largerCodeMaxPayloadSize : smallerCodeMaxPayloadSize
            let correctionLevel = (frameNumber % 2 == 0) ? largerCodeCorrectionLevel : smallerCodeCorrectionLevel
            
            // Get payload segment
            let bytesNotSplit = dataSize - bytesSplit
            let payloadSize = min(bytesNotSplit, maxPayloadSize)
            let payloadIndexRange = bytesSplit...(bytesSplit + payloadSize - 1)
            let payload = data[payloadIndexRange]
            
            // Create packet
            let packet = DataPacket(flag: DataPacket.Flag.void,
                                    frameNumber: frameNumber,
                                    payload: payload)
            
            // Create image
            let image = generateUnitSizedQRCode(for: packet.archive(), correctionLevel: correctionLevel)
            let packetImage = DataPacketImage(image: image, frameNumber: frameNumber)
            
            // Append image and increment
            dataPacketImages.append(packetImage)
            bytesSplit += payloadSize
            frameNumber += 1
        }
        
        return dataPacketImages
    }
    
    func generateMetadataCode(for packet: MetadataPacket, correctionLevel: ErrorCorrectionLevel = .medium) -> CIImage {
        
        let packetData = packet.archive()
        let image = generateUnitSizedQRCode(for: packetData, correctionLevel: correctionLevel)
        
        return image
    }
    
    func generateDataPacketImages(for data: Data, correctionLevel: ErrorCorrectionLevel, maxPacketSize: Int) -> [DataPacketImage] {
        
        let headerSize = DataPacket.headerSize
        let maxPayloadSize = maxPacketSize - headerSize
        let dataSize = data.count
        
        // Split data
        var dataPacketImage = [DataPacketImage]()
        var frameNumber: UInt32 = 0
        var bytesSplit = 0
        while bytesSplit < dataSize {
            
            // Get payload segment
            let bytesNotSplit = dataSize - bytesSplit
            let payloadSize = min(bytesNotSplit, maxPayloadSize)
            let payloadIndexRange = bytesSplit...(bytesSplit + payloadSize - 1)
            let payload = data[payloadIndexRange]
            
            // Create packet
            let packet = DataPacket(flag: DataPacket.Flag.void,
                                    frameNumber: frameNumber,
                                    payload: payload)
            
            // Create image
            let image = generateUnitSizedQRCode(for: packet.archive(), correctionLevel: correctionLevel)
            let packetImage = DataPacketImage(image: image, frameNumber: frameNumber)
            
            // Append image and increment
            dataPacketImage.append(packetImage)
            bytesSplit += payloadSize
            frameNumber += 1
        }
        
        // Convert to QR code images
        return dataPacketImage
    }
    
    /// Returns a QR code in the form of an CIImage, where each module is one pixel wide.
    ///
    /// There is also a one-pixel wide quiet area surrounding the code.
    /// - Parameters:
    ///   - data: Binary data to encode in the QR code.
    ///   - correctionLevel: Correction level of the QR code.
    private func generateUnitSizedQRCode(for data: Data, correctionLevel: ErrorCorrectionLevel) -> CIImage {
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(correctionLevel.rawValue, forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else {
            fatalError("[QR Gen] Failed to generate QR code. Please check input parameters.")
        }
        return outputImage
    }
}
