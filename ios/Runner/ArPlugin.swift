// Pont Flutter ↔ mode AR natif (canal « kitchinox/ar »).
//   supported → Bool : LiDAR (scan de pièce possible ; l'app demande iOS 18)
//   open {path, name, w, d} → Bool : ouvre le scan en plein écran avec la scène USDZ écrite par Flutter

import Flutter
import SwiftUI
import UIKit

final class ArPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "kitchinox/ar", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(ArPlugin(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "supported":
            DispatchQueue.main.async { result(ArModel.canScan) }
        case "open":
            guard let a = call.arguments as? [String: Any], let path = a["path"] as? String else { return result(false) }
            let name = a["name"] as? String ?? "Cuisine"
            let w = (a["w"] as? NSNumber)?.floatValue ?? 0, d = (a["d"] as? NSNumber)?.floatValue ?? 0
            DispatchQueue.main.async {
                result(Self.present(URL(fileURLWithPath: path), name: name, room: w > 0 && d > 0 ? SIMD2(w, d) : nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @MainActor
    private static func present(_ url: URL, name: String, room: SIMD2<Float>?) -> Bool {
        guard ArModel.canScan, let top = topController() else { return false }
        let model = ArModel(sceneURL: url, name: name, projectRoom: room)
        let host = UIHostingController(rootView: ArRootView().environmentObject(model))
        host.modalPresentationStyle = .fullScreen
        model.onClose = { [weak host] in host?.dismiss(animated: true) }
        top.present(host, animated: true)
        return true
    }

    /// Contrôleur affiché au premier plan (celui de Flutter, ou une fenêtre ouverte par-dessus).
    @MainActor
    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var c = window?.rootViewController
        while let p = c?.presentedViewController { c = p }
        return c
    }
}
