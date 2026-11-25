// Étapes 2 à 4 : la cuisine dans la vraie pièce (RealityKit, session reprise du scan).
// Placement : calée automatiquement sur le coin qui ressemble le plus au projet, puis ajustable.
//   Outil Déplacer : un doigt glisse la cuisine au sol (elle suit le doigt), deux doigts la tournent
//   autour de son centre, flèches au centimètre (ou 10 cm) le long de ses axes, rotation fine de 1°.
//   Grilles : sol de la pièce (10 cm, traits forts tous les mètres), murs scannés (50 cm),
//   et l'empreinte de la cuisine en orange au sol : on voit exactement où elle tombe.
// Show : grilles et murs masqués, cuisine opaque qui apparaît en fondu, occlusion par le maillage LiDAR
// et par les personnes, lumière de la pièce réelle.

import ARKit
import Combine
import RealityKit
import RoomPlan
import SwiftUI
import UIKit

@MainActor
final class StageController: NSObject, ObservableObject {
    @Published private(set) var loaded = false
    @Published private(set) var info = ""
    @Published private(set) var cornerCount = 0
    @Published private(set) var cornerIndex = 0
    /// Pas des flèches de déplacement (m) : 1 cm ou 10 cm.
    @Published var step: Float = 0.01
    @Published var gridsVisible = true { didSet { grids.isEnabled = gridsVisible && placing } }

    weak var arView: ARView?
    private let anchor = AnchorEntity(world: .zero) // repère de la cuisine (coin A/C au sol)
    private let holder = Entity() // la cuisine et son empreinte ; reçoit l'échelle
    private let worldAnchor = AnchorEntity(world: .zero) // murs scannés et grilles, en repère monde
    private var kitchen: Entity?
    private var footprint = Entity()
    private var outline = Entity()
    private var grids = Entity()
    private var corners: [CornerFrame] = []
    private var floorY: Float = 0
    private var placing = false
    private var loading: AnyCancellable?
    private var fade: Timer?
    private var projectRoom: SIMD2<Float>?
    private var recognizers: [UIGestureRecognizer] = []
    private var panLast: SIMD3<Float>?

    // MARK: - Vue

    func attach(_ view: ARView) {
        guard arView !== view else { return }
        arView = view
        view.scene.addAnchor(anchor)
        view.scene.addAnchor(worldAnchor)
        anchor.addChild(holder)
        worldAnchor.addChild(outline)
        worldAnchor.addChild(grids)
        installTouch(view)
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
            self.drawFootprint(e)
            self.loaded = true
        }
    }

    /// Empreinte de la cuisine au sol : un cadre orange autour de tout ce qui est posé.
    private func drawFootprint(_ e: Entity) {
        footprint.removeFromParent()
        footprint = Entity()
        let b = e.visualBounds(relativeTo: holder)
        let x0 = b.min.x, x1 = b.max.x, z0 = b.min.z, z1 = b.max.z
        var mat = UnlitMaterial(color: UIColor(red: 1, green: 0.45, blue: 0.1, alpha: 0.95))
        mat.blending = .transparent(opacity: 0.95)
        let y: Float = 0.004
        for (a, c) in [(SIMD3(x0, y, z0), SIMD3(x1, y, z0)), (SIMD3(x1, y, z0), SIMD3(x1, y, z1)),
                       (SIMD3(x1, y, z1), SIMD3(x0, y, z1)), (SIMD3(x0, y, z1), SIMD3(x0, y, z0))] {
            footprint.addChild(Self.line(a, c, width: 0.018, material: mat))
        }
        holder.addChild(footprint)
        footprint.isEnabled = placing
    }

    // MARK: - Placement

    func beginPlacing(room: CapturedRoom?, project: SIMD2<Float>?) {
        placing = true
        projectRoom = project
        if let room {
            floorY = RoomAlignment.floorHeight(room)
            corners = RoomAlignment.corners(room, project: project)
            drawRoom(room)
        } else {
            corners = []
        }
        cornerCount = corners.count
        cornerIndex = 0
        applyCorner()
        outline.isEnabled = true
        grids.isEnabled = gridsVisible
        footprint.isEnabled = true
        setOpacity(0.78)
        arView?.environment.sceneUnderstanding.options.remove(.occlusion)
        for r in recognizers { r.isEnabled = true }
    }

    func nextCorner() {
        guard !corners.isEmpty else { return }
        cornerIndex = (cornerIndex + 1) % corners.count
        applyCorner()
    }

    func quarterTurn() { rotate(by: .pi / 2) }
    func rotateFine(_ degrees: Float) { rotate(by: degrees * .pi / 180) }

    /// Flèches : déplacement le long des axes de la cuisine (dx le long du mur A, dz vers la pièce).
    func nudge(dx: Float, dz: Float) {
        anchor.position += anchor.orientation.act(SIMD3(dx, 0, dz) * step)
    }

    func setScale(_ s: Float) { holder.scale = SIMD3(repeating: s) }

    private func applyCorner() {
        holder.transform = Transform(scale: holder.scale, rotation: simd_quatf(angle: 0, axis: [0, 1, 0]), translation: .zero)
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
                floorY = m.columns.3.y
            }
            info = "Aucun coin trouvé : placez la cuisine avec l'outil Déplacer"
        }
    }

    /// Tourne la cuisine autour du centre de son empreinte (et non de son coin).
    private func rotate(by angle: Float) {
        let center = kitchen.map { $0.visualBounds(relativeTo: anchor).center } ?? .zero
        let pivot = anchor.convert(position: SIMD3(center.x, 0, center.z), to: nil)
        let q = simd_quatf(angle: angle, axis: [0, 1, 0])
        anchor.orientation = q * anchor.orientation
        anchor.position = pivot + q.act(anchor.position - pivot)
    }

    // MARK: - Gestes : un doigt glisse au sol, deux doigts tournent

    private func installTouch(_ v: ARView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.maximumNumberOfTouches = 1
        let rot = UIRotationGestureRecognizer(target: self, action: #selector(onRotate(_:)))
        for r in [pan, rot] as [UIGestureRecognizer] {
            r.isEnabled = false
            v.addGestureRecognizer(r)
        }
        recognizers = [pan, rot]
    }

    /// Point du sol sous le doigt.
    private func floorPoint(_ p: CGPoint) -> SIMD3<Float>? {
        guard let v = arView, let ray = v.ray(through: p), ray.direction.y < -1e-3 else { return nil }
        let t = (floorY - ray.origin.y) / ray.direction.y
        return t > 0 ? ray.origin + ray.direction * t : nil
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        guard placing, let v = arView else { return }
        let p = floorPoint(g.location(in: v))
        switch g.state {
        case .began:
            panLast = p
        case .changed:
            if let p, let last = panLast {
                var d = p - last
                d.y = 0
                anchor.position += d
                panLast = p
            }
        default:
            panLast = nil
        }
    }

    @objc private func onRotate(_ g: UIRotationGestureRecognizer) {
        guard placing, g.state == .changed else { return }
        rotate(by: -Float(g.rotation))
        g.rotation = 0
    }

    // MARK: - Murs scannés et grilles

    private func drawRoom(_ room: CapturedRoom) {
        outline.removeFromParent()
        grids.removeFromParent()
        outline = Entity()
        grids = Entity()
        worldAnchor.addChild(outline)
        worldAnchor.addChild(grids)

        // murs : panneaux bleutés translucides, quadrillés tous les 50 cm
        var wallMat = UnlitMaterial(color: UIColor(red: 0.35, green: 0.7, blue: 1, alpha: 0.16))
        wallMat.blending = .transparent(opacity: 0.16)
        var wallLine = UnlitMaterial(color: UIColor(red: 0.55, green: 0.82, blue: 1, alpha: 0.55))
        wallLine.blending = .transparent(opacity: 0.55)
        for w in room.walls {
            let e = ModelEntity(mesh: .generateBox(size: [w.dimensions.x, w.dimensions.y, 0.01]), materials: [wallMat])
            e.transform = Transform(matrix: w.transform)
            outline.addChild(e)
            let g = Entity()
            g.transform = Transform(matrix: w.transform)
            let hw = w.dimensions.x / 2, hh = w.dimensions.y / 2
            var x = -hw
            while x <= hw + 1e-3 {
                g.addChild(Self.line([x, -hh, 0.008], [x, hh, 0.008], width: 0.006, material: wallLine))
                x += 0.5
            }
            var y = -hh
            while y <= hh + 1e-3 {
                g.addChild(Self.line([-hw, y, 0.008], [hw, y, 0.008], width: 0.006, material: wallLine))
                y += 0.5
            }
            grids.addChild(g)
        }

        // sol : quadrillage de 10 cm (traits forts tous les mètres) dans l'axe du coin principal, sur toute la pièce
        let walls = RoomAlignment.flatWalls(room)
        guard let axis = corners.first ?? walls.first.map({ CornerFrame(origin: $0.a, xAxis: simd_normalize($0.b - $0.a), wallLength: $0.length, sideLength: 0) }) else { return }
        let x = axis.xAxis, z = simd_normalize(simd_cross(x, [0, 1, 0]))
        let pts = walls.flatMap { [$0.a, $0.b] }
        let us = pts.map { simd_dot($0 - axis.origin, x) }, vs = pts.map { simd_dot($0 - axis.origin, z) }
        guard let u0 = us.min(), let u1 = us.max(), let v0 = vs.min(), let v1 = vs.max() else { return }
        var fine = UnlitMaterial(color: UIColor(white: 1, alpha: 0.22))
        fine.blending = .transparent(opacity: 0.22)
        var bold = UnlitMaterial(color: UIColor(white: 1, alpha: 0.6))
        bold.blending = .transparent(opacity: 0.6)
        let o = SIMD3(axis.origin.x, floorY + 0.002, axis.origin.z)
        let floor = Entity()
        var i = 0
        var u = (u0 / 0.1).rounded(.down) * 0.1
        while u <= u1 + 1e-3 {
            let strong = abs(u.truncatingRemainder(dividingBy: 1)) < 1e-3
            floor.addChild(Self.line(o + x * u + z * v0, o + x * u + z * v1, width: strong ? 0.008 : 0.003, material: strong ? bold : fine))
            u += 0.1
            i += 1
            if i > 400 { break }
        }
        var v = (v0 / 0.1).rounded(.down) * 0.1
        i = 0
        while v <= v1 + 1e-3 {
            let strong = abs(v.truncatingRemainder(dividingBy: 1)) < 1e-3
            floor.addChild(Self.line(o + x * u0 + z * v, o + x * u1 + z * v, width: strong ? 0.008 : 0.003, material: strong ? bold : fine))
            v += 0.1
            i += 1
            if i > 400 { break }
        }
        grids.addChild(floor)
        grids.isEnabled = gridsVisible
    }

    /// Trait (boîte fine) entre deux points.
    private static func line(_ a: SIMD3<Float>, _ b: SIMD3<Float>, width: Float, material: Material) -> ModelEntity {
        let len = max(simd_distance(a, b), 1e-4)
        let e = ModelEntity(mesh: .generateBox(size: [len, width, width]), materials: [material])
        e.position = (a + b) / 2
        let d = (b - a) / len
        e.orientation = simd_quatf(from: [1, 0, 0], to: d)
        return e
    }

    // MARK: - Show

    func beginShow() {
        placing = false
        for r in recognizers { r.isEnabled = false }
        outline.isEnabled = false
        grids.isEnabled = false
        footprint.isEnabled = false
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
        kitchen?.components.set(OpacityComponent(opacity: o))
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

/// La vue RealityKit (créée une fois par le modèle, sur la session du scan).
struct StageView: UIViewRepresentable {
    @EnvironmentObject var model: ArModel
    let stage: StageController

    func makeUIView(context: Context) -> ARView {
        let v = model.arView
        stage.attach(v)
        stage.configure(model.session)
        return v
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
