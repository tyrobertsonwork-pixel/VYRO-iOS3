import Foundation
import UIKit
import Capacitor

@objc(VyroVlcPlugin)
public class VyroVlcPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "VyroVlcPlugin"
    public let jsName = "VyroVlc"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "play", returnType: CAPPluginReturnPromise)
    ]

    @objc func play(_ call: CAPPluginCall) {
        guard let s = call.getString("url"), let url = URL(string: s) else {
            call.reject("Invalid URL")
            return
        }
        let title = call.getString("title") ?? ""
        let start = call.getDouble("start") ?? 0
        let hasNext = call.getBool("hasNext") ?? false

        DispatchQueue.main.async {
            let vc = VyroPlayerViewController(url: url, title: title, start: start, hasNext: hasNext)
            vc.modalPresentationStyle = .fullScreen
            vc.onProgress = { [weak self] t, d in
                self?.notifyListeners("progress", data: ["t": t, "d": d])
            }
            vc.onClose = { [weak self] t, d, ended, next in
                self?.notifyListeners("closed", data: ["t": t, "d": d, "ended": ended, "next": next])
            }
            var top = self.bridge?.viewController
            while let p = top?.presentedViewController { top = p }
            guard let host = top else {
                call.reject("No view controller")
                return
            }
            host.present(vc, animated: true)
            call.resolve()
        }
    }
}
