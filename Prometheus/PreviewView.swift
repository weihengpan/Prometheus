//
//  PreviewView.swift
//  Prometheus
//
//  Created by 潘维恒 on 2020/7/7.
//  Copyright © 2020 PAN Weiheng. All rights reserved.
//

import UIKit
import AVFoundation

class PreviewView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
}
