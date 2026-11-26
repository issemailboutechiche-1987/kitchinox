/// Joues de finition (costados) : panneaux de 18 mm. Posées toutes seules aux extrémités visibles des linéaires
/// (côté d'un caisson qui ne touche ni un mur ni un autre meuble), ou ajoutées à la main sur n'importe quel caisson.
library;

import 'catalog.dart';
import 'layout_engine.dart';
import 'project.dart';

class EndPanel {
  final String wallId;
  final double s; // début du panneau le long du mur
  final double depth; // profondeur depuis le mur (façade comprise)
  final double z0, z1;
  final bool high; // joue d'élément haut
  final PlacedCabinet? item; // caisson qui la porte (joue ajoutée à la main)
  const EndPanel(this.wallId, this.s, this.depth, this.z0, this.z1, this.high, {this.item});

  static const thickness = 18.0;
  double get height => z1 - z0;

  /// Finition de la joue : celle du projet, sinon celle des façades du caisson.
  String finishId(KitchenStyle st) =>
      st.endPanelFinish ?? (item != null ? st.frontOf(item!, high: high) : (high ? (st.frontUpper ?? st.front) : (st.frontLower ?? st.front)));
}

/// Panneau de finition horizontal (18 mm, finition des joues) : sous les meubles hauts, ou sur les hauts et les colonnes.
/// Les meubles voisins qui en ont un forment un seul panneau continu, joues comprises : tout se raccorde.
class CapPanel {
  final String wallId;
  final double s0, s1; // le long du mur
  final double depth;
  final double z; // face du dessous du panneau
  final bool top; // dessus (sinon dessous)
  final List<PlacedCabinet> items;
  const CapPanel(this.wallId, this.s0, this.s1, this.depth, this.z, this.top, this.items);

  static const thickness = 18.0;
  double get length => s1 - s0;
  double get z1 => z + thickness;

  String finishId(KitchenStyle st) => st.endPanelFinish ?? st.frontOf(items.first, high: true);
}

/// Le meuble peut-il recevoir un panneau dessous ([bottom]) ou dessus ?
bool capAllowed(CabinetModel m, {required bool bottom}) =>
    !m.kind.isFiller && m.kind != CabinetKind.coverPanel && m.kind != CabinetKind.islandPanel && !m.isFreeHood &&
    (bottom ? m.kind.isHigh : (m.kind.isHigh || m.kind == CabinetKind.tall || m.kind == CabinetKind.cornerTall));

/// Panneaux de finition dessous / dessus du projet, fusionnés par rangée.
List<CapPanel> capPanels(LayoutEngine e) {
  final p = e.project;
  final out = <CapPanel>[];
  for (final top in [false, true]) {
    final byWall = <String, List<PlacedCabinet>>{};
    for (final c in p.items) {
      if (!(top ? c.capTop : c.capBottom) || !capAllowed(e.modelOf(c), bottom: !top)) continue;
      byWall.putIfAbsent(c.wallId, () => []).add(c);
    }
    for (final MapEntry(key: wallId, value: list) in byWall.entries) {
      list.sort((a, b) => a.s.compareTo(b.s));
      double from(PlacedCabinet c) => c.s - (c.hasCheek(true) ? EndPanel.thickness : 0);
      double to(PlacedCabinet c) => c.right + (c.hasCheek(false) ? EndPanel.thickness : 0);
      double level(PlacedCabinet c) => top ? c.top : c.z - CapPanel.thickness;
      var run = <PlacedCabinet>[];
      void flush() {
        if (run.isEmpty) return;
        final depth = run.map((c) => c.depth.toDouble()).reduce((a, b) => a > b ? a : b);
        out.add(CapPanel(wallId, from(run.first), to(run.last), depth, level(run.first), top, List.of(run)));
        run = [];
      }

      for (final c in list) {
        // même hauteur et bord à bord (au jeu d'une joue près) : le panneau continue
        if (run.isNotEmpty && ((level(c) - level(run.last)).abs() > 5 || from(c) - to(run.last) > 20)) flush();
        run.add(c);
      }
      flush();
    }
  }
  return out;
}

/// Joues du projet : celles ajoutées à la main, plus les automatiques ([auto], réglage du style).
/// Les panneaux « joue » posés comme un meuble occupent déjà la place.
List<EndPanel> endPanels(LayoutEngine e, {bool? auto}) {
  final p = e.project;
  final out = <EndPanel>[];
  const T = EndPanel.thickness;
  bool panelLike(CabinetModel m) => m.kind.isFiller || m.kind == CabinetKind.coverPanel || m.kind == CabinetKind.islandPanel;
  for (final c in p.items) {
    for (final left in [true, false]) {
      if (!c.hasCheek(left)) continue;
      final tb = e.cheekBox(c, left);
      final (s0, _, _, _) = p.room.wall(tb.wallId).boxToWall(tb.box);
      out.add(EndPanel(tb.wallId, s0, c.depth.toDouble(), tb.box.z0, tb.box.z1, e.modelOf(c).kind.isHigh, item: c));
    }
  }
  if (!(auto ?? p.style.endPanels)) return out;
  final all = [for (final c in p.items) ...e.solidOf(c).map((tb) => tb.box)];
  for (final w in p.room.walls.where((w) => w.enabled)) {
    for (final high in [false, true]) {
      bool test(CabinetModel m) => !panelLike(m) && !m.isFreeHood && (high ? m.kind.isHigh : (m.kind.isLow || m.kind == CabinetKind.tall));
      // boîtes de ce mur dans cette bande, en coordonnées murales
      final mine = <(double, double, double, double, double, PlacedCabinet)>[]; // s0, s1, t1, z0, z1
      for (final c in p.items) {
        final m = e.modelOf(c);
        if (!test(m)) continue;
        for (final tb in e.boxesOf(c)) {
          if (tb.wallId != w.id) continue;
          final (s0, s1, _, t1) = w.boxToWall(tb.box);
          mine.add((s0, s1, t1, tb.box.z0, tb.box.z1, c));
        }
      }
      for (final (a, b) in e.runs(w.id, test)) {
        for (final left in [true, false]) {
          final edge = left ? a : b;
          final s = left ? a - T : b;
          if (s < -0.5 || s + T > w.length + 0.5) continue;
          final ends = mine.where((x) => ((left ? x.$1 : x.$2) - edge).abs() < 1 && x.$6.cheek(left) != 'non').toList();
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
