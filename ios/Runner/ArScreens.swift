// Écrans du mode AR : scan → placement → show, avec une croix pour revenir à kitchinox.

import RealityKit
import SwiftUI

struct ArRootView: View {
    @EnvironmentObject var model: ArModel
    @StateObject private var stage = StageController()

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch model.phase {
            case .scanning:
                ScanScreen()
            case .placing, .show:
                StageScreen(stage: stage)
            }
            Button {
                model.close()
            } label: {
                Image(systemName: "xmark").font(.title2.weight(.semibold)).padding(14)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(20)
            .accessibilityLabel("Fermer et revenir à kitchinox")
        }
        .onAppear { stage.load(model.sceneURL) }
        .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Placement et show

struct StageScreen: View {
    @EnvironmentObject var model: ArModel
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

    private func enter(_ p: ArPhase) {
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
            Text("Un doigt : glisser au sol · deux doigts : tourner · le cadre orange montre l'emprise exacte")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 14) {
                moveTool
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button { stage.nextCorner() } label: { Label("Coin suivant", systemImage: "arrow.triangle.turn.up.right.diamond") }
                            .disabled(stage.cornerCount < 2)
                        Button { stage.quarterTurn() } label: { Label("Quart de tour", systemImage: "rotate.right") }
                        Toggle(isOn: $stage.gridsVisible) { Label("Grilles", systemImage: "grid") }.toggleStyle(.button)
                        Button { model.rescan() } label: { Label("Rescanner", systemImage: "viewfinder") }
                    }
                    HStack(spacing: 10) {
                        Toggle(isOn: $model.scaleUnlocked) { Label("Échelle libre", systemImage: "arrow.up.left.and.arrow.down.right") }
                            .toggleStyle(.button)
                            .onChange(of: model.scaleUnlocked) { _, on in if !on { model.scale = 1 } }
                        if model.scaleUnlocked {
                            Slider(value: $model.scale, in: 0.5 ... 1.5).frame(width: 160)
                            Text("\(Int((model.scale * 100).rounded())) %").monospacedDigit().frame(width: 52)
                            Button("1:1") { model.scale = 1 }
                        }
                        Button { model.validate() } label: { Label("Valider", systemImage: "checkmark").font(.headline).frame(minWidth: 140) }
                            .buttonStyle(.borderedProminent).tint(.orange)
                            .disabled(!stage.loaded)
                    }
                }
            }
            .buttonStyle(.bordered)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(.bottom, 24)
    }

    /// Outil Déplacer : flèches le long des axes de la cuisine, pas de 1 ou 10 cm, rotation fine.
    private var moveTool: some View {
        VStack(spacing: 6) {
            Text("Déplacer").font(.caption.weight(.semibold))
            Button { stage.nudge(dx: 0, dz: -1) } label: { Image(systemName: "arrow.up") }
            HStack(spacing: 6) {
                Button { stage.nudge(dx: -1, dz: 0) } label: { Image(systemName: "arrow.left") }
                Picker("Pas", selection: $stage.step) {
                    Text("1 cm").tag(Float(0.01))
                    Text("10 cm").tag(Float(0.1))
                }
                .pickerStyle(.segmented).frame(width: 120)
                Button { stage.nudge(dx: 1, dz: 0) } label: { Image(systemName: "arrow.right") }
            }
            Button { stage.nudge(dx: 0, dz: 1) } label: { Image(systemName: "arrow.down") }
            HStack(spacing: 6) {
                Button { stage.rotateFine(1) } label: { Label("1°", systemImage: "arrow.counterclockwise") }
                Button { stage.rotateFine(-1) } label: { Label("1°", systemImage: "arrow.clockwise") }
            }
        }
        .padding(8)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    private var showBar: some View {
        HStack(spacing: 12) {
            Button { model.replace() } label: { Label("Replacer", systemImage: "move.3d") }
            Button {
                stage.snapshot { ok in saved = ok }
            } label: { Label(saved ? "Photo enregistrée" : "Photo", systemImage: "camera") }
            Button { model.close() } label: { Label("Terminer", systemImage: "checkmark") }
        }
        .buttonStyle(.bordered)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 24)
    }
}
