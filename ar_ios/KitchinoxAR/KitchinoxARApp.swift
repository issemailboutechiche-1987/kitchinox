// Kitchinox AR : la cuisine conçue dans kitchinox, posée à l'échelle 1:1 dans la vraie pièce.
// Parcours : 1. scan complet de la pièce (RoomPlan) → 2. placement (calage automatique sur les murs scannés,
// ajustable, échelle en option) → 3. valider → 4. le show (RealityKit, occlusion par le LiDAR).
// La scène arrive de kitchinox web par kitchinoxar://open?src=<url du .usdz>&w=<largeur mm>&d=<profondeur mm>,
// ou par un fichier .usdz ouvert depuis Fichiers.

import SwiftUI

@main
struct KitchinoxARApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onOpenURL { model.open($0) }
                .preferredColorScheme(.dark)
        }
    }
}
