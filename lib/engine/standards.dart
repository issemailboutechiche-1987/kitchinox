/// Cotes de référence de la cuisine, en mm.
///
/// Valeurs validées avec l'utilisateur : caisson bas 750 + plinthe 100 + plan de travail 50
/// = plan de travail à 900 mm du sol. Elles remplacent la hauteur « 800 » du catalogue JSON.
class KitchenStandards {
  final int plinthHeight;
  final int baseCarcassHeight;
  final int worktopThickness;

  /// Dégagement minimal entre le dessus du plan de travail et le bas des caissons hauts.
  final int wallClearanceMin;

  /// Hauteur de pose par défaut du bas des caissons hauts (modifiable).
  final int wallBottomDefault;

  /// Distance en dessous de laquelle un caisson est aimanté sur un bord voisin.
  final int snapTolerance;

  /// Écart maximal comblé par un fileur (au-delà : place pour un caisson).
  final int fillerMax;

  const KitchenStandards({
    this.plinthHeight = 100,
    this.baseCarcassHeight = 750,
    this.worktopThickness = 50,
    this.wallClearanceMin = 450,
    this.wallBottomDefault = 1500, // crédence standard de 60 cm au-dessus du plan (900 + 600)
    this.snapTolerance = 50,
    this.fillerMax = 200,
  });

  /// Dessus du caisson bas = dessous du plan de travail.
  int get baseTop => plinthHeight + baseCarcassHeight;

  /// Dessus du plan de travail (900 mm par défaut).
  int get worktopTop => baseTop + worktopThickness;

  /// Bas minimal autorisé pour un caisson haut.
  int get wallBottomMin => worktopTop + wallClearanceMin;

  Map<String, dynamic> toJson() => {
        'plinth_height': plinthHeight,
        'base_carcass_height': baseCarcassHeight,
        'worktop_thickness': worktopThickness,
        'wall_clearance_min': wallClearanceMin,
        'wall_bottom_default': wallBottomDefault,
        'snap_tolerance': snapTolerance,
        'filler_max': fillerMax,
      };

  factory KitchenStandards.fromJson(Map<String, dynamic> j) {
    const d = KitchenStandards();
    return KitchenStandards(
      plinthHeight: j['plinth_height'] ?? d.plinthHeight,
      baseCarcassHeight: j['base_carcass_height'] ?? d.baseCarcassHeight,
      worktopThickness: j['worktop_thickness'] ?? d.worktopThickness,
      wallClearanceMin: j['wall_clearance_min'] ?? d.wallClearanceMin,
      wallBottomDefault: j['wall_bottom_default'] ?? d.wallBottomDefault,
      snapTolerance: j['snap_tolerance'] ?? d.snapTolerance,
      fillerMax: j['filler_max'] ?? d.fillerMax,
    );
  }
}
