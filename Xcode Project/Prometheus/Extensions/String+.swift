//
//  String+.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/8/7.
//  Copyright © 2020 PAN Weiheng. All rights reserved.
//

import Foundation

extension String {
    
    /// When used on a file name or a string that terminates with a file name, this method returns the file extension.
    func getFileExtension() -> String {
        return String(self.split(separator: ".").last!)
    }
}
