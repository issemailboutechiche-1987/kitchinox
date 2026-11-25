// Étapes 2 à 4 : la cuisine dans la vraie pièce (RealityKit, même ARSession que le scan).
// Placement : calée automatiquement sur le coin qui ressemble le plus au projet, puis ajustable
// (glisser pour déplacer, deux doigts pour tourner, coin suivant, quart de tour), échelle libre en option.
// Show : murs scannés masqués, cuisine opaque qui apparaît en fondu, occlusion par le maillage LiDAR
// et par les personnes, lumière de la pièce réelle.

import ARKit
import Combine
import RealityKit
import RoomPlan
import SwiftUI

@MainActor
final class StageController: ObservableObject {
    @Published private(set) var loaded = false
    @Published private(set) var info = ""
    @Published private(set) var cornerCount = 0
    @Published private(set) var cornerIndex = 0

    weak var arView: ARView?
    private let anchor = AnchorEntity(world: .zero)
    private let holder = ModelEntity() // reçoit les gestes ; la cuisine est son enfant
    private var kitchen: Entity?
    private let worldAnchor = AnchorEntity(world: .zero) // murs scannés, en repère monde
    private var outline = Entity()
    private var corners: [CornerFrame] = []
    private var gestures: [EntityGestureRecognizer] = []
    private var loading: AnyCancellable?
    private var fade: Timer?
    private var projectRoom: SIMD2<Float>?

    // MARK: - Vue

    func attach(_ view: ARView) {
        guard arView !== view else { return }
        arView = view
        view.scene.addAnchor(anchor)
        view.scene.addAnchor(worldAnchor)
        anchor.addChild(holder)
        worldAnchor.addChild(outline)
    }

    /// Session : suivi du monde + maillage LiDAR (occlusion), lumière réelle, personnes devant la cuisine.
    func configure(_ session: ARSession) {
        let c = ARWorldTrackingConfiguration()
        c.planeDetection = [.horizontal]
        c.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { c.sceneReconstruction = .mesh }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            c.frameSemantics.insert(.personSegmentationWithDepth)
        }
        // pas de remise à zéro : le repère du scan est gardé
        session.run(c)
    }

    // MARK: - Scène

    func load(_ url: URL?) {
        kitchen?.removeFromParent()
        kitchen = nil
        loaded = false
        guard let url else { return }
        loading = Entity.loadAsync(contentsOf: url).sink { [weak self] done in
            if case let .failure(e) = done { self?.info = "Cuisine illisible : \(e.localizedDescription)" }
        } receiveValue: { [weak self] e in
            guard let self else { return }
            self.kitchen = e
            self.holder.addChild(e)
            // zone de toucher pour les gestes : la boîte de la cuisine
            let b = e.visualBounds(relativeTo: self.holder)
            self.holder.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: b.extents).offsetBy(translation: b.center)])
            self.loaded = true
        }
    }

    // MARK: - Placement

    func beginPlacing(room: CapturedRoom?, project: SIMD2<Float>?) {
        projectRoom = project
        if let room {
            corners = RoomAlignment.corners(room, project: project)
            drawOutline(room)
        } else {
            corners = []
        }
        cornerCount = corners.count
        cornerIndex = 0
        applyCorner()
        outline.isEnabled = true
        setOpacity(0.78)
        arView?.environment.sceneUnderstanding.options.remove(.occlusion)
        enableGestures(true)
    }

    func nextCorner() {
        guard !corners.isEmpty else { return }
        cornerIndex = (cornerIndex + 1) % corners.count
        applyCorner()
    }

    func quarterTurn() {
        holder.transform.rotation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0]) * holder.transform.rotation
    }

    func setScale(_ s: Float) { holder.transform.scale = SIMD3(repeating: s) }

    private func applyCorner() {
        holder.transform = .identity
        if corners.indices.contains(cornerIndex) {
            let c = corners[cornerIndex]
            anchor.transform = Transform(matrix: c.transform)
            var t = String(format: "Calée sur le coin %d / %d : mur de %.2f m", cornerIndex + 1, corners.count, c.wallLength)
            if let p = projectRoom { t += String(format: " (projet %.2f m)", p.x / 1000) }
            info = t
        } else {
            // sans scan exploitable : devant l'appareil, au sol supposé à 1,4 m sous les yeux
            if let cam = arView?.cameraTransform {
                var m = matrix_identity_float4x4
                let fwd = -SIMD3<Float>(cam.matrix.columns.2.x, 0, cam.matrix.columns.2.z)
                m.columns.3 = SIMD4(cam.translation + simd_normalize(fwd) * 1.5 - SIMD3(0, 1.4, 0), 1)
                anchor.transform = Transform(matrix: m)
            }
            info = "Aucun coin trouvé : placez la cuisine à la main"
        }
    }

    /// Murs scannés : panneaux bleutés translucides, et sol.
    private func drawOutline(_ room: CapturedRoom) {
        outline.removeFromParent()
        outline = Entity()
        worldAnchor.addChild(outline)
        var mat = UnlitMaterial(color: UIColor(red: 0.35, green: 0.7, blue: 1, alpha: 0.22))
        mat.blending = .transparent(opacity: 0.22)
        for w in room.walls {
            let box = MeshResource.generateBox(size: [w.dimensions.x, w.dimensions.y, 0.01])
            let e = ModelEntity(mesh: box, materials: [mat])
            e.transform = Transform(matrix: w.transform)
            outline.addChild(e)
        }
        var edge = UnlitMaterial(color: UIColor(red: 0.35, green: 0.7, blue: 1, alpha: 0.9))
        edge.blending = .transparent(opacity: 0.9)
        for w in RoomAlignment.flatWalls(room) {
            let len = w.length
            let line = ModelEntity(mesh: .generateBox(size: [len, 0.008, 0.02]), materials: [edge])
            line.position = (w.a + w.b) / 2 + SIMD3(0, 0.004, 0)
            let dir = simd_normalize(w.b - w.a)
            line.orientation = simd_quatf(angle: atan2(-dir.z, dir.x), axis: [0, 1, 0])
            outline.addChild(line)
        }
    }

    private func enableGestures(_ on: Bool) {
        if on, gestures.isEmpty, let v = arView {
            gestures = v.installGestures([.translation, .rotation], for: holder)
        }
        for g in gestures { g.isEnabled = on }
    }

    // MARK: - Show

    func beginShow() {
        enableGestures(false)
        outline.isEnabled = false
        arView?.environment.sceneUnderstanding.options.insert(.occlusion)
        // apparition en fondu
        setOpacity(0)
        fade?.invalidate()
        let t0 = Date()
        fade = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] t in
            let k = Float(min(1, Date().timeIntervalSince(t0) / 1.6))
            Task { @MainActor in
                self?.setOpacity(k * k * (3 - 2 * k))
                if k >= 1 { t.invalidate() }
            }
        }
    }

    private func setOpacity(_ o: Float) {
        holder.components.set(OpacityComponent(opacity: o))
    }

    /// Photo de la vue AR, rangée dans Photos.
    func snapshot(done: @escaping (Bool) -> Void) {
        arView?.snapshot(saveToHDR: false) { image in
            guard let image else { return done(false) }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            done(true)
        }
    }
}

/// La vue RealityKit branchée sur la session partagée.
struct StageView: UIViewRepresentable {
    @EnvironmentObject var model: AppModel
    let stage: StageController

    func makeUIView(context: Context) -> ARView {
        let v = model.arView
        stage.attach(v)
        stage.configure(model.session)
        return v
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
