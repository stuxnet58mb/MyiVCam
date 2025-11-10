import UIKit
import AVFoundation

protocol CaptureManagerDelegate: AnyObject {
    func captureManager(didOutput pixelBuffer: CVPixelBuffer, presentationTime: CMTime)
    func captureManager(didFail error: Error)
}

final class CaptureManager: NSObject {
    weak var delegate: CaptureManagerDelegate?

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "capture.queue")
    private var isRunning = false

    func setup(videoPosition: AVCaptureDevice.Position = .back) {
        session.beginConfiguration()
        session.sessionPreset = .high

        // Vidéo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: videoPosition) else {
            delegate?.captureManager(didFail: NSError(domain: "CaptureManager", code: -1,
                                                      userInfo: [NSLocalizedDescriptionKey: "Caméra introuvable"]))
            session.commitConfiguration()
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch { delegate?.captureManager(didFail: error) }

        // Audio (optionnel)
        if let mic = AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: mic)
                if session.canAddInput(audioInput) { session.addInput(audioInput) }
            } catch { print("Audio input error: \(error)") }
        }

        // Sortie vidéo
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            (kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        // Sortie audio (si implémentation audio custom un jour)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }

        session.commitConfiguration()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        queue.async { self.session.startRunning() }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        queue.async { self.session.stopRunning() }
    }

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }
}

extension CaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        delegate?.captureManager(didOutput: pb, presentationTime: ts)
    }
}