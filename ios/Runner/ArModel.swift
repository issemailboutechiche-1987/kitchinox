// Mode AR de kitchinox (iPad, iOS 18 et LiDAR) : la cuisine conçue dans l'app, posée à l'échelle 1:1 dans la vraie pièce.
// Ouvert par Flutter (ArPlugin, canal « kitchinox/ar ») en plein écran par-dessus l'app :
// 1. scan complet de la pièce (RoomPlan) → 2. placement (calage automatique sur les murs scannés, ajustable,
// échelle en option) → 3. valider → 4. le show (RealityKit). La croix ramène à kitchinox.
//
// La session du scan RoomPlan est reprise par la vue RealityKit : la pièce scannée et la cuisine partagent le même repère.

import ARKit
import Foundation
import RealityKit
import RoomPlan
import simd

enum ArPhase: Equatable {
    case scanning // scan RoomPlan en cours
    case placing // la cuisine est posée : on la cale, on la tourne, on règle l'échelle
    case show // validé : la cuisine dans la pièce
}

@MainActor
final class ArModel: ObservableObject {
    @Published var phase: ArPhase = .scanning
    @Published var message: String?
    let sceneURL: URL
    let sceneName: String
    /// Dimensions de la pièce du projet (mm), pour choisir le bon coin automatiquement.
    let projectRoom: SIMD2<Float>?
    @Published private(set) var room: CapturedRoom?
    /// Échelle : 1 = taille réelle. Modifiable seulement si l'utilisateur la déverrouille.
    @Published var scale: Float = 1
    @Published var scaleUnlocked = false
    /// Ferme le mode AR (retour à kitchinox).
    var onClose: () -> Void = {}

    init(sceneURL: URL, name: String, projectRoom: SIMD2<Float>?) {
        self.sceneURL = sceneURL
        sceneName = name
        self.projectRoom = projectRoom
    }

    /// La vue RealityKit, créée une fois ; après le scan, elle prend la session du scan.
    lazy var arView: ARView = {
        let v = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        v.renderOptions.insert(.disableMotionBlur)
        return v
    }()

    var session: ARSession { arView.session }

    /// L'appareil sait-il scanner une pièce (LiDAR) ?
    static var canScan: Bool { ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) && RoomCaptureSession.isSupported }

    /// Fin du scan : la vue RealityKit reprend la session du scan, la pièce et la cuisine partagent le même repère.
    func finishScan(_ captured: CapturedRoom, session scanSession: ARSession?) {
        room = captured
        if let s = scanSession, s !== arView.session { arView.session = s }
        phase = .placing
    }

    func validate() { phase = .show }
    func replace() { phase = .placing }

    func rescan() {
        room = nil
        scale = 1
        scaleUnlocked = false
        phase = .scanning
    }

    func close() {
        session.pause()
        onClose()
    }
}
