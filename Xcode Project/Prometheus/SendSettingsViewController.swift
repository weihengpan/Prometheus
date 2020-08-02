//
//  SendSettingsViewController.swift
//  Prometheus
//
//  Created by 潘维恒 on 2020/8/2.
//  Copyright © 2020 PAN Weiheng. All rights reserved.
//

import UIKit

class SendSettingsViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    
    typealias SendMode = SendViewController.SendMode
    typealias ErrorCorrectionLevel = QRCodeInformation.ErrorCorrectionLevel
    
    // MARK: - IB Outlets
    
    @IBOutlet weak var sendModePickerView: UIPickerView!
    
    @IBOutlet weak var frameRateLabel: UILabel!
    @IBOutlet weak var frameRateStepper: UIStepper!
    
    @IBOutlet weak var codeSettingsContentStackView: UIStackView!
    @IBOutlet weak var codeVersionStackView: UIStackView!
    @IBOutlet weak var codeECLStackView: UIStackView!
    @IBOutlet weak var largerCodeVersionStackView: UIStackView!
    @IBOutlet weak var largerCodeECLStackView: UIStackView!
    @IBOutlet weak var smallerCodeVersionStackView: UIStackView!
    @IBOutlet weak var smallerCodeECLStackView: UIStackView!
    
    @IBOutlet weak var codeVersionLabel: UILabel!
    @IBOutlet weak var codeECLLabel: UILabel!
    @IBOutlet weak var largerCodeVersionLabel: UILabel!
    @IBOutlet weak var largerCodeECLLabel: UILabel!
    @IBOutlet weak var smallerCodeVersionLabel: UILabel!
    @IBOutlet weak var smallerCodeECLLabel: UILabel!
    
    @IBOutlet weak var codeVersionStepper: UIStepper!
    @IBOutlet weak var codeECLStepper: UIStepper!
    @IBOutlet weak var largerCodeVersionStepper: UIStepper!
    @IBOutlet weak var largerCodeECLStepper: UIStepper!
    @IBOutlet weak var smallerCodeVersionStepper: UIStepper!
    @IBOutlet weak var smallerCodeECLStepper: UIStepper!
    
    // MARK: - View Controller Lifecycle & Segues
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sendModePickerView.dataSource = self
        sendModePickerView.delegate = self
        
        setupPickerView()
        setupFrameRateStepper()
        setupVersionStepper(codeVersionStepper)
        setupVersionStepper(largerCodeVersionStepper)
        setupVersionStepper(smallerCodeVersionStepper)
        setupECLStepper(codeECLStepper)
        setupECLStepper(largerCodeECLStepper)
        setupECLStepper(smallerCodeECLStepper)
        
        self.title = "Send Settings"
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let sendVC = segue.destination as? SendViewController {
            
            sendVC.sendMode = UserData.sendMode
            sendVC.sendFrameRate = UserData.sendFrameRate
            sendVC.codeMaxPacketSize = QRCodeInformation.dataCapacity(forVersion: UserData.codeVersion, errorCorrectionLevel: UserData.codeECL)!
            sendVC.largerCodeMaxPacketSize = QRCodeInformation.dataCapacity(forVersion: UserData.largerCodeVersion, errorCorrectionLevel: UserData.largerCodeECL)!
            sendVC.smallerCodeMaxPacketSize = QRCodeInformation.dataCapacity(forVersion: UserData.smallerCodeVersion, errorCorrectionLevel: UserData.smallerCodeECL)!
        }
    }
    
    // MARK: - UI Management
    
    private func setupFrameRateStepper() {
        
        frameRateStepper.minimumValue = 1
        frameRateStepper.maximumValue = Double(UIScreen.main.maximumFramesPerSecond)
        frameRateStepper.addTarget(self, action: #selector(frameRateStepperValueChanged(_:)), for: .valueChanged)
        frameRateStepper.value = UserData.sendFrameRate
        frameRateStepperValueChanged(frameRateStepper)
        
    }
    
    private func setupVersionStepper(_ stepper: UIStepper) {
        
        stepper.minimumValue = 1
        stepper.maximumValue = 40
        stepper.addTarget(self, action: #selector(versionStepperValueChanged(_:)), for: .valueChanged)
        var value: Int
        switch stepper {
        case codeVersionStepper:
            value = UserData.codeVersion
        case largerCodeVersionStepper:
            value = UserData.largerCodeVersion
        case smallerCodeVersionStepper:
            value = UserData.smallerCodeVersion
        default:
            return
        }
        stepper.value = Double(value)
        versionStepperValueChanged(stepper)
    }
    
    private func setupECLStepper(_ stepper: UIStepper) {
        
        stepper.minimumValue = 0
        stepper.maximumValue = 3
        stepper.addTarget(self, action: #selector(eclStepperValueChanged(_:)), for: .valueChanged)
        var level: ErrorCorrectionLevel
        switch stepper {
        case codeECLStepper:
            level = UserData.codeECL
        case largerCodeECLStepper:
            level = UserData.largerCodeECL
        case smallerCodeECLStepper:
            level = UserData.smallerCodeECL
        default:
            return
        }
        guard let index = ErrorCorrectionLevel.allCases.firstIndex(of: level) else {
            return
        }
        stepper.value = Double(index)
        eclStepperValueChanged(stepper)
    }
    
    private func setupPickerView() {
        
        let sendMode = UserData.sendMode
        guard let row = SendMode.allCases.firstIndex(of: sendMode) else { return }
        sendModePickerView.selectRow(row, inComponent: 0, animated: false)
        pickerView(sendModePickerView, didSelectRow: row, inComponent: 0)
                
    }
    
    @objc private func frameRateStepperValueChanged(_ sender: UIStepper) {
        
        // Update label & persist value
        let value = sender.value
        let valueString = String(Int(value))
        frameRateLabel.text = valueString
        UserData.sendFrameRate = value
    }
    
    @objc private func versionStepperValueChanged(_ sender: UIStepper) {
        
        // Update label & persist value
        let value = Int(sender.value)
        let valueString = String(value)
        switch sender {
        case codeVersionStepper:
            codeVersionLabel.text = valueString
            UserData.codeVersion = value
        case largerCodeVersionStepper:
            largerCodeVersionLabel.text = valueString
            UserData.largerCodeVersion = value
        case smallerCodeVersionStepper:
            smallerCodeVersionLabel.text = valueString
            UserData.smallerCodeVersion = value
        default:
            break
        }
        
    }
    
    @objc private func eclStepperValueChanged(_ sender: UIStepper) {
        
        // Update label & persist value
        let index = Int(sender.value)
        let level = ErrorCorrectionLevel.allCases[index]
        let levelString = level.fullName
        switch sender {
        case codeECLStepper:
            codeECLLabel.text = levelString
            UserData.codeECL = level
        case largerCodeECLStepper:
            largerCodeECLLabel.text = levelString
            UserData.largerCodeECL = level
        case smallerCodeECLStepper:
            smallerCodeECLLabel.text = levelString
            UserData.smallerCodeECL = level
        default:
            break
        }
        
    }
    
    // MARK: - Picker View Data Source Methods
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return SendMode.allCases.count
    }
    
    // MARK: - Picker View Delegate Methods
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        
        let sendMode = SendMode.allCases[row]
        switch sendMode {
        case .single:
            return "Single QR Code"
        case .alternatingSingle:
            return "Alternating Single QR Code"
        case .nested:
            return "Nested QR Code"
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        
        // Update visible settings
        let sendMode = SendMode.allCases[row]
        var visibleStackViews: Set<UIView> = []
        switch sendMode {
        case .single, .alternatingSingle:
            visibleStackViews = [codeVersionStackView, codeECLStackView]
        case .nested:
            visibleStackViews = [largerCodeVersionStackView, largerCodeECLStackView, smallerCodeVersionStackView, smallerCodeECLStackView]
        }
        
        let allStackViews = Set<UIView>(codeSettingsContentStackView.subviews)
        let invisibleStackViews = allStackViews.subtracting(visibleStackViews)
        
        for view in visibleStackViews {
            if codeSettingsContentStackView.arrangedSubviews.contains(view) == false {
                view.isHidden = false
                codeSettingsContentStackView.addArrangedSubview(view)
            }
        }
        for view in invisibleStackViews {
            if codeSettingsContentStackView.subviews.contains(view) {
                codeSettingsContentStackView.removeArrangedSubview(view)
                view.isHidden = true
            }
        }
        
        // Persist value
        UserData.sendMode = sendMode
    }
}
