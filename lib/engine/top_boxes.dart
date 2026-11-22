/// Casquettes (sur-meubles) : au-dessus des hauts et des colonnes, jusqu'à une même ligne, avec une casquette d'angle
/// en L quand deux murs se rejoignent.
library;

import 'dart:math' as math;

import 'catalog.dart';
import 'layout_engine.dart';
import 'project.dart';

const topBoxId = 'wall_top_box', cornerTopBoxId = 'corner_top_l_shaped';
bool isTopBox(CabinetModel m) => m.id == topBoxId || m.id == cornerTopBoxId;

/// Pose les casquettes de [height] mm, profondes de [depth] mm. Remplace celles déjà posées. Renvoie (droites, d'angle).
(int, int) placeTopBoxes(LayoutEngine e, {required int height, required int depth}) {
  final p = e.project;
  p.items.removeWhere((c) => isTopBox(e.modelOf(c)));
  bool high(CabinetModel m) => m.kind.isHigh && !m.isFreeHood && !isTopBox(m);
  bool tall(CabinetModel m) => m.kind == CabinetKind.tall || m.kind == CabinetKind.cornerTall;
  final tops = [for (final c in p.items) if (high(e.modelOf(c))) c.top];
  final ceiling = p.room.height;
  // ligne du haut commune
  final base = tops.isEmpty ? null : tops.reduce(math.max);
  final talls = [for (final c in p.items) if (tall(e.modelOf(c))) c.top];
  final line = math.min(ceiling, base != null ? base + height : (talls.isEmpty ? 0.0 : talls.reduce(math.max) + height));
  var straight = 0, corners = 0;
  final taken = <String, List<(double, double)>>{}; // place prise par les angles, par mur

  PlacedCabinet? put(String id, String wall, double s, double z, double w, double h, int d, {int? right}) {
    final m = e.catalog.tryGet(id);
    if (m == null || h < 200 || w < 200) return null;
    final c = PlacedCabinet(
      uid: p.newUid('c'),
      modelId: id,
      wallId: wall,
      s: s,
      z: z,
      width: w.round(),
      height: h.round(),
      depth: d,
      widthRight: right,
      opening: m.openingOptions.isEmpty ? null : m.openingOptions.first,
    );
    p.items.add(c);
    if (e.clashes(c)) {
      // trop profonde ici (colonne, retour) : à l'aplomb des hauts
      c.depth = math.min(d, 370);
      if (e.clashes(c)) {
        p.items.remove(c);
        return null;
      }
    }
    return c;
  }

  final walls = [for (final w in p.room.walls) if (w.enabled && w.orthogonal) w];
  // ---- angles
  for (final w in walls) {
    final next = p.room.nextOf(w.id);
    if (!walls.any((x) => x.id == next)) continue;
    // colonne d'angle : casquette à ses bras
    final ct = p.items.where((c) => c.wallId == w.id && e.modelOf(c).kind == CabinetKind.cornerTall && e.modelOf(c).shape != CabinetShape.blind).firstOrNull;
    if (ct != null) {
      final c = put(cornerTopBoxId, w.id, w.length - ct.width, ct.top, ct.width.toDouble(), line - ct.top, ct.depth, right: ct.widthRight ?? ct.width);
      if (c != null) corners++;
      continue;
    }
    final here = e.runs(w.id, high), there = e.runs(next, high);
    if (here.isEmpty || there.isEmpty) continue;
    final a = here.last, b = there.first;
    if (a.$2 < w.length - 1 || b.$1 > 420) continue; // les hauts ne se rejoignent pas dans l'angle
    final z = [for (final c in p.items) if (high(e.modelOf(c)) && ((c.wallId == w.id && c.right > w.length - 800) || (c.wallId == next && c.s < 800))) c.top].fold<double>(0, math.max);
    if (z == 0) continue;
    final m = e.catalog.tryGet(cornerTopBoxId);
    if (m == null) continue;
    final want = depth >= 500 ? 900.0 : 680.0;
    final fit = math.min(want, math.min(a.$2 - a.$1, b.$2));
    final arm = m.widths.values.where((x) => x <= fit + 0.5 && x >= depth + 150).fold<int>(0, math.max);
    if (arm == 0) continue;
    final c = put(cornerTopBoxId, w.id, w.length - arm, z, arm.toDouble(), line - z, depth, right: arm);
    if (c == null) continue;
    corners++;
    taken.putIfAbsent(w.id, () => []).add((w.length - arm, w.length));
    taken.putIfAbsent(next, () => []).add((0, arm.toDouble()));
  }
  // ---- droites : une par haut, rognées sur les angles ; un reste trop étroit va au voisin
  for (final w in walls) {
    final items = p.items.where((c) => c.wallId == w.id && high(e.modelOf(c))).toList()..sort((x, y) => x.s.compareTo(y.s));
    final segs = <(double, double, double)>[]; // début, fin, dessous
    void seg(double s0, double s1, double z) {
      for (final (t0, t1) in taken[w.id] ?? const <(double, double)>[]) {
        if (s0 < t1 && t0 < s1) {
          if (t0 > s0 + 1) {
            s1 = t0;
          } else {
            s0 = t1;
          }
        }
      }
      if (s1 - s0 < 1) return;
      final last = segs.lastOrNull;
      if (last != null && (last.$2 - s0).abs() < 1 && (last.$3 - z).abs() < 1 && (s1 - s0 < 200 || last.$2 - last.$1 < 200) && s1 - last.$1 <= 1200) {
        segs[segs.length - 1] = (last.$1, s1, z);
      } else {
        segs.add((s0, s1, z));
      }
    }

    for (final c in items) {
      final m = e.modelOf(c);
      if (m.shape == CabinetShape.lShape || m.shape == CabinetShape.diagonal) {
        seg(c.s, w.length, c.top); // angle sans casquette d'angle : bras droit
      } else {
        seg(c.s, c.right, c.top);
      }
    }
    for (final (s0, s1, z) in segs) {
      if (put(topBoxId, w.id, s0, z, s1 - s0, line - z, depth) != null) straight++;
    }
    for (final c in p.items.where((c) => c.wallId == w.id && e.modelOf(c).kind == CabinetKind.tall).toList()) {
      if (put(topBoxId, w.id, c.s, c.top, c.width.toDouble(), line - c.top, c.depth) != null) straight++;
    }
  }
  return (straight, corners);
}
