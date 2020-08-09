//
//  Array+.swift
//  Prometheus
//
//  Created by 潘维恒 on 2020/8/10.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import Foundation

extension Array where Element: FloatingPoint {
    
    var average: Element {
        return self.reduce(0, +) / Element(self.count)
    }
    
    var variance: Element {
        let average = self.average
        var total: Element = 0
        for element in self {
            let biasedElement = element - average
            total += biasedElement * biasedElement
        }
        return total / Element(self.count)
    }
    
    var standardDeviation: Element {
        return sqrt(self.variance)
    }
}
