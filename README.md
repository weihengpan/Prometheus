# Prometheus

*Prometheus* is an open source iOS app for QR code-based screen-to-camera communication written in Swift for research purposes. 

It works by splitting file data into segments and encoding them into QR codes. The QR codes are then displayed by the sender one by one. Meanwhile, the receiver decodes the displayed QR codes with its camera. Finally, the file is reconstructed from the QR codes' payloads.

In experiments, *Prometheus* achieved a maximum stable throughput of 204 kbps.

## System Requirements

- iOS 13.0+
  - Simulators are NOT supported
- Xcode 11.6+
- Dual camera mode only supports devices with a *telephoto* camera and a wide angle camera.
  - For example, dual camera mode is not supported on iPhone 11 because it does not have a telephoto camera.

## Instructions

You will need two iOS devices as the sender and the receiver. It is recommended to use an iPad as the sender for best performance.

1. Open *Prometheus* on both devices.
2. On the sender side, select the file you want to send and set the parameters. On the receiver side, set the parameters accordingly. Press "Start" on both devices.
3. After some time, the sender will display a QR code containing information about the transfer. Position the receiver so that the entire QR code is visible inside the view frame. The QR code should be made as large as possible inside the frame, but please do leave some space between the code and the edge of the frame. You will see the file's name and size on the receiver if the QR code is successfully scanned. If you are using duplex mode, please also make sure that the receiver's flashlight is visible in the sender's view frame. It is recommended to support the two devices with stands to improve stability.
4. If you are using duplex mode, press "Start Calibration" on the sender. Otherwise, skip to step 6 instead.
5. The receiver's flashlight will flash a few times during calibration. If the calibration is successful, the "Start Sending" button will be enabled. Otherwise, please restart the transfer on both devices and try again.
6. Press "Start Receiving" on the receiver first, and then press "Start Sending" on the sender.
7. The transmission now starts. The number of received packets and the progress will be shown on the receiver.
8. If all packets are received, a share sheet will pop up on the receiver. You may then perform actions on the received file, such as importing it to another application. If a few packets are missing, you may try to resend the file again. To do so, press "Stop Sending" and then "Reset" on the sender. If a large number of packets are missing, please see Diagnosing Packet Losses.

## Diagnosing Packet Losses

Due to the nature of screen-to-camera communication, you are likely to encounter packet losses when using *Prometheus*. Here are some tips on mitigating packet losses:

- Mismatched parameters
  - While using single QR code mode or nested QR code mode, the receiver's frame rate should be at least twice the sender's frame rate.
  - While using alternating single QR code mode, the receiver's frame rate should be no less than the sender's frame rate.
  - If the QR codes are large (i.e. with large code versions), try using a video format with a higher resolution at the receiver side.
  - Both devices' modes must match. For example, when the sender is using nested QR code mode, the sender should use dual camera mode. When the sender is using duplex mode, the receiver must also use duplex mode.
- Device limitations
  - The receiver may heat up after running for some time. 
    - Their performance will suffer, and even they may be put into protection mode due to excessive heat. Since screen-to-camera communication is computationally intensive, heating is unavoidable despite *Prometheus* is highly optimized. 
    - Try to use a video format requiring less computation, such as those with a lower frame rate, a lower resolution or pixel binning. 
    - Using dual camera mode may also generate a large amount of heat. 
    - If you are running benchmarks or receiving large files, try leaving some time for the device to cool down between transfers.
  - If there are warnings about frame drops in the debug output, try using a video format with a lower frame rate or a lower resolution.
- Environmental factors
  - Make sure that the two devices are well supported and stationary.
  - Set the sender's screen brightness to maximum. This improves QR code readability.
  - Screen reflections will reduce QR code readability. Try reposition the two devices if there is strong glare on the sender's screen when viewed from the receiver.
  - Duplex mode works best when there is no bright regions in the sender's view frame. Try reposition the two devices if there are bright regions in the sender's view frame.

## License

MIT License. See [LICENSE](https://github.com/weihengpan/Prometheus/blob/master/LICENSE) for the full text.

The example file [Alice in Wonderland.txt](https://github.com/weihengpan/Prometheus/blob/master/Prometheus/Example%20Files/Alice%20in%20Wonderland.txt) is in the public domain.

## Acknowledgement

This software is an outcome of a research project at the Undergraduate Summer Research Internship Programme 2020 organized by the Faculty of Engineering of CUHK. 

You may use it for research purposes, subject to the terms and conditions imposed by the MIT License. 

You are welcome to contribute to or open issues in this repo.
