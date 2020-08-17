//
//  Data+.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/7/9.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import Foundation

extension Data {
    var hexDescription: String {
        return reduce("") {$0 + String(format: "%02x", $1)}
    }
    
    static func +(left: Data, right: Data) -> Data {
        var data = left
        data.append(right)
        return data
    }
}
