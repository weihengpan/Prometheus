//
//  SendViewController.swift
//  Prometheus
//
//  Created by 潘维恒 on 2020/7/7.
//  Copyright © 2020 PAN Weiheng. All rights reserved.
//

import UIKit
import Combine

final class SendViewController: UIViewController {
    
    // MARK: - IB Outlets, IB Actions and Related
    
    @IBOutlet weak var renderView: MetalRenderView!
    @IBOutlet weak var startButton: UIButton!
    
    private var isDisplayingQRCodeImages = false
    @IBAction func startButtonDidTouchUpInside(_ sender: Any) {
        if isDisplayingQRCodeImages {
            stopDisplayingQRCodeImages()
        } else {
            startDisplayingQRCodeImages()
        }
        isDisplayingQRCodeImages.toggle()
    }
    
    // MARK: - Properties
    
    private let codeGenerator = NestedQRCodeGenerator()
    private var metadataCodeImage: CIImage?
    private var dataCodeImages: [CIImage]?
    
    private var codeDisplaySubscription: AnyCancellable?
    
    private let generationQueue = DispatchQueue(label: "generationQueue", qos: .userInitiated)
    
    private let maxPacketSize = 1008
    private let frameRate: TimeInterval = 1.0 / 10.0
    
    // MARK: - View Controller Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
    }
    
    var generated = false
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if generated == false {
            let sideLength = renderView.frame.width * UIScreen.main.scale
            generationQueue.async {
                self.generateQRCodeImages(renderViewSideLength: sideLength)
            }
            generated = true
        }
    }
    
    // MARK: - Methods
    
    private func startDisplayingQRCodeImages() {
        
        guard var codeImagesIterator = dataCodeImages?.makeIterator() else { return }
        codeDisplaySubscription = Timer.publish(every: frameRate, on: .current, in: .common)
            .autoconnect()
            .sink { _ in
                self.renderView.image = codeImagesIterator.next()
        }
        startButton.setTitle("Reset", for: .normal)
    }
    
    private func stopDisplayingQRCodeImages() {
        guard let subscription = codeDisplaySubscription else { return }
        subscription.cancel()
        renderView.image = metadataCodeImage
        startButton.setTitle("Start", for: .normal)
    }
    
    private func generateQRCodeImages(renderViewSideLength sideLength: CGFloat) {
        
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
        
        dataCodeImages = codeGenerator.generateQRCodesForDataPackets(data: messageData, correctionLevel: .low, sideLength: sideLength, maxPacketSize: self.maxPacketSize)
        
        let numberOfFrames = dataCodeImages!.count
        let fileSize = messageData.count
        let fullFileName = fileName + "." + fileExtension
        guard let metadataPacket = MetadataPacket(flagBits: 0, numberOfFrames: UInt32(numberOfFrames), fileSize: UInt32(fileSize), fileName: fullFileName) else {
            fatalError("[SendVC] Failed to create metadata packet.")
        }
        metadataCodeImage = codeGenerator.generateQRCode(forMetadataPacket: metadataPacket, sideLength: sideLength)
        
        DispatchQueue.main.async {
            self.renderView.image = self.metadataCodeImage
        }
    }
}

