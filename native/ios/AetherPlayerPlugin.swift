import AVFoundation
import Capacitor
import AetherEngine
import UIKit

@objc(AetherPlayerPlugin)
public final class AetherPlayerPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "AetherPlayerPlugin"
    public let jsName = "AetherPlayer"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "load", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setFrame", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "play", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pause", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "seek", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "close", returnType: CAPPluginReturnPromise)
    ]

    private var engine: AetherEngine?
    private var surface: AetherPlayerView?
    private var clockTimer: Timer?
    private var endedSent = false

    @objc func load(_ call: CAPPluginCall) {
        guard let rawURL = call.getString("url"),
              let url = URL(string: rawURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            call.reject("A valid HTTP(S) stream URL is required.")
            return
        }

        Task { @MainActor in
            do {
                closeCurrentSession()
                let player = try AetherEngine()
                let videoSurface = AetherPlayerView(frame: .zero)
                guard let host = self.bridge?.viewController?.view else {
                    call.reject("VYRO player view is unavailable.")
                    return
                }
                videoSurface.translatesAutoresizingMaskIntoConstraints = true
                videoSurface.autoresizingMask = []
                videoSurface.isUserInteractionEnabled = false
                host.addSubview(videoSurface)
                self.engine = player
                self.surface = videoSurface
                player.bind(view: videoSurface)

                if let frame = call.options["frame"] as? [String: Any] {
                    self.applyFrame(frame)
                }
                let startPosition = call.getDouble("startPosition") ?? 0
                try await player.load(
                    url: url,
                    startPosition: max(0, startPosition)
                )
                player.play()
                self.startClock()
                call.resolve(["started": true, "engine": "AetherEngine"])
            } catch {
                self.closeCurrentSession()
                call.reject("Native playback failed: \(error.localizedDescription)")
            }
        }
    }

    @objc func setFrame(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let frame = call.options["frame"] as? [String: Any] else {
                call.reject("A video frame is required.")
                return
            }
            self.applyFrame(frame)
            call.resolve()
        }
    }

    @objc func play(_ call: CAPPluginCall) {
        Task { @MainActor in
            self.engine?.play()
            call.resolve()
        }
    }

    @objc func pause(_ call: CAPPluginCall) {
        Task { @MainActor in
            self.engine?.pause()
            call.resolve()
        }
    }

    @objc func seek(_ call: CAPPluginCall) {
        Task { @MainActor in
            guard let engine = self.engine else {
                call.reject("No native video is loaded.")
                return
            }
            let seconds = max(0, call.getDouble("seconds") ?? 0)
            await engine.seek(to: seconds)
            call.resolve()
        }
    }

    @objc func close(_ call: CAPPluginCall) {
        Task { @MainActor in
            self.closeCurrentSession()
            call.resolve()
        }
    }

    @MainActor
    private func applyFrame(_ values: [String: Any]) {
        guard let surface = surface else { return }
        let x = (values["x"] as? NSNumber)?.doubleValue ?? 0
        let y = (values["y"] as? NSNumber)?.doubleValue ?? 0
        let width = (values["width"] as? NSNumber)?.doubleValue ?? 0
        let height = (values["height"] as? NSNumber)?.doubleValue ?? 0
        guard width > 0, height > 0 else { return }
        surface.frame = CGRect(x: x, y: y, width: width, height: height)
    }

    @MainActor
    private func startClock() {
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let engine = self.engine else { return }
            let current = engine.clock.currentTime
            let duration = engine.duration
            self.notifyListeners("timeUpdate", data: [
                "currentTime": current.isFinite ? current : 0,
                "duration": duration.isFinite ? duration : 0,
                "state": String(describing: engine.state)
            ])
            if duration > 0, current >= duration - 0.5, !self.endedSent {
                self.endedSent = true
                self.notifyListeners("ended", data: [:])
            }
        }
    }

    @MainActor
    private func closeCurrentSession() {
        clockTimer?.invalidate()
        clockTimer = nil
        if let engine, let surface {
            engine.stop()
            engine.unbind(view: surface)
        }
        surface?.removeFromSuperview()
        surface = nil
        engine = nil
        endedSent = false
    }

    deinit {
        clockTimer?.invalidate()
    }
}
