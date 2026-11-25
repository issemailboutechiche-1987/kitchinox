// Étape 1 : scan complet de la pièce avec RoomPlan (LiDAR).
// La vue de capture utilise la session partagée : à la fin du scan, la session continue
// (stop(pauseARSession: false)), et la pièce scannée reste dans le même repère que la cuisine posée ensuite.
// « Terminer » n'est possible qu'une fois la pièce fermée : au moins 3 murs et le sol.

import ARKit
import RoomPlan
import SwiftUI

struct ScanScreen: View {
    @EnvironmentObject var model: ArModel
    @StateObject private var progress = ScanProgress()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScanView(progress: progress).ignoresSafeArea()
            VStack(spacing: 10) {
                Text(progress.hint)
                    .font(.headline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                HStack(spacing: 16) {
                    Label("\(progress.walls) murs", systemImage: "square.split.bottomrightquarter")
                    Label("\(progress.openings) portes et fenêtres", systemImage: "door.left.hand.open")
                    Label(progress.floor ? "sol" : "sol à scanner", systemImage: progress.floor ? "checkmark.circle.fill" : "circle.dotted")
                }
                .font(.subheadline)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 14) {
                    Button("Annuler") { progress.cancel(); model.close() }
                        .buttonStyle(.bordered)
                    Button {
                        progress.finish()
                    } label: {
                        Label(progress.processing ? "Analyse de la pièce…" : "Terminer le scan", systemImage: "checkmark")
                            .frame(minWidth: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!progress.complete || progress.processing)
                }
            }
            .padding(.bottom, 28)
        }
        .onReceive(progress.$result.compactMap { $0 }) { room in
            model.finishScan(room, session: progress.captureView?.captureSession.arSession)
        }
    }
}

/// Avancement du scan, lu par les boutons.
@MainActor
final class ScanProgress: ObservableObject {
    @Published var walls = 0
    @Published var openings = 0
    @Published var floor = false
    @Published var processing = false
    @Published var result: CapturedRoom?
    weak var captureView: RoomCaptureView?

    /// Pièce fermée : assez de murs et le sol.
    var complete: Bool { walls >= 3 && floor }

    var hint: String {
        if processing { return "Analyse de la pièce…" }
        if walls == 0 { return "Balayez lentement les murs, du sol au plafond" }
        if !complete { return "Faites tout le tour de la pièce, sans oublier le sol" }
        return "Pièce complète : vérifiez les coins, puis terminez"
    }

    func update(_ room: CapturedRoom) {
        walls = room.walls.count
        openings = room.doors.count + room.windows.count + room.openings.count
        floor = !room.floors.isEmpty
    }

    func finish() {
        guard complete, let v = captureView else { return }
        processing = true
        // la session AR continue : la cuisine sera posée dans le même repère que la pièce
        v.captureSession.stop(pauseARSession: false)
    }

    func cancel() { captureView?.captureSession.stop() }
}

struct ScanView: UIViewRepresentable {
    @EnvironmentObject var model: ArModel
    let progress: ScanProgress

    func makeCoordinator() -> ScanCoordinator { ScanCoordinator(progress: progress) }

    func makeUIView(context: Context) -> RoomCaptureView {
        // la vue de capture garde sa propre session : le scan s'affiche en direct (murs tracés au fur et à mesure) ;
        // à la fin, la cuisine reprend cette session (même repère que la pièce scannée)
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        view.captureSession.delegate = context.coordinator
        progress.captureView = view
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

/// Délégué du scan (au premier niveau, nom Objective-C fixe : RoomCaptureViewDelegate exige NSCoding).
@objc(KitchinoxArScanCoordinator)
final class ScanCoordinator: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    let progress: ScanProgress

    init(progress: ScanProgress) {
        self.progress = progress
        super.init()
    }

    // RoomCaptureViewDelegate exige NSCoding
    required init?(coder: NSCoder) { nil }
    func encode(with coder: NSCoder) {}

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        Task { @MainActor in self.progress.update(room) }
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool { true }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        Task { @MainActor in
            self.progress.processing = false
            if error == nil { self.progress.result = processedResult }
        }
    }
}
