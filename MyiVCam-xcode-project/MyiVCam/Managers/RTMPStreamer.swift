import Foundation
#if canImport(HaishinKit)
import HaishinKit
import AVFoundation
import VideoToolbox

final class RTMPStreamer {
    private let connection = RTMPConnection()
    private lazy var stream = RTMPStream(connection: connection)
    private var isPublishing = false

    func configure() {
        // Attachements directs (HaishinKit capture en propre)
        stream.attachAudio(AVCaptureDevice.default(for: .audio)) { error in
            if let e = error { print("Audio attach error: \(e)") }
        }
        stream.attachCamera(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)) { error in
            if let e = error { print("Camera attach error: \(e)") }
        }
        stream.captureSettings = [
            "fps": 30,
            "sessionPreset": AVCaptureSession.Preset.high,
            "continuousAutofocus": true,
            "continuousExposure": true
        ]
        stream.videoSettings = [
            "width": 1280,
            "height": 720,
            "profileLevel": kVTProfileLevel_H264_High_4_1,
            "bitrate": 1_000_000,
            "maxKeyFrameIntervalDuration": 2
        ]
    }

    func start(url: String, key: String = "live") {
        guard !isPublishing else { return }
        connection.connect(url)
        stream.publish(key)
        isPublishing = true
    }

    func stop() {
        guard isPublishing else { return }
        stream.close()
        connection.close()
        isPublishing = false
    }
}
#else
final class RTMPStreamer {
    func configure() {}
    func start(url: String, key: String = "live") { print("HaishinKit not available") }
    func stop() {}
}
#endif