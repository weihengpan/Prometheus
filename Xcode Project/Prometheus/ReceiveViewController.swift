//
//  ReceiveViewController.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/7/7.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import UIKit
import AVFoundation

final class ReceiveViewController: UIViewController, AVCaptureDataOutputSynchronizerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
    
    enum CameraType: String, CaseIterable {
        case singleCamera
        case dualCamera
    }
    
    enum DecodeMode: String, CaseIterable {
        case liveDecode
        case recordAndDecode
    }
    
    // MARK: - IB Outlets, IB Actions and Related
    
    @IBOutlet weak var mainStackView: UIStackView!
    
    @IBOutlet weak var previewStackView: UIStackView!
    @IBOutlet weak var widePreviewView: PreviewView!
    @IBOutlet weak var telephotoPreviewView: PreviewView!
    
    @IBOutlet weak var metadataLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    
    @IBOutlet weak var startButton: UIButton!
    
    @IBAction func startButtonDidTouchUpInside(_ sender: UIButton) {
        proceedToNextStateAndUpdateUI()
    }
    
    private weak var widePreviewLayer: AVCaptureVideoPreviewLayer!
    private weak var telephotoPreviewLayer: AVCaptureVideoPreviewLayer!
    
    // MARK: - UI Management
    
    private func showProgressViewAndHideMetadataLabel() {
        
        progressView.isHidden = false
        progressView.progress = 0
        if let index = mainStackView.arrangedSubviews.firstIndex(of: metadataLabel) {
            mainStackView.insertArrangedSubview(progressView, at: index)
        } else {
            mainStackView.addArrangedSubview(progressView)
        }
        
        mainStackView.removeArrangedSubview(metadataLabel)
        metadataLabel.isHidden = true
        
    }
    
    private func showMetadataLabelAndHideProgressView() {
        
        metadataLabel.isHidden = false
        metadataLabel.text = ""
        if let index = mainStackView.arrangedSubviews.firstIndex(of: progressView) {
            mainStackView.insertArrangedSubview(metadataLabel, at: index)
        } else {
            mainStackView.addArrangedSubview(metadataLabel)
        }
        
        mainStackView.removeArrangedSubview(progressView)
        progressView.isHidden = true
        
    }
    
    private func hidePreviewStackView() {
        mainStackView.removeArrangedSubview(previewStackView)
        previewStackView.isHidden = true
    }
    
    // MARK: - State Management
    
    private enum State {
        case waitingForMetadata
        case calibrating
        case waitingForReceivingData
        case receivingData
        
        case waitingForRecordingVideo
        case recordingVideo
        case decodingRecordedVideo
        case finishedDecoding
    }
    
    private func proceedToNextStateAndUpdateUI(updateUIOnly: Bool = false) {
        
        // Update state variables
        if updateUIOnly == false {
            if decodeMode == .liveDecode {
                
                switch state {
                    
                case .waitingForMetadata:
                    if usesDuplexMode {
                        state = .calibrating
                    } else {
                        state = .waitingForReceivingData
                    }
                    
                case .calibrating:
                    state = .waitingForReceivingData
                    
                case .waitingForReceivingData:
                    state = .receivingData
                    
                case .receivingData:
                    latestInfoMetadataPacket = nil
                    receivedDataPackets = []
                    receivedFrameNumbers = []
                    state = .waitingForMetadata
                    
                default:
                    break
                }
                
            } else if decodeMode == .recordAndDecode {
                
                switch state {
                    
                case .waitingForRecordingVideo:
                    startVideoRecording()
                    state = .recordingVideo
                    
                case .recordingVideo:
                    stopVideoRecording()
                    state = .decodingRecordedVideo
                    
                case .decodingRecordedVideo:
                    state = .finishedDecoding
                    
                default:
                    break
                }
            }
            print("[State] State changed to: \(state)")
        }
        
        // Update UI
        DispatchQueue.main.async {
            
            var startButtonTitle: String
            var startButtonIsEnabled: Bool
            
            switch self.state {
            case .waitingForMetadata:
                startButtonTitle = "Start Receiving"
                startButtonIsEnabled = false
                self.showMetadataLabelAndHideProgressView()
                
            case .calibrating:
                startButtonTitle = "Start Receiving"
                startButtonIsEnabled = false
                
            case .waitingForReceivingData:
                startButtonTitle = "Start Receiving"
                startButtonIsEnabled = true
                
            case .receivingData:
                startButtonTitle = "Stop Receiving"
                startButtonIsEnabled = true
                self.showProgressViewAndHideMetadataLabel()
                
            case .waitingForRecordingVideo:
                startButtonTitle = "Start Recording"
                startButtonIsEnabled = true
                
            case .recordingVideo:
                startButtonTitle = "Finish Recording"
                startButtonIsEnabled = true
                
            case .decodingRecordedVideo:
                startButtonTitle = "Done"
                startButtonIsEnabled = false
                self.showProgressViewAndHideMetadataLabel()
                self.hidePreviewStackView()
                
            case .finishedDecoding:
                startButtonTitle = "Done"
                startButtonIsEnabled = true
                self.showMetadataLabelAndHideProgressView()
            }
            
            self.startButton.setTitle(startButtonTitle, for: .normal)
            self.startButton.isEnabled = startButtonIsEnabled
        }
        
        // Stop session
        if updateUIOnly == false {
            
            switch state {
                
            case .decodingRecordedVideo:
                stopSession()
                
            default:
                break
            }
        }
    }
    
    // MARK: - View Controller Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
                
        self.title = "Receiving"
        
        // Intialize state and start button
        switch decodeMode {
        case .liveDecode:
            state = .waitingForMetadata
        case .recordAndDecode:
            state = .waitingForRecordingVideo
        }
        proceedToNextStateAndUpdateUI(updateUIOnly: true)
        
        // Assign preview layer references on the main thread
        widePreviewLayer = widePreviewView.previewLayer
        telephotoPreviewLayer = telephotoPreviewView.previewLayer
        
        // Configure session
        sessionQueue.async {
            self.configureSessionDuringSetup()
            self.startSession()
        }
        
        // Disable timed auto-lock
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Configure preview views
        if cameraType == .singleCamera {
            previewStackView.removeArrangedSubview(telephotoPreviewView)
            telephotoPreviewView.removeFromSuperview()
        }
                
        // Hide progress view
        mainStackView.removeArrangedSubview(progressView)
        progressView.isHidden = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
                
        guard let session = self.session else { return }
        if session.isRunning == false {
            startSession()
        }
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        guard let session = self.session else { return }
        if session.isRunning {
            stopSession()
        }
    }
    
    // MARK: - Live Video Processing
    
    private let ciContext = CIContext(options: [.useSoftwareRenderer : false])
    
    private var _detector: CIDetector!
    private var detector: CIDetector {
        if _detector == nil {
            let options: [String : Any] = [CIDetectorAccuracy : CIDetectorAccuracyHigh,
                                           CIDetectorTracking : true,
                                           CIDetectorMaxFeatureCount : 2,
                                           CIDetectorMinFeatureSize : 0.5]
            _detector = CIDetector(ofType: CIDetectorTypeQRCode, context: ciContext, options: options)
        }
        return _detector
    }
    
    private var state: State = .waitingForMetadata

    var cameraType: CameraType = .singleCamera
    var decodeMode: DecodeMode = .liveDecode
    var usesDuplexMode: Bool = false

    private var frameNumber = 0
    private var latestInfoMetadataPacket: MetadataPacket!
    private var totalCountOfFrames = 0
    private var receivedFrameNumbers = Set<Int>()
    private var largestReceivedFrameNumber = -1
    private var receivedDataPackets = [DataPacket]()
    
    internal func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        
        // Detect QR codes
        if let wideCameraVideoData = synchronizedDataCollection[wideCameraVideoDataOutput] as? AVCaptureSynchronizedSampleBufferData {
            let sampleBuffer = wideCameraVideoData.sampleBuffer
            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                detectCodes(imageBuffer: imageBuffer, debugCaption: "Wide")
            }
        } else {
            print("[Synchronizer] Warning: data from wide camera is dropped")
        }
        
        if let telephotoCameraVideoData = synchronizedDataCollection[telephotoCameraVideoDataOutput] as? AVCaptureSynchronizedSampleBufferData {
            let sampleBuffer = telephotoCameraVideoData.sampleBuffer
            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                detectCodes(imageBuffer: imageBuffer, debugCaption: "Telephoto")
            }
        } else {
            print("[Synchronizer] Warning: data from telephoto camera is dropped")
        }
        
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            detectCodes(imageBuffer: imageBuffer, debugCaption: "Wide")
        }
        
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        let attachments = sampleBuffer.attachments.propagated.merging(sampleBuffer.attachments.nonPropagated, uniquingKeysWith: { (a, _) -> Any in
            return a
        })
        let reasonKey = kCMSampleBufferAttachmentKey_DroppedFrameReason as String
        guard let reasonAny = attachments[reasonKey] else { return }
        let reasonString = reasonAny as! CFString
        var reason: String
        switch reasonString {
        case kCMSampleBufferDroppedFrameReason_FrameWasLate:
            reason = "frame was late. Processing is taking too long."
        case kCMSampleBufferDroppedFrameReason_OutOfBuffers:
            reason = "out of buffer. The buffers are being held for too long."
        case kCMSampleBufferDroppedFrameReason_Discontinuity:
            reason = "discontinuity. The system was too busy."
        default:
            reason = "unknown reason."
        }
        
        print("[SampleBufferDelegate] Warning: frame loss, reason: \(reason)")
    }
    
    // MARK: - Video Recording
    
    private var movieFileURLs = [URL]()
    
    private func generateMovieFileURL() -> URL {
        let fileName = UUID().uuidString as NSString
        let fileExtension = "mov"
        let fileDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filePath = fileDirectory.appendingPathComponent(fileName.appendingPathExtension(fileExtension)!)
        return filePath
    }
    
    private func startVideoRecording() {
        
        print("[Video Recording] Video recording started.")
        
        switch cameraType {
        case .singleCamera:
            
            let wideCameraMovieURL = generateMovieFileURL()
            movieFileURLs = [wideCameraMovieURL]
            wideCameraMovieFileOutput.startRecording(to: wideCameraMovieURL, recordingDelegate: self)
            
        case .dualCamera:
            
            let wideCameraMovieURL = generateMovieFileURL()
            let telephotoCameraMovieURL = generateMovieFileURL()
            movieFileURLs = [wideCameraMovieURL, telephotoCameraMovieURL]
            wideCameraMovieFileOutput.startRecording(to: wideCameraMovieURL, recordingDelegate: self)
            telephotoCameraMovieFileOutput.startRecording(to: telephotoCameraMovieURL, recordingDelegate: self)
            
        }
        
    }
    
    private func stopVideoRecording() {
        
        print("[Video Recording] Video recording stopped.")
        
        switch cameraType {
        case .singleCamera:
            
            wideCameraMovieFileOutput.stopRecording()
            
        case .dualCamera:
            
            wideCameraMovieFileOutput.stopRecording()
            telephotoCameraMovieFileOutput.stopRecording()
            
        }
        
    }
    
    /// A Boolean preventing calling `startVideoFileDecoding()` twice.
    private var startedDecoding = false
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
                
        guard startedDecoding == false else { return }
        startedDecoding = true
        // Start decoding
        videoFileDecodingQueue.async {
            self.startVideoFileDecoding()
        }
    }
    
    // MARK: - Offline Video Processing
    
    private let videoFileDecodingQueue = DispatchQueue(label: "videoFileDecodingQueue", qos: .userInitiated)

    /// Starts decoding the captured video files.
    ///
    /// You must call this method on an appropriate `DispatchQueue`.
    private func startVideoFileDecoding() {
        
        print("[Video Decoding] Video file decoding started.")
        
        defer {
            // Delete files
            for url in movieFileURLs {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch let error {
                    print("[Video Decoding] Failed to delete file at url \(url.path), error: \(error)")
                }
            }
        }
        
        for (index, url) in movieFileURLs.enumerated() {
            
            // Create reader
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("[Video Decoding] Failed to read file because file does not exist at URL: \(url.path)")
                return
            }
            let asset = AVAsset(url: url)
            var reader: AVAssetReader
            do {
                reader = try AVAssetReader(asset: asset)
            } catch let error {
                print("[Video Decoding] Failed to instantiate AVAssetReader, error: \(error)")
                return
            }
            
            // Create output
            guard let videoTrack = asset.tracks(withMediaType: .video).first else {
                print("[Video Decoding] Video track is not found in asset.")
                return
            }
            let options = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: options)
            
            // Add output
            guard reader.canAdd(output) else {
                print("[Video Decoding] Cannot add AVAssetReaderTrackOutput to AVAssetReader.")
                return
            }
            reader.add(output)
            
            // Start reading & decoding video
            let totalNumberOfFrames = Float(videoTrack.nominalFrameRate) * Float(CMTimeGetSeconds(asset.duration))
            var frameCount: Float = 1
            reader.startReading()
            while reader.status == .reading {
                
                // Autoreleasepool is required for releasing CMSampleBuffer, otherwise there will be memory leaks
                var breakFlag = false
                autoreleasepool {
                    
                    if let sampleBuffer = output.copyNextSampleBuffer() {
                        guard let imageBuffer = sampleBuffer.imageBuffer else { return }
                        var image = CIImage(cvImageBuffer: imageBuffer) // remove this
                        let debugCaption = index == 0 ? "Wide" : "Telephoto"
                        detectCodes(imageBuffer: imageBuffer, debugCaption: debugCaption)
                        frameCount += 1
                        image = image.clampedToExtent() // remove this
                        
                        // Update progress view
                        let progress = frameCount / totalNumberOfFrames
                        DispatchQueue.main.async {
                            self.progressView.setProgress(progress, animated: false)
                        }
                        
                    } else {
                        breakFlag = true
                    }
                }
                if breakFlag { break }
            }
            
            // Check if there is any error after reading is finished
            guard reader.status != .failed else {
                print("[Video Decoding] AVAssetReader has failed to read, error: \(reader.error!)")
                return
            }
            
        }
        
        // Advance the state
        proceedToNextStateAndUpdateUI()
        
        print("[Video Decoding] Video file decoding finished.")
    }
    
    // MARK: - Code Detection
    
    func debugPrintQRCode(sampleBuffer: CMSampleBuffer, caption: String) {
        
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvImageBuffer: imageBuffer)
        let codes = detector.features(in: image) as? [CIQRCodeFeature] ?? []
        for code in codes {
            guard let messageString = code.messageString, let descriptor = code.symbolDescriptor else { continue }
            let version = descriptor.symbolVersion
            print("[ReceiveVC] \(caption): \(messageString.count) bytes received, version \(version)")
        }
    }
    
    func detectCodes(imageBuffer: CVImageBuffer, debugCaption: String) {
        
        switch state {
            
        case .waitingForMetadata, .calibrating:
            detectMetadataPackets(imageBuffer: imageBuffer)
            
        case .receivingData:
            detectDataPackets(imageBuffer: imageBuffer, debugCaption: debugCaption)
            
        case .decodingRecordedVideo:
            detectMetadataPackets(imageBuffer: imageBuffer)
            detectDataPackets(imageBuffer: imageBuffer, debugCaption: debugCaption)
            
        default:
            break
        }
    }
    
    /// A state variable controlling whether the calibration reply should be sent,
    /// used to prevent sending out two replies in a row.
    /// It is set to `false` each time the calibration reply is sent, and is set to
    /// `true` after a time interval of `waitingTime`.
    private var canSendCalibrationReply = true
    
    /// Minimum time between calibration replies.
    private let calibrationReplyWaitingTime: TimeInterval = 0.1
    
    func detectMetadataPackets(imageBuffer: CVPixelBuffer) {
        
        let codes = detectQRCodes(imageBuffer: imageBuffer)
        for code in codes {
            
            // Detect code
            guard let descriptor = code.symbolDescriptor else { continue }
            guard let data = descriptor.data else { continue }
            guard let packet = MetadataPacket(archive: data) else { continue }
            guard let fileName = packet.fileName else {
                print("[ReceiveVC] Warning: Failed to decode file name in metadata packet. Dropping metadata packet.")
                continue
            }
            
            // Process metadata packets based on their flags
            switch packet.flag {
                
            case MetadataPacket.Flag.info:
                guard state == .waitingForMetadata else { continue }
                
                latestInfoMetadataPacket = packet
                totalCountOfFrames = Int(packet.numberOfFrames)
                
                // Update metadata label
                DispatchQueue.main.async {
                    self.metadataLabel.text = "No. of frames: \(packet.numberOfFrames)\nFile size: \(packet.fileSize)\nFile name: \(fileName)"
                }
                
                // Update state
                proceedToNextStateAndUpdateUI()
                
            case MetadataPacket.Flag.request:
                guard usesDuplexMode && state == .calibrating && decodeMode == .liveDecode else { continue }
                
                // Reply with torch
                if canSendCalibrationReply {
                    sendTorchSignal()
                    canSendCalibrationReply = false
                    DispatchQueue.main.async {
                        Timer.scheduledTimer(withTimeInterval: self.calibrationReplyWaitingTime, repeats: false) { _ in
                            self.canSendCalibrationReply = true
                        }
                    }
                }
                
            case MetadataPacket.Flag.ready:
                guard usesDuplexMode && state == .calibrating && decodeMode == .liveDecode else { continue }
                
                proceedToNextStateAndUpdateUI()
                
            default:
                continue
            }
            
            print("[ReceiveVC] Metadata packet received. No. of frames: \(packet.numberOfFrames), file size: \(packet.fileSize), file name: \(fileName), flag: \(packet.flagString)")
        }
    }
    
    private var numberOfRetransmissionRequestsToSend = 0
    
    func detectDataPackets(imageBuffer: CVPixelBuffer, debugCaption: String) {
        
        guard state == .receivingData || state == .decodingRecordedVideo else { return }
        guard let metadataPacket = latestInfoMetadataPacket else {
            print("[ReceiveVC] Warning: \(#function) called before info metadata packet is received.")
            return
        }
        
        let codes = detectQRCodes(imageBuffer: imageBuffer)
        for code in codes {
            
            guard let descriptor = code.symbolDescriptor else { continue }
            guard let data = descriptor.data else { continue }
            guard let packet = DataPacket(archive: data) else { continue }
            let frameNumber = Int(packet.frameNumber)
            
            // Discard packet if it has already been received
            guard receivedFrameNumbers.contains(frameNumber) == false else { continue }
            
            // Add received data packet to storage
            receivedFrameNumbers.insert(frameNumber)
            receivedDataPackets.append(packet)
            let receivedDataPacketsCount = receivedDataPackets.count
            
            // Update progress view
            DispatchQueue.main.async {
                self.progressView.progress = Float(receivedDataPacketsCount) / Float(self.totalCountOfFrames)
            }
                        
            // Check if all packets have been received
            if receivedDataPackets.count == totalCountOfFrames {
                
                guard let fileName = metadataPacket.fileName else { return }
                
                receivedDataPackets.sort(by: { $0.frameNumber < $1.frameNumber })
                let combinedData = receivedDataPackets.lazy.map { $0.payload }.reduce(Data(), +)
                print("[ReceiveVC] File \"\(fileName)\" received; \(combinedData.count) bytes of data.")
                
                // Try to convert to string if the file extension is "txt"
                if fileName.getFileExtension() == "txt" {
                    let encoding = String.Encoding.utf8
                    guard let messageString = String(data: combinedData, encoding: encoding) else {
                        print("[ReceiveVC] Failed to decode data into string with encoding \(encoding)")
                        return
                    }

                    print("[ReceiveVC] String successfully decoded, length: \(messageString.count)")
                }
                
                // Save file on disk
                let url = generateReceivedFileURL(fileName: fileName)
                do {
                    try combinedData.write(to: url)
                } catch let error {
                    print("[ReceiveVC] Failed to save received file to disk, error: \(error)")
                }
                
                // Push UIActivityViewController, so that the user may share the file
                let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                activityViewController.completionWithItemsHandler = { (_, _, _, error) in
                    if let error = error {
                        print("[ReceiveVC] UIActivityViewController threw an error: \(error)")
                    }
                    
                    // Delete file
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch let error {
                        print("[ReceiveVC] Failed to delete received file, error: \(error)")
                    }
                }
                
                stopSession()
                
                DispatchQueue.main.async {
                    self.present(activityViewController, animated: true) {
                        self.startSession()
                        self.proceedToNextStateAndUpdateUI()
                    }
                }
                
                return
            }
            
            /// - TODO: Nested mode compatibility
            // Detect dropped frames and send retransmission requests
            if usesDuplexMode {
                
                if frameNumber - largestReceivedFrameNumber > 1 {
                    
                    let droppedFrameRange = (largestReceivedFrameNumber + 1)...(frameNumber - 1)
                    numberOfRetransmissionRequestsToSend = droppedFrameRange.count
                    print("[Retransmission] Frame(s) \(droppedFrameRange) dropped, sending retransmission request(s).")
                }
            }
            if numberOfRetransmissionRequestsToSend > 0 {
                sendTorchSignal()
                numberOfRetransmissionRequestsToSend -= 1
            }
            if frameNumber > largestReceivedFrameNumber {
                largestReceivedFrameNumber = frameNumber
            }
            
            print("[ReceiveVC] \(debugCaption): Frame \(frameNumber) (\(packet.payload.count) bytes) received, \(receivedDataPacketsCount) frames received in total")
        }
    }
    
    func detectQRCodes(imageBuffer: CVPixelBuffer) -> [CIQRCodeFeature] {
        
        let image = CIImage(cvImageBuffer: imageBuffer)
        let codes = detector.features(in: image) as? [CIQRCodeFeature] ?? []
        return codes
    }
    
    func generateReceivedFileURL(fileName: String) -> URL {
        
        let fileDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let filePath = fileDirectory.appendingPathComponent(fileName)
        return filePath
    }
    
    // MARK: - Torch
    
    private func sendTorchSignal() {
        turnOnTorch(for: 1 / TimeInterval(latestInfoMetadataPacket.frameRate))
    }
    
    private func turnOnTorch(for duration: TimeInterval) {
        
        DispatchQueue.main.async {
            self.toggleTorch()
            Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
                self.toggleTorch()
            }
        }
    }
    
    private func toggleTorch() {
        
        guard let camera = currentCamera else { return }
        guard camera.hasTorch, camera.isTorchAvailable else { return }
        
        let newTorchMode: AVCaptureDevice.TorchMode = (camera.torchMode == .on) ? .off : .on
        do {
            try camera.lockForConfiguration()
            camera.torchMode = newTorchMode
            camera.unlockForConfiguration()
        } catch let error {
            print("[Torch] Failed to lock camera while toggling torch, error: \(error)")
        }
    }

    // MARK: - Capture Session Management
    
    private enum SessionSetupResult {
        case success(CameraType)
        case notAuthorized
        case configurationFailed
    }
    
    var videoFormat: AVCaptureDevice.Format?
    var videoFrameRate: Double! {
        guard let format = videoFormat else { return nil }
        return format.videoSupportedFrameRateRanges[0].maxFrameRate
    }
    
    private let sessionQueue = DispatchQueue(label: "sessionQueue", qos: .userInitiated)
    private let dataOutputQueue = DispatchQueue(label: "dataOutputQueue")
    private var session: AVCaptureSession!
    private var multiCamSession: AVCaptureMultiCamSession! {
        return session as? AVCaptureMultiCamSession
    }
    private var setupResult: SessionSetupResult = .success(.dualCamera)
    
    private var currentCamera: AVCaptureDevice!
    private(set) var dualCameraDeviceInput: AVCaptureDeviceInput!
    private(set) var wideCameraDeviceInput: AVCaptureDeviceInput!
    private let wideCameraVideoDataOutput = AVCaptureVideoDataOutput()
    private let telephotoCameraVideoDataOutput = AVCaptureVideoDataOutput()
    private let wideCameraMovieFileOutput = AVCaptureMovieFileOutput()
    private let telephotoCameraMovieFileOutput = AVCaptureMovieFileOutput()
    private var dataOutputSynchronizer: AVCaptureDataOutputSynchronizer!
    
    private func configureSessionDuringSetup() {
        guard case .success(_) = setupResult else { return }
        
        configureSession(forCameraType: cameraType)
    }
    
    private func configureSession(forCameraType cameraType: CameraType) {
        
        // Clean up
        if session != nil {
            session.stopRunning()
            widePreviewLayer.session = nil
            telephotoPreviewLayer.session = nil
        }
        
        // Configure session
        switch cameraType {
        case .dualCamera:
            
            // Intitialize session
            session = AVCaptureMultiCamSession()
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            
            // Setup preview layers
            widePreviewLayer.setSessionWithNoConnection(session)
            telephotoPreviewLayer.setSessionWithNoConnection(session)
            
            // Find dual camera
            let dualCamera = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)!
            currentCamera = dualCamera
            
            // Add device input
            dualCameraDeviceInput = try? AVCaptureDeviceInput(device: dualCamera)
            guard let dualCameraDeviceInput = dualCameraDeviceInput, session.canAddInput(dualCameraDeviceInput) else {
                print("[Session Configuration] Could not add dual camera device input.")
                setupResult = .configurationFailed
                return
            }
            session.addInputWithNoConnections(dualCameraDeviceInput)
            
            // Configure camera
            if let videoFormat = videoFormat {
                setVideoFormat(of: dualCamera, to: videoFormat)
            }
            let frameDuration = dualCamera.activeFormat.videoSupportedFrameRateRanges[0].minFrameDuration
            lockVideoFrameDuration(of: dualCamera, to: frameDuration)
            
            // Find ports of the constituent devices of the device input
            guard let wideCameraVideoPort = dualCameraDeviceInput.ports(for: .video,
                                                                        sourceDeviceType: .builtInWideAngleCamera,
                                                                        sourceDevicePosition: dualCamera.position).first
                else {
                    print("[Session Configuration] Could not find wide camera video port.")
                    setupResult = .configurationFailed
                    return
            }
            guard let telephotoCameraVideoPort = dualCameraDeviceInput.ports(for: .video,
                                                                             sourceDeviceType: .builtInTelephotoCamera,
                                                                             sourceDevicePosition: dualCamera.position).first
                else {
                    print("[Session Configuration] Could not find telephoto camera video port.")
                    setupResult = .configurationFailed
                    return
            }
            
            // Add outputs and create connections
            switch decodeMode {
            case .liveDecode:
                
                // Add video data outputs
                guard session.canAddOutput(wideCameraVideoDataOutput) else {
                    print("[Session Configuration] Could not add wide camera video data output.")
                    setupResult = .configurationFailed
                    return
                }
                guard session.canAddOutput(telephotoCameraVideoDataOutput) else {
                    print("[Session Configuration] Could not add telephoto camera video data output.")
                    setupResult = .configurationFailed
                    return
                }
                session.addOutputWithNoConnections(wideCameraVideoDataOutput)
                session.addOutputWithNoConnections(telephotoCameraVideoDataOutput)
                wideCameraVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
                telephotoCameraVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
                wideCameraVideoDataOutput.alwaysDiscardsLateVideoFrames = false
                telephotoCameraVideoDataOutput.alwaysDiscardsLateVideoFrames = false
                
                // Add video data connections
                let wideCameraVideoDataOutputConnection = AVCaptureConnection(inputPorts: [wideCameraVideoPort], output: wideCameraVideoDataOutput)
                let telephotoCameraVideoDataOutputConnection = AVCaptureConnection(inputPorts: [telephotoCameraVideoPort], output: telephotoCameraVideoDataOutput)
                guard session.canAddConnection(wideCameraVideoDataOutputConnection) else {
                    print("[Session Configuration] Could not add wide camera video connection.")
                    setupResult = .configurationFailed
                    return
                }
                session.addConnection(wideCameraVideoDataOutputConnection)
                guard session.canAddConnection(telephotoCameraVideoDataOutputConnection) else {
                    print("[Session Configuration] Could not add telephoto camera video connection.")
                    setupResult = .configurationFailed
                    return
                }
                session.addConnection(telephotoCameraVideoDataOutputConnection)
                
                // Add data output synchronizer
                let dataOutputs = [wideCameraVideoDataOutput, telephotoCameraVideoDataOutput]
                dataOutputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: dataOutputs)
                dataOutputSynchronizer.setDelegate(self, queue: dataOutputQueue)
                
            case .recordAndDecode:
                
                // Add movie file outputs
                guard session.canAddOutput(wideCameraMovieFileOutput) else {
                    print("[Session Configuration] Could not add wide camera movie file output.")
                    setupResult = .configurationFailed
                    return
                }
                session.addOutputWithNoConnections(wideCameraMovieFileOutput)
                guard session.canAddOutput(telephotoCameraMovieFileOutput) else {
                    print("[Session Configuration] Could not add telephoto camera movie file output.")
                    setupResult = .configurationFailed
                    return
                }
                session.addOutputWithNoConnections(telephotoCameraMovieFileOutput)
                
                // Add movie file output connections
                let wideCameraMovieFileOutputConnection = AVCaptureConnection(inputPorts: [wideCameraVideoPort], output: wideCameraMovieFileOutput)
                let telephotoCameraMovieFileOutputConnection = AVCaptureConnection(inputPorts: [telephotoCameraVideoPort], output: telephotoCameraMovieFileOutput)
                guard session.canAddConnection(wideCameraMovieFileOutputConnection) else {
                    print("[Session Configuration] Could not add wide movie file output connection.")
                    setupResult = .configurationFailed
                    return
                }
                session.addConnection(wideCameraMovieFileOutputConnection)
                guard session.canAddConnection(telephotoCameraMovieFileOutputConnection) else {
                    print("[Session Configuration] Could not add telephoto movie file output connection.")
                    setupResult = .configurationFailed
                    return
                }
                session.addConnection(telephotoCameraMovieFileOutputConnection)
            }
            
            // Add video preview layer connections
            let widePreviewLayerConnection = AVCaptureConnection(inputPort: wideCameraVideoPort, videoPreviewLayer: widePreviewLayer)
            let telephotoPreviewLayerConnection = AVCaptureConnection(inputPort: telephotoCameraVideoPort, videoPreviewLayer: telephotoPreviewLayer)
            guard session.canAddConnection(widePreviewLayerConnection) else {
                print("[Session Configuration] Could not add wide camera preview layer connection.")
                setupResult = .configurationFailed
                return
            }
            guard session.canAddConnection(telephotoPreviewLayerConnection) else {
                print("[Session Configuration] Could not add telephoto camera preview layer connection.")
                setupResult = .configurationFailed
                return
            }
            session.addConnection(widePreviewLayerConnection)
            session.addConnection(telephotoPreviewLayerConnection)
            
            // Check system cost
            print("[Session Configuration] MultiCam system pressure cost: \(multiCamSession.systemPressureCost), hardware cost: \(multiCamSession.hardwareCost)")
            
            setupResult = .success(.dualCamera)
            print("[Session Configuration] Dual camera Session configuration is successful.")
            
        case .singleCamera:
                        
            // Initialize session
            session = AVCaptureSession()
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            session.sessionPreset = .inputPriority
            
            // Setup preview layers
            widePreviewLayer.session = session
            
            // Find wide camera
            let wideCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)!
            currentCamera = wideCamera
            
            // Add device input
            wideCameraDeviceInput = try? AVCaptureDeviceInput(device: wideCamera)
            guard let wideCameraDeviceInput = wideCameraDeviceInput, session.canAddInput(wideCameraDeviceInput) else {
                print("[Session Configuration] Could not add wide camera device input.")
                setupResult = .configurationFailed
                return
            }
            session.addInput(wideCameraDeviceInput)
            
            // Add output
            switch decodeMode {
            case .liveDecode:
                
                // Add video data output
                guard session.canAddOutput(wideCameraVideoDataOutput) else {
                    print("[Session Configuration] Could not add wide camera video data output.")
                    setupResult = .configurationFailed
                    return
                }
                session.addOutput(wideCameraVideoDataOutput)
                wideCameraVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
                wideCameraVideoDataOutput.alwaysDiscardsLateVideoFrames = false
                wideCameraVideoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
                
            case .recordAndDecode:
                
                // Add movie file output
                guard session.canAddOutput(wideCameraMovieFileOutput) else {
                    print("[Session Configuration] Could not add wide camera movie file output.")
                    setupResult = .configurationFailed
                    return
                }
                session.addOutput(wideCameraMovieFileOutput)
            }
            
            // Configure camera
            if let videoFormat = videoFormat {
                setVideoFormat(of: wideCamera, to: videoFormat)
            }
            let frameDuration = wideCamera.activeFormat.videoSupportedFrameRateRanges[0].minFrameDuration
            lockVideoFrameDuration(of: wideCamera, to: frameDuration)

            setupResult = .success(.singleCamera)
            print("[Session Configuration] Single camera session configuration is successful.")
        }
        
    }
    
    private func startSession() {
        guard let session = self.session, state != .decodingRecordedVideo, state != .finishedDecoding else { return }
        
        if case .success(_) = self.setupResult {
            sessionQueue.async {
                session.startRunning()
                
                // Print video spec
                for input in session.inputs {
                    guard let input = input as? AVCaptureDeviceInput else { continue }
                    let format = input.device.activeFormat
                    let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    let maxFrameRate = format.videoSupportedFrameRateRanges.first!.maxFrameRate
                    print("[Info] Video format: \(dimensions.width)x\(dimensions.height)@\(maxFrameRate)fps")
                }
            }
        }
    }
    
    private func stopSession() {
        guard let session = self.session else { return }
        sessionQueue.async {
            session.stopRunning()
        }
    }
    
    private func setVideoFormat(of device: AVCaptureDevice, to format: AVCaptureDevice.Format) {
        
        guard device.formats.contains(format) else {
            print("[ReceiveVC] Failed to set device format becuase the device does not support the format.")
            return
        }
        
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.unlockForConfiguration()
        } catch let error {
            print("[ReceiveVC] Could not lock device \(device.localizedName) for changing format, reason: \(error)")
        }
        
    }
    
    private func lockVideoFrameDuration(of camera: AVCaptureDevice, to duration: CMTime) {
        
        do {
            try camera.lockForConfiguration()
            
            // Disable video HDR
            if camera.activeFormat.isVideoHDRSupported {
                camera.automaticallyAdjustsVideoHDREnabled = false
                camera.isVideoHDREnabled = false
            }
            
            // Fix video frame rate
            camera.activeVideoMinFrameDuration = duration
            camera.activeVideoMaxFrameDuration = duration
            
            camera.unlockForConfiguration()
        } catch let error {
            print("[ReceiveVC] Failed to lock front camera for configuration, error: \(error)")
        }
        
    }
        
}
