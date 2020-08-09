//
//  SendSettingsViewController.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/8/2.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import UIKit
import AVFoundation

class SendSettingsViewController: UITableViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    
    typealias CodeType = SendViewController.CodeType
    typealias ErrorCorrectionLevel = QRCodeInformation.ErrorCorrectionLevel
    
    @UserDefaultEnum(key: "sendMode", defaultValue: .single)
    var sendMode: SendViewController.CodeType
    
    @UserDefault(key: "sendFrameRate", defaultValue: 15.0)
    var sendFrameRate: Double
    
    @UserDefault(key: "codeVersion", defaultValue: 18)
    var codeVersion: Int
    
    @UserDefaultEnum(key: "codeECL", defaultValue: .low)
    var codeECL: QRCodeInformation.ErrorCorrectionLevel
    
    @UserDefault(key: "largerCodeVersion", defaultValue: 18)
    var largerCodeVersion: Int
    
    @UserDefaultEnum(key: "largerCodeECL", defaultValue: .quartile)
    var largerCodeECL: QRCodeInformation.ErrorCorrectionLevel
    
    @UserDefault(key: "smallerCodeVersion", defaultValue: 13)
    var smallerCodeVersion: Int
    
    @UserDefaultEnum(key: "smallerCodeECL", defaultValue: .low)
    var smallerCodeECL: QRCodeInformation.ErrorCorrectionLevel
    
    @UserDefault(key: "sizeRatio", defaultValue: 0.3)
    var sizeRatio: Double
    
    @UserDefault(key: "senderUsesDuplexMode", defaultValue: false)
    var usesDuplexMode: Bool
    
    // MARK: - IB Outlets
    
    @IBOutlet weak var sendModeLabel: UILabel!
    @IBOutlet weak var sendModePickerView: UIPickerView!
    
    @IBOutlet weak var frameRateLabel: UILabel!
    @IBOutlet weak var frameRateStepper: UIStepper!
    
    @IBOutlet weak var transmissionModeSegmentedControl: UISegmentedControl!
    
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
    
    @IBOutlet weak var sizeRatioTextField: UITextField!
    
    @IBOutlet weak var startButton: UIButton!
    
    // MARK: - View Controller Lifecycle & Segues
    
    override func viewDidLoad() {
        super.viewDidLoad()
                
        sendModePickerView.dataSource = self
        sendModePickerView.delegate = self
        
        self.title = "Send"
        
        dynamicCellSubviews = [codeVersionLabel, codeECLLabel, largerCodeVersionLabel, largerCodeECLLabel, smallerCodeVersionLabel, smallerCodeECLLabel, sizeRatioTextField]
        dynamicCellsVisibilities = .init(repeatElement(true, count: dynamicCellSubviews.count))
        
        setupCodeTypeLabelAndPickerView()
        setupFrameRateStepper()
        setupTransmissionModeSegmentedControl()
        setupVersionStepper(codeVersionStepper)
        setupVersionStepper(largerCodeVersionStepper)
        setupVersionStepper(smallerCodeVersionStepper)
        setupECLStepper(codeECLStepper)
        setupECLStepper(largerCodeECLStepper)
        setupECLStepper(smallerCodeECLStepper)
        setupSizeRatioTextField()
        
        dismissKeyboardWhenTapped()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let sendVC = segue.destination as? SendViewController {
            
            sendVC.sendMode = self.sendMode
            sendVC.sendFrameRate = self.sendFrameRate
            sendVC.usesDuplexMode = self.usesDuplexMode
            sendVC.codeMaxPacketSize = QRCodeInformation.dataCapacity(forVersion: self.codeVersion, errorCorrectionLevel: self.codeECL)!
            sendVC.largerCodeMaxPacketSize = QRCodeInformation.dataCapacity(forVersion: self.largerCodeVersion, errorCorrectionLevel: self.largerCodeECL)!
            sendVC.smallerCodeMaxPacketSize = QRCodeInformation.dataCapacity(forVersion: self.smallerCodeVersion, errorCorrectionLevel: self.smallerCodeECL)!
            sendVC.smallerCodeSideLengthRatio = self.sizeRatio
        }
    }
    
    // MARK: - UI Management
        
    private func setupCodeTypeLabelAndPickerView() {
        
        // Set label text
        let sendMode = self.sendMode
        sendModeLabel.text = sendMode.readableName
        
        // Hide picker
        sendModePickerView.isHidden = true
        
        // Select row
        guard let row = CodeType.allCases.firstIndex(of: sendMode) else { return }
        sendModePickerView.selectRow(row, inComponent: 0, animated: false)
        pickerView(sendModePickerView, didSelectRow: row, inComponent: 0)
        
    }
    
    private func setupFrameRateStepper() {
        
        frameRateStepper.minimumValue = 1
        frameRateStepper.maximumValue = Double(UIScreen.main.maximumFramesPerSecond)
        frameRateStepper.addTarget(self, action: #selector(frameRateStepperValueChanged(_:)), for: .valueChanged)
        frameRateStepper.value = self.sendFrameRate
        frameRateStepperValueChanged(frameRateStepper)
        
    }
    
    private func setupTransmissionModeSegmentedControl() {
        
        let wideCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)!
        if wideCamera.hasTorch == false {
            transmissionModeSegmentedControl.setEnabled(false, forSegmentAt: 1)
            transmissionModeSegmentedControl.selectedSegmentIndex = 0
            return
        }
        transmissionModeSegmentedControl.selectedSegmentIndex = usesDuplexMode ? 1 : 0
    }
    
    private func setupVersionStepper(_ stepper: UIStepper) {
        
        stepper.minimumValue = 1
        stepper.maximumValue = 40
        stepper.addTarget(self, action: #selector(versionStepperValueChanged(_:)), for: .valueChanged)
        var value: Int
        switch stepper {
        case codeVersionStepper:
            value = self.codeVersion
        case largerCodeVersionStepper:
            value = self.largerCodeVersion
        case smallerCodeVersionStepper:
            value = self.smallerCodeVersion
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
            level = self.codeECL
        case largerCodeECLStepper:
            level = self.largerCodeECL
        case smallerCodeECLStepper:
            level = self.smallerCodeECL
        default:
            return
        }
        guard let index = ErrorCorrectionLevel.allCases.firstIndex(of: level) else {
            return
        }
        stepper.value = Double(index)
        eclStepperValueChanged(stepper)
    }
    
    private func setupSizeRatioTextField() {
        
        sizeRatioTextField.text = String(sizeRatio)
    }
    
    private func changeCodeTypePickerViewVisibility(to isVisible: Bool) {
        
        self.sendModePickerView.isHidden = !isVisible
        UIView.animate(withDuration: 0.3) {
            // Trigger table view update
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
        }
        
    }
    
    // MARK: - Actions
    
    @objc private func frameRateStepperValueChanged(_ sender: UIStepper) {
        
        // Update label & persist value
        let value = sender.value
        let valueString = String(Int(value))
        frameRateLabel.text = valueString
        self.sendFrameRate = value
    }
    
    @IBAction func transmissionModeSegmentedControlValueChanged(_ sender: UISegmentedControl) {
        
        switch sender.selectedSegmentIndex {
        case 0:
            usesDuplexMode = false
        case 1:
            usesDuplexMode = true
        default:
            break
        }
    }
    
    @objc private func versionStepperValueChanged(_ sender: UIStepper) {
        
        // Update label & persist value
        let value = Int(sender.value)
        let valueString = String(value)
        switch sender {
        case codeVersionStepper:
            codeVersionLabel.text = valueString
            self.codeVersion = value
        case largerCodeVersionStepper:
            largerCodeVersionLabel.text = valueString
            self.largerCodeVersion = value
        case smallerCodeVersionStepper:
            smallerCodeVersionLabel.text = valueString
            self.smallerCodeVersion = value
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
            self.codeECL = level
        case largerCodeECLStepper:
            largerCodeECLLabel.text = levelString
            self.largerCodeECL = level
        case smallerCodeECLStepper:
            smallerCodeECLLabel.text = levelString
            self.smallerCodeECL = level
        default:
            break
        }
        
    }
    
    @IBAction func sizeRatioTextFieldEditingDidEnd(_ sender: UITextField) {
        
        defer { sender.text = String(self.sizeRatio) }
        
        guard let text = sender.text else { return }
        guard let sizeRatio = Double(text) else { return }
        guard sizeRatio >= 0 && sizeRatio <= 1 else { return }
        self.sizeRatio = sizeRatio
    }
    
    // MARK: - Table View Delegate Methods
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        // Default height of cell as in Interface Builder
        let defaultHeight = super.tableView(tableView, heightForRowAt: indexPath)
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        
        if sendModePickerView.isDescendant(of: cell) {
            return sendModePickerView.isHidden ? 0 : defaultHeight
        }
        
        if let label = dynamicCellSubviews.first(where: { $0.isDescendant(of: cell) }) {
            let index = dynamicCellSubviews.firstIndex(of: label)!
            let isVisible = dynamicCellsVisibilities[index]
            cell.isHidden = !isVisible
            return isVisible ? defaultHeight : 0
        }
        
        return defaultHeight
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        
        if sendModeLabel.isDescendant(of: cell) {
            changeCodeTypePickerViewVisibility(to: sendModePickerView.isHidden)
        }
        
        if startButton.isDescendant(of: cell) {
            performSegue(withIdentifier: "showSendViewController", sender: nil)
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: - Picker View Data Source Methods
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return CodeType.allCases.count
    }
    
    // MARK: - Picker View Delegate Methods
        
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        
        let sendMode = CodeType.allCases[row]
        return sendMode.readableName
    }
    
    private var dynamicCellSubviews = [UIView]()
    private var dynamicCellsVisibilities = [Bool]()
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        
        // Update label
        let sendMode = CodeType.allCases[row]
        sendModeLabel.text = sendMode.readableName

        // Persist value
        self.sendMode = sendMode
        
        // Update cells' visibilities
        var visibleCellSubviews: [UIView]
        switch sendMode {
        case .single, .alternatingSingle:
            visibleCellSubviews = [codeVersionLabel, codeECLLabel]
        case .nested:
            visibleCellSubviews = [largerCodeVersionLabel, largerCodeECLLabel, smallerCodeVersionLabel, smallerCodeECLLabel, sizeRatioTextField]
        }
                
        guard dynamicCellsVisibilities.count > 0 else { return }
        for (index, label) in dynamicCellSubviews.enumerated() {
            dynamicCellsVisibilities[index] = visibleCellSubviews.contains(label)
        }
        
        tableView.beginUpdates()
        tableView.endUpdates()
    }
}
