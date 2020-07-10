//
//  Data+.swift
//  Prometheus
//
//  Created by 潘维恒 on 2020/7/9.
//  Copyright © 2020 PAN Weiheng. All rights reserved.
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
