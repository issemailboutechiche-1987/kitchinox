// Tracé des réseaux en 3D : depuis le tableau électrique et les arrivées d'eau / de gaz, des conduits
// qui longent les murs jusqu'à chaque point (prises, interrupteurs, points lumineux, robinets, évacuations).
// Électricité : gaine horizontale en haut des murs puis descentes verticales, trois conducteurs
// (phase rouge, neutre bleu, terre vert / jaune). Eau froide / chaude en bas des murs, évacuations
// en pente vers la descente, gaz en tube jaune.

import 'dart:math' as math;

import 'home_appliances.dart';
import 'networks.dart';
import 'project.dart';

/// Un conducteur ou un tuyau : polyligne en mm (x, y en plan, z depuis le sol).
class NetRun {
  final String wire; // L N PE data cold hot drain gas
  final double radius; // mm
  final List<(double, double, double)> pts;
  const NetRun(this.wire, this.radius, this.pts);

  Map<String, dynamic> toJson() => {
        'w': wire,
        'r': radius,
        'p': [for (final (x, y, z) in pts) [x.roundToDouble(), y.roundToDouble(), z.roundToDouble()]],
      };
}

/// Couleurs normalisées des conducteurs et des réseaux.
const netWireColors = <String, int>{
  'L': 0xD32F2F, // phase : rouge (ou marron)
  'N': 0x1E63C8, // neutre : bleu
  'PE': 0x4CAF50, // terre : vert / jaune (rayé jaune en 3D)
  'data': 0x7048E8,
  'cold': 0x1C7ED6,
  'hot': 0xE03131,
  'drain': 0x8A8F96,
  'gas': 0xF2B705,
};

/// Le tracé : conduits et position du tableau électrique.
class NetLayout {
  final List<NetRun> runs;
  final (double, double, double)? board; // centre du tableau
  final (double, double)? boardNormal; // vers l'intérieur de la pièce
  final (double, double)? boardDir; // le long du mur
  const NetLayout(this.runs, {this.board, this.boardNormal, this.boardDir});
}

class _Perimeter {
  final List<Wall> walls;
  final List<double> start = [];
  double total = 0;
  _Perimeter(this.walls) {
    for (final w in walls) {
      start.add(total);
      total += w.length;
    }
  }

  double norm(double t) => ((t % total) + total) % total;

  int wallAt(double t) {
    t = norm(t);
    for (var i = walls.length - 1; i >= 0; i--) {
      if (t >= start[i]) return i;
    }
    return 0;
  }

  /// Point à l'abscisse [t] du tour, à [off] mm du mur, à la hauteur [z].
  (double, double, double) at(double t, double off, double z) {
    final i = wallAt(t);
    final w = walls[i];
    final s = (norm(t) - start[i]).clamp(math.min(off, w.length / 2), math.max(w.length - off, w.length / 2)).toDouble();
    final (x, y) = w.toPlan(s, off);
    return (x, y, z);
  }

  /// Chemin le plus court le long des murs de [t0] à [t1] (coins compris).
  List<(double, double, double)> path(double t0, double t1, double off, double z) {
    final fwd = norm(t1 - t0);
    final forward = fwd <= total / 2;
    final len = forward ? fwd : total - fwd;
    final out = [at(t0, off, z)];
    // coins traversés
    final corners = <double>[];
    for (var i = 0; i < walls.length; i++) {
      final c = start[i];
      final d = forward ? norm(c - t0) : norm(t0 - c);
      if (d > 1 && d < len - 1) corners.add(d);
    }
    corners.sort();
    for (final d in corners) {
      final c = forward ? t0 + d : t0 - d;
      // coin intérieur : fin du mur précédent, à [off] du mur suivant
      final i = wallAt(norm(c) - 0.5);
      final w = walls[i];
      final (x, y) = w.toPlan(math.max(w.length - off, 0), off);
      out.add((x, y, z));
    }
    out.add(at(t1, off, z));
    return out;
  }

  /// Abscisse du tour la plus proche du point (x, y) du plan.
  double nearest(double x, double y) {
    var best = 0.0, bd = double.infinity;
    for (var i = 0; i < walls.length; i++) {
      final w = walls[i];
      final (s, _) = w.toWall(x, y);
      final sc = s.clamp(0, w.length).toDouble();
      final (px, py) = w.toPlan(sc, 0);
      final d = math.sqrt(math.pow(px - x, 2) + math.pow(py - y, 2));
      if (d < bd) {
        bd = d;
        best = start[i] + sc;
      }
    }
    return best;
  }
}

List<(double, double, double)> _join(List<List<(double, double, double)>> parts) {
  final out = <(double, double, double)>[];
  for (final p in parts) {
    for (final q in p) {
      if (out.isNotEmpty) {
        final l = out.last;
        if ((l.$1 - q.$1).abs() < 0.5 && (l.$2 - q.$2).abs() < 0.5 && (l.$3 - q.$3).abs() < 0.5) continue;
      }
      out.add(q);
    }
  }
  return out;
}

/// Conducteurs d'un point électrique.
List<String> _wiresOf(NetKind k) {
  if (k.network == 'data') return const ['data'];
  if (k.isSwitch) return const ['L'];
  return const ['L', 'N', 'PE'];
}

/// Tracé des réseaux de [p] (points visibles posés sur les murs, le plafond ou l'îlot).
NetLayout netLayout(Project p) {
  final room = p.room;
  final walls = room.walls;
  if (walls.isEmpty) return const NetLayout([]);
  final per = _Perimeter(walls);
  if (per.total <= 0) return const NetLayout([]);
  final pts = visiblePoints(p).toList();
  final runs = <NetRun>[];
  final h = room.height;
  final high = h - 150; // gaine électrique en haut des murs

  double tOf(NetPoint x) => per.start[walls.indexWhere((w) => w.id == x.wallId)] + x.s;
  bool onWall(NetPoint x) => walls.any((w) => w.id == x.wallId);

  // ---- tableau électrique : à côté de la porte, à 1,40 m (bas entre 1,00 et 1,80 m)
  double tBoard;
  final door = p.openings.where((o) => o.isDoor && walls.any((w) => w.id == o.wallId)).firstOrNull;
  if (door != null) {
    final i = walls.indexWhere((w) => w.id == door.wallId);
    final w = walls[i];
    final after = door.s + door.width + 300;
    tBoard = per.start[i] + (after + 250 < w.length ? after : math.max(250, door.s - 300));
  } else {
    tBoard = 350;
  }
  const boardZ = 1400.0, boardTop = 1650.0;
  final bw = walls[per.wallAt(tBoard)];
  final (bx, by, _) = per.at(tBoard, 60, boardZ);

  final elec = pts.where((x) => x.kind.network == 'elec' || x.kind.network == 'data').toList();
  for (final x in elec) {
    final ws = _wiresOf(x.kind);
    for (var k = 0; k < ws.length; k++) {
      final wire = ws[k];
      final ds = (k - 1) * 22.0 + (wire == 'data' ? 70 : 0); // conducteurs côte à côte
      final dz = (k - 1) * 22.0;
      const off = 18.0;
      final zt = high + dz;
      final up = [per.at(tBoard + ds, off, boardTop), per.at(tBoard + ds, off, zt)];
      if (onWall(x)) {
        final t = tOf(x);
        final zEnd = x.z + (x.z < zt ? 45 : -45);
        runs.add(NetRun(wire, 6, _join([up, per.path(tBoard + ds, t + ds, off, zt), [per.at(t + ds, off, zEnd)]])));
      } else if (x.onCeiling) {
        // plafond : jusqu'au mur le plus proche, puis sous le plafond jusqu'au point
        final t = per.nearest(x.s, x.z);
        final (wx, wy, _) = per.at(t + ds, off, 0);
        runs.add(NetRun(wire, 6, _join([up, per.path(tBoard + ds, t + ds, off, zt), [(wx, wy, h - 30 + dz / 3), (x.s + ds, x.z, h - 30 + dz / 3)]])));
      } else if (x.wallId == 'I' && room.island != null) {
        // îlot : par le sol, sous la chape
        final w = room.wall('I');
        final (ix, iy) = w.toPlan(x.s + ds, -40);
        final t = per.nearest(ix, iy);
        final (wx, wy, _) = per.at(t + ds, off, 0);
        runs.add(NetRun(wire, 6, _join([up, per.path(tBoard + ds, t + ds, off, zt), [per.at(t + ds, off, 25 + dz / 2), (wx, wy, 25 + dz / 2), (ix, iy, 25 + dz / 2), (ix, iy, x.z - 45)]])));
      }
    }
  }

  // ---- eau : arrivée dans le coin du premier mur qui en a besoin, en bas des murs
  final water = pts.where((x) => x.kind.network == 'water' && onWall(x)).toList();
  final drains = pts.where((x) => x.kind.network == 'drain' && onWall(x)).toList();
  final gas = pts.where((x) => x.kind.network == 'gas' && onWall(x)).toList();
  double sourceOf(List<NetPoint> l) {
    final i = walls.indexWhere((w) => w.id == l.first.wallId);
    return per.start[i] + 150;
  }

  if (water.isNotEmpty) {
    final src = sourceOf(water);
    // eau chaude : depuis le chauffe-eau s'il y en a un dans la pièce
    final heater = p.objects.where((o) => isHeater(o.fixture)).firstOrNull;
    final hotSrc = heater != null ? per.nearest(heater.x, heater.y) : src + 60;
    for (final x in water) {
      final t = tOf(x);
      final hot = x.kind == NetKind.waterHot;
      final s0 = hot ? hotSrc : src;
      final ds = hot ? 30.0 : -30.0;
      const off = 28.0;
      final low = hot ? 230.0 : 180.0;
      final start = heater != null && hot
          ? [(heater.x, heater.y, heater.z + 150), per.at(s0, off, heater.z + 150), per.at(s0, off, low)]
          : [per.at(s0, off, 0), per.at(s0, off, low)];
      runs.add(NetRun(hot ? 'hot' : 'cold', 8, _join([start, per.path(s0, t + ds, off, low), [per.at(t + ds, off, x.z - 30)]])));
    }
  }
  if (drains.isNotEmpty) {
    final src = sourceOf(drains) - 60;
    for (final x in drains) {
      final t = tOf(x);
      final r = x.kind == NetKind.drainWc ? 50.0 : 20.0;
      const off = 45.0;
      // pente 1 cm/m vers la descente
      final path = per.path(t, src, off, 0);
      var acc = 0.0;
      final z0 = math.min(x.z, 120.0) + r;
      final slope = <(double, double, double)>[];
      for (var i = 0; i < path.length; i++) {
        if (i > 0) acc += math.sqrt(math.pow(path[i].$1 - path[i - 1].$1, 2) + math.pow(path[i].$2 - path[i - 1].$2, 2));
        slope.add((path[i].$1, path[i].$2, math.max(r, z0 - acc * 0.01)));
      }
      runs.add(NetRun('drain', r, _join([[per.at(t, off, x.z)], slope, [per.at(src, off, 0)]])));
    }
  }
  for (final x in gas) {
    final src = sourceOf(gas) + 120;
    final t = tOf(x);
    const off = 24.0;
    runs.add(NetRun('gas', 7, _join([[per.at(src, off, 0)], per.path(src, t, off, 300), [per.at(t, off, x.z)]])));
  }
  return NetLayout(runs, board: (bx, by, boardZ), boardNormal: (bw.nx, bw.ny), boardDir: (bw.dx, bw.dy));
}
