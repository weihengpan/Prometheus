//
//  ReceiveViewController.swift
//  Prometheus
//
//  Created by 潘维恒 on 2020/7/7.
//  Copyright © 2020 PAN Weiheng. All rights reserved.
//

import UIKit
import AVFoundation

class ReceiveViewController: UIViewController, AVCaptureDataOutputSynchronizerDelegate {
    
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
            }
        }
    }
    
    // MARK: - Video Processing
    
    internal func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        /// - Todo: Process video frames
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
            session.addInputWithNoConnections(dualCameraDeviceInput)
            
            // Find ports of the constituent devices of the device input
            guard let widePort = dualCameraDeviceInput.ports(for: .video,
                                                             sourceDeviceType: .builtInWideAngleCamera,
                                                             sourceDevicePosition: dualCamera.position).first
                else {
                    print("[Session Configuration] Could not find wide camera input port.")
                    setupResult = .configurationFailed
                    return
            }
            guard let telephotoPort = dualCameraDeviceInput.ports(for: .video,
                                                             sourceDeviceType: .builtInTelephotoCamera,
                                                             sourceDevicePosition: dualCamera.position).first
                else {
                    print("[Session Configuration] Could not find telephoto camera input port.")
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
            let wideCameraVideoDataOutputConnection = AVCaptureConnection(inputPorts: [widePort], output: wideCameraVideoDataOutput)
            let telephotoCameraVideoDataOutputConnection = AVCaptureConnection(inputPorts: [telephotoPort], output: telephotoCameraVideoDataOutput)
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
            let widePreviewLayerConnection = AVCaptureConnection(inputPort: widePort, videoPreviewLayer: widePreviewLayer)
            let telephotoPreviewLayerConnection = AVCaptureConnection(inputPort: telephotoPort, videoPreviewLayer: telephotoPreviewLayer)
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
            dataOutputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [wideCameraVideoDataOutput, telephotoCameraVideoDataOutput])
            dataOutputSynchronizer.setDelegate(self, queue: dataOutputQueue)
    
            // Check system cost
            print("[Session Configuration] MultiCam system pressure cost: \(multiCamSession.systemPressureCost), hardware cost: \(multiCamSession.hardwareCost)")
            
            print("[Session Configuration] Session configuration is successful.")
                        
        } else {
            
            print("[Session Configuration] MultiCam is not supported.")
            
            session = AVCaptureSession()
            
            /// - Todo: Session configuration for single-camera mode
        }
        
    }

}

