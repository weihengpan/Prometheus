//
//  DuplexViewContoller.swift
//  Prometheus
//
//  Created by 潘维恒 on 2020/8/8.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import UIKit
import AVFoundation

class DuplexViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet weak var previewView: PreviewView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sessionQueue.async { 
            self.setupSession()
            self.startSession()
            self.lockCameraExposure(after: 0.5)
        }
        
        // Disable timed auto-lock
        UIApplication.shared.isIdleTimerDisabled = true
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if session.isRunning == false {
            startSession()
        }
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if session.isRunning {
            stopSession()
        }
    }
    
    // MARK: - Processing
    
    private let dataOutputQueue = DispatchQueue(label: "data output queue")
    private let histogramFilter = HistogramFilter()
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }
        let inputImage = CIImage(cvImageBuffer: imageBuffer)
        let histogram = histogramFilter.calculateHistogram(of: inputImage)
        print(histogram.last!)
        
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("Warning: frame dropped")
    }
    
    // MARK: - Session
    
    private let sessionQueue = DispatchQueue(label: "session queue")
    
    private let session = AVCaptureSession()
    private var frontCamera: AVCaptureDevice!
    private let frontCameraVideoDataOutput = AVCaptureVideoDataOutput()
    
    private func setupSession() {
        
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720
        
        // Set up preview layer
        DispatchQueue.main.async {
            self.previewView.previewLayer.session = self.session
        }
        
        // Find front camera
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Front camera not found.")
            return
        }
        self.frontCamera = frontCamera
        do {
            try frontCamera.lockForConfiguration()
            if frontCamera.activeFormat.isVideoHDRSupported {
                frontCamera.automaticallyAdjustsVideoHDREnabled = false
                frontCamera.isVideoHDREnabled = false
            }
            frontCamera.unlockForConfiguration()
        } catch let error {
            print("Failed to lock front camera for configuration, error: \(error)")
        }
        
        // Add input
        guard let frontCameraDeviceInput = try? AVCaptureDeviceInput(device: frontCamera) else {
            print("Failed to create device input.")
            return
        }
        guard session.canAddInput(frontCameraDeviceInput) else {
            print("Failed to add device input.")
            return
        }
        session.addInput(frontCameraDeviceInput)
        
        // Add output
        guard session.canAddOutput(frontCameraVideoDataOutput) else {
            print("Cannot add output.")
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
            print("Video format: \(self.frontCamera.activeFormat.description)")
        }
    }
    
    private func stopSession() {
        sessionQueue.async {
            self.session.stopRunning()
        }
    }
    
    private func lockCameraExposure(after delay: TimeInterval) {
        sessionQueue.asyncAfter(deadline: .now() + delay) {
            do {
                try self.frontCamera.lockForConfiguration()
                self.frontCamera.exposureMode = .autoExpose
            } catch let error {
                print("Failed to lock front camera for configuration, error: \(error)")
            }
        }
    }
}
