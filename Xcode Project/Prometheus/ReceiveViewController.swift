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
    
    private enum State {
        case waitingForMetadata
        case metadataReceivedAndWaitingForStart
        case receivingData
        
        case waitingForRecordingVideo
        case recordingVideo
        case decodingRecordedVideo
        case finishedDecoding
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
    
    private func proceedToNextStateAndUpdateUI(updateUIOnly: Bool = false) {
        
        let startButtonTitles: [State : String] = [
            .waitingForMetadata : "Start Receiving",
            .metadataReceivedAndWaitingForStart : "Start Receiving",
            .receivingData : "Stop Receiving",
            .waitingForRecordingVideo : "Start Recording",
            .recordingVideo : "Finish Recording",
            .decodingRecordedVideo : "Done",
            .finishedDecoding : "Done"
        ]
        let startButtonEnabledStates: [State : Bool] = [
            .waitingForMetadata : false,
            .metadataReceivedAndWaitingForStart : true,
            .receivingData : true,
            .waitingForRecordingVideo : true,
            .recordingVideo : true,
            .decodingRecordedVideo : false,
            .finishedDecoding : true
        ]
        
        // Update state variables
        if updateUIOnly == false {
            if decodeMode == .liveDecode {
                
                switch state {
                case .waitingForMetadata:
                    state = .metadataReceivedAndWaitingForStart
                case .metadataReceivedAndWaitingForStart:
                    state = .receivingData
                case .receivingData:
                    receivedMetadataPacket = nil
                    receivedDataPackets = []
                    receivedFrameIndices = []
                    
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
        }
        
        // Update UI
        DispatchQueue.main.async {
            self.startButton.setTitle(startButtonTitles[self.state], for: .normal)
            self.startButton.isEnabled = startButtonEnabledStates[self.state]!
            switch self.state {
            case .waitingForMetadata:
                self.showMetadataLabelAndHideProgressView()
            case .receivingData:
                self.showProgressViewAndHideMetadataLabel()
            case .decodingRecordedVideo:
                self.showProgressViewAndHideMetadataLabel()
                self.hidePreviewStackView()
            case .finishedDecoding:
                self.showMetadataLabelAndHideProgressView()
            default:
                break
            }
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

    private var frameNumber = 0
    private var receivedMetadataPacket: MetadataPacket!
    private var totalCountOfFrames = 0
    private var receivedFrameIndices = Set<UInt32>()
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
        case .waitingForMetadata:
            detectAndReceiveMetadataPackets(imageBuffer: imageBuffer)
        case .receivingData:
            detectAndReceiveDataPackets(imageBuffer: imageBuffer, caption: debugCaption)
        case .decodingRecordedVideo:
            detectAndReceiveMetadataPackets(imageBuffer: imageBuffer)
            detectAndReceiveDataPackets(imageBuffer: imageBuffer, caption: debugCaption)
        default:
            break
        }
    }
    
    func detectAndReceiveMetadataPackets(imageBuffer: CVPixelBuffer) {
        let codes = detectQRCodes(imageBuffer: imageBuffer)
        for code in codes {
            guard let descriptor = code.symbolDescriptor else { continue }
            guard let data = descriptor.data else { continue }
            guard let packet = MetadataPacket(archive: data) else { continue }
            
            guard let fileName = packet.fileName else {
                print("[ReceiveVC] Warning: Failed to decode file name in metadata packet. Dropping metadata packet.")
                continue
            }
            receivedMetadataPacket = packet
            
            totalCountOfFrames = Int(packet.numberOfFrames)
            print("[ReceiveVC] Metadata packet received. No. of frames: \(packet.numberOfFrames), file size: \(packet.fileSize), file name: \(fileName)")
          
            // Update metadata label
            DispatchQueue.main.async {
                self.metadataLabel.text = "No. of frames: \(packet.numberOfFrames)\nFile size: \(packet.fileSize)\nFile name: \(fileName)"
            }
            
            // Update state
            if decodeMode == .liveDecode {
                proceedToNextStateAndUpdateUI()
            }
        }
    }
    
    func detectAndReceiveDataPackets(imageBuffer: CVPixelBuffer, caption: String) {
        guard let metadataPacket = receivedMetadataPacket else {
            print("[ReceiveVC] Warning: detectAndReceiveDataPackets(imageBuffer:caption:) called before metadata packet is received.")
            return
        }
        
        let codes = detectQRCodes(imageBuffer: imageBuffer)
        for code in codes {
            guard let descriptor = code.symbolDescriptor else { continue }
            guard let data = descriptor.data else { continue }
            guard let packet = DataPacket(archive: data) else { continue }
            let frameIndex = packet.frameIndex
            
            guard receivedFrameIndices.contains(frameIndex) == false else { continue }
            receivedFrameIndices.insert(frameIndex)
            receivedDataPackets.append(packet)
            let receivedDataPacketsCount = receivedDataPackets.count
            DispatchQueue.main.async {
                self.progressView.progress = Float(receivedDataPacketsCount) / Float(self.totalCountOfFrames)
            }
            print("[ReceiveVC] \(caption): Frame \(frameIndex) (\(packet.payload.count) bytes) received, \(receivedDataPacketsCount) frames received in total")
                        
            // Received all packets
            if receivedDataPackets.count == totalCountOfFrames {
                
                guard let fileName = metadataPacket.fileName else { return }
                
                receivedDataPackets.sort(by: { $0.frameIndex < $1.frameIndex })
                let combinedData = receivedDataPackets.lazy.map { $0.payload }.reduce(Data(), +)
                print("[ReceiveVC] File \(fileName) received; \(combinedData.count) bytes of data.")
                
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
            }
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

    // MARK: - Capture Session Management
    
    private enum SessionSetupResult {
        case success(CameraType)
        case notAuthorized
        case configurationFailed
    }
    
    var videoFormat: AVCaptureDevice.Format?
    private let sessionQueue = DispatchQueue(label: "sessionQueue", qos: .userInitiated)
    private let dataOutputQueue = DispatchQueue(label: "dataOutputQueue")
    private var session: AVCaptureSession!
    private var multiCamSession: AVCaptureMultiCamSession! {
        return session as? AVCaptureMultiCamSession
    }
    private var setupResult: SessionSetupResult = .success(.dualCamera)
    
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
            
            // Find dual camera and create device input
            let dualCamera = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)!
            dualCameraDeviceInput = try? AVCaptureDeviceInput(device: dualCamera)
            guard let dualCameraDeviceInput = dualCameraDeviceInput, session.canAddInput(dualCameraDeviceInput) else {
                print("[Session Configuration] Could not add dual camera device input.")
                setupResult = .configurationFailed
                return
            }
            if let videoFormat = videoFormat {
                setVideoFormat(of: dualCamera, to: videoFormat)
            }
            session.addInputWithNoConnections(dualCameraDeviceInput)
            
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
            
            // Add device input
            let wideCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)!
            wideCameraDeviceInput = try? AVCaptureDeviceInput(device: wideCamera)
            guard let wideCameraDeviceInput = wideCameraDeviceInput, session.canAddInput(wideCameraDeviceInput) else {
                print("[Session Configuration] Could not add wide camera device input.")
                setupResult = .configurationFailed
                return
            }
            if let videoFormat = videoFormat {
                setVideoFormat(of: wideCamera, to: videoFormat)
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
        
}
