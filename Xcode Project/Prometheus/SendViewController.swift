//
//  SendViewController.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/7/7.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import UIKit
import AVFoundation
import Combine

final class SendViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
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
    
    @IBOutlet weak var previewView: PreviewView!
    
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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        guard let session = session else { return }
        if usesDuplexMode && session.isRunning == false {
            startSession()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        guard let session = session else { return }
        if usesDuplexMode && session.isRunning {
            stopSession()
        }
    }
    
    override func viewDidLayoutSubviews() {
        
        // Wait until all leaf subviews have finished layout
        DispatchQueue.main.async {
            if self.hasGeneratedCodes == false {
                
                let scale = UIScreen.main.scale
                var sideLength: CGFloat
                switch self.sendMode {
                
                case .single, .nested:
                    sideLength = self.singleRenderView.frame.width * scale
                    
                case .alternatingSingle:
                    sideLength = self.topRenderView.frame.width * scale
                }
                
                self.sessionQueue.async {
                    self.generateCodeImages(renderViewSideLength: sideLength)
                    self.setupSession()
                    self.startSession()
                    self.lockCameraExposure(after: 0.5)
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
                clearRenderViewImages()
                
            case .waitingForManualStart:
                
                if usesDuplexMode == false {
                    displayStaticMetadataCodeImage()
                }
                
            case .calibrating:
                break
                
            case .calibrationFinishedAndWaitingForStart:
                metadataCodeDisplaySubscription = nil
                stopSession()
                displayStaticMetadataCodeImage()
                
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
            
            if self.state == .calibrationFinishedAndWaitingForStart {
                self.previewView.isHidden = true
            }
        }
        
    }

    // MARK: - Code Generation & Display
    
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
    
    /* State variables */
    
    private(set) var dataPacketFrameIndex = 0
    private(set) var metadataPacketFrameIndex = 0
    
    private var metadataCodeImage: CIImage?
    
    // Metadata code images used during calibration. For duplex mode only.
    private var requestMetadataCodeImage: CIImage!
    private var readyMetadataCodeImage: CIImage!
    
    private var dataCodeImages = [CIImage]()
    
    // For duplex mode only.
    private var metadataCodeDisplaySubscription: AnyCancellable?
    
    private var dataCodeDisplaySubscription: AnyCancellable?
    
    private func displayStaticMetadataCodeImage() {
        
        let image = usesDuplexMode ? readyMetadataCodeImage : metadataCodeImage
        
        DispatchQueue.main.async {
            switch self.sendMode {
                
            case .single, .nested:
                self.singleRenderView.image = image
                
            case .alternatingSingle:
                self.topRenderView.image = image
                self.bottomRenderView.image = image
            }
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
        
        clearRenderViewImages()
    }
    
    private func generateCodeImages(renderViewSideLength sideLength: CGFloat) {
        
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
                        
            // Generate request metadata packet
            guard let requestMetadataPacket = MetadataPacket(flagBits: MetadataPacket.Flag.reply,
                                                      numberOfFrames: UInt32(frameCount),
                                                      fileSize: UInt32(fileSize),
                                                      fileName: fullFileName)
                else {
                    fatalError("[SendVC] Failed to create metadata packet.")
            }
            requestMetadataCodeImage = codeGenerator.generateQRCode(forMetadataPacket: requestMetadataPacket, sideLength: sideLength)
            
            // Generate ready metadata packet
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
    
    private func clearRenderViewImages() {
                
        let clearImage: CIImage = .clear
        DispatchQueue.main.async {
            self.singleRenderView.image = clearImage
            self.topRenderView.image = clearImage
            self.bottomRenderView.image = clearImage
        }
    }
    
    // MARK: - Video Processing & Calibration
    
    private let dataOutputQueue = DispatchQueue(label: "dataOutputQueue")
    private let histogramFilter = HistogramFilter()
    
    /*
     
     State variables
     
     */
    
    /// Whether the reply to the calibration request has been received.
    ///
    /// When it is `true`, the sender will send out a new request during the next frame.
    private var hasReceivedReply = true
        
    /// The number of white pixels in the last frame.
    private var lastPixelCount: Int!
    
    /// Number of frames that has elapsed since the calibration request was sent.
    private var transmissionDelay = 0
    
    /// Samples of the difference in the number of white pixels in successive frames.
    ///
    /// Only samples of rising edges will be collected, so the elements are all positive.
    private var pixelCountDeltaSamples = [Int]()
    
    /// Samples of `transmissionDelay`.
    private var transmissionDelaySamples = [Int]()
    
    /// The minimum waiting time between the receipt of a reply and the next request.
    private let minimumTimeToWaitUntilNextRequest: TimeInterval = 0.3
    
    /// Whether enough time (equal to `minimumTimeToWaitUntilNextRequest`) has passed since the receipt of a reply.
    private var hasFinishedWaiting = true
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard state == .calibrating else { return }
        
        // Receive calibration reply
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }
        let inputImage = CIImage(cvImageBuffer: imageBuffer)
        let histogram = histogramFilter.calculateHistogram(of: inputImage)
        let currentPixelCount = Int(histogram.last!)
        
        if let lastPixelCount = lastPixelCount, hasReceivedReply == false {
            
            let pixelCountDelta = currentPixelCount - lastPixelCount
            let pixelCountRatioThreshold = 0.01 // empirical value
            let framePixelCount = pixelCount(of: frontCamera.activeFormat)
            
            // Detect whether the number of white pixels have suddenly increased i.e. the torch was turned on
            if Double(pixelCountDelta) >= Double(framePixelCount) * pixelCountRatioThreshold {
                
                hasReceivedReply = true
                pixelCountDeltaSamples.append(pixelCountDelta)
                transmissionDelaySamples.append(transmissionDelay)
                print("[Calibration] Reply received.")
                print("[Calibration] White pixel count delta: \(pixelCountDelta)")
                print("[Calibration] Transmission delay: \(transmissionDelay)")
                
                hasFinishedWaiting = false
                DispatchQueue.main.async {
                    Timer.scheduledTimer(withTimeInterval: self.minimumTimeToWaitUntilNextRequest, repeats: false) { _ in
                        self.hasFinishedWaiting = true
                    }
                }
            }
            
            // Finish the calibration if enough samples have been collected
            let numberOfSamplesNeeded = 10
            if pixelCountDeltaSamples.count >= numberOfSamplesNeeded {
                
                let pixelCountDeltaSamplesInDouble = pixelCountDeltaSamples.map { Double($0) }
                let pixelCountDeltaSamplesMean = pixelCountDeltaSamplesInDouble.average
                let pixelCountDeltaSamplesStandardDeviation = pixelCountDeltaSamplesInDouble.standardDeviation
                
                let transmissionDelaySamplesInDouble = transmissionDelaySamples.map { Double($0) }
                let transmissionDelaySamplesMean = transmissionDelaySamplesInDouble.average
                let transmissionDelaySamplesStandardDeviation = transmissionDelaySamplesInDouble.standardDeviation
                
                print("[Calibration] Enough samples have been collected.")
                
                print("[Calibration] Pixel count delta samples: \(pixelCountDeltaSamples)")
                print("[Calibration] Mean: \(pixelCountDeltaSamplesMean)")
                print("[Calibration] Standard deviation: \(pixelCountDeltaSamplesStandardDeviation)")
                
                print("[Calibration] Transmission delay samples: \(transmissionDelaySamples)")
                print("[Calibration] Mean: \(transmissionDelaySamplesMean)")
                print("[Calibration] Standard deviation: \(transmissionDelaySamplesStandardDeviation)")

                proceedToNextStateAndUpdateUI()
                return
            }
        }
        
        // Send calibration request
        if hasReceivedReply && hasFinishedWaiting {
            
            let image = requestMetadataCodeImage
            DispatchQueue.main.async {
                switch self.sendMode {
                    
                case .single, .nested:
                    self.singleRenderView.image = image
                    
                case .alternatingSingle:
                    self.topRenderView.image = image
                    self.bottomRenderView.image = image
                }
            }
            print("[Calibration] Request sent.")
            
            hasReceivedReply = false
            transmissionDelay = 0 // Note that this will become 1 at the end of the method
            
            DispatchQueue.main.async {
                Timer.scheduledTimer(withTimeInterval: 1 / self.sendFrameRate, repeats: false) { _ in
                    self.clearRenderViewImages()
                    print("images cleared in timer")
                }
            }
            
        }
        
        // Update state variables
        transmissionDelay += 1
        lastPixelCount = currentPixelCount
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard state == .calibrating else { return }
        
        print("[SendVC] Warning: frame dropped")
    }
    
    func pixelCount(of format: AVCaptureDevice.Format) -> Int {
        
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        return width * height
    }
    
    // MARK: - Session Management
    
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    
    private var session: AVCaptureSession!
    
    private var frontCamera: AVCaptureDevice!
    private let frontCameraVideoDataOutput = AVCaptureVideoDataOutput()
    
    private func setupSession() {
        
        session = AVCaptureSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720
        
        // Set up preview layer
        DispatchQueue.main.async {
            self.previewView.previewLayer.session = self.session
        }
        
        // Find front camera
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("[SendVC] Front camera not found.")
            return
        }
        self.frontCamera = frontCamera
        do {
            try frontCamera.lockForConfiguration()
            
            // Disable video HDR
            if frontCamera.activeFormat.isVideoHDRSupported {
                frontCamera.automaticallyAdjustsVideoHDREnabled = false
                frontCamera.isVideoHDREnabled = false
            }
            
            // Fix video frame rate
            let sendFrameDuration = CMTime(value: 1, timescale: Int32(sendFrameRate))
            frontCamera.activeVideoMinFrameDuration = sendFrameDuration
            frontCamera.activeVideoMaxFrameDuration = sendFrameDuration
                
            frontCamera.unlockForConfiguration()
        } catch let error {
            print("[SendVC] Failed to lock front camera for configuration, error: \(error)")
        }
        
        // Add input
        guard let frontCameraDeviceInput = try? AVCaptureDeviceInput(device: frontCamera) else {
            print("[SendVC] Failed to create device input.")
            return
        }
        guard session.canAddInput(frontCameraDeviceInput) else {
            print("[SendVC] Failed to add device input.")
            return
        }
        session.addInput(frontCameraDeviceInput)
        
        // Add output
        guard session.canAddOutput(frontCameraVideoDataOutput) else {
            print("[SendVC] Cannot add output.")
            return
        }
        session.addOutput(frontCameraVideoDataOutput)
        frontCameraVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        frontCameraVideoDataOutput.alwaysDiscardsLateVideoFrames = false
        frontCameraVideoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
    }
    
    private func startSession() {
        sessionQueue.async {
            self.session.startRunning()
            print("[SendVC] Session started, video format: \(self.frontCamera.activeFormat.description)")
        }
    }
    
    private func stopSession() {
        sessionQueue.async {
            self.session.stopRunning()
            print("[SendVC] Session stopped.")
        }
    }
    
    private func lockCameraExposure(after delay: TimeInterval) {
        sessionQueue.asyncAfter(deadline: .now() + delay) {
            do {
                try self.frontCamera.lockForConfiguration()
                self.frontCamera.exposureMode = .autoExpose
            } catch let error {
                print("[SendVC] Failed to lock front camera for configuration, error: \(error)")
            }
        }
    }
}

