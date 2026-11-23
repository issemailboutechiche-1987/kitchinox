/// Objets de la pièce (hors caissons) : sanitaires paramétriques kitchinox (cotes réelles, dégagements,
/// arrivées d'eau et évacuations) et objets de décoration du catalogue libre (CC0), posés librement en plan.
library;

import 'i18n_hook.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'home_appliances.dart';
import 'layout_engine.dart';
import 'materials.dart' show PriceRange;
import 'project.dart';

/// Sanitaire paramétrique : tailles proposées, hauteur, hauteur de pose, dégagement devant, points d'eau.
class FixtureType {
  final String id, name, category;
  final List<(int, int)> sizes; // largeur x profondeur (mm)
  final int h, z; // hauteur de l'objet, hauteur de pose (bas)
  final int clearance; // dégagement libre devant (mm)
  final List<(String, double, int)> water; // (nature : froide | chaude | evac, position en largeur 0..1, hauteur)
  final String note;
  final List<FixtureVariant> variants; // capacités proposées (vide : seulement des tailles)
  final int def; // capacité par défaut
  const FixtureType(this.id, this.name, this.category, this.sizes, this.h, this.z, this.clearance, this.water, this.note, {this.variants = const [], this.def = 0});

  FixtureVariant? get defaultVariant => variants.isEmpty ? null : variants[def];
}

/// Capacité d'un appareil : libellé (80 L, 8 kg…), cotes hors tout, hauteur de pose, prix indicatif.
class FixtureVariant {
  final String label;
  final int w, d, h;
  final double min, max;
  final int? z;
  const FixtureVariant(this.label, this.w, this.d, this.h, this.min, this.max, {this.z});

  PriceRange get price => PriceRange(min, max);
}

const fixtureTypes = <FixtureType>[
  FixtureType('wc_suspendu', 'WC suspendu + bâti-support', 'Sanitaires', [(360, 540), (360, 490)], 400, 0, 600,
      [('froide', 0.75, 1000), ('evac', 0.5, 230)], 'Bâti-support 500 mm derrière le mur fini ; assise à 400 mm.'),
  FixtureType('wc_sol', 'WC à poser', 'Sanitaires', [(380, 650), (360, 700)], 780, 0, 600, [('froide', 0.8, 150), ('evac', 0.5, 180)],
      'Sortie horizontale ou verticale ; réservoir attenant.'),
  FixtureType('bidet', 'Bidet suspendu', 'Sanitaires', [(360, 540)], 400, 0, 600, [('froide', 0.3, 650), ('chaude', 0.7, 650), ('evac', 0.5, 230)], ''),
  FixtureType('lavabo', 'Lavabo suspendu', 'Sanitaires', [(500, 400), (600, 460), (800, 460)], 180, 670, 700,
      [('froide', 0.35, 550), ('chaude', 0.65, 550), ('evac', 0.5, 500)], 'Plan de vasque à 850 mm.'),
  FixtureType('vasque_double', 'Plan double vasque', 'Sanitaires', [(1200, 500), (1400, 500), (1600, 500)], 150, 700, 700,
      [('froide', 0.25, 550), ('chaude', 0.3, 550), ('evac', 0.27, 500), ('froide', 0.7, 550), ('chaude', 0.75, 550), ('evac', 0.73, 500)], ''),
  FixtureType('baignoire', 'Baignoire', 'Sanitaires', [(1600, 700), (1700, 750), (1800, 800)], 580, 0, 700,
      [('froide', 0.12, 750), ('chaude', 0.18, 750), ('evac', 0.1, 50)], 'Tablier à prévoir ; mitigeur à 200 mm au-dessus du bord.'),
  FixtureType('douche', 'Receveur de douche + paroi', 'Sanitaires', [(800, 800), (900, 900), (1200, 800), (1400, 900)], 2000, 0, 700,
      [('froide', 0.45, 1100), ('chaude', 0.55, 1100), ('evac', 0.5, 0)], 'Receveur extra-plat 40 mm, paroi verre 8 mm hauteur 2000.'),
  FixtureType('douche_italienne', 'Douche à l’italienne', 'Sanitaires', [(1200, 900), (1400, 1000), (1600, 900)], 2000, 0, 700,
      [('froide', 0.45, 1100), ('chaude', 0.55, 1100), ('evac', 0.85, 0)], 'Sol à pente 1 à 2 %, caniveau au fond.'),
  FixtureType('seche_serviettes', 'Radiateur sèche-serviettes', 'Sanitaires', [(500, 100), (600, 100)], 1200, 200, 500, [],
      'Prise ou sortie de câble à 200 mm du sol, hors volume 1.'),
  FixtureType('miroir', 'Miroir LED', 'Sanitaires', [(600, 30), (800, 30), (1000, 30), (1200, 30)], 800, 1050, 0, [],
      'Miroir rétroéclairé ; prise ou sortie de câble à côté, hors volume 1.'),
  ...homeAppliances,
];

FixtureType? fixtureById(String id) => fixtureTypes.where((f) => f.id == id).firstOrNull;

/// Objet du catalogue libre (modèle 3D glTF) avec ses dimensions réelles.
class CatalogObject {
  final String id, name, category, file, thumb;
  final int w, h, d;
  final bool wall; // se pose contre un mur
  final int yaw; // rotation du modèle pour que sa largeur soit le long de x (degrés)
  final bool ceiling; // suspendu au plafond
  final bool hidden; // remplacé par un modèle plus réaliste : gardé pour les anciens projets, absent du catalogue
  final String source; // Poly Haven, Kenney (licence CC0)
  const CatalogObject(this.id, this.name, this.category, this.file, this.thumb, this.w, this.h, this.d, this.wall,
      {this.yaw = 0, this.ceiling = false, this.hidden = false, this.source = ''});

  /// Catalogue chargé (pour nommer les objets dans les plans, le devis et les PDF).
  static final Map<String, CatalogObject> byId = {};

  static List<CatalogObject> parse(String src) {
    final out = [
      for (final o in (jsonDecode(src) as Map<String, dynamic>)['objects'] as List)
        CatalogObject('${o['id']}', '${o['name']}', '${o['category']}', '${o['file']}', '${o['thumb']}', (o['w'] as num).toInt(), (o['h'] as num).toInt(),
            (o['d'] as num).toInt(), o['wall'] == true,
            yaw: (o['yaw'] as num?)?.toInt() ?? 0, ceiling: o['ceiling'] == true, hidden: o['hidden'] == true, source: '${o['source'] ?? ''}'),
    ];
    for (final c in out) {
      byId[c.id] = c;
    }
    return out;
  }
}

/// Objet posé : référence `fixture:id` (sanitaire) ou id du catalogue ; centre (x, y) en plan, rotation 0/90/180/270
/// (0 : le dos vers le mur A, la face vers l'intérieur de la pièce).
class RoomObject {
  final String uid;
  final String ref;
  double x, y, z;
  int rot;
  int w, h, d;
  String? variant; // capacité choisie (80 L, 8 kg…)
  RoomObject({required this.uid, required this.ref, required this.x, required this.y, this.z = 0, this.rot = 0, required this.w, required this.h, required this.d, this.variant});

  bool get isFixture => ref.startsWith('fixture:');
  FixtureType? get fixture => isFixture ? fixtureById(ref.substring(8)) : null;

  /// Capacité : celle choisie, sinon celle dont les cotes correspondent.
  FixtureVariant? get capacity {
    final vs = fixture?.variants ?? const <FixtureVariant>[];
    if (variant != null) return vs.where((v) => v.label == variant).firstOrNull;
    return vs.where((v) => v.w == w && v.d == d && v.h == h).firstOrNull;
  }

  /// Prend la capacité [v] : cotes et hauteur de pose, sans dépasser le plafond.
  void setCapacity(FixtureVariant v, double ceiling) {
    variant = v.label;
    w = v.w;
    d = v.d;
    h = v.h;
    final at = (v.z ?? fixture?.z ?? 0).toDouble();
    z = at <= 0 ? 0 : math.max(0, math.min(at, ceiling - h - 100));
  }

  /// Emprise au sol (x0, y0, x1, y1), rotation comprise.
  (double, double, double, double) get footprint {
    final turned = rot % 180 != 0;
    final fw = turned ? d : w, fd = turned ? w : d;
    return (x - fw / 2, y - fd / 2, x + fw / 2, y + fd / 2);
  }

  /// Sens « vers l'avant » (de la face) en plan.
  (double, double) get front => switch (rot % 360) { 90 => (-1.0, 0.0), 180 => (0.0, -1.0), 270 => (1.0, 0.0), _ => (0.0, 1.0) };

  RoomObject copy({String? uid}) => RoomObject(uid: uid ?? this.uid, ref: ref, x: x, y: y, z: z, rot: rot, w: w, h: h, d: d, variant: variant);

  Map<String, dynamic> toJson() => {'uid': uid, 'ref': ref, 'x': x, 'y': y, 'z': z, 'rot': rot, 'w': w, 'h': h, 'd': d, if (variant != null) 'variant': variant};
  factory RoomObject.fromJson(Map<String, dynamic> j) => RoomObject(
        uid: '${j['uid']}',
        ref: '${j['ref']}',
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        z: (j['z'] as num?)?.toDouble() ?? 0,
        rot: (j['rot'] as num?)?.toInt() ?? 0,
        w: (j['w'] as num).toInt(),
        h: (j['h'] as num).toInt(),
        d: (j['d'] as num).toInt(),
        variant: j['variant'] as String?,
      );
}

/// Mur le plus proche de l'objet et la rotation qui y plaque son dos.
(String, int, double) nearestWallFor(Room room, double x, double y) {
  if (room.outline != null) {
    // pièce quelconque : mur droit (parallèle aux axes) le plus proche, le point se projetant sur lui
    (String, int, double)? best;
    for (final w in room.walls.where((w) => w.orthogonal)) {
      final (s, t) = w.toWall(x, y);
      if (t < -50) continue; // derrière le mur
      final out = s < 0 ? -s : (s > w.length ? s - w.length : 0.0);
      final d = t.abs() + out * 3;
      if (best == null || d < best.$3) best = (w.id, w.rot, d);
    }
    if (best != null) return best;
  }
  final cands = <(String, int, double)>[
    ('A', 0, y),
    ('B', 90, room.width - x),
    ('D', 180, room.depth - y),
    ('C', 270, x),
  ];
  cands.sort((a, b) => a.$3.compareTo(b.$3));
  return cands.first;
}

/// Plaque l'objet contre le mur le plus proche (dos au mur), en gardant sa position le long du mur.
void snapToWall(Room room, RoomObject o) {
  final (wid, rot, _) = nearestWallFor(room, o.x, o.y);
  o.rot = rot;
  if (room.outline != null) {
    // contre le mur choisi, centré sur la projection, sans dépasser ses extrémités
    final w = room.wall(wid);
    final half = (rot % 180 == 0 ? o.w : o.d) / 2, depth = (rot % 180 == 0 ? o.d : o.w) / 2;
    final (s0, _) = w.toWall(o.x, o.y);
    final s1 = w.length < 2 * half ? w.length / 2 : s0.clamp(half, w.length - half);
    final (x, y) = w.toPlan(s1.toDouble(), depth);
    o
      ..x = x
      ..y = y;
    return;
  }
  final (x0, y0, x1, y1) = o.footprint;
  final hw = (x1 - x0) / 2, hd = (y1 - y0) / 2;
  switch (rot) {
    case 0:
      o.y = hd;
    case 90:
      o.x = room.width - hw;
    case 180:
      o.y = room.depth - hd;
    default:
      o.x = hw;
  }
  o.x = o.x.clamp(hw, room.width - hw);
  o.y = o.y.clamp(hd, room.depth - hd);
}

/// Ramène l'objet dans la pièce (après un changement de dimensions) ; un objet qui avait le dos
/// contre un mur y reste plaqué.
void keepInRoom(Room room, RoomObject o, {required bool wasOnWall}) {
  final (x0, y0, x1, y1) = o.footprint;
  final hw = (x1 - x0) / 2, hd = (y1 - y0) / 2;
  o.x = o.x.clamp(hw, math.max(hw, room.width - hw)).toDouble();
  o.y = o.y.clamp(hd, math.max(hd, room.depth - hd)).toDouble();
  if (!wasOnWall) return;
  if (room.outline != null) {
    snapToWall(room, o);
    return;
  }
  switch (o.rot % 360) {
    case 0:
      o.y = hd;
    case 90:
      o.x = room.width - hw;
    case 180:
      o.y = room.depth - hd;
    default:
      o.x = hw;
  }
}

/// L'objet a-t-il le dos contre son mur (à 5 mm près) ?
bool onItsWall(Room room, RoomObject o) {
  if (room.outline != null) {
    final w = room.wall(fixtureWall(o, room));
    final (_, t) = w.toWall(o.x, o.y);
    return (t - (o.rot % 180 == 0 ? o.d : o.w) / 2).abs() < 5;
  }
  final (x0, y0, x1, y1) = o.footprint;
  return switch (o.rot % 360) {
    0 => y0.abs() < 5,
    90 => (x1 - room.width).abs() < 5,
    180 => (y1 - room.depth).abs() < 5,
    _ => x0.abs() < 5,
  };
}

/// Dégagements devant les sanitaires : un meuble, un caisson ou un autre objet dans la zone libre → avertissement.
List<Issue> objectChecks(LayoutEngine e) {
  final p = e.project;
  final out = <Issue>[];
  bool overlap((double, double, double, double) a, (double, double, double, double) b) => a.$1 < b.$3 - 1 && b.$1 < a.$3 - 1 && a.$2 < b.$4 - 1 && b.$2 < a.$4 - 1;
  final obstacles = <(String, (double, double, double, double), double)>[
    for (final c in p.items)
      for (final tb in e.boxesOf(c))
        if (tb.box.z0 < 900) (c.uid, (tb.box.x0, tb.box.y0, tb.box.x1, tb.box.y1), tb.box.z1),
    for (final o in p.objects) if (o.h > 100) (o.uid, o.footprint, o.z + o.h),
  ];
  for (final o in p.objects) {
    final (ox0, oy0, ox1, oy1) = o.footprint;
    if (ox0 < -1 || oy0 < -1 || ox1 > p.room.width + 1 || oy1 > p.room.depth + 1) {
      out.add(Issue(Severity.error, 'object_outside', L('{0} sort de la pièce', [objectName(o)]), [o.uid]));
    }
  }
  for (final o in p.objects) {
    final f = o.fixture;
    if (f == null || f.clearance <= 0) continue;
    final (x0, y0, x1, y1) = o.footprint;
    final (fx, fy) = o.front;
    final c = f.clearance.toDouble();
    final zone = fx != 0 ? (fx > 0 ? (x1, y0, x1 + c, y1) : (x0 - c, y0, x0, y1)) : (fy > 0 ? (x0, y1, x1, y1 + c) : (x0, y0 - c, x1, y0));
    // chauffe-eau accroché au-dessus des meubles : ils ne gênent pas sa façade
    final hit = obstacles.where((ob) => ob.$1 != o.uid && overlap(zone, ob.$2) && !(isHeater(f) && ob.$3 <= o.z + 60)).toList();
    if (hit.isNotEmpty) {
      out.add(Issue(Severity.warning, 'fixture_clearance', L('{0} : {1} mm libres devant conseillés', [L(f.name), f.clearance]), [o.uid, ...hit.map((h) => h.$1)]));
    }
    final room = p.room;
    if (zone.$1 < -1 || zone.$2 < -1 || zone.$3 > room.width + 1 || zone.$4 > room.depth + 1) {
      out.add(Issue(Severity.warning, 'fixture_clearance', L('{0} : le dégagement devant sort de la pièce', [L(f.name)]), [o.uid]));
    }
  }
  return out;
}

/// Nom lisible d'un objet posé.
String objectName(RoomObject o) {
  final n = L(o.fixture?.name ?? CatalogObject.byId[o.ref]?.name ?? 'Objet'), v = o.capacity;
  return v == null ? n : '$n ${v.label}';
}

/// Position d'un objet le long de son mur : (mur, début, fin) en mm depuis le départ du mur.
(String, double, double) objectOnWall(Room room, RoomObject o) {
  final wall = fixtureWall(o, room);
  final w = room.wall(wall);
  final (x0, y0, x1, y1) = o.footprint;
  final (a, _) = w.toWall(x0, y0);
  final (b, _) = w.toWall(x1, y1);
  return (wall, math.min(a, b), math.max(a, b));
}

/// Mur contre lequel l'objet a le dos (d'après sa rotation).
String fixtureWall(RoomObject o, [Room? room]) {
  if (room == null || room.outline == null) return const {0: 'A', 90: 'B', 180: 'D', 270: 'C'}[o.rot % 360] ?? 'A';
  // pièce quelconque : le mur droit de même orientation le plus proche du dos de l'objet
  String? best;
  var bestD = double.infinity;
  for (final w in room.walls.where((w) => w.orthogonal && w.rot == o.rot % 360)) {
    final (s, t) = w.toWall(o.x, o.y);
    final out = s < 0 ? -s : (s > w.length ? s - w.length : 0.0);
    final d = t.abs() + out * 2;
    if (d < bestD) {
      bestD = d;
      best = w.id;
    }
  }
  return best ?? room.order.first;
}

/// Point du repère de l'objet (lx le long de sa largeur depuis son milieu, lz depuis son dos) en plan,
/// avec la même rotation que la vue 3D.
(double, double) objectLocalToPlan(RoomObject o, double lx, double lz) {
  final r = (o.rot % 360) * math.pi / 180;
  final c = math.cos(r), sn = math.sin(r);
  final lzc = lz - o.d / 2;
  return (o.x + lx * c - lzc * sn, o.y + lx * sn + lzc * c);
}

/// Attentes d'un sanitaire dans son repère : (nature, lx depuis le milieu, hauteur), calées sur le modèle 3D
/// (mitigeur de la baignoire côté bonde, colonne de douche décalée, deux postes de la double vasque...).
List<(String, double, int)> fixtureWaterLocal(RoomObject o) {
  final f = o.fixture;
  if (f == null) return const [];
  final w = o.w, hw = o.w / 2;
  switch (f.id) {
    case 'baignoire':
      // mitigeur sur le rebord côté bonde : alimentations sous le rebord, derrière le tablier
      final mx = -hw + 55, drain = -(hw - 110) * 0.7;
      return [('froide', mx, 450), ('chaude', mx + 80, 450), ('evac', drain, 50)];
    case 'douche':
    case 'douche_italienne':
      // colonne de douche (mitigeur thermostatique entraxe 150) ; bonde centrée ou caniveau sur la largeur
      final cx = f.id == 'douche' ? hw * 0.2 : -hw * 0.2;
      return [('froide', cx - 75, 1100), ('chaude', cx + 75, 1100), ('evac', 0, 0)];
    case 'vasque_double':
      return [
        for (final cx in [-hw + w * 0.25, -hw + w * 0.75]) ...[('froide', cx - 60, 550), ('chaude', cx + 60, 550), ('evac', cx, 500)],
      ];
    default:
      if (isHeater(f) && o.z > 300) {
        // piquages sous la cuve (couché : à gauche), groupe de sécurité relié à l'évacuation
        final bottom = o.z.round(), k = math.min(70.0, hw * 0.45), at = f.id.endsWith('_h') ? -hw + 160.0 : 0.0;
        return [('froide', at - k, bottom - 120), ('chaude', at + k, bottom - 120), if (f.water.length > 2) ('evac', at, bottom - 250)];
      }
      return [for (final (kind, at, z) in f.water) (kind, -hw + w * at, z)];
  }
}

/// Sanitaire collé à son mur (le dos à moins de 15 cm) : ses attentes sortent du mur, à l'aplomb.
bool fixtureAgainstWall(Room room, RoomObject o) {
  final w = room.wall(fixtureWall(o, room));
  final (bx, by) = objectLocalToPlan(o, 0, 0);
  final (_, t) = w.toWall(bx, by);
  return t.abs() < 150;
}

/// Points d'eau des sanitaires (pour le plan des réseaux) : (mur, position le long du mur, hauteur, nature, objet).
/// Chaque attente est à l'aplomb du robinet ou de la bonde du sanitaire, sur le mur contre lequel il est posé.
List<(String, double, int, String, String)> fixtureWaterPoints(Room room, List<RoomObject> objects) {
  final out = <(String, double, int, String, String)>[];
  for (final o in objects) {
    final f = o.fixture;
    if (f == null) continue;
    final wall = fixtureWall(o, room);
    if (!room.isWallEnabled(wall)) continue;
    final w = room.wall(wall);
    for (final (kind, lx, z) in fixtureWaterLocal(o)) {
      final (px, py) = objectLocalToPlan(o, lx, 0);
      final (s, _) = w.toWall(px, py);
      out.add((wall, s.clamp(0, w.length).toDouble(), z, kind, o.uid));
    }
  }
  return out;
}

/// Points du mur cachés en 3D par le bâti-support d'un WC ou d'un bidet suspendu (attentes dans le coffrage).
bool concealedInFrame(Room room, List<RoomObject> objects, String wallId, double s, double z) {
  for (final o in objects) {
    final id = o.fixture?.id;
    if (id != 'wc_suspendu' && id != 'bidet') continue;
    if (fixtureWall(o, room) != wallId || z > 1150) continue;
    final (_, a, b) = objectOnWall(room, o);
    final mid = (a + b) / 2;
    if ((s - mid).abs() < 260) return true; // bâti de 500 mm de large
  }
  return false;
}

/// Zones mouillées (baignoire, douche) en plan, pour tenir prises et interrupteurs hors des volumes 0 à 2.
List<(double, double, double, double)> wetZones(List<RoomObject> objects) => [
      for (final o in objects)
        if (const {'baignoire', 'douche', 'douche_italienne'}.contains(o.fixture?.id)) o.footprint,
    ];

/// Distance en plan d'un point à la zone mouillée la plus proche (mm).
double wetDistance(List<(double, double, double, double)> zones, double px, double py) {
  var best = double.infinity;
  for (final (x0, y0, x1, y1) in zones) {
    final dx = math.max(0.0, math.max(x0 - px, px - x1)), dy = math.max(0.0, math.max(y0 - py, py - y1));
    best = math.min(best, math.sqrt(dx * dx + dy * dy));
  }
  return best;
}

double objectArea(RoomObject o) {
  final (x0, y0, x1, y1) = o.footprint;
  return math.max(0, x1 - x0) * math.max(0, y1 - y0);
}
