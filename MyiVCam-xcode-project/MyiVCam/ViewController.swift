import UIKit
import AVFoundation

final class ViewController: UIViewController {

    private let hostField = UITextField()
    private let connectButton = UIButton(type: .system)
    private let startStopButton = UIButton(type: .system)
    private let modeSegment = UISegmentedControl(items: ["WebRTC", "MJPEG", "RTMP"])
    private let statusLabel = UILabel()
    private let statsLabel = UILabel()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private let captureManager = CaptureManager()
    private let networkManager = NetworkManager()
    private let webRTCManager = WebRTCManager()
    private var mjpegStreamer: MJPEGStreamer?
    private let rtmpStreamer = RTMPStreamer()

    private var currentMode = 0
    private var isStreaming = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "My iVCam"

        setupUI()
        requestPermissions()
        configureManagers()
    }

    private func setupUI() {
        hostField.placeholder = "PC IP:port (ex: 192.168.1.10:3000)"
        hostField.borderStyle = .roundedRect
        hostField.autocapitalizationType = .none

        connectButton.setTitle("Connect", for: .normal)
        connectButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)

        startStopButton.setTitle("Start", for: .normal)
        startStopButton.addTarget(self, action: #selector(startStopTapped), for: .touchUpInside)

        modeSegment.selectedSegmentIndex = 0
        modeSegment.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        statusLabel.text = "Status: Idle"
        statsLabel.text = "Stats: -"
        statusLabel.numberOfLines = 0
        statsLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [hostField, connectButton, startStopButton, modeSegment, statusLabel, statsLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if !granted {
                DispatchQueue.main.async { self.statusLabel.text = "Camera permission denied." }
            }
        }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    private func configureManagers() {
        captureManager.delegate = self
        networkManager.delegate = self
        webRTCManager.delegate = self

        captureManager.setup()
        previewLayer = captureManager.makePreviewLayer()
        if let pl = previewLayer {
            pl.frame = CGRect(x: 16, y: 340, width: self.view.bounds.width - 32, height: 300)
            pl.cornerRadius = 8
            pl.masksToBounds = true
            self.view.layer.addSublayer(pl)
        }
        mjpegStreamer = MJPEGStreamer(network: networkManager)
        rtmpStreamer.configure()
    }

    @objc private func connectTapped() {
        guard let host = hostField.text, !host.isEmpty else {
            statusLabel.text = "Enter host:port"
            return
        }
        // Pas nécessaire en RTMP pur, mais inoffensif
        networkManager.connect(to: host)
    }

    @objc private func startStopTapped() {
        isStreaming ? stopStreaming() : startStreaming()
    }

    @objc private func modeChanged() {
        currentMode = modeSegment.selectedSegmentIndex
    }

    private func startStreaming() {
        switch currentMode {
        case 0: // WebRTC
            guard networkManager.isConnected else {
                statusLabel.text = "Connect first."
                return
            }
            captureManager.start()
            webRTCManager.setupPeer()
            webRTCManager.createOffer()
        case 1: // MJPEG
            guard networkManager.isConnected else {
                statusLabel.text = "Connect first."
                return
            }
            captureManager.start()
            statusLabel.text = "MJPEG mode starting..."
        case 2: // RTMP (HaishinKit capture interne, ne pas démarrer notre capture)
            if let host = hostField.text {
                let baseHost = host.components(separatedBy: ":").first ?? host
                let url = "rtmp://\(baseHost):1935/live"
                rtmpStreamer.start(url: url, key: "live")
                statusLabel.text = "RTMP publishing..."
            } else {
                statusLabel.text = "Enter PC IP first."
                return
            }
        default: break
        }
        isStreaming = true
        startStopButton.setTitle("Stop", for: .normal)
    }

    private func stopStreaming() {
        captureManager.stop()
        webRTCManager.close()
        rtmpStreamer.stop()
        statusLabel.text = "Stopped."
        statsLabel.text = "Stats: -"
        isStreaming = false
        startStopButton.setTitle("Start", for: .normal)
    }
}

extension ViewController: CaptureManagerDelegate {
    func captureManager(didOutput pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        switch currentMode {
        case 0:
            webRTCManager.pushFrame(pixelBuffer: pixelBuffer, time: presentationTime)
        case 1:
            mjpegStreamer?.send(pixelBuffer: pixelBuffer)
            if let s = mjpegStreamer?.currentStats() {
                DispatchQueue.main.async {
                    self.statsLabel.text = String(format: "MJPEG kbps: %.1f fps: %.1f", s.kbps, s.fps)
                }
            }
        case 2:
            break // RTMP géré en interne
        default: break
        }
    }

    func captureManager(didFail error: Error) {
        DispatchQueue.main.async { self.statusLabel.text = "Capture error: \(error.localizedDescription)" }
    }
}

extension ViewController: NetworkManagerDelegate {
    func networkManager(didReceiveRemoteSDP sdp: String, type: String) {
        webRTCManager.setRemote(sdp: sdp, type: type)
    }
    func networkManager(didReceiveICECandidate candidate: [String : Any]) {
        webRTCManager.addICECandidate(candidate)
    }
    func networkManagerStatusChanged(connected: Bool) {
        DispatchQueue.main.async {
            self.statusLabel.text = connected ? "Socket connected" : "Socket disconnected"
        }
    }
}

extension ViewController: WebRTCManagerDelegate {
    func webRTCManagerDidChange(state: ConnectionState) {
        DispatchQueue.main.async { self.statusLabel.text = "WebRTC: \(state.rawValue)" }
    }
    func webRTCManagerDidGenerateLocalSDP(type: RTCSdpType, sdp: String) {
        type == .offer ? networkManager.sendOffer(sdp: sdp) : networkManager.sendAnswer(sdp: sdp)
    }
    func webRTCManagerDidGenerateICE(candidate: [String : Any]) {
        networkManager.sendICE(candidate: candidate)
    }
    func webRTCManagerStats(bitrateKbps: Double, fps: Double) {
        DispatchQueue.main.async {
            self.statsLabel.text = String(format: "WebRTC kbps: %.1f fps*: %.1f", bitrateKbps, fps)
        }
    }
    func webRTCManagerError(_ error: Error) {
        DispatchQueue.main.async { self.statusLabel.text = "WebRTC error: \(error.localizedDescription)" }
    }
}