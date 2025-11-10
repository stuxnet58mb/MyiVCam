import Foundation
import UIKit
import AVFoundation

final class MJPEGStreamer {
    private let network: NetworkManager
    private let bitrate = BitrateCalculator()

    init(network: NetworkManager) { self.network = network }

    func send(pixelBuffer: CVPixelBuffer) {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let ctx = CIContext(options: nil)
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return }
        let img = UIImage(cgImage: cg)
        guard let data = img.jpegData(compressionQuality: 0.6) else { return }
        network.sendMJPEGFrame(base64JPEG: data.base64EncodedString())
        bitrate.addFrame(sizeInBytes: data.count)
    }

    func currentStats() -> (kbps: Double, fps: Double) {
        (bitrate.kbps, bitrate.fps)
    }
}