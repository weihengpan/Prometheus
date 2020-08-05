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
    
    enum ReceiveMode: String, CaseIterable {
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
        let index = mainStackView.arrangedSubviews.firstIndex(of: metadataLabel)!
        mainStackView.insertArrangedSubview(progressView, at: index)
        
        mainStackView.removeArrangedSubview(metadataLabel)
        metadataLabel.isHidden = true
        
    }
    
    private func showMetadataLabelAndHideProgressView() {
        
        metadataLabel.isHidden = false
        metadataLabel.text = ""
        let index = mainStackView.arrangedSubviews.firstIndex(of: progressView)!
        mainStackView.insertArrangedSubview(metadataLabel, at: index)
        
        mainStackView.removeArrangedSubview(progressView)
        progressView.isHidden = true
        
    }
    
    private func proceedToNextStateAndUpdateUI() {
        let startButtonTitles: [State : String] = [
            .waitingForMetadata : "Start",
            .metadataReceivedAndWaitingForStart : "Start",
            .receivingData : "Stop",
            .recordingVideo : "Finish Recording",
            .decodingRecordedVideo : "Done",
            .finishedDecoding : "Done"
        ]
        let startButtonEnabledStates: [State : Bool] = [
            .waitingForMetadata : false,
            .metadataReceivedAndWaitingForStart : true,
            .receivingData : true,
            .recordingVideo : true,
            .decodingRecordedVideo : false,
            .finishedDecoding : true
        ]
        
        // Update state variables
        if decodeMode == .liveDecode {
            
            switch state {
            case .receivingData:
                // Ending data transmission
                state = .waitingForMetadata
            case .metadataReceivedAndWaitingForStart:
                // Starting data transmission
                receivedDataPackets = []
                receivedFrameIndices = []
                state = .receivingData
            default:
                break
            }
            
        } else if decodeMode == .recordAndDecode {
            
            switch state {
            case .metadataReceivedAndWaitingForStart:
                startRecordingVideo()
                state = .recordingVideo
            case .recordingVideo:
                StopRecordingVideo()
                state = .decodingRecordedVideo
            default:
                break
            }
            
        }
        
        // Update UI
        startButton.setTitle(startButtonTitles[state], for: .normal)
        startButton.isEnabled = startButtonEnabledStates[state]!
        switch state {
        case .waitingForMetadata:
            showMetadataLabelAndHideProgressView()
        case .receivingData:
            showProgressViewAndHideMetadataLabel()
        case .decodingRecordedVideo:
            showProgressViewAndHideMetadataLabel()
        case .finishedDecoding:
            showMetadataLabelAndHideProgressView()
        default:
            break
        }
        
        // Stop session
        switch state {
        case .decodingRecordedVideo:
            self.sessionQueue.async {
                self.stopSession()
            }
        default:
            break
        }
    }
    
    // MARK: - View Controller Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
                
        self.title = "Receiving"
        
        // Assign preview layer references on the main thread
        widePreviewLayer = widePreviewView.previewLayer
        telephotoPreviewLayer = telephotoPreviewView.previewLayer
        
        sessionQueue.async {
            self.configureSessionDuringSetup()
        }
        
        // Disable timed auto-lock
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Configure preview views
        if receiveMode == .singleCamera {
            previewStackView.removeArrangedSubview(telephotoPreviewView)
            telephotoPreviewView.removeFromSuperview()
        }
        
        // Disable start button
        startButton.isEnabled = false
        
        // Hide progress view
        mainStackView.removeArrangedSubview(progressView)
        progressView.isHidden = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
                
        sessionQueue.async {
            self.startSession()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        sessionQueue.async {
            self.stopSession()
        }
    }
    
    private func startSession() {
        guard let session = self.session else { return }
        
        if case .success(_) = self.setupResult {
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
    
    private func stopSession() {
        guard let session = self.session else { return }
        session.stopRunning()
    }
    
    // MARK: - Realtime Video Processing
    
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
    
    var receiveMode: ReceiveMode = .dualCamera
    var decodeMode: DecodeMode = .liveDecode
    private var frameNumber = 0
    private var state: State = .waitingForMetadata
    private var totalCountOfFrames = 0
    private var receivedFrameIndices = Set<UInt32>()
    private var receivedDataPackets = [DataPacket]()
    
    internal func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        
        // Detect QR codes
        if let wideCameraVideoData = synchronizedDataCollection[dualCameraWideVideoDataOutput] as? AVCaptureSynchronizedSampleBufferData {
            let sampleBuffer = wideCameraVideoData.sampleBuffer
            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                detectCodes(imageBuffer: imageBuffer, debugCaption: "Wide")
            }
        } else {
            print("[Synchronizer] Warning: data from wide camera is dropped")
        }
        
        if let telephotoCameraVideoData = synchronizedDataCollection[dualCameraTelephotoVideoDataOutput] as? AVCaptureSynchronizedSampleBufferData {
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
        
        let attachments =  sampleBuffer.attachments.propagated.merging(sampleBuffer.attachments.nonPropagated, uniquingKeysWith: { (a, _) -> Any in
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
    
    // MARK: - Video Recording And Postprocessing
    
    private var movieFileURLs = [URL]()
    
    private func startRecordingVideo() {
        
        movieFileURLs = []
        
        for output in movieFileOutputs {
            let url = generateMovieFileURL()
            output.startRecording(to: url, recordingDelegate: self)
            movieFileURLs.append(url)
        }
    }
    
    private func StopRecordingVideo() {
        
        for output in movieFileOutputs {
            output.stopRecording()
        }
    }
    
    private func startDecodingRecordedVideo() {
        
        
        
    }
    
    // Video recording is finished
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
        // Update UI and state
        DispatchQueue.main.async {
            self.proceedToNextStateAndUpdateUI()
        }
                
        // Start decoding
        startDecodingRecordedVideo()
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
        
        if state == .waitingForMetadata {
            detectAndReceiveMetadataPackets(imageBuffer: imageBuffer)
        } else if state == .receivingData {
            detectAndReceiveDataPackets(imageBuffer: imageBuffer, caption: debugCaption)
        }
    }
    
    func detectAndReceiveMetadataPackets(imageBuffer: CVPixelBuffer) {
        let codes = detectQRCodes(imageBuffer: imageBuffer)
        for code in codes {
            guard let descriptor = code.symbolDescriptor else { continue }
            guard let data = descriptor.data else { continue }
            guard let packet = MetadataPacket(archive: data) else { continue }
            
            guard let fileName = String(bytes: packet.fileNameData, encoding: .utf8) else {
                print("[ReceiveVC] Failed to decode file name in metadata packet.")
                continue
            }
            
            totalCountOfFrames = Int(packet.numberOfFrames)
            print("[ReceiveVC] Metadata packet received. No. of frames: \(packet.numberOfFrames), file size: \(packet.fileSize), file name: \(fileName)")
            DispatchQueue.main.async {
                self.metadataLabel.text = "No. of frames: \(packet.numberOfFrames)\nFile size: \(packet.fileSize)\nFile name: \(fileName)"
            }
            
            // Update variables
            state = .metadataReceivedAndWaitingForStart
            DispatchQueue.main.async {
                self.startButton.isEnabled = true
            }
        }
    }
    
    func detectAndReceiveDataPackets(imageBuffer: CVPixelBuffer, caption: String) {
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
                        
            if receivedDataPackets.count == totalCountOfFrames {
                receivedDataPackets.sort(by: { $0.frameIndex < $1.frameIndex })
                let combinedData = receivedDataPackets.lazy.map { $0.payload }.reduce(Data(), +)
                print("[ReceiveVC] All frames received; \(combinedData.count) bytes of data.")
                let encoding = String.Encoding.utf8
                guard let messageString = String(data: combinedData, encoding: encoding) else {
                    print("[ReceiveVC] Failed to decode data into string with encoding \(encoding)")
                    return
                }
                /*print("------ BEGIN MESSAGE ------")
                print(messageString)
                print("------  END MESSAGE  ------")*/
                print("[ReceiveVC] Converted string length: \(messageString.count)")
            }
        }
    }
    
    func detectQRCodes(imageBuffer: CVPixelBuffer) -> [CIQRCodeFeature] {
        let image = CIImage(cvImageBuffer: imageBuffer)
        let codes = detector.features(in: image) as? [CIQRCodeFeature] ?? []
        return codes
    }

    // MARK: - Capture Session Management
    
    private enum SessionSetupResult {
        case success(ReceiveMode)
        case notAuthorized
        case configurationFailed
    }
    
    var videoFormat: AVCaptureDevice.Format?
    private let sessionQueue = DispatchQueue(label: "sessionQueue", qos: .userInitiated)
    private let dataOutputQueue = DispatchQueue(label: "dataOutputQueue")
    private let videoFileDecodingQueue = DispatchQueue(label: "videoFileDecodingQueue", qos: .userInitiated)
    private var session: AVCaptureSession!
    private var multiCamSession: AVCaptureMultiCamSession! {
        return session as? AVCaptureMultiCamSession
    }
    private var setupResult: SessionSetupResult = .success(.dualCamera)
    
    private(set) var dualCameraDeviceInput: AVCaptureDeviceInput!
    private(set) var wideCameraDeviceInput: AVCaptureDeviceInput!
    private let dualCameraWideVideoDataOutput = AVCaptureVideoDataOutput()
    private let dualCameraTelephotoVideoDataOutput = AVCaptureVideoDataOutput()
    private let wideCameraVideoDataOutput = AVCaptureVideoDataOutput()
    private let wideCameraMovieFileOutput = AVCaptureMovieFileOutput()
    private let telephotoCameraMovieFileOutput = AVCaptureMovieFileOutput()
    private var dataOutputSynchronizer: AVCaptureDataOutputSynchronizer!
    
    private var movieFileOutputs: [AVCaptureMovieFileOutput] {
        switch receiveMode {
        case .singleCamera:
            return [wideCameraMovieFileOutput]
        case .dualCamera:
            return [wideCameraMovieFileOutput, telephotoCameraMovieFileOutput]
        }
    }
    
    private func configureSessionDuringSetup() {
        guard case .success(_) = setupResult else { return }
        
        configureSession(forReceiveMode: receiveMode)
    }
    
    private func configureSession(forReceiveMode receiveMode: ReceiveMode) {
        
        // Clean up
        if session != nil {
            session.stopRunning()
            widePreviewLayer.session = nil
            telephotoPreviewLayer.session = nil
        }
        
        // Configure session
        switch receiveMode {
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
            
            // Add video data outputs
            guard session.canAddOutput(dualCameraWideVideoDataOutput) else {
                print("[Session Configuration] Could not add wide camera video data output.")
                setupResult = .configurationFailed
                return
            }
            guard session.canAddOutput(dualCameraTelephotoVideoDataOutput) else {
                print("[Session Configuration] Could not add telephoto camera video data output.")
                setupResult = .configurationFailed
                return
            }
            session.addOutputWithNoConnections(dualCameraWideVideoDataOutput)
            session.addOutputWithNoConnections(dualCameraTelephotoVideoDataOutput)
            dualCameraWideVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            dualCameraTelephotoVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            dualCameraWideVideoDataOutput.alwaysDiscardsLateVideoFrames = false
            dualCameraTelephotoVideoDataOutput.alwaysDiscardsLateVideoFrames = false
            
            // Add movie file outputs
            guard session.canAddOutput(wideCameraMovieFileOutput) else {
                print("[Session Configuration] Could not add wide camera movie file output.")
                setupResult = .configurationFailed
                return
            }
            session.addOutput(wideCameraMovieFileOutput)
            guard session.canAddOutput(telephotoCameraMovieFileOutput) else {
                print("[Session Configuration] Could not add telephoto camera movie file output.")
                setupResult = .configurationFailed
                return
            }
            session.addOutput(telephotoCameraMovieFileOutput)
            
            // Add video data connections
            let wideCameraVideoDataOutputConnection = AVCaptureConnection(inputPorts: [wideCameraVideoPort], output: dualCameraWideVideoDataOutput)
            let telephotoCameraVideoDataOutputConnection = AVCaptureConnection(inputPorts: [telephotoCameraVideoPort], output: dualCameraTelephotoVideoDataOutput)
            guard session.canAddConnection(wideCameraVideoDataOutputConnection) else {
                print("[Session Configuration] Could not add wide camera video connection.")
                setupResult = .configurationFailed
                return
            }
            guard session.canAddConnection(telephotoCameraVideoDataOutputConnection) else {
                print("[Session Configuration] Could not add telephoto camera video connection.")
                setupResult = .configurationFailed
                return
            }
            session.addConnection(wideCameraVideoDataOutputConnection)
            session.addConnection(telephotoCameraVideoDataOutputConnection)
            
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
            
            // Add data output synchronizer
            let dataOutputs = [dualCameraWideVideoDataOutput, dualCameraTelephotoVideoDataOutput]
            dataOutputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: dataOutputs)
            dataOutputSynchronizer.setDelegate(self, queue: dataOutputQueue)
            
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
            
            // Add outputs
            guard session.canAddOutput(wideCameraVideoDataOutput) else {
                print("[Session Configuration] Could not add wide camera video data output.")
                setupResult = .configurationFailed
                return
            }
            session.addOutput(wideCameraVideoDataOutput)
            guard session.canAddOutput(wideCameraMovieFileOutput) else {
                print("[Session Configuration] Could not add wide camera movie file output.")
                setupResult = .configurationFailed
                return
            }
            session.addOutput(wideCameraMovieFileOutput)
            wideCameraVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            wideCameraVideoDataOutput.alwaysDiscardsLateVideoFrames = false
            wideCameraVideoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
            
            setupResult = .success(.singleCamera)
            print("[Session Configuration] Single camera session configuration is successful.")
        }
        
    }
    
    // MARK: - Utilities
    
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
    
    private func generateMovieFileURL() -> URL {
        let fileName = NSUUID().uuidString as NSString
        let fileDirectory = NSTemporaryDirectory() as NSString
        let fileExtension = "mov"
        let filePath = fileDirectory.appendingPathComponent(fileName.appendingPathExtension(fileExtension)!)
        return URL(fileURLWithPath: filePath)
    }
}
