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
    
    enum CodeType: Int, CaseIterable {
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
    
    private enum State {
        case generatingCodes
        case waitingForManualStart
        case calibrating
        case calibrationFinishedAndWaitingForStart
        case sending
    }
    
    // MARK: - IB Outlets, IB Actions and Related
    
    @IBOutlet weak var singleRenderView: MetalRenderView!
    @IBOutlet weak var topRenderView: MetalRenderView!
    @IBOutlet weak var bottomRenderView: MetalRenderView!
    
    @IBOutlet weak var startButton: UIButton!
    
    @IBAction func startButtonDidTouchUpInside(_ sender: Any) {
        proceedToNextStateAndUpdateUI()
    }
    
    // MARK: - View Controller Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Sending"
        
        // Disable timed auto-lock
        UIApplication.shared.isIdleTimerDisabled = true
        
        proceedToNextStateAndUpdateUI(updateUIOnly: true)
    } 
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Wait until all leaf subviews have finished layout
        DispatchQueue.main.async {
            if self.hasGeneratedCodes == false {
                var sideLength: CGFloat
                switch self.sendMode {
                    
                case .single, .nested:
                    sideLength = self.singleRenderView.frame.width * UIScreen.main.scale
                    
                case .alternatingSingle:
                    sideLength = self.topRenderView.frame.width * UIScreen.main.scale
                }
                
                self.generationQueue.async {
                    self.generateCodeImagesAndDisplayMetadataCode(renderViewSideLength: sideLength)
                }
                self.hasGeneratedCodes = true
            }
        }
    }
    
    // MARK: - State Management
    
    private var hasGeneratedCodes = false
    private var state: State = .generatingCodes
    
    private func proceedToNextStateAndUpdateUI(updateUIOnly: Bool = false) {
        
        if updateUIOnly == false {
    
            // Update state variables
            switch state {
                
            case .generatingCodes:
                state = .waitingForManualStart
                
            case .waitingForManualStart:
                state = usesDuplexMode ? .calibrating : .sending
                
            case .calibrating:
                state = .calibrationFinishedAndWaitingForStart
                
            case .calibrationFinishedAndWaitingForStart:
                state = .sending
                
            case .sending:
                state = .waitingForManualStart
            }
            
            // Perform actions
            switch state {
                
            case .generatingCodes:
                stopDisplayingDataCodeImages()
                
            case .waitingForManualStart:
                
                if usesDuplexMode == false {
                    displayMetadataCodeImage()
                }
                
            case .calibrating:
                startDisplayingMetadataCodeImages()
                
            case .calibrationFinishedAndWaitingForStart:
                /// - TODO: Delay and start transmission
                break
                
            case .sending:
                startDisplayingDataCodeImages()
            }
        }
        
        // Update UI
        var startButtonTitle: String
        var startButtonIsEnabled: Bool
        
        switch state {
            
        case .generatingCodes:
            startButtonTitle = usesDuplexMode ? "Start Calibration" : "Start Sending"
            startButtonIsEnabled = false
            
        case .waitingForManualStart:
            startButtonTitle = usesDuplexMode ? "Start Calibration" : "Start Sending"
            startButtonIsEnabled = true
            
        case .calibrating:
            startButtonTitle = "Start Sending"
            startButtonIsEnabled = false
            
        case .calibrationFinishedAndWaitingForStart:
            startButtonTitle = "Start Sending"
            startButtonIsEnabled = true
            
        case .sending:
            startButtonTitle = "Stop Sending"
            startButtonIsEnabled = true
        }
        
        DispatchQueue.main.async {
            self.startButton.setTitle(startButtonTitle, for: .normal)
            self.startButton.isEnabled = startButtonIsEnabled
        }
        
    }

    // MARK: - Code Display
    
    var sendMode: CodeType = .nested
    var usesDuplexMode: Bool = false
    var sendFrameRate = 15.0
    
    /// For single code modes only.
    var codeMaxPacketSize = QRCodeInformation.dataCapacity(forVersion: 13,
                                                           errorCorrectionLevel: .low)!
    
    /// For nested code mode only.
    var largerCodeMaxPacketSize = QRCodeInformation.dataCapacity(forVersion: 18,
                                                                 errorCorrectionLevel: .quartile)!
    var smallerCodeMaxPacketSize = QRCodeInformation.dataCapacity(forVersion: 13,
                                                                  errorCorrectionLevel: .low)!
    
    var smallerCodeSideLengthRatio = 0.3
    
    private let codeGenerator = NestedQRCodeGenerator()
    private let generationQueue = DispatchQueue(label: "generationQueue", qos: .userInitiated)
    
    /* State variables */
    
    private(set) var dataPacketFrameIndex = 0
    private(set) var metadataPacketFrameIndex = 0
    
    /// For simplex mode only.
    private var metadataCodeImage: CIImage?
    
    /// For duplex mode only.
    private var replyAndNoReplyMetadataCodeImages = [CIImage]()
    private var readyMetadataCodeImage: CIImage?
    
    private var dataCodeImages = [CIImage]()
    
    /// Only used in duplex mode.
    private var metadataCodeDisplaySubscription: AnyCancellable?
    
    private var dataCodeDisplaySubscription: AnyCancellable?
    
    private func displayMetadataCodeImage() {
        
        switch self.sendMode {
        case .single, .nested:
            self.singleRenderView.image = self.metadataCodeImage
        case .alternatingSingle:
            self.topRenderView.image = self.metadataCodeImage
            self.bottomRenderView.image = self.metadataCodeImage
        }
    }
    
    private func startDisplayingDataCodeImages() {
        
        var codeImagesIterator = dataCodeImages.makeIterator()
        dataCodeDisplaySubscription = Timer.publish(every: 1.0 / sendFrameRate, on: .current, in: .common)
            .autoconnect()
            .sink { _ in
                
                let nextImage = codeImagesIterator.next()
                DispatchQueue.main.async {
                    
                    switch self.sendMode {
                        
                    case .single, .nested:
                        self.singleRenderView.image = nextImage
                        
                    case .alternatingSingle:
                        if self.dataPacketFrameIndex % 2 == 0 {
                            
                            self.topRenderView.image = nextImage
                            self.bottomRenderView.image = nil
                            
                        } else {
                            
                            self.bottomRenderView.image = nextImage
                            self.topRenderView.image = nil
                        }
                    }
                }
                
                self.dataPacketFrameIndex += 1
        }
    }
    
    private func stopDisplayingDataCodeImages() {
        
        guard let subscription = dataCodeDisplaySubscription else { return }
        subscription.cancel()
        dataCodeDisplaySubscription = nil
            
        dataPacketFrameIndex = 0
        
        clearPreviewViewImages()
    }
    
    private func startDisplayingMetadataCodeImages() {
        
        metadataCodeDisplaySubscription = Timer.publish(every: 1.0 / sendFrameRate, on: .current, in: .common)
            .autoconnect()
            .sink { _ in
                
                let index = self.metadataPacketFrameIndex
                let nextImage = self.replyAndNoReplyMetadataCodeImages[index]
                
                DispatchQueue.main.async {
                    switch self.sendMode {
                        
                    case .single, .nested:
                        self.singleRenderView.image = nextImage
                        
                    case .alternatingSingle:
                        self.topRenderView.image = nextImage
                        self.bottomRenderView.image = nextImage
                    }
                }
                
                self.metadataPacketFrameIndex = (self.metadataPacketFrameIndex + 1) % self.replyAndNoReplyMetadataCodeImages.count
        }
    }
    
    private func stopDisplayingMetadataCodeImages() {
        
        guard let subscription = metadataCodeDisplaySubscription else { return }
        subscription.cancel()
        metadataCodeDisplaySubscription = nil
        
        metadataPacketFrameIndex = 0
        
        clearPreviewViewImages()
    }
    
    private func generateCodeImagesAndDisplayMetadataCode(renderViewSideLength sideLength: CGFloat) {
        
        /// - TODO: select file from Files.app
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
        
        // Generate data codes
        var frameCount: Int
        switch sendMode {
        case .single, .alternatingSingle:
            dataCodeImages = codeGenerator.generateQRCodes(forData: messageData,
                                                           correctionLevel: .low,
                                                           sideLength: sideLength,
                                                           maxPacketSize: self.codeMaxPacketSize)
            frameCount = dataCodeImages.count
        case .nested:
            (dataCodeImages, frameCount) = codeGenerator
                .generateNestedQRCodes(forData: messageData,
                                       largerCodeMaxPacketSize: largerCodeMaxPacketSize,
                                       smallerCodeMaxPacketSize: smallerCodeMaxPacketSize,
                                       smallerCodeSideLengthRatio: smallerCodeSideLengthRatio,
                                       sideLength: sideLength)
        }
        
        // Generate metadata code
        let fileSize = messageData.count
        let fullFileName = fileName + "." + fileExtension
        
        if usesDuplexMode {
            
            let flags: [UInt32] = [
                MetadataPacket.Flag.noReply,
                MetadataPacket.Flag.noReply,
                MetadataPacket.Flag.reply
            ]
            var metadataPackets = [MetadataPacket]()
            for flag in flags {
                guard let metadataPacket = MetadataPacket(flagBits: flag,
                                                          numberOfFrames: UInt32(frameCount),
                                                          fileSize: UInt32(fileSize),
                                                          fileName: fullFileName)
                    else {
                        fatalError("[SendVC] Failed to create metadata packet.")
                }
                metadataPackets.append(metadataPacket)
            }
            replyAndNoReplyMetadataCodeImages = metadataPackets.map { packet in
                self.codeGenerator.generateQRCode(forMetadataPacket: packet,
                                                  sideLength: sideLength)
            }
            
            guard let readyMetadataPacket = MetadataPacket(flagBits: MetadataPacket.Flag.ready,
                                                      numberOfFrames: UInt32(frameCount),
                                                      fileSize: UInt32(fileSize),
                                                      fileName: fullFileName)
                else {
                    fatalError("[SendVC] Failed to create metadata packet.")
            }
            readyMetadataCodeImage = codeGenerator.generateQRCode(forMetadataPacket: readyMetadataPacket,
                                                                                     sideLength: sideLength)
            
        } else {
            
            guard let metadataPacket = MetadataPacket(flagBits: MetadataPacket.Flag.void,
                                                      numberOfFrames: UInt32(frameCount),
                                                      fileSize: UInt32(fileSize),
                                                      fileName: fullFileName)
                else {
                    fatalError("[SendVC] Failed to create metadata packet.")
            }
            metadataCodeImage = codeGenerator.generateQRCode(forMetadataPacket: metadataPacket,
                                                             sideLength: sideLength)
        }
        
        // Advance state
        proceedToNextStateAndUpdateUI()
    }
    
    private func clearPreviewViewImages() {
        
        DispatchQueue.main.async {
            self.singleRenderView.image = nil
            self.topRenderView.image = nil
            self.bottomRenderView.image = nil
        }
    }
}

