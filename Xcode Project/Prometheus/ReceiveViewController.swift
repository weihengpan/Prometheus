//
//  ReceiveViewController.swift
//  Prometheus
//
//  Created by 潘维恒 on 2020/7/7.
//  Copyright © 2020 PAN Weiheng. All rights reserved.
//

import UIKit
import AVFoundation

class ReceiveViewController: UIViewController, AVCaptureDataOutputSynchronizerDelegate, AVCaptureMetadataOutputObjectsDelegate {
    
    // MARK: - IB Outlets and Related
    
    @IBOutlet weak var widePreviewView: PreviewView!
    @IBOutlet weak var telephotoPreviewView: PreviewView!
    
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
                    print("[Info] Video dimensions: \(dimensions.width)x\(dimensions.height)")
                    let maxFrameRate = format.videoSupportedFrameRateRanges.first!.maxFrameRate
                    print("[Info] Video max frame rate: \(maxFrameRate)")
                    
                    // Print available formats
                    let printsAvailableMultiCamFormats = false
                    if printsAvailableMultiCamFormats {
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
                }
                
            }
        }
    }
    
    // MARK: - Video Processing
    
    private let ciContext = CIContext()
    private var detector: CIDetector!
    private var frameNumber = 1
    internal func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        
        func detectQRCode(sampleBuffer: CMSampleBuffer, caption: String) {
            guard let imageBuffer = sampleBuffer.imageBuffer else { return }
            let image = CIImage(cvImageBuffer: imageBuffer)
            let codes = detector.features(in: image) as? [CIQRCodeFeature] ?? []
            for code in codes {
                guard let messageString = code.messageString else { continue }
                print("\(caption): \(messageString.count) bytes received")
            }
        }
        
        if detector == nil {
            detector = CIDetector(ofType: CIDetectorTypeQRCode, context: ciContext, options: nil)
        }
        
        if frameNumber <= 120 {
            
            defer { frameNumber += 1 }
            
            let count = synchronizedDataCollection.count
            //guard count > 2 else { return }
            print("[Synchronizer] Frame number: \(frameNumber)")
            
            if let wideCameraVideoData = synchronizedDataCollection[wideCameraVideoDataOutput] as? AVCaptureSynchronizedSampleBufferData {
                //print("[Synchronizer] Wide camera video frame received")
                let sampleBuffer = wideCameraVideoData.sampleBuffer
                detectQRCode(sampleBuffer: sampleBuffer, caption: "Wide")
            }
            if let telephotoCameraVideoData = synchronizedDataCollection[telephotoCameraVideoDataOutput] as? AVCaptureSynchronizedSampleBufferData {
                //print("[Synchronizer] Telephoto camera video frame received")
                let sampleBuffer = telephotoCameraVideoData.sampleBuffer
                detectQRCode(sampleBuffer: sampleBuffer, caption: "Telephoto")
            }
            if let wideCameraMetadataObjectData = synchronizedDataCollection[wideCameraMetadataOutput] as? AVCaptureSynchronizedMetadataObjectData {
                let metadataObjects = wideCameraMetadataObjectData.metadataObjects
                for object in metadataObjects {
                    guard let code = object as? AVMetadataMachineReadableCodeObject else { continue }
                    guard let text = code.stringValue else { continue }
                    //print("[Synchronizer] Wide camera QR code detected, text length:\t\t\(text.count)")
                }
            }
            if let telephotoCameraMetadataObjectData = synchronizedDataCollection[telephotoCameraMetadataOutput] as? AVCaptureSynchronizedMetadataObjectData {
                let metadataObjects = telephotoCameraMetadataObjectData.metadataObjects
                for object in metadataObjects {
                    guard let code = object as? AVMetadataMachineReadableCodeObject else { continue }
                    guard let text = code.stringValue else { continue }
                    //print("[Synchronizer] Telephoto camera QR code detected, text length:\t\(text.count)")
                }
            }
            
            print()
        }
        
        
    }
    
    // MARK: - Capture Session Management
    
    private enum SessionSetupResult {
        case success(AVCaptureDevice.DeviceType)
        case notAuthorized
        case configurationFailed
    }
    
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private let dataOutputQueue = DispatchQueue(label: "dataOutputQueue")
    private var session: AVCaptureSession!
    private var multiCamSession: AVCaptureMultiCamSession! {
        return session as? AVCaptureMultiCamSession
    }
    private var setupResult: SessionSetupResult = .success(.builtInDualCamera)
    
    private(set) var dualCameraDeviceInput: AVCaptureDeviceInput!
    private let wideCameraVideoDataOutput = AVCaptureVideoDataOutput()
    private let telephotoCameraVideoDataOutput = AVCaptureVideoDataOutput()
    private let wideCameraMetadataOutput = AVCaptureMetadataOutput()
    private let telephotoCameraMetadataOutput = AVCaptureMetadataOutput()
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
                dualCamera.focusMode = .continuousAutoFocus
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
            guard let wideCameraMetadataObjectPort = dualCameraDeviceInput.ports(for: .metadataObject,
                                                                        sourceDeviceType: .builtInWideAngleCamera,
                                                                        sourceDevicePosition: dualCamera.position).first
                else {
                    print("[Session Configuration] Could not find wide camera metadata port.")
                    setupResult = .configurationFailed
                    return
            }
            guard let telephotoCameraMetadataObjectPort = dualCameraDeviceInput.ports(for: .metadataObject,
                                                                             sourceDeviceType: .builtInTelephotoCamera,
                                                                             sourceDevicePosition: dualCamera.position).first
                else {
                    print("[Session Configuration] Could not find telephoto camera metadata port.")
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
            
            // Add metadata outputs
            guard session.canAddOutput(wideCameraMetadataOutput) else {
                print("[Session Configuration] Could not add wide camera metadata output.")
                setupResult = .configurationFailed
                return
            }
            guard session.canAddOutput(telephotoCameraMetadataOutput) else {
                print("[Session Configuration] Could not add telephoto camera metadata output.")
                setupResult = .configurationFailed
                return
            }
            session.addOutputWithNoConnections(wideCameraMetadataOutput)
            session.addOutputWithNoConnections(telephotoCameraMetadataOutput)
            
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
            
            // Add metadata connections
            let wideCameraMetadataOutputConnection = AVCaptureConnection(inputPorts: [wideCameraMetadataObjectPort], output: wideCameraMetadataOutput)
            let telephotoCameraMetadataOutputConnection = AVCaptureConnection(inputPorts: [telephotoCameraMetadataObjectPort], output: telephotoCameraMetadataOutput)
            guard session.canAddConnection(wideCameraMetadataOutputConnection) else {
                print("[Session Configuration] Could not add wide camera metadata connection.")
                setupResult = .configurationFailed
                return
            }
            guard session.canAddConnection(telephotoCameraMetadataOutputConnection) else {
                print("[Session Configuration] Could not add telephoto camera metadata connection.")
                setupResult = .configurationFailed
                return
            }
            session.addConnection(wideCameraMetadataOutputConnection)
            session.addConnection(telephotoCameraMetadataOutputConnection)
            wideCameraMetadataOutput.metadataObjectTypes = [.qr]
            telephotoCameraMetadataOutput.metadataObjectTypes = [.qr]
            
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
            let dataOutputs = [wideCameraVideoDataOutput, telephotoCameraVideoDataOutput, wideCameraMetadataOutput, telephotoCameraMetadataOutput]
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

