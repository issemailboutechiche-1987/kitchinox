/// Composition de façade programmable : une pile de cases du haut vers le bas
/// (porte, 2 portes, tiroir, abattant, porte vitrée, niche ouverte, appareil, panneau fixe).
///
/// Une case a une hauteur fixe en mm, ou 0 pour « le reste » (partagé entre les cases à 0).
/// Le catalogue peut décrire un modèle par sa composition (`front_layout`) et chaque caisson posé
/// peut avoir la sienne : le dessin, le débit et la quincaillerie la suivent.
library;

import 'catalog.dart';
import 'project.dart';

enum CellKind {
  door('Porte'),
  door2('2 portes'),
  drawer('Tiroir'),
  flap('Abattant'),
  glass('Porte vitrée'),
  niche('Niche ouverte'),
  appliance('Appareil'),
  panel('Panneau fixe');

  final String label;
  const CellKind(this.label);

  static CellKind parse(String s) => CellKind.values.firstWhere((k) => k.name == s, orElse: () => CellKind.door);

  /// La case a-t-elle une façade (panneau découpé) ?
  bool get hasFront => this != niche && this != appliance;
}

class FrontRow {
  CellKind kind;
  int h; // mm ; 0 = reste
  String? hinge; // 'left' | 'right' (porte simple)
  FrontRow(this.kind, [this.h = 0, this.hinge]);

  FrontRow copy() => FrontRow(kind, h, hinge);

  Map<String, dynamic> toJson() => {'k': kind.name, 'h': h, if (hinge != null) 'hinge': hinge};
  factory FrontRow.fromJson(Map<String, dynamic> j) =>
      FrontRow(CellKind.parse(j['k'] as String? ?? j['type'] as String? ?? 'door'), (j['h'] as num?)?.toInt() ?? 0, j['hinge'] as String?);

  @override
  String toString() => '${kind.name}:$h';
}

/// Case positionnée (mm depuis le haut de la façade).
class FrontCell {
  final CellKind kind;
  final double y, h;
  final String? hinge;
  final int index; // n° parmi les cases de même nature « appareil » (pour l'électroménager)
  const FrontCell(this.kind, this.y, this.h, this.hinge, this.index);
}

List<FrontRow> parseRows(Object? j) =>
    j is List ? [for (final r in j) FrontRow.fromJson((r as Map).cast<String, dynamic>())] : const [];

/// Composition effective : celle du caisson, sinon celle du modèle, sinon null (dessin standard).
List<FrontRow>? rowsOf(CabinetModel m, PlacedCabinet c) {
  if (!m.kind.isLow && !m.kind.isHigh && m.kind != CabinetKind.tall) return null;
  if (m.kind.isFiller || m.kind.isCorner) return null;
  return c.layout ?? m.frontLayout;
}

/// Hauteurs réelles des cases pour une façade de [height] mm.
List<FrontCell> cellsOf(List<FrontRow> rows, int height) {
  if (rows.isEmpty) return const [];
  final fixed = rows.fold<int>(0, (a, r) => a + (r.h > 0 ? r.h : 0));
  final flex = rows.where((r) => r.h <= 0).length;
  final rest = (height - fixed).toDouble();
  // trop de hauteur fixe ou aucune case libre : on met à l'échelle
  final scale = flex == 0 || rest < 0 ? height / (fixed == 0 ? 1 : fixed) : 1.0;
  final each = flex == 0 || rest < 0 ? 0.0 : rest / flex;
  final out = <FrontCell>[];
  var y = 0.0;
  var app = 0;
  for (final r in rows) {
    final h = r.h > 0 ? r.h * scale : each;
    out.add(FrontCell(r.kind, y, h, r.hinge, r.kind == CellKind.appliance ? app++ : -1));
    y += h;
  }
  return out;
}

/// Limites de fabrication d'une composition : nombre de cases et de portes / abattants.
(int, int) layoutLimits(CabinetKind kind) => kind.isHigh
    ? (2, 2)
    : kind == CabinetKind.tall
        ? (5, 3)
        : (4, 2);

bool _doorLike(CellKind k) => k == CellKind.door || k == CellKind.door2 || k == CellKind.glass || k == CellKind.flap;

/// Types de cases possibles selon le meuble :
/// - haut : portes, vitrine, abattant, niche, panneau (jamais de tiroir ni d'appareil) ;
/// - bas : portes, tiroirs, niche, appareil (four), panneau (pas d'abattant ni de vitrine) ;
/// - colonne : portes, vitrine, tiroirs, niche, appareil, panneau (pas d'abattant).
List<CellKind> allowedCellKinds(CabinetKind kind) => kind.isHigh
    ? const [CellKind.door, CellKind.door2, CellKind.glass, CellKind.flap, CellKind.niche, CellKind.panel]
    : kind == CabinetKind.tall
        ? const [CellKind.door, CellKind.door2, CellKind.glass, CellKind.drawer, CellKind.niche, CellKind.appliance, CellKind.panel]
        : const [CellKind.door, CellKind.door2, CellKind.drawer, CellKind.niche, CellKind.appliance, CellKind.panel];

/// Hauteur minimale d'une case (mm) : porte / abattant 250, tiroir 100, appareil 560 en bas (four)
/// et 380 en colonne (micro-ondes), niche 150, panneau 50.
int minCellHeight(CabinetKind kind, CellKind k) => switch (k) {
      CellKind.door || CellKind.door2 || CellKind.glass || CellKind.flap => 250,
      CellKind.drawer => 100,
      CellKind.appliance => kind.isLow ? 560 : 380,
      CellKind.niche => 150,
      CellKind.panel => 50,
    };

/// Raison du refus d'une composition (null = possible). Avec [height], vérifie aussi les tailles.
String? layoutProblem(CabinetKind kind, List<FrontRow> rows, [int? height]) {
  final (maxCases, maxDoors) = layoutLimits(kind);
  if (rows.isEmpty) return 'au moins une case';
  if (rows.length > maxCases) return '$maxCases cases au plus pour ce meuble';
  final allowed = allowedCellKinds(kind);
  for (final r in rows) {
    if (!allowed.contains(r.kind)) {
      return kind.isHigh
          ? '« ${r.kind.label} » impossible dans un élément haut'
          : '« ${r.kind.label} » impossible dans ${kind == CabinetKind.tall ? 'une colonne' : 'un élément bas'}';
    }
  }
  final doors = rows.where((r) => _doorLike(r.kind)).length;
  if (doors > maxDoors) return '$maxDoors portes ou abattants superposés au plus';
  if (rows.where((r) => r.kind == CellKind.appliance).length > (kind == CabinetKind.tall ? 2 : 1)) return 'trop d’appareils pour ce meuble';
  if (height != null) {
    for (final c in cellsOf(rows, height)) {
      final min = minCellHeight(kind, c.kind);
      if (c.h < min - 0.5) return '« ${c.kind.label} » de ${c.h.round()} mm : $min mm minimum';
    }
  }
  return null;
}

/// Composition de départ quand on personnalise un modèle standard.
List<FrontRow> seedRows(CabinetModel m, PlacedCabinet c) {
  final rows = rowsOf(m, c);
  if (rows != null) return [for (final r in rows) r.copy()];
  final H = c.height;
  int pct(double k) => (H * k).round();
  switch (m.id) {
    case 'base_drawers_multi':
      return switch (c.variant) {
        '2_deep_drawers' => [FrontRow(CellKind.drawer), FrontRow(CellKind.drawer)],
        '1_low_2_deep' => [FrontRow(CellKind.drawer, pct(0.2)), FrontRow(CellKind.drawer), FrontRow(CellKind.drawer)],
        '4_drawers' => [for (var i = 0; i < 4; i++) FrontRow(CellKind.drawer)],
        _ => [for (var i = 0; i < 3; i++) FrontRow(CellKind.drawer)],
      };
    case 'base_cooktop_oven':
      // niche du four (≥ 560 mm) puis tiroir sous le four
      return [FrontRow(CellKind.appliance), FrontRow(CellKind.drawer, 150)];
    case 'tall_oven_microwave':
      // micro-ondes 380, four 595, deux tiroirs de 250, la porte haute prend le reste
      return [
        FrontRow(CellKind.door),
        FrontRow(CellKind.appliance, 380),
        FrontRow(CellKind.appliance, 595),
        FrontRow(CellKind.drawer, 250),
        FrontRow(CellKind.drawer, 250),
      ];
    case 'tall_integrated_fridge':
      final split = c.variant == '50_50' ? 0.5 : c.variant == 'single_door' ? 1.0 : 0.62;
      return [FrontRow(CellKind.door, split < 1 ? pct(split) : 0, 'right'), if (split < 1) FrontRow(CellKind.door, 0, 'right')];
    case 'wall_lift_up':
      return [FrontRow(CellKind.flap)];
    case 'wall_open_shelf':
      return [FrontRow(CellKind.niche)];
    case 'wall_integrated_hood':
      return [FrontRow(CellKind.door, pct(0.8)), FrontRow(CellKind.panel)];
  }
  final two = c.opening == 'double_hinged' || m.id.contains('double_door') || c.width >= 800;
  if (m.kind == CabinetKind.tall && H > 1800) {
    return [FrontRow(two ? CellKind.door2 : CellKind.door, H ~/ 2), FrontRow(two ? CellKind.door2 : CellKind.door)];
  }
  return [FrontRow(two ? CellKind.door2 : CellKind.door, 0, c.opening == 'hinged_right' ? 'right' : null)];
}

/// Compositions toutes faites proposées dans l'inspecteur (selon la hauteur de pose).
List<(String, List<FrontRow>)> frontPresets(CabinetKind kind, int height) {
  int p(double k) => (height * k).round();
  if (kind.isHigh) {
    return [
      ('1 porte', [FrontRow(CellKind.door)]),
      ('2 portes', [FrontRow(CellKind.door2)]),
      ('Vitrine', [FrontRow(CellKind.glass)]),
      ('Abattant', [FrontRow(CellKind.flap)]),
      ('Niche ouverte', [FrontRow(CellKind.niche)]),
      ('Porte + niche', [FrontRow(CellKind.door), FrontRow(CellKind.niche, p(0.35))]),
      ('2 abattants', [FrontRow(CellKind.flap), FrontRow(CellKind.flap)]),
    ];
  }
  if (kind == CabinetKind.tall) {
    return [
      ('2 portes superposées', [FrontRow(CellKind.door, p(0.5)), FrontRow(CellKind.door)]),
      ('Porte pleine hauteur', [FrontRow(CellKind.door)]),
      ('Four + tiroirs', [FrontRow(CellKind.door, p(0.3)), FrontRow(CellKind.appliance, 595), FrontRow(CellKind.drawer), FrontRow(CellKind.drawer)]),
      ('Four + micro-ondes', [FrontRow(CellKind.door, p(0.2)), FrontRow(CellKind.appliance, 380), FrontRow(CellKind.appliance, 595), FrontRow(CellKind.drawer), FrontRow(CellKind.drawer)]),
      ('Porte + niche + porte', [FrontRow(CellKind.door, p(0.35)), FrontRow(CellKind.niche, 450), FrontRow(CellKind.door)]),
      ('Garde-manger vitré', [FrontRow(CellKind.glass, p(0.5)), FrontRow(CellKind.door)]),
      ('Réfrigérateur pose libre', [FrontRow(CellKind.door, 400), FrontRow(CellKind.appliance)]),
    ];
  }
  return [
    ('1 porte', [FrontRow(CellKind.door)]),
    ('2 portes', [FrontRow(CellKind.door2)]),
    ('Tiroir + porte', [FrontRow(CellKind.drawer, 150), FrontRow(CellKind.door)]),
    ('Tiroir + 2 portes', [FrontRow(CellKind.drawer, 150), FrontRow(CellKind.door2)]),
    ('3 tiroirs', [FrontRow(CellKind.drawer), FrontRow(CellKind.drawer), FrontRow(CellKind.drawer)]),
    ('1 + 2 casseroliers', [FrontRow(CellKind.drawer, 150), FrontRow(CellKind.drawer), FrontRow(CellKind.drawer)]),
    ('2 casseroliers', [FrontRow(CellKind.drawer), FrontRow(CellKind.drawer)]),
    ('4 tiroirs', [for (var i = 0; i < 4; i++) FrontRow(CellKind.drawer)]),
    ('Niche ouverte', [FrontRow(CellKind.niche)]),
    ('Tiroir + niche', [FrontRow(CellKind.drawer, 150), FrontRow(CellKind.niche)]),
    ('Four + tiroir', [FrontRow(CellKind.appliance), FrontRow(CellKind.drawer, 150)]),
  ];
}
