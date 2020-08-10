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
    
    private lazy var commandQueue: MTLCommandQueue? = {
        [unowned self] in
        return self.device!.makeCommandQueue()
        }()
    
    private lazy var ciContext: CIContext = { [unowned self] in
        return CIContext(mtlDevice: self.device!,
                         options: [.cacheIntermediates: false])
        }()
    
    private var image: CIImage? {
        didSet {
            renderImage()
        }
    }
        
    // MARK: - Initializers
    
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
    
    // MARK: - Methods
    
    /// Displays an image.
    /// - Parameters:
    ///   - image: The image to display.
    ///   - scaleToFit: Whether to scale the image to fit the view.
    func setImage(_ image: CIImage?, scaleToFit: Bool = true) {
        
        guard let image = image else { return }
        
        let scale = UIScreen.main.scale
        let boundsInPixels = self.bounds
            .applying(.init(scaleX: scale, y: scale))
        
        if scaleToFit {
            let transform = scaleToFitTransform(from: image.extent, to: boundsInPixels)
            self.image = image.transformed(by: transform)
        } else {
            self.image = image
        }
        
    }
    
    /// Displays two images in a nested configuration.
    ///
    /// The two images are assumed to share the same aspect ratio. The composited image will be scaled to fit `self.bounds`.
    /// - Parameters:
    ///   - largerImage: The larger image.
    ///   - smallerImage: The smaller image.
    ///   - sizeRatio: The ratio of the larger image's side length to the smaller image's side length.
    func setNestedImages(larger largerImage: CIImage, smaller smallerImage: CIImage, sizeRatio: CGFloat) {
    
        // Scale and position the smaller image
        let xInset = largerImage.extent.width * (1 - sizeRatio)
        let yInset = largerImage.extent.height * (1 - sizeRatio)
        let insets = UIEdgeInsets(top: yInset, left: xInset, bottom: yInset, right: xInset)
        let smallerImageTargetExtent = largerImage.extent.inset(by: insets)
        let positionedSmallerImage = smallerImage.transformed(by: scaleToFitTransform(from: smallerImage.extent, to: smallerImageTargetExtent))
        
        // Composite the image
        let compositedImage = positionedSmallerImage.composited(over: largerImage)
        
        // Set image
        setImage(compositedImage)
    }
    
    private func setup() {
        
        framebufferOnly = false // allow Core Image to use Metal to compute
        isOpaque = false
        clearColor = MTLClearColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        
        // Pause draw loop and opt for drawing manually
        isPaused = true
        enableSetNeedsDisplay = false
    }
    
    private func renderImage() {
        
        guard let image = image else { return }
        
        let commandBuffer = commandQueue?.makeCommandBuffer()
        let destination = CIRenderDestination(width: Int(drawableSize.width),
                                              height: Int(drawableSize.height),
                                              pixelFormat: .rgba8Unorm,
                                              commandBuffer: commandBuffer) { () -> MTLTexture in
                                                return self.currentDrawable!.texture
        }
                
        // Render image
        try! ciContext.startTask(toRender: image, from: image.extent, to: destination, at: image.extent.origin)
        
        commandBuffer?.present(currentDrawable!)
        commandBuffer?.commit()
        
        draw()
    }
    
    // MARK: - Utilities
    
    /// Returns a porprotional scaling combined with a translation which makes a `CGRect` fit inside another `CGRect` when applied.
    /// The resulting `CGRect` is centered inside `self`.
    /// - Parameter rect: The rectangle to apply the transformation to.
    /// - Parameter targetRect: The rectangle to fit.
    private func scaleToFitTransform(from rect: CGRect, to targetRect: CGRect) -> CGAffineTransform {
                
        // Scale to appropriate size
        let boundAspectRatio = rect.width / rect.height
        let targetAspectRatio = targetRect.width / targetRect.height
        var scaleFactor: CGFloat
        if (boundAspectRatio < targetAspectRatio) {
            // bound is thinner than targetBound
            scaleFactor = targetRect.height / rect.height
        } else {
            // bound is fatter than targetBound
            scaleFactor = targetRect.width / rect.width
        }
        let scaleTransform = CGAffineTransform(scaleX: scaleFactor, y: scaleFactor)
        let scaledBound = rect.applying(scaleTransform)
        
        // Translate to new location
        let translationX = targetRect.midX - scaledBound.midX
        let translationY = targetRect.midY - scaledBound.midY
        let translateTransform = CGAffineTransform(translationX: translationX, y: translationY)
        
        // Concatenate transforms
        let transform = scaleTransform.concatenating(translateTransform)
        return transform
    }
    
}
