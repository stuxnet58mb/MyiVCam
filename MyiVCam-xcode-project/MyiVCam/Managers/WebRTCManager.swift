import Foundation
import WebRTC
import AVFoundation

protocol WebRTCManagerDelegate: AnyObject {
    func webRTCManagerDidChange(state: ConnectionState)
    func webRTCManagerDidGenerateLocalSDP(type: RTCSdpType, sdp: String)
    func webRTCManagerDidGenerateICE(candidate: [String: Any])
    func webRTCManagerStats(bitrateKbps: Double, fps: Double)
    func webRTCManagerError(_ error: Error)
}

final class WebRTCManager: NSObject {
    weak var delegate: WebRTCManagerDelegate?

    private var factory: RTCPeerConnectionFactory!
    private var pc: RTCPeerConnection?
    private var videoSource: RTCVideoSource?
    private var videoTrack: RTCVideoTrack?
    private var audioTrack: RTCAudioTrack?
    private var statsTimer: Timer?

    private let rtcConfig: RTCConfiguration = {
        let c = RTCConfiguration()
        // LAN pur par défaut: pas de STUN/TURN externe
        // c.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        c.sdpSemantics = .unifiedPlan
        return c
    }()

    override init() {
        super.init()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        // On laissera la préférence H264 via SDP munging
        factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
    }

    func setupPeer() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        pc = factory.peerConnection(with: rtcConfig, constraints: constraints, delegate: self)
        createMediaSenders()
        startStats()
        delegate?.webRTCManagerDidChange(state: .connecting)
    }

    private func createMediaSenders() {
        videoSource = factory.videoSource()
        videoTrack = factory.videoTrack(with: videoSource!, trackId: "video0")

        let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")

        // Unified Plan: ajouter des transceivers
        if let vt = videoTrack {
            let _ = pc?.add(vt, streamIds: ["stream0"])
        }
        if let at = audioTrack {
            let _ = pc?.add(at, streamIds: ["stream0"])
        }
    }

    func createOffer() {
        let cons = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "false",
                                                              "OfferToReceiveVideo": "false"],
                                       optionalConstraints: nil)
        pc?.offer(for: cons) { [weak self] sdp, err in
            guard let self else { return }
            if let e = err { self.delegate?.webRTCManagerError(e); return }
            guard let sdp = sdp else { return }
            // Préférer H264 dans le SDP
            let munged = self.preferH264(sdp: sdp.sdp)
            let local = RTCSessionDescription(type: .offer, sdp: munged)
            self.pc?.setLocalDescription(local, completionHandler: { error in
                if let e2 = error { self.delegate?.webRTCManagerError(e2); return }
                self.delegate?.webRTCManagerDidGenerateLocalSDP(type: .offer, sdp: munged)
            })
        }
    }

    func createAnswer() {
        let cons = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        pc?.answer(for: cons) { [weak self] sdp, err in
            guard let self else { return }
            if let e = err { self.delegate?.webRTCManagerError(e); return }
            guard let sdp = sdp else { return }
            let munged = self.preferH264(sdp: sdp.sdp)
            let local = RTCSessionDescription(type: .answer, sdp: munged)
            self.pc?.setLocalDescription(local, completionHandler: { error in
                if let e2 = error { self.delegate?.webRTCManagerError(e2); return }
                self.delegate?.webRTCManagerDidGenerateLocalSDP(type: .answer, sdp: munged)
            })
        }
    }

    func setRemote(sdp remote: String, type: String) {
        let t: RTCSdpType = (type == "offer") ? .offer : .answer
        let desc = RTCSessionDescription(type: t, sdp: remote)
        pc?.setRemoteDescription(desc, completionHandler: { [weak self] error in
            if let e = error { self?.delegate?.webRTCManagerError(e); return }
            if t == .offer { self?.createAnswer() }
        })
    }

    func addICECandidate(_ dict: [String: Any]) {
        guard let sdp = dict["candidate"] as? String,
              let sdpMLineIndex = dict["sdpMLineIndex"] as? Int32,
              let sdpMid = dict["sdpMid"] as? String else { return }
        pc?.add(RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid))
    }

    func pushFrame(pixelBuffer: CVPixelBuffer, time: CMTime) {
        let rtcPB = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let frame = RTCVideoFrame(buffer: rtcPB, rotation: ._0,
                                  timeStampNs: Int64(CMTimeGetSeconds(time) * 1_000_000_000))
        videoSource?.capturer(nil, didCapture: frame)
    }

    private func preferH264(sdp: String) -> String {
        // SDP munging: faire passer H264 en premier dans m=video + rtpmap
        // Simplifié: déplace les payload types H264 (packetization-mode=1) devant.
        let lines = sdp.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var mLineIndex: Int?
        var h264Payloads = [String]()
        var rtpmapForPayload = [String: String]()
        var fmtpForPayload = [String: String]()

        for (i, l) in lines.enumerated() {
            if l.hasPrefix("m=video ") { mLineIndex = i }
            if l.hasPrefix("a=rtpmap:") && l.contains("H264") {
                if let pt = l.split(separator: ":").last?.split(separator: " ").first {
                    h264Payloads.append(String(pt))
                    rtpmapForPayload[String(pt)] = l
                }
            }
            if l.hasPrefix("a=fmtp:") && l.contains("packetization-mode=1") {
                if let pt = l.split(separator: ":").last?.split(separator: " ").first {
                    fmtpForPayload[String(pt)] = l
                }
            }
        }

        guard let mi = mLineIndex, !h264Payloads.isEmpty else { return sdp }
        var parts = lines[mi].split(separator: " ").map(String.init) // m= video <port> RTP/SAVPF PTs...
        guard parts.count > 3 else { return sdp }
        // Réordonner: H264 d’abord (conservant uniquement ceux avec fmtp p-mode=1 si présent)
        let pts = parts[3...]
        let h264First = h264Payloads.filter { fmtpForPayload[$0] != nil } + h264Payloads.filter { fmtpForPayload[$0] == nil }
        let others = pts.filter { !h264First.contains($0) }
        parts = Array(parts[0...2]) + h264First + others
        var newLines = lines
        newLines[mi] = parts.joined(separator: " ")
        return newLines.joined(separator: "\n")
    }

    func startStats() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true, block: { [weak self] _ in
            guard let pc = self?.pc else { return }
            pc.statistics { report in
                var kbps: Double = 0
                var fps: Double = 0
                for s in report.statistics where s.type == "outbound-rtp" {
                    if let bytesSent = s.values["bytesSent"] as? String, let br = Double(bytesSent) {
                        kbps = (br * 8.0) / 1000.0 // approx cumul
                    }
                    if let framesSent = s.values["framesSent"] as? String, let fr = Double(framesSent) {
                        fps = fr
                    }
                }
                self?.delegate?.webRTCManagerStats(bitrateKbps: kbps, fps: fps)
            }
        })
    }

    func close() {
        statsTimer?.invalidate()
        statsTimer = nil
        pc?.close()
        pc = nil
        delegate?.webRTCManagerDidChange(state: .disconnected)
    }
}

extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .connected, .completed: delegate?.webRTCManagerDidChange(state: .connected)
        case .disconnected, .failed: delegate?.webRTCManagerDidChange(state: .disconnected)
        default: break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let dict: [String: Any] = [
            "candidate": candidate.sdp,
            "sdpMLineIndex": candidate.sdpMLineIndex,
            "sdpMid": candidate.sdpMid ?? ""
        ]
        delegate?.webRTCManagerDidGenerateICE(candidate: dict)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}