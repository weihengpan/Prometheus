//
//  NestedQRCodeGenerator.swift
//  Prometheus
//
//  Created by 潘维恒 on 2020/7/8.
//  Copyright © 2020 PAN Weiheng. All rights reserved.
//

import CoreImage

class NestedQRCodeGenerator {
        
    enum CorrectionLevel: String {
        case low = "L"
        case medium = "M"
        case quartile = "Q"
        case high = "H"
    }
    
    private let filter = CIFilter(name: "CIQRCodeGenerator")!
    private let ciContext = CIContext()
    
    // MARK: - Methods
    
    func generateQRCode(forMetadataPacket packet: MetadataPacket, sideLength outputSideLength: CGFloat) -> CIImage {
        let correctionLevel: CorrectionLevel = .medium
        let packetData = packet.archive()
        let image = generateQRCodeWithUnitPixelSize(from: packetData, correctionLevel: correctionLevel)
        
        let imageSideLength = image.extent.width
        let scalingFactor = outputSideLength / imageSideLength
        let transform = CGAffineTransform(scaleX: scalingFactor, y: scalingFactor)
        let scaledImage = image.transformed(by: transform)
        
        let renderedImage = ciContext.createCGImage(scaledImage, from: scaledImage.extent)!
        return CIImage(cgImage: renderedImage)
    }
    
    func generateQRCodesForDataPackets(data: Data, correctionLevel: CorrectionLevel = .low, sideLength outputSideLength: CGFloat, maxPacketSize: Int) -> [CIImage] {
        let codeImages = generateQRCodesForDataPacketsWithUnitPixelSize(data: data, correctionLevel: correctionLevel, maxPacketSize: maxPacketSize)
        var scaledCodeImages: [CIImage] = []
        for image in codeImages {
            let imageSideLength = image.extent.width
            let scalingFactor = outputSideLength / imageSideLength
            let transform = CGAffineTransform(scaleX: scalingFactor, y: scalingFactor)
            let scaledImage = image.transformed(by: transform)
            scaledCodeImages.append(scaledImage)
        }
        return scaledCodeImages
    }
    
    func generateQRCodesForDataPacketsWithUnitPixelSize(data messageData: Data, correctionLevel: CorrectionLevel, maxPacketSize: Int) -> [CIImage] {
        
        let identifierWidth = MemoryLayout<UInt32>.size
        let headerWidth = MemoryLayout<UInt32>.size
        let unusableWidth = identifierWidth + headerWidth
        let maxPayloadSize = maxPacketSize - unusableWidth
        let messageDataSize = messageData.count
        
        // Split data
        var dataOfPackets: [Data] = []
        var frameIndex: UInt32 = 0
        var bytesSplit = 0
        while bytesSplit < messageDataSize {
            // Get payload segment
            let bytesNotSplit = messageDataSize - bytesSplit
            let payloadSize = min(bytesNotSplit, maxPayloadSize)
            let payloadIndexRange = bytesSplit...(bytesSplit + payloadSize - 1)
            let payload = messageData[payloadIndexRange]
            
            // Create packet
            let packet = DataPacket(flagBits: 0, frameIndex: frameIndex, payload: payload)
            
            // Append segment and increment
            dataOfPackets.append(packet.archive())
            frameIndex += 1
            bytesSplit += payloadSize
        }
        
        // Convert to QR code images
        return dataOfPackets.map { generateQRCodeWithUnitPixelSize(from: $0, correctionLevel: correctionLevel) }
    }
    
    /// Returns a QR code in the form of an CIImage, where the each block is one pixel wide.
    /// - Parameters:
    ///   - data: Binary data to encode in the QR code.
    ///   - correctionLevel: Correction level of the QR code.
    /// - Returns: A QR code in the form of an CIImage, where the each block is one pixel wide.
    private func generateQRCodeWithUnitPixelSize(from data: Data, correctionLevel: CorrectionLevel) -> CIImage {
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(correctionLevel.rawValue, forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else {
            fatalError("[QR Gen] Failed to generate QR code. Please check input parameters.")
        }
        return outputImage
    }
}
