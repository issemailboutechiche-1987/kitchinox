/// Accès à la cuisine depuis chaque porte : une personne doit pouvoir aller de la porte jusqu'à la
/// zone de travail (devant l'évier) par un passage d'au moins [accessMin] mm ([accessAdvised] conseillés).
/// Calcul sur une grille du sol : meubles posés au sol et murs = obstacles ; carte des distances,
/// puis plus large passage possible (chemin dont le point le plus étroit est le plus large).
library;

import 'i18n_hook.dart';
import 'dart:math' as math;

import 'catalog.dart';
import 'layout_engine.dart';
import 'project.dart';

const accessMin = 800;
const accessAdvised = 900;

class DoorAccess {
  final String doorUid;
  final double width; // passage le plus étroit du meilleur chemin (mm) ; 0 = aucun chemin
  const DoorAccess(this.doorUid, this.width);
}

/// Largeur du meilleur passage entre chaque porte et la zone de travail.
List<DoorAccess> doorAccess(LayoutEngine e, {double cell = 50}) {
  final p = e.project;
  final r = p.room;
  final doors = p.openings.where((o) => o.isDoor).toList();
  if (doors.isEmpty || p.items.isEmpty) return const [];
  final nx = (r.width / cell).ceil(), ny = (r.depth / cell).ceil();
  final blocked = List.filled(nx * ny, false);
  // meubles au sol (et colonnes) : leur emprise bloque le passage
  for (final c in p.items) {
    for (final tb in e.boxesOf(c)) {
      final b = tb.box;
      if (b.z0 > 900) continue; // éléments hauts : on passe dessous
      final x0 = (b.x0 / cell).floor().clamp(0, nx - 1), x1 = ((b.x1 / cell).ceil() - 1).clamp(0, nx - 1);
      final y0 = (b.y0 / cell).floor().clamp(0, ny - 1), y1 = ((b.y1 / cell).ceil() - 1).clamp(0, ny - 1);
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          blocked[y * nx + x] = true;
        }
      }
    }
  }
  // pièce à contour libre : les cases hors de la pièce sont des obstacles
  if (r.outline != null) {
    for (var y = 0; y < ny; y++) {
      for (var x = 0; x < nx; x++) {
        if (!r.contains((x + 0.5) * cell, (y + 0.5) * cell)) blocked[y * nx + x] = true;
      }
    }
  }
  // distance (mm) du centre de chaque case libre au plus proche obstacle ou mur : chanfrein 8 voisins
  const inf = 1e9;
  final dist = List<double>.filled(nx * ny, inf);
  for (var y = 0; y < ny; y++) {
    for (var x = 0; x < nx; x++) {
      final i = y * nx + x;
      if (blocked[i]) {
        dist[i] = 0;
      } else {
        // murs : distance aux bords de la pièce
        final cx = (x + 0.5) * cell, cy = (y + 0.5) * cell;
        dist[i] = math.min(math.min(cx, r.width - cx), math.min(cy, r.depth - cy));
      }
    }
  }
  final d1 = cell, d2 = cell * math.sqrt2;
  for (var y = 0; y < ny; y++) {
    for (var x = 0; x < nx; x++) {
      final i = y * nx + x;
      var v = dist[i];
      if (x > 0) v = math.min(v, dist[i - 1] + d1);
      if (y > 0) {
        v = math.min(v, dist[i - nx] + d1);
        if (x > 0) v = math.min(v, dist[i - nx - 1] + d2);
        if (x < nx - 1) v = math.min(v, dist[i - nx + 1] + d2);
      }
      dist[i] = v;
    }
  }
  for (var y = ny - 1; y >= 0; y--) {
    for (var x = nx - 1; x >= 0; x--) {
      final i = y * nx + x;
      var v = dist[i];
      if (x < nx - 1) v = math.min(v, dist[i + 1] + d1);
      if (y < ny - 1) {
        v = math.min(v, dist[i + nx] + d1);
        if (x < nx - 1) v = math.min(v, dist[i + nx + 1] + d2);
        if (x > 0) v = math.min(v, dist[i + nx - 1] + d2);
      }
      dist[i] = v;
    }
  }
  int at(double px, double py) => (py / cell).floor().clamp(0, ny - 1) * nx + (px / cell).floor().clamp(0, nx - 1);

  // zone de travail : devant l'évier, sinon le point le plus dégagé de la pièce
  int target;
  final sink = p.items.where((c) => e.washes(c)).firstOrNull;
  if (sink != null && sink.wallId != 'I') {
    final w = r.wall(sink.wallId);
    final (tx, ty) = w.toPlan(sink.s + sink.width / 2, sink.depth + 500.0);
    target = at(tx, ty);
  } else {
    target = 0;
    for (var i = 1; i < dist.length; i++) {
      if (dist[i] > dist[target]) target = i;
    }
  }

  // cases libres de la plus dégagée à la moins dégagée (une seule fois pour toutes les portes)
  final order = [for (var i = 0; i < dist.length; i++) if (!blocked[i]) i]..sort((a, b) => dist[b].compareTo(dist[a]));
  final out = <DoorAccess>[];
  for (final o in doors) {
    final w = r.wall(o.wallId);
    // départ juste au-delà de la demi-largeur de passage : le mur de la porte ne doit pas limiter le passage
    // (sinon une porte de 800 mm serait toujours jugée trop étroite)
    final (sx, sy) = w.toPlan(o.s + o.width / 2, math.max(o.width, accessMin) / 2 + cell);
    final start = at(sx, sy);
    // chemin « le plus large » : on ajoute les cases de la plus dégagée à la moins dégagée en reliant
    // les voisines (union-find) ; dès que la porte et la cuisine sont reliées, le passage vaut la dernière case
    final best = <double>[_widestLink(order, dist, blocked, nx, ny, start, target)];
    // la porte elle-même limite le passage : on ne compte pas plus large que son ouverture
    final width = best.first <= 0 ? 0.0 : math.min(2 * best.first, o.width);
    out.add(DoorAccess(o.uid, width));
  }
  return out;
}

double _widestLink(List<int> order, List<double> dist, List<bool> blocked, int nx, int ny, int start, int target) {
  if (blocked[start] || blocked[target]) return 0;
  final parent = List<int>.filled(dist.length, -1); // -1 : case pas encore ajoutée
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  for (final i in order) {
    parent[i] = i;
    final x = i % nx, y = i ~/ nx;
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]) {
      final xx = x + dx, yy = y + dy;
      if (xx < 0 || yy < 0 || xx >= nx || yy >= ny) continue;
      final j = yy * nx + xx;
      if (parent[j] < 0) continue;
      final ri = find(i), rj = find(j);
      if (ri != rj) parent[ri] = rj;
    }
    if (parent[start] >= 0 && parent[target] >= 0 && find(start) == find(target)) return dist[i];
  }
  return 0;
}

/// Contrôles d'accès : passage trop étroit entre une porte et la cuisine.
List<Issue> accessChecks(LayoutEngine e) {
  final dest = e.kitchen ? 'la cuisine' : 'les meubles';
  return [
      for (final a in doorAccess(e))
        if (a.width < accessMin - 25)
          Issue(Severity.error, 'door_access',
              a.width <= 0
                  ? L('Accès bloqué : aucun passage entre la porte et {0}', [dest])
                  : L('Accès trop étroit : passage de {0} mm entre la porte et {1} ({2} mm minimum)', [(a.width / 10).round() * 10, dest, accessMin]),
              [a.doorUid])
        // conseil : seulement si ce sont les meubles qui rétrécissent le passage (pas la porte elle-même)
        else if (a.width < math.min(accessAdvised, e.project.openings.firstWhere((x) => x.uid == a.doorUid).width) - 25)
          Issue(Severity.info, 'door_access_tight',
              L('Accès un peu serré : passage de {0} mm depuis la porte ({1} mm conseillés)', [(a.width / 10).round() * 10, accessAdvised]), [a.doorUid]),
    ];
}

/// Dégage l'entrée : tant qu'une porte n'a pas son passage de 800 mm vers la cuisine, on retire le
/// meuble au sol le plus proche de cette porte (jamais l'évier, la cuisson ni le froid) et les hauts
/// au-dessus. Faux si l'accès reste impossible.
bool clearDoorAccess(LayoutEngine e, {double min = accessMin - 25.0}) {
  final p = e.project;
  for (var k = 0; k < 6; k++) {
    final blocked = doorAccess(e).where((a) => a.width < min).firstOrNull;
    if (blocked == null) return true;
    final door = p.openings.where((o) => o.uid == blocked.doorUid).firstOrNull;
    if (door == null) return false;
    final w = p.room.wall(door.wallId);
    final (dx, dy) = w.toPlan(door.s + door.width / 2, door.width / 2);
    double near(Box3 b) {
      final ex = math.max(0.0, math.max(b.x0 - dx, dx - b.x1)), ey = math.max(0.0, math.max(b.y0 - dy, dy - b.y1));
      return math.sqrt(ex * ex + ey * ey);
    }

    PlacedCabinet? victim;
    var best = double.infinity;
    for (final c in p.items) {
      final m = e.modelOf(c);
      if (!(m.kind.isLow || m.kind == CabinetKind.tall)) continue;
      if (e.washes(c) || e.cooks(c) || e.cools(c)) continue;
      final d = e.boxesOf(c).map((tb) => near(tb.box)).reduce(math.min);
      if (d < best) {
        best = d;
        victim = c;
      }
    }
    if (victim == null) return false;
    final v = victim;
    p.items.removeWhere((c) =>
        identical(c, v) || (c.wallId == v.wallId && e.modelOf(c).kind.isHigh && c.s < v.right - 1 && v.s < c.right - 1 && !e.cooks(c)));
  }
  return doorAccess(e).every((a) => a.width >= min);
}
