//
//  CIQRCodeDescriptor+.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/7/9.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import CoreImage

extension CIQRCodeDescriptor {
    
    /// Bytes encoded in the QR code. If the QR code is not using byte mode, `nil` is returned.
    var data: Data? {
        
        // Check mode indicator
        let modeIndicator = errorCorrectedPayload.first! >> 4
        guard modeIndicator == 4 else { return nil }
        
        // Get character count
        var characterCountWidth: Int // in bytes
        var characterCount: UInt16
        if symbolVersion >= 1 && symbolVersion <= 9 {
            characterCountWidth = 1
            characterCount = UInt16(errorCorrectedPayload[0] << 4 + errorCorrectedPayload[1] >> 4)
        } else if symbolVersion >= 10 && symbolVersion <= 40 {
            characterCountWidth = 2
            let firstByte = UInt16(errorCorrectedPayload[0] << 4 + errorCorrectedPayload[1] >> 4)
            let secondByte = UInt16(errorCorrectedPayload[1] << 4 + errorCorrectedPayload[2] >> 4)
            characterCount = firstByte << 8 + secondByte
        } else {
            return nil
        }
        
        // Extract data
        let halfBytePosition = characterCountWidth
        let byteCount = Int(characterCount)
        var bytes: [UInt8] = []
        for i in halfBytePosition..<halfBytePosition + byteCount {
            let byte = errorCorrectedPayload[i] << 4 + errorCorrectedPayload[i+1] >> 4
            bytes.append(byte)
        }
        bytes.append(errorCorrectedPayload[halfBytePosition + byteCount] >> 4)
        
        return Data(bytes: &bytes, count: byteCount)
    }
}
