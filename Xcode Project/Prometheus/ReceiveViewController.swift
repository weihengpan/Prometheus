//
//  ReceiveViewController.swift
//  Prometheus
//
//  Created by 潘维恒 on 2020/7/7.
//  Copyright © 2020 PAN Weiheng. All rights reserved.
//

import UIKit
import AVFoundation

final class ReceiveViewController: UIViewController, AVCaptureDataOutputSynchronizerDelegate {
    
    // MARK: - IB Outlets, IB Actions and Related
    
    @IBOutlet weak var widePreviewView: PreviewView!
    @IBOutlet weak var telephotoPreviewView: PreviewView!
    @IBOutlet weak var startButton: UIButton!
    
    @IBAction func startButtonDidTouchUpInside(_ sender: Any) {
        if startButton.currentTitle ?? "" == "Stop" {
            // Ending data transmission
            isReceivingMetadata = true
            isReceivingData = false
            startButton.setTitle("Start", for: .normal)
            startButton.isEnabled = false
        } else {
            // Starting data transmission
            receivedDataPackets = []
            receivedFrameIndices = []
            isReceivingMetadata = false
            isReceivingData = true
            startButton.setTitle("Stop", for: .normal)
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
            self.configureSession()
        }
        
        // Disable timed auto-lock
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Disable start button
        startButton.isEnabled = false
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            if case .success(_) = self.setupResult {
                self.session.startRunning()
                
                // Print video spec
                for input in self.session.inputs {
                    guard let input = input as? AVCaptureDeviceInput else { continue }
                    let format = input.device.activeFormat
                    let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    let maxFrameRate = format.videoSupportedFrameRateRanges.first!.maxFrameRate
                    print("[Info] Video format: \(dimensions.width)x\(dimensions.height)@\(maxFrameRate)fps")
                    
                    // Print available formats
//                    print("------ Available MultiCam formats ------")
//                    let formats = input.device.formats
//                    for format in formats {
//                        guard format.isMultiCamSupported else { continue }
//                        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
//                        let maxFrameRate = format.videoSupportedFrameRateRanges.first!.maxFrameRate
//                        let binnedString = format.isVideoBinned ? "binned" : "not binned"
//                        print("\(dimensions.width)x\(dimensions.height) @ \(maxFrameRate) fps, \(binnedString)")
//                        print()
//                    }
                }
                
            }
        }
    }
    
    // MARK: - Video Processing
    
    private let ciContext = CIContext(options: [.useSoftwareRenderer : false])
    private var detector: CIDetector!
    private var frameNumber = 1
    private var isReceivingData = false
    private var isReceivingMetadata = true
    private var totalCountOfFrames = 0
    private var receivedFrameIndices = Set<UInt32>()
    private var receivedDataPackets = [DataPacket]()
    internal func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        
        // Intialize detector
        if detector == nil {
            let options: [String : Any] = [CIDetectorAccuracy : CIDetectorAccuracyHigh,
                                           CIDetectorTracking : true,
                                           CIDetectorMaxFeatureCount : 2,
                                           CIDetectorMinFeatureSize : 0.5]
            detector = CIDetector(ofType: CIDetectorTypeQRCode, context: ciContext, options: options)
        }
        
        // Detect QR codes
        if let wideCameraVideoData = synchronizedDataCollection[wideCameraVideoDataOutput] as? AVCaptureSynchronizedSampleBufferData {
            let sampleBuffer = wideCameraVideoData.sampleBuffer
            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let copiedImageBuffer = imageBuffer.copy()
                if isReceivingMetadata {
                    detectAndReceiveMetadataPackets(imageBuffer: copiedImageBuffer)
                } else if isReceivingData {
                    detectAndReceiveDataPackets(imageBuffer: copiedImageBuffer, caption: "Wide")
                }
            }
        } else {
            print("[Synchronizer] Warning: data from wide camera is dropped")
        }
        
        if let telephotoCameraVideoData = synchronizedDataCollection[telephotoCameraVideoDataOutput] as? AVCaptureSynchronizedSampleBufferData {
            /*let sampleBuffer = telephotoCameraVideoData.sampleBuffer
            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let copiedImageBuffer = imageBuffer.copy()
                if isReceivingMetadata {
                    detectAndReceiveMetadataPackets(imageBuffer: copiedImageBuffer)
                } else if isReceivingData {
                    detectAndReceiveDataPackets(imageBuffer: copiedImageBuffer, caption: "Wide")
                }
            }*/
        } else {
            print("[Synchronizer] Warning: data from telephoto camera is dropped")
        }
        
    }
    
    func debugPrintQRCode(sampleBuffer: CMSampleBuffer, caption: String) {
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvImageBuffer: imageBuffer)
        let codes = detector.features(in: image) as? [CIQRCodeFeature] ?? []
        for code in codes {
            guard let messageString = code.messageString, let descriptor = code.symbolDescriptor else { continue }
            let version = descriptor.symbolVersion
            print("[Synchronizer] \(caption): \(messageString.count) bytes received, version \(version)")
        }
    }
    
    func detectAndReceiveMetadataPackets(imageBuffer: CVPixelBuffer) {
        let codes = detectQRCodes(imageBuffer: imageBuffer)
        for code in codes {
            guard let descriptor = code.symbolDescriptor else { continue }
            guard let data = descriptor.data else { continue }
            guard let packet = MetadataPacket(archive: data) else { continue }
            
            guard let fileName = String(bytes: packet.fileNameData, encoding: .utf8) else {
                print("[Synchronizer] Failed to decode file name in metadata packet.")
                continue
            }
            
            totalCountOfFrames = Int(packet.numberOfFrames)
            print("[Synchronizer] Metadata packet received. No. of frames: \(packet.numberOfFrames), file size: \(packet.fileSize), file name: \(fileName)")
            
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
            print("[Synchronizer] \(caption): Frame \(frameIndex) (\(packet.payload.count) bytes) received, \(receivedDataPackets.count) frames received in total")
                        
            if receivedDataPackets.count == totalCountOfFrames {
                receivedDataPackets.sort(by: { $0.frameIndex < $1.frameIndex })
                let combinedData = receivedDataPackets.lazy.map { $0.payload }.reduce(Data(), +)
                print("[Synchronizer] All frames received, \(combinedData.count) bytes in total")
                let encoding = String.Encoding.utf8
                guard let messageString = String(data: combinedData, encoding: encoding) else {
                    print("[Synchronizer] Failed to decode data into string with encoding \(encoding)")
                    return
                }
                print("------ BEGIN MESSAGE ------")
                print(messageString)
                print("------  END MESSAGE  ------")
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
        case success(AVCaptureDevice.DeviceType)
        case notAuthorized
        case configurationFailed
    }
    
    private let sessionQueue = DispatchQueue(label: "sessionQueue", qos: .userInitiated)
    private let dataOutputQueue = DispatchQueue(label: "dataOutputQueue")
    private var session: AVCaptureSession!
    private var multiCamSession: AVCaptureMultiCamSession! {
        return session as? AVCaptureMultiCamSession
    }
    private var setupResult: SessionSetupResult = .success(.builtInDualCamera)
    
    private(set) var dualCameraDeviceInput: AVCaptureDeviceInput!
    private let wideCameraVideoDataOutput = AVCaptureVideoDataOutput()
    private let telephotoCameraVideoDataOutput = AVCaptureVideoDataOutput()
    private var dataOutputSynchronizer: AVCaptureDataOutputSynchronizer!
    
    private func configureSession() {
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
            guard let dualCameraDeviceInput = dualCameraDeviceInput,
                session.canAddInput(dualCameraDeviceInput) else {
                    print("[Session Configuration] Could not add dual camera device input.")
                    setupResult = .configurationFailed
                    return
            }
            do {
                try dualCamera.lockForConfiguration()
                
                // Set focus mode to continuous AF
                //dualCamera.focusMode = .continuousAutoFocus
                
                // Set video format to 1920x1080@60fps binned
                /*
                for format in dualCamera.formats {
                    let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    let maxFrameRate = format.videoSupportedFrameRateRanges.first!.maxFrameRate
                    if dimensions.width == 1920 && dimensions.height == 1080
                        && maxFrameRate == 60
                        && format.isMultiCamSupported {
                        dualCamera.activeFormat = format
                    }
                }*/
                
                dualCamera.unlockForConfiguration()
            } catch let error {
                print("[Session Configuration] Could not lock dual camera for configuration: \(error)")
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
            
            // Add video data connections
            let wideCameraVideoDataOutputConnection = AVCaptureConnection(inputPorts: [wideCameraVideoPort], output: wideCameraVideoDataOutput)
            let telephotoCameraVideoDataOutputConnection = AVCaptureConnection(inputPorts: [telephotoCameraVideoPort], output: telephotoCameraVideoDataOutput)
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
            let dataOutputs = [wideCameraVideoDataOutput, telephotoCameraVideoDataOutput]
            dataOutputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: dataOutputs)
            dataOutputSynchronizer.setDelegate(self, queue: dataOutputQueue)
            
            // Check system cost
            print("[Session Configuration] MultiCam system pressure cost: \(multiCamSession.systemPressureCost), hardware cost: \(multiCamSession.hardwareCost)")
            
            setupResult = .success(.builtInDualCamera)
            print("[Session Configuration] Session configuration is successful.")
            
        } else {
            
            print("[Session Configuration] MultiCam is not supported. Reverting to wide camera only mode.")
            
            session = AVCaptureSession()
            
            /// - Todo: Session configuration for single-camera mode
        }
        
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
        
        //print("copy data size: \(CVPixelBufferGetDataSize(copy))")
        //print("self data size: \(CVPixelBufferGetDataSize(self))")
        
        memcpy(copyBaseAddress, currBaseAddress, CVPixelBufferGetDataSize(copy))
        //memcpy(copyBaseAddress, currBaseAddress, CVPixelBufferGetDataSize(self) * 2)
        
        CVPixelBufferUnlockBaseAddress(copy, CVPixelBufferLockFlags(rawValue: 0))
        CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags.readOnly)
        
        return copy
    }
}
