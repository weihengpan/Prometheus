//
//  SendViewController.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/7/7.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import UIKit
import Combine

final class SendViewController: UIViewController {
    
    enum SendMode: Int, CaseIterable {
        case single = 0
        case alternatingSingle
        case nested
        
        var readableName: String {
            switch self {
            case .single:
                return "Single QR Code"
            case .alternatingSingle:
                return "Alternating Single QR Code"
            case .nested:
                return "Nested QR Code"
            }
        }
    }
    
    // MARK: - IB Outlets, IB Actions and Related
    
    @IBOutlet weak var singleRenderView: MetalRenderView!
    @IBOutlet weak var topRenderView: MetalRenderView!
    @IBOutlet weak var bottomRenderView: MetalRenderView!
    @IBOutlet weak var startButton: UIButton!
    
    private var isDisplayingQRCodeImages = false
    @IBAction func startButtonDidTouchUpInside(_ sender: Any) {
        if isDisplayingQRCodeImages {
            stopDisplayingDataQRCodeImages()
        } else {
            startDisplayingDataQRCodeImages()
        }
        isDisplayingQRCodeImages.toggle()
    }
    
    // MARK: - Properties
    
    private let codeGenerator = NestedQRCodeGenerator()
    private var metadataCodeImage: CIImage?
    private var dataCodeImages: [CIImage]?
    
    private var codeDisplaySubscription: AnyCancellable?
    
    private let generationQueue = DispatchQueue(label: "generationQueue", qos: .userInitiated)
    
    // MARK: - View Controller Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Sending"
        
        // Disable timed auto-lock
        UIApplication.shared.isIdleTimerDisabled = true
    } 
    
    private var generated = false
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Wait until all leaf subviews have finished layout
        DispatchQueue.main.async {
            if self.generated == false {
                var sideLength: CGFloat
                switch self.sendMode {
                case .single, .nested:
                    sideLength = self.singleRenderView.frame.width * UIScreen.main.scale
                case .alternatingSingle:
                    sideLength = self.topRenderView.frame.width * UIScreen.main.scale
                }
                self.generationQueue.async {
                    self.generateQRCodeImagesAndDisplayMetadataCode(renderViewSideLength: sideLength)
                }
                self.generated = true
            }
        }
    }
    
    // MARK: - Methods
    
    /// For single code mode only.
    var sendMode: SendMode = .nested
    var sendFrameRate = 15.0
    var codeMaxPacketSize = QRCodeInformation.dataCapacity(forVersion: 13, errorCorrectionLevel: .low)!
    var largerCodeMaxPacketSize = QRCodeInformation.dataCapacity(forVersion: 18, errorCorrectionLevel: .quartile)!
    var smallerCodeMaxPacketSize = QRCodeInformation.dataCapacity(forVersion: 13, errorCorrectionLevel: .low)!
    private(set) var currentFrameIndex = 0
    
    private func startDisplayingDataQRCodeImages() {
        
        guard var codeImagesIterator = dataCodeImages?.makeIterator() else { return }
        codeDisplaySubscription = Timer.publish(every: 1.0 / sendFrameRate, on: .current, in: .common)
            .autoconnect()
            .sink { _ in
                
                let nextImage = codeImagesIterator.next()
                switch self.sendMode {
                case .single, .nested:
                    self.singleRenderView.image = nextImage
                case .alternatingSingle:
                    if self.currentFrameIndex % 2 == 0 {
                        self.topRenderView.image = nextImage
                        self.bottomRenderView.image = nil
                    } else {
                        self.bottomRenderView.image = nextImage
                        self.topRenderView.image = nil
                    }
                }
                
                self.currentFrameIndex += 1
        }
        startButton.setTitle("Reset", for: .normal)
    }
    
    private func stopDisplayingDataQRCodeImages() {
        guard let subscription = codeDisplaySubscription else { return }
        subscription.cancel()
        
        switch sendMode {
        case .single, .nested:
            singleRenderView.image = metadataCodeImage
        case .alternatingSingle:
            topRenderView.image = metadataCodeImage
            bottomRenderView.image = metadataCodeImage
        }
            
        currentFrameIndex = 0
        startButton.setTitle("Start", for: .normal)
    }
    
    private func generateQRCodeImagesAndDisplayMetadataCode(renderViewSideLength sideLength: CGFloat) {
        
        let fileName = "Alice's Adventures in Wonderland"
        let fileExtension = "txt"
        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
            fatalError("[SendVC] File not found.")
        }
        guard let message = try? String(contentsOf: url) else {
            fatalError("[SendVC] Failed to read file.")
        }
        guard let messageData = message.data(using: .utf8) else {
            fatalError("[SendVC] Failed to encode message in UTF-8.")
        }
        
        var frameCount: Int
        switch sendMode {
        case .single, .alternatingSingle:
            dataCodeImages = codeGenerator.generateQRCodes(forData: messageData, correctionLevel: .low, sideLength: sideLength, maxPacketSize: self.codeMaxPacketSize)
            frameCount = dataCodeImages!.count
        case .nested:
            (dataCodeImages, frameCount) = codeGenerator.generateNestedQRCodes(forData: messageData, largerCodeMaxPacketSize: largerCodeMaxPacketSize, smallerCodeMaxPacketSize: smallerCodeMaxPacketSize, smallerCodeSideLengthRatio: 0.4, sideLength: sideLength)
        }
        
        let fileSize = messageData.count
        let fullFileName = fileName + "." + fileExtension
        guard let metadataPacket = MetadataPacket(flagBits: 0, numberOfFrames: UInt32(frameCount), fileSize: UInt32(fileSize), fileName: fullFileName) else {
            fatalError("[SendVC] Failed to create metadata packet.")
        }
        metadataCodeImage = codeGenerator.generateQRCode(forMetadataPacket: metadataPacket, sideLength: sideLength)
        
        DispatchQueue.main.async {
            switch self.sendMode {
            case .single, .nested:
                self.singleRenderView.image = self.metadataCodeImage
            case .alternatingSingle:
                self.topRenderView.image = self.metadataCodeImage
                self.bottomRenderView.image = self.metadataCodeImage
            }
        }
    }
}

