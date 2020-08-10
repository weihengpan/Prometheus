//
//  UIViewController+.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/8/8.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import UIKit

extension UIViewController {
    func dismissKeyboardWhenTapped() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
    }
    
    @objc func dismissKeyboard() {
        view.endEditing(true)
    }
}
