//
//  SendSettingsViewController.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/8/2.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import UIKit
import AVFoundation
import MobileCoreServices

class SendSettingsViewController: UITableViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    
    typealias CodeType = SendViewController.CodeType
    typealias ErrorCorrectionLevel = QRCodeInformation.ErrorCorrectionLevel
    
    @UserDefaultEnum(key: "sendMode", defaultValue: .single)
    var sendMode: SendViewController.CodeType
    
    @UserDefault(key: "sendFrameRate", defaultValue: 15.0)
    var sendFrameRate: Double
    
    @UserDefault(key: "codeVersion", defaultValue: 18)
    var singleCodeVersion: Int
    
    @UserDefaultEnum(key: "codeECL", defaultValue: .low)
    var singleCodeECL: QRCodeInformation.ErrorCorrectionLevel
    
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
    
    var selectedFileNameWithExtension: String? {
        didSet {
            selectedFileLabel.text = selectedFileNameWithExtension
            reloadSectionFooters()
        }
    }
    
    var selectedFileData: NSData?
    
    // MARK: - IB Outlets
    
    @IBOutlet weak var selectedFileLabel: UILabel!
    
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
        
        setupSelectedFileLabelAndLoadExampleFile()
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
            
            sendVC.fileData = self.selectedFileData
            sendVC.fileNameWithExtension = self.selectedFileNameWithExtension
            sendVC.sendMode = self.sendMode
            sendVC.sendFrameRate = self.sendFrameRate
            sendVC.usesDuplexMode = self.usesDuplexMode
            sendVC.singleCodeVersion = self.singleCodeVersion
            sendVC.singleCodeErrorCorrectionLevel = self.singleCodeECL
            sendVC.largerCodeVersion = self.largerCodeVersion
            sendVC.largerCodeErrorCorrectionLevel = self.largerCodeECL
            sendVC.smallerCodeVersion = self.smallerCodeVersion
            sendVC.smallerCodeErrorCorrectionLevel = self.smallerCodeECL
            sendVC.codesSideLengthRatio = self.sizeRatio
        }
    }
    
    // MARK: - UI Management
    
    private func setupSelectedFileLabelAndLoadExampleFile() {
        
        // Fetch example file URL
        let fileName = "Alice in Wonderland"
        let fileExtension = "txt"
        let fileNameWithExtension = (fileName as NSString).appendingPathExtension(fileExtension)!
        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
            fatalError("[Send Settings] Example file \"\(fileNameWithExtension)\" not found in bundle.")
        }
        selectedFileNameWithExtension = fileNameWithExtension
        
        // Read and load example file
        let data = try! Data(contentsOf: url)
        selectedFileData = data as NSData
                
    }
        
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
            value = self.singleCodeVersion
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
            level = self.singleCodeECL
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
            self.updateCellVisibilities()
        }
        
    }
    
    private func enableDuplexMode() {
        transmissionModeSegmentedControl.setEnabled(true, forSegmentAt: 1)
    }
    
    private func disableDuplexMode() {
        
        transmissionModeSegmentedControl.setEnabled(false, forSegmentAt: 1)
        transmissionModeSegmentedControl.selectedSegmentIndex = 0
        usesDuplexMode = false
        transmissionModeSegmentedControlValueChanged(transmissionModeSegmentedControl)
    }
    
    private func updateCellVisibilities() {
        tableView.beginUpdates()
        tableView.endUpdates()
    }
    
    private func reloadSectionFooters() {
        tableView.reloadData()
    }
    
    // MARK: - Actions
    
    @objc private func frameRateStepperValueChanged(_ sender: UIStepper) {
        
        // Update label & persist value
        let value = sender.value
        let valueString = String(Int(value))
        frameRateLabel.text = valueString
        self.sendFrameRate = value
        
        // Reload footer
        reloadSectionFooters()
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
            self.singleCodeVersion = value
        case largerCodeVersionStepper:
            largerCodeVersionLabel.text = valueString
            self.largerCodeVersion = value
        case smallerCodeVersionStepper:
            smallerCodeVersionLabel.text = valueString
            self.smallerCodeVersion = value
        default:
            break
        }
        
        // Reload footer
        reloadSectionFooters()
    }
    
    @objc private func eclStepperValueChanged(_ sender: UIStepper) {
        
        // Update label & persist value
        let index = Int(sender.value)
        let level = ErrorCorrectionLevel.allCases[index]
        let levelString = level.fullName
        switch sender {
        case codeECLStepper:
            codeECLLabel.text = levelString
            self.singleCodeECL = level
        case largerCodeECLStepper:
            largerCodeECLLabel.text = levelString
            self.largerCodeECL = level
        case smallerCodeECLStepper:
            smallerCodeECLLabel.text = levelString
            self.smallerCodeECL = level
        default:
            break
        }
        
        // Reload footer
        reloadSectionFooters()
    }
    
    @IBAction func sizeRatioTextFieldEditingDidEnd(_ sender: UITextField) {
        
        defer { sender.text = String(self.sizeRatio) }
        
        guard let text = sender.text else { return }
        guard let sizeRatio = Double(text) else { return }
        guard sizeRatio >= 0 && sizeRatio <= 1 else { return }
        self.sizeRatio = sizeRatio
        
        // Reload footer
        reloadSectionFooters()
    }
    
    // MARK: - Table View Delegate Methods
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        // Default height of cell as in Interface Builder
        let defaultHeight = super.tableView(tableView, heightForRowAt: indexPath)
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        
        // Set selected file name cell visibility
        if selectedFileLabel.isDescendant(of: cell) {
            return (selectedFileNameWithExtension == nil) ? 0 : defaultHeight
        }
        
        // Set picker view visiblities
        if sendModePickerView.isDescendant(of: cell) {
            return sendModePickerView.isHidden ? 0 : defaultHeight
        }
        
        // Set code setting cells visibilities
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
        
        // "Select File" cell
        let selectFileCellIndexPath = IndexPath(row: 1, section: 0)
        if indexPath == selectFileCellIndexPath {
            
            // Present document picker
            let dataTypeUTI = kUTTypeData as String
            let pickerViewController = UIDocumentPickerViewController(documentTypes: [dataTypeUTI], in: .open)
            pickerViewController.delegate = self
            pickerViewController.shouldShowFileExtensions = true
            pickerViewController.allowsMultipleSelection = false
            self.present(pickerViewController, animated: true) {
                //self.reloadSectionFooters()
            }
        }
        
        if sendModeLabel.isDescendant(of: cell) {
            changeCodeTypePickerViewVisibility(to: sendModePickerView.isHidden)
        }
        
        if startButton.isDescendant(of: cell) {
            performSegue(withIdentifier: "showSendViewController", sender: nil)
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: - Table View Data Source Methods
    
    private let codeSettingsSectionIndex = 2
    
    private let fileSelectionSectionIndex = 0

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        
        switch section {
            
        case codeSettingsSectionIndex:
            // Display code information and transmission information
            return codeSettingsSectionFooterString
        
        case fileSelectionSectionIndex:
            // Display file size information
            return fileSelectionSectionFooterString

        default:
            return nil
        }
        
    }
    
    override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        
        guard let footerView = view as? UITableViewHeaderFooterView else { return }
        
        // Disable table section header full capitalization
        switch section {
            
        case codeSettingsSectionIndex:
            footerView.textLabel?.text = codeSettingsSectionFooterString
            
        case fileSelectionSectionIndex:
            footerView.textLabel?.text = fileSelectionSectionFooterString
            
        default:
            return
        }
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
        
        // Enable/disable duplex mode
        if sendMode == .nested {
            disableDuplexMode()
        } else {
            enableDuplexMode()
        }
        
        // Update code settings footer
        reloadSectionFooters()
        
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
        
        updateCellVisibilities()
    }
}

extension SendSettingsViewController : UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        
        guard urls.count == 1 else {
            print("[Send Settings] Warning: more than one files selected in document picker. Cancelling actions.")
            return
        }
        
        // Request file access permission
        let url = urls.first!
        let nsURL = url as NSURL
        guard nsURL.startAccessingSecurityScopedResource() else {
            print("[Send Settings] Failed access security scoped resource at url: \(url)")
            return
        }
        defer { nsURL.stopAccessingSecurityScopedResource() }
        
        // Read file data
        var data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error {
            print("[Send Settings] Failed to open file at url: \(url), error: \(error)")
            return
        }
        selectedFileData = data as NSData
        
        // Get file name
        let urlString = url.absoluteString
        let fileNameWithExtensionInPercentEncoding = (urlString as NSString).lastPathComponent
        guard let fileNameWithExtension = fileNameWithExtensionInPercentEncoding.removingPercentEncoding else {
            print("[Send Settings] File name \(fileNameWithExtensionInPercentEncoding) contains invalid percent-encoding sequence.")
            return
        }
        selectedFileNameWithExtension = fileNameWithExtension
        print("[Send Settings] File \"\(fileNameWithExtension)\" selected, size: \(data.count) bytes.")
        
        // Update cell
        let selectedFileCell = tableView.cellForRow(at: IndexPath(row: 0, section: 0))
        selectedFileCell?.accessoryType = .checkmark
        updateCellVisibilities()
    }
    
    // MARK: - Utilities
    
    private var codeSettingsSectionFooterString: String {
        
        var displayedString = ""
        
        // Code information
        var totalDataCapacityPerFrame: Int
        var codeInformation = ""
        if sendMode == .nested {
            
            let largerCodeDataCapacity = QRCodeInformation.dataCapacity(forVersion: largerCodeVersion,
                                                                        errorCorrectionLevel: largerCodeECL)!
            let smallerCodeDataCapacity = QRCodeInformation.dataCapacity(forVersion: smallerCodeVersion,
                                                                         errorCorrectionLevel: smallerCodeECL)!
            totalDataCapacityPerFrame = largerCodeDataCapacity + smallerCodeDataCapacity
            
            let largerCodeModuleSideLength = 1.0 / Double(2 + QRCodeInformation.sideLengthInModules(forVersion: largerCodeVersion)!)
            let smallerCodeModuleSideLength = 1.0 * sizeRatio / Double(2 + QRCodeInformation.sideLengthInModules(forVersion: smallerCodeVersion)!)
            let moduleSideLengthRatio = smallerCodeModuleSideLength / largerCodeModuleSideLength
            
            codeInformation += "Larger code data capacity: \(largerCodeDataCapacity) bytes\n"
            codeInformation += "Smaller code data capacity: \(smallerCodeDataCapacity) bytes\n"
            codeInformation += "Total data capacity: \(totalDataCapacityPerFrame) bytes\n"
            codeInformation += String(format: "Module side length ratio: %.3lf\n", moduleSideLengthRatio)
            
        } else {
            
            totalDataCapacityPerFrame = QRCodeInformation.dataCapacity(forVersion: singleCodeVersion,
                                                                       errorCorrectionLevel: singleCodeECL)!
            codeInformation += "Code data capacity: \(totalDataCapacityPerFrame) bytes\n"
        }
        displayedString += codeInformation
        
        // Transmission information
        let transmissionRate = totalDataCapacityPerFrame * Int(sendFrameRate)
        let transmissionRateString = ByteCountFormatter.string(fromByteCount: Int64(transmissionRate), countStyle: .file) + "/s"
        let transmissionRateInformation = "Transmission rate: " + transmissionRateString + "\n"
        displayedString += transmissionRateInformation
        
        if let fileData = selectedFileData {
            let fileSize = fileData.count
            let transmissionTime: TimeInterval = TimeInterval(fileSize) / TimeInterval(transmissionRate)
            
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.allowedUnits = [.day, .hour, .minute, .second]
            let transmissionTimeString = formatter.string(from: transmissionTime)!
            let transmissionTimeInformation = "Estimated transmission time: " + transmissionTimeString
            displayedString += transmissionTimeInformation
        }
        
        return displayedString
    }
    
    private var fileSelectionSectionFooterString: String? {
        
        guard let fileData = selectedFileData else { return nil }
        
        let fileSize = fileData.count
        let fileSizeString = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
        return "File size: \(fileSizeString)"
        
    }
    
}
