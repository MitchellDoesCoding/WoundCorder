import AVFoundation
import Combine

class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var capturedData: CameraCapturedData = CameraCapturedData()
    @Published var isDataAvailable: Bool = false

    var captureSession: AVCaptureSession
    var photoOutput: AVCapturePhotoOutput

    override init() {
        captureSession = AVCaptureSession()
        photoOutput = AVCapturePhotoOutput()
        super.init()

        setupSession()
    }

    private func setupSession() {
        captureSession.beginConfiguration()

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Unable to access the camera.")
            return
        }

        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(videoDeviceInput) {
                captureSession.addInput(videoDeviceInput)
            }

            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
        } catch {
            print("Error setting up camera: \(error)")
        }

        captureSession.commitConfiguration()
    }

    func startStream() {
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }

    func stopStream() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    func capturePhoto() {
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isHighResolutionPhotoEnabled = true
        photoSettings.flashMode = .auto

        photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            print("Failed to retrieve image data.")
            return
        }

        // Handle image data here
        print("Captured photo of size: \(imageData.count) bytes")
    }
}

import Photos

extension CameraController {
    func savePhotoToLibrary(imageData: Data) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                print("Photo library access denied.")
                return
            }

            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: imageData, options: options)
            }) { success, error in
                if success {
                    print("Photo saved successfully.")
                } else {
                    print("Failed to save photo: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
}


