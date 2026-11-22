/// Dégagement d'ouverture : volume balayé par les portes (rotation sur charnières), les tiroirs
/// (coulissement), les abattants (relevage) et les portes basculantes (lave-vaisselle).
/// - « bloqué » : l'ouverture heurte un mur, une colonne ou un autre meuble → angle maximal atteint ;
/// - « pas en même temps » : deux ouvertures se croisent (ex. lave-vaisselle et tiroir dans un angle).
library;

import 'i18n_hook.dart';
import 'dart:math' as math;

import 'catalog.dart';
import 'front_layout.dart';
import 'layout_engine.dart';
import 'project.dart';

typedef _P = (double, double, double);

/// Cases qui s'ouvrent (portes, tiroirs, abattants) : composition du caisson ou modèle standard.
List<FrontCell> openableCells(CabinetModel m, PlacedCabinet c) {
  if (m.kind.isCorner || m.kind.isFiller || !m.isCarcass && m.id != 'base_integrated_dishwasher_door') return const [];
  if (m.id == 'base_integrated_dishwasher_door') return [FrontCell(CellKind.flap, 0, c.height.toDouble(), null, -1)];
  final rows = rowsOf(m, c) ?? seedRows(m, c);
  return cellsOf(rows, c.height).where((x) => _moves(x.kind)).toList();
}

bool _moves(CellKind k) => k == CellKind.door || k == CellKind.door2 || k == CellKind.glass || k == CellKind.flap || k == CellKind.drawer;

/// Points des parties mobiles d'un caisson ouvert à [p] (0..1), par partie.
List<List<_P>> _movingPoints(LayoutEngine e, PlacedCabinet c, double p) {
  final m = e.modelOf(c);
  final cells = openableCells(m, c);
  if (cells.isEmpty || p <= 0) return const [];
  final tb = e.boxesOf(c).first;
  final w = e.project.room.wall(tb.wallId);
  final b = tb.box;
  final (s0, s1, _, t1) = w.boxToWall(b);
  final all = cellsOf(rowsOf(m, c) ?? seedRows(m, c), c.height);
  final total = all.isEmpty ? c.height.toDouble() : all.last.y + all.last.h;
  final kz = (b.z1 - b.z0) / (total <= 0 ? 1 : total);
  _P at(double s, double t, double z) {
    final (x, y) = w.toPlan(s, t);
    return (x, y, z);
  }

  final out = <List<_P>>[];
  final width = s1 - s0;
  for (final cell in cells) {
    final zTop = b.z1 - cell.y * kz, h = cell.h * kz, zBot = zTop - h;
    final zs = [for (var z = zBot + 30; z <= zTop - 30; z += 120) z, zTop - 30];
    switch (cell.kind) {
      case CellKind.door:
      case CellKind.glass:
      case CellKind.door2:
        final a = p * math.pi / 2;
        final halves = cell.kind == CellKind.door2 || (cell.kind == CellKind.glass && width >= 790)
            ? [(s0, width / 2, true), (s0 + width / 2, width / 2, false)]
            : [(s0, width, c.opening == 'hinged_left' || (c.opening != 'hinged_right' && cell.hinge != 'right'))];
        for (final (ls, lw, left) in halves) {
          final hinge = left ? ls : ls + lw;
          final sign = left ? 1.0 : -1.0;
          final pts = <_P>[];
          // panneau de porte (la poignée dépasse vers l'avant, pas sur le côté)
          for (var r = 25.0; r <= lw - 5; r += 40) {
            final ds = sign * math.cos(a) * r, dt = math.sin(a) * r;
            for (final z in zs) {
              final (x, y, _) = at(hinge + ds, t1 + dt + 2, z);
              pts.add((x, y, z));
            }
          }
          out.add(pts);
        }
      case CellKind.drawer:
        final ext = p * math.min(450.0, c.depth - 120.0) + 30; // façade + poignée
        out.add([
          for (var s = s0 + 20; s <= s1 - 20; s += 40)
            for (final z in zs) at(s, t1 + ext, z),
        ]);
      case CellKind.flap:
        final up = m.kind.isHigh;
        final a = p * (up ? 100 : 85) * math.pi / 180;
        final pts = <_P>[];
        for (var r = 25.0; r <= h; r += 60) {
          // abattant relevable : pivote autour du bord haut ; porte basculante : autour du bord bas
          final dt = math.sin(a) * r;
          final dz = up ? -math.cos(a) * r : math.cos(a) * r;
          final z = (up ? zTop : zBot) + dz;
          for (var s = s0 + 20; s <= s1 - 20; s += 60) {
            pts.add(at(s, t1 + dt + 2, z));
          }
        }
        out.add(pts);
      default:
        break;
    }
  }
  return out;
}

bool _inside(_P q, Box3 b, [double eps = 2]) =>
    q.$1 > b.x0 + eps && q.$1 < b.x1 - eps && q.$2 > b.y0 + eps && q.$2 < b.y1 - eps && q.$3 > b.z0 + eps && q.$3 < b.z1 - eps;

/// Obstacles fixes pour [c] : les autres meubles (et le plan de l'îlot).
List<(String, Box3)> _obstacles(LayoutEngine e, PlacedCabinet c) => [
      for (final o in e.project.items)
        if (o.uid != c.uid)
          for (final tb in e.boxesOf(o)) (o.uid, tb.box),
      if (c.wallId != 'I' && e.islandFootprint() != null) ('I', e.islandFootprint()!),
    ];

/// Ouverture maximale possible (0..1) et ce qui l'arrête (uid, « mur » ou null).
(double, String?) openLimit(LayoutEngine e, PlacedCabinet c, {int steps = 9}) {
  final room = e.project.room;
  // volume balayé à toutes les étapes, calculé une fois ; seuls les obstacles qui le touchent sont testés
  // (un obstacle hors de ce volume ne contient aucun point : même résultat, bien moins de tests)
  final sweep = [for (var k = 1; k <= steps; k++) _movingPoints(e, c, k / steps)];
  var x0 = double.infinity, y0 = double.infinity, z0 = double.infinity;
  var x1 = -double.infinity, y1 = -double.infinity, z1 = -double.infinity;
  for (final parts in sweep) {
    for (final part in parts) {
      for (final q in part) {
        if (q.$1 < x0) x0 = q.$1;
        if (q.$1 > x1) x1 = q.$1;
        if (q.$2 < y0) y0 = q.$2;
        if (q.$2 > y1) y1 = q.$2;
        if (q.$3 < z0) z0 = q.$3;
        if (q.$3 > z1) z1 = q.$3;
      }
    }
  }
  final obs = [
    for (final o in _obstacles(e, c))
      if (o.$2.x1 > x0 && o.$2.x0 < x1 && o.$2.y1 > y0 && o.$2.y0 < y1 && o.$2.z1 > z0 && o.$2.z0 < z1) o,
  ];
  for (var k = 1; k <= steps; k++) {
    for (final part in sweep[k - 1]) {
      for (final q in part) {
        if (q.$1 < -1 || q.$2 < -1 || q.$1 > room.width + 1 || q.$2 > room.depth + 1) return ((k - 1) / steps, 'mur');
        for (final (uid, b) in obs) {
          if (_inside(q, b)) return ((k - 1) / steps, uid);
        }
      }
    }
  }
  return (1.0, null);
}

/// Boîte englobante des parties mobiles d'un caisson grand ouvert.
List<Box3> _openBoxes(LayoutEngine e, PlacedCabinet c) => [
      for (final part in _movingPoints(e, c, 1))
        if (part.isNotEmpty)
          Box3(part.map((q) => q.$1).reduce(math.min) - 10, part.map((q) => q.$2).reduce(math.min) - 10, part.map((q) => q.$3).reduce(math.min) - 10,
              part.map((q) => q.$1).reduce(math.max) + 10, part.map((q) => q.$2).reduce(math.max) + 10, part.map((q) => q.$3).reduce(math.max) + 10),
    ];

/// Contrôles d'ouverture de toute la cuisine.
List<Issue> openingChecks(LayoutEngine e) {
  final out = <Issue>[];
  final items = e.project.items.where((c) => openableCells(e.modelOf(c), c).isNotEmpty).toList();
  String name(String uid) => uid == 'mur' ? 'le mur' : uid == 'I' ? 'l\'îlot' : '« ${e.modelOf(e.project.byUid(uid)!).name} »';
  for (final c in items) {
    final (lim, by) = openLimit(e, c);
    if (lim < 0.85 && by != null) {
      final m = e.modelOf(c);
      final drawer = openableCells(m, c).every((x) => x.kind == CellKind.drawer);
      final what = drawer ? 'tiroir sorti à ${(lim * 100).round()} %' : 'ouverture limitée à ${(lim * 90).round()}°';
      out.add(Issue(Severity.warning, 'open_blocked', L('« {0} » : {1}, heurte {2}', [L(m.name), what, name(by)]), [c.uid, if (by != 'mur' && by != 'I') by]));
    }
  }
  // deux ouvertures qui se croisent (on ne peut pas ouvrir les deux en même temps)
  final boxes = {for (final c in items) c.uid: _openBoxes(e, c)};
  for (var i = 0; i < items.length; i++) {
    for (var j = i + 1; j < items.length; j++) {
      final a = items[i], b = items[j];
      if (a.wallId == b.wallId && a.wallId != 'I' && (a.s >= b.right || b.s >= a.right)) {
        // même mur, côte à côte : les portes s'ouvrent vers l'avant, pas l'une dans l'autre
        continue;
      }
      final hit = boxes[a.uid]!.any((x) => boxes[b.uid]!.any((y) => x.intersects(y)));
      if (hit) {
        // lave-vaisselle contre un tiroir : vraie gêne ; ailleurs (angles) : simple information
        final dw = [a, b].any((x) => e.modelOf(x).id == 'base_integrated_dishwasher_door');
        out.add(Issue(dw ? Severity.warning : Severity.info, 'open_pair',
            L('{0} et {1} ne peuvent pas être ouverts en même temps', [name(a.uid), name(b.uid)]), [a.uid, b.uid]));
      }
    }
  }
  return out;
}

/// Comme un cuisiniste : quand une porte ne peut pas s'ouvrir (angle, colonne, mur), on inverse
/// ses charnières si l'ouverture devient meilleure. Renvoie le nombre de portes inversées.
int improveHinges(LayoutEngine e) {
  var n = 0;
  for (final c in e.project.items) {
    final cells = openableCells(e.modelOf(c), c);
    if (!cells.any((x) => x.kind == CellKind.door || x.kind == CellKind.glass)) continue;
    final (lim, _) = openLimit(e, c);
    if (lim >= 0.85) continue;
    final old = c.opening;
    final leftNow = c.opening == 'hinged_left' || (c.opening != 'hinged_right' && cells.first.hinge != 'right');
    c.opening = leftNow ? 'hinged_right' : 'hinged_left';
    final (lim2, _) = openLimit(e, c);
    if (lim2 > lim + 0.05) {
      n++;
    } else {
      c.opening = old;
    }
  }
  return n;
}

/// Contrôles de conception « de pro » : compositions conformes, pas d'appareil dans un haut,
/// plan libre entre évier et plaque, four éloigné du froid, hotte centrée sur la plaque.
List<Issue> designChecks(LayoutEngine e) {
  final out = <Issue>[];
  if (!e.kitchen) return out; // règles de cuisine (hotte, four, évier...)
  final items = e.project.items;
  String n(PlacedCabinet c) => '« ${e.modelOf(c).name} »';
  bool hasOven(CabinetModel m, PlacedCabinet c) =>
      m.id == 'base_cooktop_oven' || m.id == 'base_oven_only' || m.id == 'tall_oven_microwave' || m.id == 'tall_oven_single';
  for (final c in items) {
    final m = e.modelOf(c);
    final rows = rowsOf(m, c);
    if (rows != null) {
      final why = layoutProblem(m.kind, rows, c.height);
      if (why != null) out.add(Issue(Severity.error, 'layout_invalid', '${n(c)} : $why', [c.uid]));
    }
    if (m.kind.isHigh && !m.isHoodUnit && !m.isFreeHood && (c.appliances?.isNotEmpty ?? m.appliances.isNotEmpty)) {
      out.add(Issue(Severity.error, 'wall_appliance', L('{0} : un élément haut ne reçoit pas d\'appareil', [n(c)]), [c.uid]));
    }
  }
  for (final a in items) {
    final ma = e.modelOf(a);
    for (final b in items) {
      if (identical(a, b) || a.wallId != b.wallId) continue;
      final mb = e.modelOf(b);
      final gap = math.max(b.s - a.right, a.s - b.right);
      // évier et plaque : au moins 300 mm de plan entre les deux (éclaboussures, casseroles)
      if (e.washes(a) && e.hasHob(b) && gap < 300 && a.uid.compareTo(b.uid) != 0) {
        out.add(Issue(Severity.warning, 'sink_hob_close',
            L('Évier et plaque à {0} mm : laisser au moins 300 mm de plan de travail entre les deux', [math.max(0, gap).round()]), [a.uid, b.uid]));
      }
      // four contre le réfrigérateur : la chaleur du four nuit au froid
      if (e.isCooling(ma) && hasOven(mb, b) && gap < 10 && gap > -1) {
        out.add(Issue(Severity.warning, 'oven_fridge', L('{0} contre {1} : séparer le four du réfrigérateur par un caisson', [n(b), n(a)]), [a.uid, b.uid]));
      }
    }
    // hotte centrée sur la plaque
    if (ma.isHoodUnit || ma.isFreeHood) {
      for (final hob in items.where((h) => h.wallId == a.wallId && e.cooks(h) && e.modelOf(h).kind.isLow)) {
        if (hob.s < a.right && a.s < hob.right) {
          final off = ((a.s + a.width / 2) - (hob.s + hob.width / 2)).abs();
          if (off > 50) out.add(Issue(Severity.warning, 'hood_offset', L('Hotte décentrée de {0} mm par rapport à la plaque', [off.round()]), [a.uid, hob.uid]));
        }
      }
    }
  }
  return out;
}
