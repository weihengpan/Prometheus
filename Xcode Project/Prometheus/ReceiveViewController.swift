//
//  ReceiveViewController.swift
//  Prometheus
//
//  Created by 潘维恒 on 2020/7/7.
//  Copyright © 2020 PAN Weiheng. All rights reserved.
//

import UIKit
import AVFoundation

final class ReceiveViewController: UIViewController, AVCaptureDataOutputSynchronizerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
    
    enum ReceiveMode {
        case singleCamera
        case dualCamera
    }
    
    enum DecodeMode {
        case liveDecode
        case recordAndDecode
    }
    
    // MARK: - IB Outlets, IB Actions and Related
    
    @IBOutlet weak var widePreviewView: PreviewView!
    @IBOutlet weak var telephotoPreviewView: PreviewView!
    @IBOutlet weak var previewStackView: UIStackView!
    @IBOutlet weak var startButton: UIButton!
    
    @IBAction func startButtonDidTouchUpInside(_ sender: UIButton) {
        
        if decodeMode == .liveDecode {
            
            if startButton.currentTitle ?? "" == "Stop" {
                
                // Ending data transmission
                isReceivingMetadata = true
                isReceivingData = false
                
            } else {
                
                // Starting data transmission
                receivedDataPackets = []
                receivedFrameIndices = []
                isReceivingMetadata = false
                isReceivingData = true
            }
            
        } else if decodeMode == .recordAndDecode {
            
            if movieFileOutput.isRecording == true {
                
                // Start recording
                
                
                let url = generateMovieFileURL()
                movieFileOutput.startRecording(to: url, recordingDelegate: self)
                
                movieFileURLs = []
                movieFileURLs.append(url)
                
            } else {
            
                // Stop recording
                movieFileOutput.stopRecording()
                
            }
        }
        
        // Update UI
        if startButton.currentTitle ?? "" == "Stop" {
            
            startButton.setTitle("Start", for: .normal)
            startButton.isEnabled = false
            
        } else {
            
            startButton.setTitle("Stop", for: .normal)

        }
    }
    
    @IBOutlet weak var receiveModeSegmentedControl: UISegmentedControl!
    @IBAction func receiveModeSegmentedControlIndexChanged(_ sender: UISegmentedControl) {
        
        switch sender.selectedSegmentIndex {
        case 0:
            receiveMode = .singleCamera
        case 1:
            receiveMode = .dualCamera
        default:
            break
        }
        
    }
    
    @IBOutlet weak var decodeModeSegmentedControl: UISegmentedControl!
    @IBAction func decodeModeSegmentedControlIndexChanged(_ sender: UISegmentedControl) {
        
        switch sender.selectedSegmentIndex {
        case 0:
            decodeMode = .liveDecode
        case 1:
            decodeMode = .recordAndDecode
        default:
            break
        }
    }
    
    private weak var widePreviewLayer: AVCaptureVideoPreviewLayer!
    private weak var telephotoPreviewLayer: AVCaptureVideoPreviewLayer!
    
    // MARK: - View Controller Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Assign preview layer references on the main thread
        widePreviewLayer = widePreviewView.previewLayer
        telephotoPreviewLayer = telephotoPreviewView.previewLayer
        
        sessionQueue.async {
            self.configureSessionDuringSetup()
        }
        
        // Disable timed auto-lock
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Disable start button
        startButton.isEnabled = false
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
    
    // MARK: - Video Processing
    
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
    
    private var receiveMode: ReceiveMode = .dualCamera {
        didSet {
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.5) {
                    switch self.receiveMode {
                    case .singleCamera:
                        self.previewStackView.removeArrangedSubview(self.telephotoPreviewView)
                    case .dualCamera:
                        self.previewStackView.addArrangedSubview(self.telephotoPreviewView)
                    }
                    // Animate layout change
                    self.view.layoutIfNeeded()
                }
            }
            
            sessionQueue.async {
                self.configureSession(forReceiveMode: self.receiveMode)
                self.startSession()
            }
        }
    }
    private var decodeMode: DecodeMode = .liveDecode
    private var frameNumber = 1
    private var isReceivingData = false
    private var isReceivingMetadata = true
    private var totalCountOfFrames = 0
    private var receivedFrameIndices = Set<UInt32>()
    private var receivedDataPackets = [DataPacket]()
    private var movieFileURLs = [URL]()
    
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
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
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
        
        /*let copiedImageBuffer = imageBuffer.copy()
        if isReceivingMetadata {
            detectAndReceiveMetadataPackets(imageBuffer: copiedImageBuffer)
        } else if isReceivingData {
            detectAndReceiveDataPackets(imageBuffer: copiedImageBuffer, caption: debugCaption)
        }*/
        
        if isReceivingMetadata {
            detectAndReceiveMetadataPackets(imageBuffer: imageBuffer)
        } else if isReceivingData {
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
            
            // Update variables
            isReceivingMetadata = false
            isReceivingData = false
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
            print("[ReceiveVC] \(caption): Frame \(frameIndex) (\(packet.payload.count) bytes) received, \(receivedDataPackets.count) frames received in total")
                        
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
    
    private let sessionQueue = DispatchQueue(label: "sessionQueue", qos: .userInitiated)
    private let dataOutputQueue = DispatchQueue(label: "dataOutputQueue")
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
    private let movieFileOutput = AVCaptureMovieFileOutput()
    private var dataOutputSynchronizer: AVCaptureDataOutputSynchronizer!
    
    private func configureSessionDuringSetup() {
        guard case .success(_) = setupResult else { return }
        
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            print("[Session Configuration] MultiCam is not supported.")
            return
        }
        
        // Test if device supports MultiCam mode
        let isMultiCamSupported = AVCaptureMultiCamSession.isMultiCamSupported
            && AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) != nil
        if isMultiCamSupported {
            
            print("[Session Configuration] MultiCam is supported.")
            
            configureSession(forReceiveMode: .dualCamera)
            
        } else {
            
            print("[Session Configuration] MultiCam is not supported. Reverting to wide camera only mode.")
            
            // Change UI
            DispatchQueue.main.async {
                self.receiveModeSegmentedControl.setEnabled(false, forSegmentAt: 1)
                self.receiveModeSegmentedControl.selectedSegmentIndex = 0
                self.receiveModeSegmentedControlIndexChanged(self.receiveModeSegmentedControl)
            }
            
            configureSession(forReceiveMode: .singleCamera)
        }
        
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
            setVideoFormat(ofDevice: dualCamera, width: 1280, height: 720, fps: 60.0, isBinned: true, multiCamOnly: true)
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
            setVideoFormat(ofDevice: wideCamera, width: 1280, height: 720, fps: 60.0, isBinned: false)
            session.addInput(wideCameraDeviceInput)
            
            // Add outputs
            guard session.canAddOutput(wideCameraVideoDataOutput) else {
                print("[Session Configuration] Could not add wide camera video data output.")
                setupResult = .configurationFailed
                return
            }
            session.addOutput(wideCameraVideoDataOutput)
            guard session.canAddOutput(movieFileOutput) else {
                print("[Session Configuration] Could not add movie file output.")
                setupResult = .configurationFailed
                return
            }
            wideCameraVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            wideCameraVideoDataOutput.alwaysDiscardsLateVideoFrames = false
            wideCameraVideoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
            
            setupResult = .success(.singleCamera)
            print("[Session Configuration] Single camera session configuration is successful.")
        }
        
    }
    
    // MARK: - Utilities
    
    private func setVideoFormat(ofDevice device: AVCaptureDevice, width: Int, height: Int, fps: Double, isBinned: Bool, multiCamOnly: Bool = false) {
                
        let width = Int32(width)
        let height = Int32(height)
        let fps = Float64(fps)
        
        var formatFound = false
        
        do {
            try device.lockForConfiguration()
            
            for format in device.formats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let maxFrameRate = format.videoSupportedFrameRateRanges.first!.maxFrameRate
                let isVideoBinned = format.isVideoBinned
                
                var isMatching = dimensions.width == width && dimensions.height == height && maxFrameRate == fps && isVideoBinned == isBinned
                if multiCamOnly {
                    isMatching = isMatching && format.isMultiCamSupported
                }
                
                if isMatching {
                    device.activeFormat = format
                    formatFound = true
                    break
                }
            }
            
            device.unlockForConfiguration()
        } catch let error {
            print("[ReceiveVC] Could not lock device \(device.localizedName) for changing format, reason: \(error)")
        }
        
        if formatFound == false {
            print("[ReceiveVC] Warning: format \(width)x\(height)@\(fps), binned: \(isBinned), multiCamOnly: \(multiCamOnly), was not found for device \(device.localizedName)")
        }
    }
        
    private func printAvailableMultiCamFormats() {
        guard let input = dualCameraDeviceInput else { return }
        print("------ Available MultiCam formats ------")
        let formats = input.device.formats
        for format in formats {
            guard format.isMultiCamSupported else { continue }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let maxFrameRate = format.videoSupportedFrameRateRanges.first!.maxFrameRate
            let binnedString = format.isVideoBinned ? "binned" : "not binned"
            print("\(dimensions.width)x\(dimensions.height) @ \(maxFrameRate) fps, \(binnedString)")
            print()
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

extension CVPixelBuffer {
    func copy() -> CVPixelBuffer {
        precondition(CFGetTypeID(self) == CVPixelBufferGetTypeID(), "copy() cannot be called on a non-CVPixelBuffer")
        
        var _copy : CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            CVPixelBufferGetWidth(self),
            CVPixelBufferGetHeight(self),
            CVPixelBufferGetPixelFormatType(self),
            nil,
            &_copy)
        
        guard let copy = _copy else { fatalError() }
        
        CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags.readOnly)
        CVPixelBufferLockBaseAddress(copy, CVPixelBufferLockFlags(rawValue: 0))
        
        let copyBaseAddress = CVPixelBufferGetBaseAddress(copy)
        let currBaseAddress = CVPixelBufferGetBaseAddress(self)
        
        memcpy(copyBaseAddress, currBaseAddress, CVPixelBufferGetDataSize(copy))
        
        CVPixelBufferUnlockBaseAddress(copy, CVPixelBufferLockFlags(rawValue: 0))
        CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags.readOnly)
        
        return copy
    }
}
