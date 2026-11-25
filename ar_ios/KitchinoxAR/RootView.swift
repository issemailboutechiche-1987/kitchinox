// Écrans : accueil → scan → placement → show.

import RealityKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var stage = StageController()

    var body: some View {
        ZStack {
            switch model.phase {
            case .home, .loading:
                HomeScreen()
            case .scanning:
                ScanScreen()
            case .placing, .show:
                StageScreen(stage: stage)
            }
        }
        .onChange(of: model.sceneURL) { _, url in stage.load(url) }
        .onAppear { stage.load(model.sceneURL) }
        .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }
}

// MARK: - Accueil

struct HomeScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var picking = false

    var body: some View {
        HStack(spacing: 48) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Kitchinox AR").font(.system(size: 44, weight: .bold))
                Text("Votre cuisine, à l'échelle réelle, dans votre pièce.").font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Scannez toute la pièce : murs, portes, fenêtres et sol.")
                    step(2, "La cuisine se cale sur les vrais murs : ajustez si besoin.")
                    step(3, "Validez : le show commence, tournez autour.")
                }
                .padding(.top, 8)
            }
            VStack(spacing: 16) {
                if model.phase == .loading {
                    ProgressView("Réception de la cuisine…").controlSize(.large)
                } else if model.sceneURL != nil {
                    Label(model.sceneName, systemImage: "cube.transparent").font(.title2.weight(.semibold))
                    Button {
                        model.startScan()
                    } label: {
                        Label("Scanner la pièce", systemImage: "viewfinder").font(.title3.weight(.semibold)).frame(minWidth: 280, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    Image(systemName: "arrow.down.circle").font(.system(size: 54)).foregroundStyle(.orange)
                    Text("Dans kitchinox : vue 3D → Voir dans ma pièce → Scanner la pièce.")
                        .multilineTextAlignment(.center).frame(maxWidth: 320)
                }
                Button("Ouvrir un fichier .usdz…") { picking = true }.buttonStyle(.bordered)
                if !model.canScan {
                    Text("Le scan de la pièce demande un appareil avec LiDAR.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 340)
        }
        .padding(48)
        .fileImporter(isPresented: $picking, allowedContentTypes: [UTType(filenameExtension: "usdz") ?? .data]) { r in
            if case let .success(url) = r { model.open(url) }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).frame(width: 28, height: 28).background(Circle().fill(.orange))
            Text(text).font(.body)
        }
    }
}

// MARK: - Placement et show

struct StageScreen: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var stage: StageController
    @State private var saved = false

    var body: some View {
        ZStack(alignment: .bottom) {
            StageView(stage: stage).ignoresSafeArea()
            if model.phase == .placing { placingBar } else { showBar }
        }
        .onAppear { enter(model.phase) }
        .onChange(of: model.phase) { _, p in enter(p) }
        .onChange(of: model.scale) { _, s in stage.setScale(s) }
    }

    private func enter(_ p: Phase) {
        if p == .placing {
            stage.beginPlacing(room: model.room, project: model.projectRoom)
            stage.setScale(model.scale)
        } else if p == .show {
            stage.beginShow()
        }
    }

    private var placingBar: some View {
        VStack(spacing: 10) {
            Text(stage.loaded ? stage.info : "Chargement de la cuisine…")
                .font(.subheadline).padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            Text("Glissez pour déplacer · deux doigts pour tourner")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button { stage.nextCorner() } label: { Label("Coin suivant", systemImage: "arrow.triangle.turn.up.right.diamond") }
                    .disabled(stage.cornerCount < 2)
                Button { stage.quarterTurn() } label: { Label("Quart de tour", systemImage: "rotate.right") }
                Toggle(isOn: $model.scaleUnlocked) { Label("Échelle libre", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .toggleStyle(.button)
                    .onChange(of: model.scaleUnlocked) { _, on in if !on { model.scale = 1 } }
                if model.scaleUnlocked {
                    Slider(value: $model.scale, in: 0.5 ... 1.5).frame(width: 180)
                    Text("\(Int((model.scale * 100).rounded())) %").monospacedDigit().frame(width: 52)
                    Button("1:1") { model.scale = 1 }
                }
                Button { model.restart() } label: { Label("Rescanner", systemImage: "viewfinder") }
                Button { model.validate() } label: { Label("Valider", systemImage: "checkmark").font(.headline).frame(minWidth: 140) }
                    .buttonStyle(.borderedProminent).tint(.orange)
                    .disabled(!stage.loaded)
            }
            .buttonStyle(.bordered)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(.bottom, 24)
    }

    private var showBar: some View {
        HStack(spacing: 12) {
            Button { model.replace() } label: { Label("Replacer", systemImage: "move.3d") }
            Button {
                stage.snapshot { ok in saved = ok }
            } label: { Label(saved ? "Photo enregistrée" : "Photo", systemImage: "camera") }
            Button { model.phase = .home } label: { Label("Terminer", systemImage: "xmark") }
        }
        .buttonStyle(.bordered)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 24)
    }
}
