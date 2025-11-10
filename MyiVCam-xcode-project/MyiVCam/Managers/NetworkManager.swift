import Foundation
import SocketIO

protocol NetworkManagerDelegate: AnyObject {
    func networkManager(didReceiveRemoteSDP sdp: String, type: String)
    func networkManager(didReceiveICECandidate candidate: [String: Any])
    func networkManagerStatusChanged(connected: Bool)
}

final class NetworkManager {
    weak var delegate: NetworkManagerDelegate?

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private(set) var isConnected = false

    func connect(to hostPort: String) {
        // Exemple: 192.168.1.10:3000
        guard let url = URL(string: "http://\(hostPort)") else { return }
        manager = SocketManager(socketURL: url, config: [.log(true), .compress])
        socket = manager?.defaultSocket

        socket?.on(clientEvent: .connect) { [weak self] _, _ in
            self?.isConnected = true
            self?.delegate?.networkManagerStatusChanged(connected: true)
            self?.announceSender()
        }
        socket?.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.isConnected = false
            self?.delegate?.networkManagerStatusChanged(connected: false)
        }

        socket?.on("webrtc-offer") { [weak self] data, _ in
            if let dict = data.first as? [String: Any],
               let sdp = dict["sdp"] as? String {
                self?.delegate?.networkManager(didReceiveRemoteSDP: sdp, type: "offer")
            }
        }
        socket?.on("webrtc-answer") { [weak self] data, _ in
            if let dict = data.first as? [String: Any],
               let sdp = dict["sdp"] as? String {
                self?.delegate?.networkManager(didReceiveRemoteSDP: sdp, type: "answer")
            }
        }
        socket?.on("webrtc-ice") { [weak self] data, _ in
            if let dict = data.first as? [String: Any] {
                self?.delegate?.networkManager(didReceiveICECandidate: dict)
            }
        }

        socket?.connect()
    }

    func disconnect() {
        socket?.disconnect()
        isConnected = false
    }

    func sendOffer(sdp: String) { socket?.emit("webrtc-offer", ["sdp": sdp]) }
    func sendAnswer(sdp: String) { socket?.emit("webrtc-answer", ["sdp": sdp]) }
    func sendICE(candidate: [String: Any]) { socket?.emit("webrtc-ice", candidate) }

    // MJPEG
    func sendMJPEGFrame(base64JPEG: String) {
        socket?.emit("mjpeg-frame", ["image": base64JPEG])
    }

    func announceSender() {
        socket?.emit("sender-join", ["role": "ios"])
    }
}