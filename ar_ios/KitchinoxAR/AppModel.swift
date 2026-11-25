// État de l'application : la scène reçue, le scan, le placement et le show.
// Une seule ARSession pour tout le parcours : le scan RoomPlan et la cuisine partagent le même repère du monde,
// la cuisine se cale donc exactement sur les murs scannés.

import ARKit
import Foundation
import RealityKit
import RoomPlan
import simd

enum Phase: Equatable {
    case home // en attente d'une scène ou du scan
    case loading // téléchargement de la scène
    case scanning // scan RoomPlan en cours
    case placing // la cuisine est posée : on la cale, on la tourne, on règle l'échelle
    case show // validé : la cuisine dans la pièce
}

@MainActor
final class AppModel: ObservableObject {
    @Published var phase: Phase = .home
    @Published var message: String?
    @Published private(set) var sceneURL: URL?
    @Published private(set) var sceneName = ""
    /// Dimensions de la pièce du projet (mm), pour choisir le bon coin automatiquement.
    @Published private(set) var projectRoom: SIMD2<Float>?
    @Published private(set) var room: CapturedRoom?
    /// Échelle : 1 = taille réelle. Modifiable seulement si l'utilisateur la déverrouille.
    @Published var scale: Float = 1
    @Published var scaleUnlocked = false

    /// La vue RealityKit, créée une fois : sa session sert aussi au scan RoomPlan (même repère du monde).
    lazy var arView: ARView = {
        let v = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        v.renderOptions.insert(.disableMotionBlur)
        return v
    }()

    /// La session partagée par le scan et l'affichage.
    var session: ARSession { arView.session }

    init() {
        // dernière scène reçue : gardée d'une ouverture à l'autre
        let f = Self.sceneFile
        if FileManager.default.fileExists(atPath: f.path) {
            sceneURL = f
            sceneName = UserDefaults.standard.string(forKey: "sceneName") ?? "Cuisine"
            if let w = UserDefaults.standard.object(forKey: "roomW") as? Float, let d = UserDefaults.standard.object(forKey: "roomD") as? Float {
                projectRoom = SIMD2(w, d)
            }
        }
    }

    static var sceneFile: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("scene.usdz")
    }

    // MARK: - Réception de la scène

    func open(_ url: URL) {
        if url.isFileURL {
            importFile(url)
            return
        }
        guard url.scheme == "kitchinoxar",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let src = items.first(where: { $0.name == "src" })?.value,
              let remote = URL(string: src)
        else {
            message = "Lien kitchinox illisible."
            return
        }
        let num = { (k: String) in items.first(where: { $0.name == k })?.value.flatMap(Float.init) }
        if let w = num("w"), let d = num("d"), w > 0, d > 0 { setRoom(w, d) }
        sceneName = items.first(where: { $0.name == "name" })?.value ?? "Cuisine"
        download(remote)
    }

    private func setRoom(_ w: Float, _ d: Float) {
        projectRoom = SIMD2(w, d)
        UserDefaults.standard.set(w, forKey: "roomW")
        UserDefaults.standard.set(d, forKey: "roomD")
    }

    private func download(_ remote: URL) {
        phase = .loading
        message = nil
        Task {
            do {
                let (tmp, response) = try await URLSession.shared.download(from: remote)
                if let h = response as? HTTPURLResponse, h.statusCode != 200 {
                    throw NSError(domain: "kitchinox", code: h.statusCode, userInfo: [NSLocalizedDescriptionKey: "le serveur répond \(h.statusCode)"])
                }
                try store(tmp)
                phase = .home
            } catch {
                phase = .home
                message = "Scène non reçue : \(error.localizedDescription). Le PC et l'iPad sont-ils sur le même Wi-Fi ?"
            }
        }
    }

    private func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            var name = url.deletingPathExtension().lastPathComponent
            // « Cuisine_3600x3000mm » : les cotes de la pièce du projet, pour choisir le bon coin
            if let m = name.range(of: #"_(\d+)x(\d+)mm$"#, options: .regularExpression) {
                let dims = name[m].dropFirst().dropLast(2).split(separator: "x").compactMap { Float($0) }
                if dims.count == 2 { setRoom(dims[0], dims[1]) }
                name = String(name[..<m.lowerBound])
            }
            sceneName = name
            try store(url)
        } catch {
            message = "Fichier illisible : \(error.localizedDescription)"
        }
    }

    private func store(_ src: URL) throws {
        let dst = Self.sceneFile
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: src, to: dst)
        UserDefaults.standard.set(sceneName, forKey: "sceneName")
        sceneURL = nil // force le rechargement de l'entité
        sceneURL = dst
        message = nil
    }

    // MARK: - Parcours

    var canScan: Bool { ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) && RoomCaptureSession.isSupported }

    func startScan() {
        guard sceneURL != nil else {
            message = "Envoyez d'abord la cuisine depuis kitchinox (mode AR → Scanner la pièce)."
            return
        }
        guard canScan else {
            message = "Cet appareil n'a pas de LiDAR : le scan de la pièce est impossible."
            return
        }
        room = nil
        scale = 1
        scaleUnlocked = false
        phase = .scanning
    }

    func finishScan(_ captured: CapturedRoom) {
        room = captured
        phase = .placing
    }

    func cancelScan() { phase = .home }
    func validate() { phase = .show }
    func replace() { phase = .placing }
    func restart() { startScan() }
}
