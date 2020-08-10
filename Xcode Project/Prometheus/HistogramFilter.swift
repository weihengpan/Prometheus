//
//  HistogramFilter.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/8/8.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import CoreImage.CIFilterBuiltins
import MetalPerformanceShaders

class HistogramFilter {
    
    typealias EntryType = UInt32
    
    /// Must be a power of 2 (minimum 256)
    var numberOfHistogramEntries = 256
    
    // Rendering variables
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var ciContext: CIContext!
    var monochromeFilter = CIFilter.colorControls()
    
    init() {
        
        // Setup rendering variables
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Cannot create MTLDevice.") }
        self.device = device
        
        guard let commandQueue = device.makeCommandQueue() else { fatalError("Cannot create MTLCommandQueue.") }
        self.commandQueue = commandQueue
        
        self.ciContext = CIContext(mtlDevice: device)
        
        // Initialize sRGB to luma filter
        monochromeFilter.saturation = 0
        monochromeFilter.brightness = 0
        
    }
    
    /// Calculates the monochrome histogram of an image.
    /// - Parameter inputImage: The input image.
    /// - Returns: An array containing the histogram data of the image, arranged in increasing pixel value order.
    func calculateHistogram(of inputImage: CIImage) -> [EntryType] {
        
        // Convert image to grayscale
        monochromeFilter.inputImage = inputImage
        guard let inputImage = monochromeFilter.outputImage else {
            fatalError("Failed to create output image from monochrome filter.")
        }
        
        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { fatalError("Cannot create MTLCommandBuffer.") }
        
        // Create color space
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // Create texture descriptor
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(inputImage.extent.width),
            height: Int(inputImage.extent.height),
            mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        // Create input texture
        guard let inputTexture = device.makeTexture(descriptor: textureDescriptor) else { fatalError("Cannot create input texture.") }
        
        // Render input image to texture
        ciContext.render(inputImage,
                         to: inputTexture,
                         commandBuffer: commandBuffer,
                         bounds: inputImage.extent,
                         colorSpace: colorSpace)
        
        // Prepare histogram info
        var histogramInfo = MPSImageHistogramInfo(
            numberOfHistogramEntries: self.numberOfHistogramEntries, // Each value inside a bin is a UInt32
            histogramForAlpha: false,
            minPixelValue: vector_float4(0, 0, 0, 0),
            maxPixelValue: vector_float4(1, 1, 1, 1))
        
        // Create histogram calculation object
        let calculation = MPSImageHistogram(device: device, histogramInfo: &histogramInfo)
        
        // Create histogram buffer
        let bufferLength = calculation.histogramSize(forSourceFormat: inputTexture.pixelFormat)
        guard let histogramBuffer = device.makeBuffer(
            bytes: &histogramInfo,
            length: bufferLength,
            options: [.storageModeShared])
            else { fatalError("Cannot create histogram buffer.") }
        
        // Encode GPU command to command queue
        calculation.encode(
            to: commandBuffer,
            sourceTexture: inputTexture,
            histogram: histogramBuffer,
            histogramOffset: 0)
        
        // Execute GPU code
        commandBuffer.commit()
        
        // Wait for GPU execution
        commandBuffer.waitUntilCompleted()
        
        // Extract histogram data from buffer
        let count = bufferLength / MemoryLayout<EntryType>.stride
        let rawPointer = histogramBuffer.contents()
        let pointer = rawPointer.bindMemory(to: EntryType.self, capacity: count)
        let bufferPointer = UnsafeBufferPointer(start: pointer, count: count)
        
        // Order: [R0, R1, ..., R255, G0, G1, ..., G255, B1, ..., B255]
        let histogram = Array(bufferPointer)
        
        // Only return the histogram associated with the red channel (luma values)
        let monochromeHistogram = Array(histogram.prefix(upTo: self.numberOfHistogramEntries))
        return monochromeHistogram
    }
}
