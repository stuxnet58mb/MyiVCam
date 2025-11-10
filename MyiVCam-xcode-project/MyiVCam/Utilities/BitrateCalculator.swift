import Foundation

final class BitrateCalculator {
    private var bytes = 0
    private var frames = 0
    private var last = Date().timeIntervalSince1970
    private(set) var kbps: Double = 0
    private(set) var fps: Double = 0

    func addFrame(sizeInBytes: Int) {
        bytes += sizeInBytes
        frames += 1
        let now = Date().timeIntervalSince1970
        let dt = now - last
        if dt >= 1 {
            kbps = (Double(bytes) * 8.0) / 1000.0 / dt
            fps = Double(frames) / dt
            bytes = 0; frames = 0; last = now
        }
    }
}