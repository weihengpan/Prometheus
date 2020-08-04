//
//  ReceiveSettingsViewController.swift
//  Prometheus
//
//  Created by 潘维恒 on 2020/8/4.
//  Copyright © 2020 PAN Weiheng. All rights reserved.
//

import UIKit
import AVFoundation

class ReceiveSettingsViewController: UITableViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    
    typealias ReceiveMode = ReceiveViewController.ReceiveMode
    typealias DecodeMode = ReceiveViewController.DecodeMode
    
    // MARK: - IB Outlets
    
    @IBOutlet weak var cameraSegmentedControl: UISegmentedControl!

    @IBOutlet weak var videoFormatLabel: UILabel!
    @IBOutlet weak var videoFormatPickerView: UIPickerView!
    
    @IBOutlet weak var decodeModeSegmentedControl: UISegmentedControl!
    
    @IBOutlet weak var startButton: UIButton!
    
    // MARK: - View Controller Lifecycle & Segues
    
    private var availableVideoFormats: [AVCaptureDevice.Format]!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        videoFormatPickerView.dataSource = self
        videoFormatPickerView.delegate = self
        
        self.title = "Receive"
        
        setupCameraSegmentedControl()
        setupVideoFormatLabelAndPickerView()
        setupDecodeModeSegmentedControl()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if let viewController = segue.destination as? ReceiveViewController {
                        
            viewController.receiveMode = UserData.receiveMode
            viewController.decodeMode = UserData.decodeMode
            if let videoFormat = selectedVideoFormat {
                viewController.videoFormat = videoFormat
            }
        }
    }
    
    // MARK: - UI Management
    
    private func setupCameraSegmentedControl() {
        
        let receiveMode = UserData.receiveMode
        let index = ReceiveMode.allCases.firstIndex(of: receiveMode)!
        cameraSegmentedControl.selectedSegmentIndex = index
        cameraSegmentedControl.addTarget(self, action: #selector(cameraSegmentedControlValueChanged(_:)), for: .valueChanged)
        
        let isMultiCamSupported = AVCaptureMultiCamSession.isMultiCamSupported
            && AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) != nil
        if isMultiCamSupported == false {
            cameraSegmentedControl.setEnabled(false, forSegmentAt: 1)
            cameraSegmentedControl.selectedSegmentIndex = 0
        }
        
        cameraSegmentedControlValueChanged(cameraSegmentedControl)
    }
    
    private func setupVideoFormatLabelAndPickerView() {
        
        // Select row
        let row = UserData.videoFormatPickerViewSelectedRow
        videoFormatPickerView.selectRow(row, inComponent: 0, animated: false)
    
        // Hide picker
        videoFormatPickerView.isHidden = true
        
        // Set label text
        let clippedRow = min(row, availableVideoFormats.count - 1)
        let format = availableVideoFormats[clippedRow]
        videoFormatLabel.text = videoFormatDescription(of: format)
        
    }
    
    private func setupDecodeModeSegmentedControl() {
        
        let decodeMode = UserData.decodeMode
        let index = DecodeMode.allCases.firstIndex(of: decodeMode)!
        decodeModeSegmentedControl.selectedSegmentIndex = index
        decodeModeSegmentedControl.addTarget(self, action: #selector(decodeModeSegmentedControlValueChanged(_:)), for: .valueChanged)
        decodeModeSegmentedControlValueChanged(decodeModeSegmentedControl)
    }
    
    private func changeVideoFormatPickerViewVisibility(to isVisible: Bool) {
        
        videoFormatPickerView.isHidden = !isVisible
        UIView.animate(withDuration: 0.3) {
            // Trigger table view update
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
        }
        
    }
    
    // MARK: - Actions
    
    @objc private func cameraSegmentedControlValueChanged(_ sender: UISegmentedControl) {
        
        /// State variable for preventing accessing `availableVideoFormats` while it is still `nil`.
        let availableVideoFormatsIsLoaded = availableVideoFormats != nil
        
        var row: Int?
        var rowTitle: String?
        if availableVideoFormatsIsLoaded {
            // Save row and row title before change
            row = videoFormatPickerView.selectedRow(inComponent: 0)
            rowTitle = pickerView(videoFormatPickerView, titleForRow: row!, forComponent: 0)
        }
        
        // Persist data
        let receiveMode = ReceiveMode.allCases[sender.selectedSegmentIndex]
        UserData.receiveMode = receiveMode
        
        // Update available video formats and picker view rows
        let multiCamOnly = receiveMode == .dualCamera
        availableVideoFormats = getAvailableVideoFormats(multiCamOnly: multiCamOnly)
        videoFormatPickerView.reloadAllComponents()
        
        if availableVideoFormatsIsLoaded {
            // Select the same format, if possible
            guard let title = rowTitle else { return }
            let formatDescriptions = availableVideoFormats.map { videoFormatDescription(of: $0) }
            
            var foundIndex: Int?
            for (index, description) in formatDescriptions.enumerated() {
                if description == title {
                    foundIndex = index
                    break
                }
            }
            
            if foundIndex != nil {
                videoFormatPickerView.selectRow(foundIndex!, inComponent: 0, animated: false)
                // Update video format label & persist row selection data
                pickerView(videoFormatPickerView, didSelectRow: foundIndex!, inComponent: 0)
            } else {
                // Update video format label & persist row selection data
                let clippedRow = min(row!, availableVideoFormats.count - 1)
                pickerView(videoFormatPickerView, didSelectRow: clippedRow, inComponent: 0)
            }
        }
    }
    
    @objc private func decodeModeSegmentedControlValueChanged(_ sender: UISegmentedControl) {
        
        let index = sender.selectedSegmentIndex
        let decodeMode = DecodeMode.allCases[index]
        UserData.decodeMode = decodeMode
        
    }
    
    // MARK: - Table View Delegate Methods
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        // Default height of cell as in Interface Builder
        let defaultHeight = super.tableView(tableView, heightForRowAt: indexPath)
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        
        if videoFormatPickerView.isDescendant(of: cell) {
            return videoFormatPickerView.isHidden ? 0 : defaultHeight
        }
        
        return defaultHeight
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        
        if videoFormatLabel.isDescendant(of: cell) {
            changeVideoFormatPickerViewVisibility(to: videoFormatPickerView.isHidden)
        }
    
        if startButton.isDescendant(of: cell) {
            performSegue(withIdentifier: "showReceiveViewController", sender: nil)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: - Picker View Data Source Methods
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return availableVideoFormats.count
    }
    
    // MARK: - Picker View Delegate Methods
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        
        let format = availableVideoFormats[row]
        return videoFormatDescription(of: format)
    }
    
    private var selectedVideoFormat: AVCaptureDevice.Format?
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        
        // Update label
        let format = availableVideoFormats[row]
        videoFormatLabel.text = videoFormatDescription(of: format)
        
        // Update value
        selectedVideoFormat = format
        
        // Persist value
        UserData.videoFormatPickerViewSelectedRow = row
    }
    
    // MARK: - Utilities
    
    /// Returns the available video formats.
    ///
    /// Do not call this method directly unless in `cameraSegmentedControlValueChanged(_:)`. Use the property `availableVideoFormats` instead.
    /// - Parameter multiCamOnly: Whether to return only formats that support multi-camera sessions.
    private func getAvailableVideoFormats(multiCamOnly: Bool) -> [AVCaptureDevice.Format] {
        
        let deviceType: AVCaptureDevice.DeviceType = multiCamOnly ? .builtInDualCamera : .builtInWideAngleCamera
        guard let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) else { return [] }
    
        let formats = device.formats
        if multiCamOnly {
            return formats.filter { $0.isMultiCamSupported }
        }
        return formats
    }
    
    private func videoFormatDescription(of format: AVCaptureDevice.Format) -> String {
        let dimension = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let frameRate = format.videoSupportedFrameRateRanges[0].maxFrameRate
        
        let dimensionString = "\(dimension.width)×\(dimension.height)"
        let frameRateString = "@\(Int(frameRate))fps"
        let binnedString = format.isVideoBinned ? " (binned)" : ""
        let string = dimensionString + frameRateString + binnedString
        return string
    }
}
