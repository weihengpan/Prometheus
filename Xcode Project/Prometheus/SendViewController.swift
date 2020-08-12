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
                
                self.sessionQueue.async {
                    self.generateCodeImagesAndLoadTransmissionQueue()
                    
                    guard self.usesDuplexMode else { return }
                    self.setupSession()
                    self.startSession()
                    self.lockCameraExposure(after: 0.5)
                }
                self.hasGeneratedCodes = true
            }
        }
    }
    
    // MARK: - State Management
    
    private enum State {
        case generatingCodes
        case waitingForManualStart
        case calibrating
        case calibrationFinishedAndWaitingForStart
        case sending
        case finishedSending
    }
    
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
                
            case .finishedSending:
                state = .waitingForManualStart
            }
            print("[State] State changed to: \(state)")
        }
        
        // Update UI
        var startButtonTitle: String
        var startButtonIsEnabled: Bool
        
        switch state {
            
        case .generatingCodes:
            startButtonTitle = usesDuplexMode ? "Start Calibration" : "Start Sending"
            startButtonIsEnabled = false
            clearRenderViewImages()
            
        case .waitingForManualStart:
            startButtonTitle = usesDuplexMode ? "Start Calibration" : "Start Sending"
            startButtonIsEnabled = true
            displaySingleCodeImage(infoMetadataCodeImage)
            
        case .calibrating:
            startButtonTitle = "Start Sending"
            startButtonIsEnabled = false
            
        case .calibrationFinishedAndWaitingForStart:
            startButtonTitle = "Start Sending"
            startButtonIsEnabled = true
            displaySingleCodeImage(readyMetadataCodeImage)
            
        case .sending:
            startButtonTitle = "Stop Sending"
            startButtonIsEnabled = true
            if usesDuplexMode == false {
                startDisplayingDataCodeImages()
            }
            
        case .finishedSending:
            startButtonTitle = "Reset"
            startButtonIsEnabled = true
            resetStateVariablesForNewTransmission()
        }
        
        DispatchQueue.main.async {
            self.startButton.setTitle(startButtonTitle, for: .normal)
            self.startButton.isEnabled = startButtonIsEnabled
        }
        
    }
    
    /// Resets some state variables to their initial values, so that a new transmission may begin.
    ///
    /// You should only call this method when `state` transitions to `finishedSending`.
    private func resetStateVariablesForNewTransmission() {
        
        dataCodeDisplayTimerSubscription = nil
        
        hasReceivedReply = true
        lastPixelCount = nil
        roundTripTime = 0
        pixelCountDeltaSamples = []
        roundTripTimeSamples = []
        canSendCalibrationRequest = true
        
        calibratedPixelCountDeltaThreshold = nil
        calibratedRoundTripTimeMean = nil
        calibratedRoundTripTimeVariation = nil
        
        transmissionQueue.clear()
        retransmissionQueue.clear()
        transmissionHistory = []
        retransmissionRequestDetectedLastFrame = false
        retransmissionRequestsCount = 0
    }

    // MARK: - Code Generation & Display
    
    var sendMode: CodeType = .nested
    var usesDuplexMode: Bool = false
    var sendFrameRate = 15.0
    
    /// For single code modes only.
    var singleCodeVersion = 13
    var singleCodeErrorCorrectionLevel: QRCodeInformation.ErrorCorrectionLevel = .low
    var singleCodeMaxPacketSize: Int {
        return QRCodeInformation.dataCapacity(forVersion: singleCodeVersion,
                                              errorCorrectionLevel: singleCodeErrorCorrectionLevel)!
    }
    
    /// For nested code mode only.
    var largerCodeVersion = 18
    var largerCodeErrorCorrectionLevel: QRCodeInformation.ErrorCorrectionLevel = .quartile
    var largerCodeMaxPacketSize: Int {
        return QRCodeInformation.dataCapacity(forVersion: largerCodeVersion,
                                              errorCorrectionLevel: largerCodeErrorCorrectionLevel)!
    }
    var smallerCodeVersion = 13
    var smallerCodeErrorCorrectionLevel: QRCodeInformation.ErrorCorrectionLevel = .low
    var smallerCodeMaxPacketSize: Int {
        return QRCodeInformation.dataCapacity(forVersion: smallerCodeVersion,
                                              errorCorrectionLevel: smallerCodeErrorCorrectionLevel)!
    }
    
    var codesSideLengthRatio = 0.3
    
    private let codeGenerator = NestedQRCodeGenerator()
    
    /* State variables */
    
    private var infoMetadataCodeImage: CIImage!
    
    // Metadata code images used during calibration. For duplex mode only.
    private var requestMetadataCodeImage: CIImage!
    private var readyMetadataCodeImage: CIImage!
    
    /// The data packet images, arranged in increasing order of their frame numbers.
    ///
    /// Once set, this variable should not be mutated in a transmission.
    private var dataPacketImages = [DataPacketImage]()
    
    private var dataCodeDisplayTimerSubscription: AnyCancellable?
    
    
    private func displaySingleCodeImage(_ image: CIImage) {
                
        DispatchQueue.main.async {
            switch self.sendMode {
                
            case .single, .nested:
                self.singleRenderView.setImage(image)
                
            case .alternatingSingle:
                self.topRenderView.setImage(image)
                self.bottomRenderView.setImage(image)
            }
        }
    }
    
    /// Start displaying data code images with a timer subscription.
    ///
    /// Only call this method in simplex mode.
    private func startDisplayingDataCodeImages() {
        
        dataCodeDisplayTimerSubscription = Timer.publish(every: 1 / sendFrameRate, on: .current, in: .common)
            .autoconnect()
            .sink { [unowned self] _ in
                self.displayNextDataCodeImage()
        }
    }
    
    /// Stops displaying data code images.
    ///
    /// You should only call this method in simplex mode.
    private func stopDisplayingDataCodeImages() {
        
        guard let subscription = dataCodeDisplayTimerSubscription else { return }
        subscription.cancel()
        dataCodeDisplayTimerSubscription = nil
        
        transmissionQueue.clear()
        
        clearRenderViewImages()
    }
    
    /// Displays the next data code image.
    ///
    /// This method should be invoked in:
    ///     1. `dataCodeDisplayTimerSubscription`'s block (simplex mode), or
    ///     2. `captureOutput(_:didOutput:from:)` (duplex mode)
    private func displayNextDataCodeImage() {
        
        // Fetch next image, preferring retransmission queue
        var nextPacketImage: DataPacketImage
        if let image = self.retransmissionQueue.dequeue() {
            nextPacketImage = image
        } else {
            guard let image = self.transmissionQueue.dequeue() else { return }
            nextPacketImage = image
        }
        
        // Display image
        DispatchQueue.main.async {
            
            switch self.sendMode {
                
            case .single:
                self.singleRenderView.setImage(nextPacketImage.image)
                
            case .alternatingSingle:
                if nextPacketImage.frameNumber % 2 == 0 {
                    
                    self.topRenderView.setImage(nextPacketImage.image)
                    self.bottomRenderView.setImage(nil)
                    
                } else {
                    
                    self.bottomRenderView.setImage(nextPacketImage.image)
                    self.topRenderView.setImage(nil)
                }
                
            case .nested:
                let largerCodeImage = nextPacketImage.image
                let smallerCodeImage = self.transmissionQueue.dequeue()?.image ?? .empty()
                self.singleRenderView.setNestedImages(larger: largerCodeImage, smaller: smallerCodeImage, sizeRatio: CGFloat(self.codesSideLengthRatio))
            }
        }
        
        // Add image to transmission history
        self.transmissionHistory.append(nextPacketImage)
    }
    
    private func generateCodeImagesAndLoadTransmissionQueue() {
        
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
        switch sendMode {
            
        case .single, .alternatingSingle:
            dataPacketImages = codeGenerator
                .generateDataPacketImages(for: messageData,
                                          correctionLevel: singleCodeErrorCorrectionLevel,
                                          maxPacketSize: singleCodeMaxPacketSize)
            
        case .nested:
            dataPacketImages = codeGenerator
                .generateDataPacketImagesForNestedDisplay(for: messageData,
                                                          largerCodeCorrectionLevel: largerCodeErrorCorrectionLevel,
                                                          largerCodeMaxPacketSize: largerCodeMaxPacketSize,
                                                          smallerCodeCorrectionLevel: smallerCodeErrorCorrectionLevel,
                                                          smallerCodeMaxPacketSize: smallerCodeMaxPacketSize)
        }
        let frameCount = dataPacketImages.count
        
        // Load transmission queue
        transmissionQueue = Queue(dataPacketImages)
        
        // Generate metadata code images
        let fileSize = messageData.count
        let fileNameWithExtension = fileName + "." + fileExtension
        
        // Generate info metadata packet code image
        guard let metadataPacket = MetadataPacket(flag: MetadataPacket.Flag.info,
                                                  numberOfFrames: UInt32(frameCount),
                                                  frameRate: UInt32(sendFrameRate),
                                                  fileSize: UInt32(fileSize),
                                                  fileName: fileNameWithExtension)
            else {
                fatalError("[SendVC] Failed to create info metadata packet.")
        }
        infoMetadataCodeImage = codeGenerator.generateMetadataCode(for: metadataPacket)
        
        if usesDuplexMode {
                        
            // Generate request metadata packet code image
            guard let requestMetadataPacket = MetadataPacket(flag: MetadataPacket.Flag.request,
                                                             numberOfFrames: UInt32(frameCount),
                                                             frameRate: UInt32(sendFrameRate),
                                                             fileSize: UInt32(fileSize),
                                                             fileName: fileNameWithExtension)
                else {
                    fatalError("[SendVC] Failed to create request metadata packet.")
            }
            requestMetadataCodeImage = codeGenerator.generateMetadataCode(for: requestMetadataPacket)
            
            // Generate ready metadata packet code image
            guard let readyMetadataPacket = MetadataPacket(flag: MetadataPacket.Flag.ready,
                                                           numberOfFrames: UInt32(frameCount),
                                                           frameRate: UInt32(sendFrameRate),
                                                           fileSize: UInt32(fileSize),
                                                           fileName: fileNameWithExtension)
                else {
                    fatalError("[SendVC] Failed to create ready metadata packet.")
            }
            readyMetadataCodeImage = codeGenerator.generateMetadataCode(for: readyMetadataPacket)
            
        }
        
        // Update state
        if state == .generatingCodes {
            proceedToNextStateAndUpdateUI()
        }
    }
    
    private func clearRenderViewImages() {
       
        let clearImage: CIImage = .clear
        DispatchQueue.main.async {
            self.singleRenderView.setImage(clearImage)
            self.topRenderView.setImage(clearImage)
            self.bottomRenderView.setImage(clearImage)
        }
    }
    
    // MARK: - Video Processing, Calibration & Retransmission
    
    private let dataOutputQueue = DispatchQueue(label: "dataOutputQueue")
    private let histogramFilter = HistogramFilter()
    
    /*
     
     Calibration State Variables
     
     */
    
    /// Whether the reply to the calibration request has been received.
    ///
    /// When it is `true`, the sender will send out a new request during the next frame.
    private var hasReceivedReply = true
        
    /// The number of white pixels in the last frame.
    ///
    /// This variable is reused during sending.
    private var lastPixelCount: Int!
    
    /// Number of frames that has elapsed since the calibration request was sent.
    private var roundTripTime = 0
    
    /// Samples of the difference in the number of white pixels in successive frames.
    ///
    /// Only samples of rising edges will be collected, so the elements are all positive.
    private var pixelCountDeltaSamples = [Int]()
    
    /// Samples of `roundTripTime`.
    private var roundTripTimeSamples = [Int]()
    
    /// The minimum waiting time between the receipt of a reply and the next request.
    private let minimumTimeToWaitUntilNextRequest: TimeInterval = 0.15
    
    /// Whether enough time (equal to `minimumTimeToWaitUntilNextRequest`) has passed since the receipt of a reply.
    private var canSendCalibrationRequest = true
    
    /*
     
     Calibrated Parameters
     
     These variables are used during sending and determined by calibration.
     
     */
    
    /// Estimated threshold of the number of white pixels in a frame for it to be recognized as a reply.
    private var calibratedPixelCountDeltaThreshold: Int!
    
    /// The calibrated mean round trip time from a request to its reply, measured in numbers of frames.
    /// It is used to estimate which frame was lost by subtracting this value from the current frame
    /// number when a retransmission request is received.
    private var calibratedRoundTripTimeMean: Int!
    
    /// The calibrated variation of the round trip time away from its mean.
    /// This value is guaranteed to be at least 1.
    /// During retransmission, frames whose numbers are in the range `[FN-V, FN+V]` will be retransmitted,
    /// where `FN` is the estimated number of the lost frame, and `V` is the value of this variable.
    private var calibratedRoundTripTimeVariation: Int!
    
    /*
     
     Retransmission State Variables
     
     */
    
    /// A queue used to hold data packet code images to be transmitted.
    ///
    /// It is only dequeued if `retransmissionQueue` is empty.
    private var transmissionQueue = Queue<DataPacketImage>()
    
    /// A queue for holding packet images to be retransmitted.
    private var retransmissionQueue = Queue<DataPacketImage>()
    
    /// An array containing data packet images that has been transmitted, including retransmitted ones.
    /// It is used for querying transmission history for retransmission.
    ///
    /// The latest image is at the end of the array.
    private var transmissionHistory = [DataPacketImage]()
    
    /// Whether a retransmission request was detected in the last video frame.
    private var retransmissionRequestDetectedLastFrame = false
    
    /// The total number of retransmission requests received in a row.
    private var retransmissionRequestsCount = 0
    
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard usesDuplexMode else { return }
                
        switch state {
            
        /* Calibration */
            
        case .calibrating:
            
            // Calculate histogram
            guard let imageBuffer = sampleBuffer.imageBuffer else { return }
            let inputImage = CIImage(cvImageBuffer: imageBuffer)
            let histogram = histogramFilter.calculateHistogram(of: inputImage)
            let currentPixelCount = Int(histogram.last!)
            
            // Detect calibration reply
            if let lastPixelCount = lastPixelCount, hasReceivedReply == false {
                
                let pixelCountDelta = currentPixelCount - lastPixelCount
                let pixelCountRatioThreshold = 0.01 // empirical value
                let framePixelCount = pixelCount(of: frontCamera.activeFormat)
                
                // Detect whether the number of white pixels have suddenly increased i.e. the torch was turned on
                let fixedPixelCountDeltaThreshold = Double(framePixelCount) * pixelCountRatioThreshold
                if Double(pixelCountDelta) >= fixedPixelCountDeltaThreshold {
                    
                    hasReceivedReply = true
                    pixelCountDeltaSamples.append(pixelCountDelta)
                    roundTripTimeSamples.append(roundTripTime)
                    print("[Calibration] Reply received.")
                    print("[Calibration] White pixel count delta: \(pixelCountDelta)")
                    print("[Calibration] Round trip time: \(roundTripTime)")
                    
                    canSendCalibrationRequest = false
                    DispatchQueue.main.async {
                        Timer.scheduledTimer(withTimeInterval: self.minimumTimeToWaitUntilNextRequest, repeats: false) { _ in
                            self.canSendCalibrationRequest = true
                        }
                    }
                }
                
                // Finish the calibration if enough samples have been collected
                let numberOfSamplesNeeded = 10
                if pixelCountDeltaSamples.count >= numberOfSamplesNeeded {
                    
                    // Calculate statistics
                    let pixelCountDeltaSamplesInDouble = pixelCountDeltaSamples.map { Double($0) }
                    let pixelCountDeltaSamplesMean = pixelCountDeltaSamplesInDouble.average
                    let pixelCountDeltaSamplesStandardDeviation = pixelCountDeltaSamplesInDouble.standardDeviation
                    
                    let roundTripTimeSamplesInDouble = roundTripTimeSamples.map { Double($0) }
                    let roundTripTimeSamplesMean = roundTripTimeSamplesInDouble.average
                    let roundTripTimeSamplesStandardDeviation = roundTripTimeSamplesInDouble.standardDeviation
                    
                    // Update calibrated parameters
                    let estimatedPixelCountDeltaThreshold = pixelCountDeltaSamplesMean - 2 * pixelCountDeltaSamplesStandardDeviation
                    calibratedPixelCountDeltaThreshold = Int(max(estimatedPixelCountDeltaThreshold, fixedPixelCountDeltaThreshold).rounded())
                    
                    calibratedRoundTripTimeMean = Int(roundTripTimeSamplesMean.rounded())
                    calibratedRoundTripTimeVariation = Int((2 * roundTripTimeSamplesStandardDeviation).rounded(.up))
                    calibratedRoundTripTimeVariation = max(calibratedRoundTripTimeVariation, 1)
                    
                    // Print
                    print("[Calibration] Enough samples have been collected.")
                    
                    print("[Calibration] Pixel count delta samples: \(pixelCountDeltaSamples)")
                    print("[Calibration] Mean: \(pixelCountDeltaSamplesMean)")
                    print("[Calibration] Standard deviation: \(pixelCountDeltaSamplesStandardDeviation)")
                    
                    print("[Calibration] Round trip time samples: \(roundTripTimeSamples)")
                    print("[Calibration] Mean: \(roundTripTimeSamplesMean)")
                    print("[Calibration] Standard deviation: \(roundTripTimeSamplesStandardDeviation)")

                    proceedToNextStateAndUpdateUI()
                    return
                }
            }
            
            // Send calibration request
            if hasReceivedReply && canSendCalibrationRequest {
                
                let image = requestMetadataCodeImage
                DispatchQueue.main.async {
                    switch self.sendMode {
                        
                    case .single, .nested:
                        self.singleRenderView.setImage(image)
                        
                    case .alternatingSingle:
                        self.topRenderView.setImage(image)
                        self.bottomRenderView.setImage(image)
                    }
                }
                print("[Calibration] Request sent.")
                
                hasReceivedReply = false
                roundTripTime = 0 // Note that this will become 1 at the end of the method
                
                DispatchQueue.main.async {
                    Timer.scheduledTimer(withTimeInterval: 1 / self.sendFrameRate, repeats: false) { _ in
                        self.clearRenderViewImages()
                    }
                }
                
            }
            
            // Update state variables
            roundTripTime += 1
            lastPixelCount = currentPixelCount
            
            
        /* Retransmission */
            
            
        case .sending:
           
            // Detect retransmission request
            guard let imageBuffer = sampleBuffer.imageBuffer else { return }
            let inputImage = CIImage(cvImageBuffer: imageBuffer)
            let histogram = histogramFilter.calculateHistogram(of: inputImage)
            let currentPixelCount = Int(histogram.last!)
            let transmissionRequestDetected = currentPixelCount - lastPixelCount >= calibratedPixelCountDeltaThreshold
            if transmissionRequestDetected {
                retransmissionRequestsCount += 1
                print("[Retransmission] Retransmission request received. Current count: \(retransmissionRequestsCount)")
            }

            // Retransmit if necessary
            if retransmissionRequestDetectedLastFrame && transmissionRequestDetected == false && retransmissionRequestsCount > 0 {
                
                let lastIndex = transmissionHistory.count - 1
                let packetCount = 2 * calibratedRoundTripTimeVariation + retransmissionRequestsCount
                var rightEnd = lastIndex - calibratedRoundTripTimeMean - (retransmissionRequestsCount - 1) + calibratedRoundTripTimeVariation
                var leftEnd = rightEnd - (packetCount - 1)
                rightEnd = min(rightEnd, lastIndex)
                leftEnd = max(leftEnd, 0)
                let packets = transmissionHistory[leftEnd...rightEnd]
                
                retransmissionQueue.enqueue(contentsOf: packets)
                print("[Retransmission] Retransmission scheduled in queue, packet numbers: \(packets.map { $0.frameNumber })")
                
                retransmissionRequestsCount = 0
            }
            
            
            // Update retransmission state variables
            if transmissionRequestDetected {
                retransmissionRequestDetectedLastFrame = true
            } else {
                retransmissionRequestDetectedLastFrame = false
            }

            // Display next image
            displayNextDataCodeImage()
            
        default:
            return
        }
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
        
        // Configure camera
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
        
        // Update state
        if state == .generatingCodes {
            proceedToNextStateAndUpdateUI()
        }
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
