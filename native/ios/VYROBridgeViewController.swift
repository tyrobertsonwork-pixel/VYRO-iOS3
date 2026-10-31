import Capacitor

@objc(VYROBridgeViewController)
final class VYROBridgeViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        bridge?.registerPluginType(AetherPlayerPlugin.self)
    }
}
