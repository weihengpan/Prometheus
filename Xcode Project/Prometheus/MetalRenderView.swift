//
//  MetalRenderView.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/7/8.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import MetalKit
import CoreImage

final class MetalRenderView : MTKView {
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        
        guard super.device != nil else {
            fatalError("You must specify a MTLDevice for this class.")
        }
        setup()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        
        device = MTLCreateSystemDefaultDevice()
        setup()
    }
    
    private func setup() {
        framebufferOnly = false // allow Core Image to use Metal compute
        isOpaque = false
        clearColor = MTLClearColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        
        isPaused = false
        enableSetNeedsDisplay = false
    }
    
    private lazy var commandQueue: MTLCommandQueue? = {
        [unowned self] in
        return self.device!.makeCommandQueue()
        }()
    
    private lazy var ciContext: CIContext = {
        [unowned self] in
        return CIContext(mtlDevice: self.device!,
                         options: [
                            .cacheIntermediates: false
        ])
        }()
    
    var image: CIImage? {
        didSet {
            renderImage()
        }
    }
    
    var isAnimating: Bool = false
    
    private func renderImage() {
        guard let image = image else { return }
        
        let commandBuffer = commandQueue?.makeCommandBuffer()
        let destination = CIRenderDestination(width: Int(drawableSize.width),
                                              height: Int(drawableSize.height),
                                              pixelFormat: .rgba8Unorm,
                                              commandBuffer: commandBuffer) { () -> MTLTexture in
                                                return self.currentDrawable!.texture
        }
        
        // Start render task
        
        // Render image
        try! ciContext.startTask(toRender: image, from: image.extent, to: destination, at: image.extent.origin)
        
        commandBuffer?.present(currentDrawable!)
        commandBuffer?.commit()
        
        draw()
    }
}
