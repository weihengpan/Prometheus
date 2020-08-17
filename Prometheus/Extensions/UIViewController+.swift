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
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGestureRecognizer.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGestureRecognizer)
    }
    
    @objc func dismissKeyboard() {
        view.endEditing(true)
    }
}
