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
    
    func generateNestedQRCodes(forData data: Data, largerCodeMaxPacketSize: Int, smallerCodeMaxPacketSize: Int, smallerCodeSideLengthRatio: Double, sideLength outputSideLength: CGFloat) -> ([CIImage], Int) {
        
        let unusableWidth = DataPacket.sizeExceptPayload
        let largerCodeMaxPayloadSize = largerCodeMaxPacketSize - unusableWidth
        let smallerCodeMaxPayloadSize = smallerCodeMaxPacketSize - unusableWidth
        let dataSize = data.count
        
        // Split data
        var largerCodesData = [Data]()
        var smallerCodesData = [Data]()
        var frameIndex: UInt32 = 0
        var bytesSplit = 0
        while bytesSplit < dataSize {
            let maxPayloadSize = (frameIndex % 2 == 0) ? largerCodeMaxPayloadSize : smallerCodeMaxPayloadSize
            
            // Get payload segment
            let bytesNotSplit = dataSize - bytesSplit
            let payloadSize = min(bytesNotSplit, maxPayloadSize)
            let payloadIndexRange = bytesSplit...(bytesSplit + payloadSize - 1)
            let payload = data[payloadIndexRange]
            
            // Create packet
            let packet = DataPacket(flagBits: 0, frameIndex: frameIndex, payload: payload)
            let packetData = packet.archive()
            
            // Append segment and increment
            if frameIndex % 2 == 0 {
                largerCodesData.append(packetData)
            } else {
                smallerCodesData.append(packetData)
            }
            frameIndex += 1
            bytesSplit += payloadSize
        }
        
        // Convert to QR code images
        let unitSizedLargerCodes = largerCodesData.map { generateUnitSizedQRCode(forData: $0, correctionLevel: .quartile) }
        let unitSizedSmallerCodes = smallerCodesData.map { generateUnitSizedQRCode(forData: $0, correctionLevel: .low) }
        
        // Scale code images
        func scaleImages(images: [CIImage], sideLength outputSideLength: CGFloat) -> [CIImage] {
            var scaledImages = [CIImage]()
            for image in images {
                let imageSideLength = image.extent.width
                let scalingFactor = outputSideLength / imageSideLength
                let transform = CGAffineTransform(scaleX: scalingFactor, y: scalingFactor)
                let scaledImage = image.transformed(by: transform)
                scaledImages.append(scaledImage)
            }
            return scaledImages
        }
        let smallerCodeSideLength = outputSideLength * CGFloat(smallerCodeSideLengthRatio)
        let largerCodes = scaleImages(images: unitSizedLargerCodes, sideLength: outputSideLength)
        let smallerCodes = scaleImages(images: unitSizedSmallerCodes, sideLength: smallerCodeSideLength)
        
        // Translate smaller codes to the center of the larger code
        let translationDistance = (outputSideLength - smallerCodeSideLength) / 2.0
        let translation = CGAffineTransform(translationX: translationDistance, y: translationDistance)
        var translatedSmallerCodes = smallerCodes.map { $0.transformed(by: translation) }
        
        // Merge the two types of codes
        if largerCodes.count > translatedSmallerCodes.count {
            translatedSmallerCodes.append(.empty())
        }
        var mergedCodes = [CIImage]()
        for i in 0..<largerCodes.count {
            let largerCode = largerCodes[i]
            let translatedSmallerCode = translatedSmallerCodes[i]
            let mergedCode = translatedSmallerCode.composited(over: largerCode)
            mergedCodes.append(mergedCode)
        }
        
        let frameCount = largerCodes.count + smallerCodes.count
        return (mergedCodes, frameCount)
    }
    
    func generateQRCode(forMetadataPacket packet: MetadataPacket, sideLength outputSideLength: CGFloat) -> CIImage {
        let correctionLevel: ErrorCorrectionLevel = .medium
        let packetData = packet.archive()
        let image = generateUnitSizedQRCode(forData: packetData, correctionLevel: correctionLevel)
        
        let imageSideLength = image.extent.width
        let scalingFactor = outputSideLength / imageSideLength
        let transform = CGAffineTransform(scaleX: scalingFactor, y: scalingFactor)
        let scaledImage = image.transformed(by: transform)
        
        let renderedImage = ciContext.createCGImage(scaledImage, from: scaledImage.extent)!
        return CIImage(cgImage: renderedImage)
    }
    
    func generateQRCodes(forData data: Data, correctionLevel: ErrorCorrectionLevel = .low, sideLength outputSideLength: CGFloat, maxPacketSize: Int) -> [CIImage] {
        let codeImages = generateUnitSizedQRCodes(forData: data, correctionLevel: correctionLevel, maxPacketSize: maxPacketSize)
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
    
    func generateUnitSizedQRCodes(forData data: Data, correctionLevel: ErrorCorrectionLevel, maxPacketSize: Int) -> [CIImage] {
        
        let unusableWidth = DataPacket.sizeExceptPayload
        let maxPayloadSize = maxPacketSize - unusableWidth
        let dataSize = data.count
        
        // Split data
        var PacketsData: [Data] = []
        var frameIndex: UInt32 = 0
        var bytesSplit = 0
        while bytesSplit < dataSize {
            // Get payload segment
            let bytesNotSplit = dataSize - bytesSplit
            let payloadSize = min(bytesNotSplit, maxPayloadSize)
            let payloadIndexRange = bytesSplit...(bytesSplit + payloadSize - 1)
            let payload = data[payloadIndexRange]
            
            // Create packet
            let packet = DataPacket(flagBits: 0, frameIndex: frameIndex, payload: payload)
            
            // Append segment and increment
            PacketsData.append(packet.archive())
            frameIndex += 1
            bytesSplit += payloadSize
        }
        
        // Convert to QR code images
        return PacketsData.map { generateUnitSizedQRCode(forData: $0, correctionLevel: correctionLevel) }
    }
    
    /// Returns a QR code in the form of an CIImage, where the each block is one pixel wide.
    /// - Parameters:
    ///   - data: Binary data to encode in the QR code.
    ///   - correctionLevel: Correction level of the QR code.
    /// - Returns: A QR code in the form of an CIImage, where the each block is one pixel wide.
    private func generateUnitSizedQRCode(forData data: Data, correctionLevel: ErrorCorrectionLevel) -> CIImage {
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(correctionLevel.rawValue, forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else {
            fatalError("[QR Gen] Failed to generate QR code. Please check input parameters.")
        }
        return outputImage
    }
}
