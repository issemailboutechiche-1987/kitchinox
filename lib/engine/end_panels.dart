/// Joues de finition : panneaux de 18 mm posés aux extrémités visibles des linéaires
/// (côté d'un caisson qui ne touche ni un mur ni un autre meuble).
library;

import 'catalog.dart';
import 'layout_engine.dart';

class EndPanel {
  final String wallId;
  final double s; // début du panneau le long du mur
  final double depth; // profondeur depuis le mur (façade comprise)
  final double z0, z1;
  final bool high; // joue d'élément haut
  const EndPanel(this.wallId, this.s, this.depth, this.z0, this.z1, this.high);

  static const thickness = 18.0;
  double get height => z1 - z0;
}

/// Joues à poser automatiquement (sans compter celles déjà posées à la main : elles occupent la place).
List<EndPanel> endPanels(LayoutEngine e) {
  final p = e.project;
  final all = [for (final c in p.items) ...e.boxesOf(c).map((tb) => tb.box)];
  final out = <EndPanel>[];
  const T = EndPanel.thickness;
  bool panelLike(CabinetModel m) => m.kind.isFiller || m.kind == CabinetKind.coverPanel || m.kind == CabinetKind.islandPanel;
  for (final w in p.room.walls.where((w) => w.enabled)) {
    for (final high in [false, true]) {
      bool test(CabinetModel m) => !panelLike(m) && (high ? m.kind.isHigh : (m.kind.isLow || m.kind == CabinetKind.tall));
      // boîtes de ce mur dans cette bande, en coordonnées murales
      final mine = <(double, double, double, double, double)>[]; // s0, s1, t1, z0, z1
      for (final c in p.items) {
        final m = e.modelOf(c);
        if (!test(m)) continue;
        for (final tb in e.boxesOf(c)) {
          if (tb.wallId != w.id) continue;
          final (s0, s1, _, t1) = w.boxToWall(tb.box);
          mine.add((s0, s1, t1, tb.box.z0, tb.box.z1));
        }
      }
      for (final (a, b) in e.runs(w.id, test)) {
        for (final left in [true, false]) {
          final edge = left ? a : b;
          final s = left ? a - T : b;
          if (s < -0.5 || s + T > w.length + 0.5) continue;
          final ends = mine.where((x) => ((left ? x.$1 : x.$2) - edge).abs() < 1).toList();
          if (ends.isEmpty) continue;
          var depth = 0.0, z0 = double.infinity, z1 = 0.0;
          for (final x in ends) {
            if (x.$3 > depth) depth = x.$3;
            if (x.$4 < z0) z0 = x.$4;
            if (x.$5 > z1) z1 = x.$5;
          }
          if (!high) z0 = 0; // une joue de bas ou de colonne descend jusqu'au sol (elle cache la plinthe)
          final box = w.strip(s, T, depth, z0, z1 - z0);
          if (all.any((o) => o.intersects(box))) continue;
          out.add(EndPanel(w.id, s, depth, z0, z1, high));
        }
      }
    }
  }
  return out;
}
