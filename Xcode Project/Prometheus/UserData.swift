//
//  UserDefaultsManager.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/8/2.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import Foundation

final class UserData {
    
    static let defaults = UserDefaults.standard
    
    // MARK: - Receive Settings
    
    @UserDefaultEnum(key: "cameraType", defaultValue: .singleCamera)
    static var cameraType: ReceiveViewController.CameraType
    
    @UserDefault(key: "videoFormatPickerViewSelectedRow", defaultValue: 0)
    static var videoFormatPickerViewSelectedRow: Int
    
    @UserDefaultEnum(key: "decodeMode", defaultValue: .liveDecode)
    static var decodeMode: ReceiveViewController.DecodeMode
    
    // MARK: - Send Settings
    
    @UserDefaultEnum(key: "sendMode", defaultValue: .single)
    static var sendMode: SendViewController.SendMode
    
    @UserDefault(key: "sendFrameRate", defaultValue: 15.0)
    static var sendFrameRate: Double
    
    @UserDefault(key: "codeVersion", defaultValue: 18)
    static var codeVersion: Int
    
    @UserDefaultEnum(key: "codeECL", defaultValue: .low)
    static var codeECL: QRCodeInformation.ErrorCorrectionLevel
    
    @UserDefault(key: "largerCodeVersion", defaultValue: 18)
    static var largerCodeVersion: Int
    
    @UserDefaultEnum(key: "largerCodeECL", defaultValue: .quartile)
    static var largerCodeECL: QRCodeInformation.ErrorCorrectionLevel
    
    @UserDefault(key: "smallerCodeVersion", defaultValue: 13)
    static var smallerCodeVersion: Int
    
    @UserDefaultEnum(key: "smallerCodeECL", defaultValue: .low)
    static var smallerCodeECL: QRCodeInformation.ErrorCorrectionLevel
}
