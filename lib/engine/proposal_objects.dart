/// Objets inclus dans les compositions proposées (sanitaires, canapé, téléviseur, tapis…) :
/// chaque objet a une préférence de place (même mur, mur opposé, murs latéraux, centre, sur ou sous un module)
/// et se pose au premier endroit libre : pas sur un meuble, pas devant une porte, dégagement devant respecté.
library;

import 'dart:math' as math;

import 'layout_engine.dart';
import 'project.dart';
import 'room_objects.dart';

enum Spot { wall, side, opposite, center, onSlot, underSlot }

class ObjSpec {
  final String ref; // 'fixture:id' ou id du catalogue libre
  final Spot spot;
  final int? slot; // module de la composition (onSlot, underSlot)
  final bool corner; // de préférence dans un angle
  final int? w, h, d; // cotes (objets du catalogue libre)
  final int clear; // dégagement devant (objets du catalogue libre)
  const ObjSpec(this.ref, {this.spot = Spot.wall, this.slot, this.corner = false, this.w, this.h, this.d, this.clear = 0});
}

const _f = 'fixture:';

/// Objets de chaque composition (par identifiant de modèle).
const templateObjects = <String, List<ObjSpec>>{
  // salle de bain
  'oualidia': [ObjSpec('${_f}douche', spot: Spot.side, corner: true), ObjSpec('${_f}wc_suspendu', spot: Spot.side), ObjSpec('${_f}seche_serviettes')],
  'mogador': [ObjSpec('${_f}baignoire', spot: Spot.opposite, corner: true), ObjSpec('${_f}wc_suspendu', spot: Spot.side), ObjSpec('${_f}seche_serviettes', spot: Spot.side)],
  'taghazout': [ObjSpec('${_f}wc_suspendu', spot: Spot.underSlot, slot: 2), ObjSpec('${_f}douche', spot: Spot.opposite, corner: true)],
  'hammam': [ObjSpec('${_f}douche_italienne', spot: Spot.opposite, corner: true), ObjSpec('${_f}wc_suspendu', spot: Spot.side), ObjSpec('${_f}chauffe_eau', spot: Spot.side)],
  'essaouira_bain': [ObjSpec('${_f}baignoire', spot: Spot.opposite, corner: true), ObjSpec('${_f}wc_sol', spot: Spot.side), ObjSpec('${_f}bidet', spot: Spot.side)],
  'agadir': [ObjSpec('${_f}douche', spot: Spot.opposite, corner: true), ObjSpec('${_f}wc_suspendu', spot: Spot.side), ObjSpec('${_f}seche_serviettes', spot: Spot.side)],
  'fes_bain': [
    ObjSpec('${_f}baignoire', spot: Spot.opposite, corner: true),
    ObjSpec('${_f}douche', spot: Spot.side, corner: true),
    ObjSpec('${_f}wc_suspendu', spot: Spot.side),
    ObjSpec('${_f}chauffe_eau', spot: Spot.side),
  ],
  'dakhla': [ObjSpec('${_f}douche', spot: Spot.side, corner: true), ObjSpec('${_f}wc_suspendu', spot: Spot.side)],
  // dressing : pouf, banc, miroir sur pied, tapis
  'atlas': [ObjSpec('ph_Ottoman_01', spot: Spot.center, w: 885, h: 624, d: 621), ObjSpec('kenney_rugRound', spot: Spot.center, w: 1600, h: 10, d: 1600)],
  'ifrane': [ObjSpec('kenney_benchCushionLow', spot: Spot.opposite, w: 1200, h: 400, d: 380), ObjSpec('ph_potted_plant_02', spot: Spot.side, corner: true, w: 701, h: 841, d: 657)],
  'zagora': [ObjSpec('ph_Ottoman_01', spot: Spot.center, w: 885, h: 624, d: 621), ObjSpec('kenney_rugRectangle', spot: Spot.center, w: 2000, h: 10, d: 1400)],
  'asilah': [ObjSpec('ph_ArmChair_01', spot: Spot.side, corner: true, w: 848, h: 1065, d: 766), ObjSpec('kenney_rugRound', spot: Spot.center, w: 1600, h: 10, d: 1600)],
  'riad': [ObjSpec('kenney_benchCushion', spot: Spot.opposite, w: 1200, h: 450, d: 380), ObjSpec('kenney_rugSquare', spot: Spot.center, w: 1600, h: 10, d: 1600)],
  'toubkal': [ObjSpec('ph_Ottoman_01', spot: Spot.center, w: 885, h: 624, d: 621), ObjSpec('kenney_coatRackStanding', spot: Spot.side, corner: true, w: 450, h: 1750, d: 450)],
  'chefchaouen': [ObjSpec('kenney_benchCushionLow', spot: Spot.opposite, w: 1200, h: 400, d: 380), ObjSpec('kenney_rugRound', spot: Spot.center, w: 1600, h: 10, d: 1600)],
  'kenitra': [ObjSpec('ph_potted_plant_02', spot: Spot.side, corner: true, w: 701, h: 841, d: 657)],
  'medina': [ObjSpec('kenney_bedSingle', spot: Spot.opposite, corner: true, w: 940, h: 500, d: 2040, clear: 500), ObjSpec('kenney_desk', spot: Spot.side, w: 1200, h: 750, d: 600, clear: 600)],
};

/// Objets du salon pour toutes les compositions TV : téléviseur sur le meuble, canapé face à l'écran, table basse, tapis, plante.
const _tvObjects = <ObjSpec>[
  ObjSpec('kenney_televisionModern', spot: Spot.onSlot, w: 1230, h: 750, d: 220),
  ObjSpec('ph_sofa_02', spot: Spot.opposite, w: 1807, h: 709, d: 818, clear: 400),
  ObjSpec('kenney_rugRectangle', spot: Spot.center, w: 2000, h: 10, d: 1400),
  ObjSpec('ph_modern_coffee_table_01', spot: Spot.center, w: 1202, h: 390, d: 600),
  ObjSpec('ph_potted_plant_02', spot: Spot.wall, corner: true, w: 701, h: 841, d: 657),
];

/// Module sur lequel poser le téléviseur : le banc TV (ou le premier module bas) de la composition.
int? _tvSlot(LayoutEngine e, Map<int, PlacedCabinet> placed) {
  for (final i in placed.keys.toList()..sort()) {
    final id = placed[i]!.modelId;
    if (id.contains('bench') || id.contains('fireplace')) return i;
  }
  return null;
}

List<ObjSpec> objectsFor(String universe, String templateId) => universe == 'tv' ? _tvObjects : (templateObjects[templateId] ?? const []);

const _opposite = {'A': 'D', 'D': 'A', 'B': 'C', 'C': 'B'};

/// Boîte d'un rectangle donné en coordonnées du mur (s0..s1 le long, t0..t1 vers l'intérieur).
Box3 _st(Wall w, double s0, double s1, double t0, double t1, double z0, double z1) {
  final (ax, ay) = w.toPlan(s0, t0);
  final (bx, by) = w.toPlan(s1, t1);
  return Box3(math.min(ax, bx), math.min(ay, by), z0, math.max(ax, bx), math.max(ay, by), z1);
}

/// Pose les objets de la composition dans le projet de [e] ; renvoie le nombre d'objets posés.
int placeTemplateObjects(LayoutEngine e, String templateId, String wallId, Map<int, PlacedCabinet> placed) {
  final p = e.project;
  final room = p.room;
  final specs = objectsFor(p.universe, templateId);
  if (specs.isEmpty) return 0;
  p.objects.clear();
  final obstacles = <Box3>[
    for (final c in p.items)
      for (final tb in e.boxesOf(c)) tb.box,
    for (final o in p.openings) o.box(room),
  ];
  final enabled = {for (final w in room.walls.where((w) => w.enabled)) w.id};
  // mur opposé et murs latéraux (pièce quelconque : murs droits, l'opposé est le plus long tourné vers celui-ci)
  final opposites = room.walls.where((w) => w.orthogonal && w.rot == (room.wall(wallId).rot + 180) % 360).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final opp = room.outline == null ? _opposite[wallId] : opposites.firstOrNull?.id;
  final sides = [for (final w in room.walls) if (w.orthogonal && w.id != wallId && w.id != opp && enabled.contains(w.id)) w.id];
  var n = 0;
  String newUid() => p.newUid('o');

  bool inRoom(Box3 b) => b.x0 >= -1 && b.y0 >= -1 && b.x1 <= room.width + 1 && b.y1 <= room.depth + 1;
  bool free(Box3 b) => inRoom(b) && !obstacles.any((o) => o.intersects(b));

  for (final sp in specs) {
    final fx = sp.ref.startsWith(_f) ? fixtureById(sp.ref.substring(_f.length)) : null;
    final sizes = fx != null ? fx.sizes : [(sp.w ?? 600, sp.d ?? 600)];
    final h = fx?.h ?? sp.h ?? 600;
    final z0 = (fx?.z ?? 0).toDouble();
    final clear = (fx?.clearance ?? sp.clear).toDouble();
    RoomObject? done;

    // sur ou sous un module de la composition
    if (sp.spot == Spot.onSlot || sp.spot == Spot.underSlot) {
      final i = sp.slot ?? _tvSlot(e, placed);
      final under = i == null ? null : placed[i];
      if (under != null) {
        final w = room.wall(under.wallId);
        final (ow, od) = sizes.first;
        final width = math.min(ow.toDouble(), sp.spot == Spot.onSlot ? under.width - 40 : under.width);
        final s = under.s + under.width / 2;
        final t = sp.spot == Spot.onSlot ? math.max(od / 2 + 40, under.depth / 2) : od / 2;
        final (x, y) = w.toPlan(s, t);
        done = RoomObject(
            uid: newUid(),
            ref: sp.ref,
            x: x,
            y: y,
            z: sp.spot == Spot.onSlot ? under.top : z0,
            rot: w.rot,
            w: sp.spot == Spot.onSlot ? width.round() : ow,
            h: sp.spot == Spot.onSlot ? (h * width / ow).round() : h,
            d: od);
      }
    } else if (sp.spot == Spot.center) {
      // centre de la pièce, décalé si nécessaire ; tapis : sous le reste, réduit pour laisser 600 mm autour
      final (ow, od) = sizes.first;
      final rug = h <= 20;
      final w = rug ? math.min(ow.toDouble(), room.width - 1200) : ow.toDouble();
      final d = rug ? math.min(od.toDouble(), room.depth - 1200) : od.toDouble();
      if (w >= 400 && d >= 400) {
        final cx = room.width / 2, cy = room.depth / 2;
        for (final (dx, dy) in [(0, 0), (0, 300), (0, -300), (300, 0), (-300, 0), (300, 300), (-300, -300), (0, 600), (0, -600)]) {
          final b = Box3(cx + dx - w / 2, cy + dy - d / 2, 0, cx + dx + w / 2, cy + dy + d / 2, h.toDouble());
          if (rug ? inRoom(b) : free(b)) {
            done = RoomObject(uid: newUid(), ref: sp.ref, x: cx + dx, y: cy + dy, z: 0, rot: room.wall(wallId).rot, w: w.round(), h: h, d: d.round());
            break;
          }
        }
      }
    } else {
      final order = switch (sp.spot) {
        Spot.side => [...sides, ?opp, wallId],
        Spot.opposite => [?opp, ...sides, wallId],
        _ => [wallId, ...sides, ?opp],
      }.where(enabled.contains);
      search:
      for (final (ow, od) in sizes) {
        for (final wid in order) {
          final w = room.wall(wid);
          final L = w.length;
          if (ow > L) continue;
          final steps = [for (var s = 0.0; s <= L - ow; s += 50) s];
          if (steps.isEmpty || steps.last < L - ow - 1) steps.add(L - ow);
          final cands = sp.corner ? [0.0, L - ow, ...steps] : steps;
          for (final s in cands) {
            final body = _st(w, s, s + ow, 0, od.toDouble(), z0, z0 + h);
            if (!free(body)) continue;
            if (clear > 0) {
              final zone = _st(w, s, s + ow, od.toDouble(), od + clear, 0, 1000);
              if (!free(zone)) continue;
            }
            final (x, y) = w.toPlan(s + ow / 2, od / 2);
            done = RoomObject(uid: newUid(), ref: sp.ref, x: x, y: y, z: z0, rot: room.wall(wid).rot, w: ow, h: h, d: od);
            break search;
          }
        }
      }
    }
    if (done == null) continue;
    p.objects.add(done);
    n++;
    final (x0, y0, x1, y1) = done.footprint;
    if (done.h > 20) {
      obstacles.add(Box3(x0, y0, done.z, x1, y1, done.z + done.h));
      // dégagement devant : réservé (sans hauteur au-dessus de 1 m)
      if (clear > 0) {
        final (fx0, fy0) = done.front;
        final c = clear;
        obstacles.add(fx0 != 0
            ? (fx0 > 0 ? Box3(x1, y0, 0, x1 + c, y1, 1000) : Box3(x0 - c, y0, 0, x0, y1, 1000))
            : (fy0 > 0 ? Box3(x0, y1, 0, x1, y1 + c, 1000) : Box3(x0, y0 - c, 0, x1, y0, 1000)));
      }
    }
  }
  return n;
}
