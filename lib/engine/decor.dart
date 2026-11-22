/// Décor du rendu final : petits appareils, plantes, fruits, rideaux… posés tout seuls aux places libres.
/// Il ne compte ni dans les contrôles, ni dans le débit, ni dans le devis ; on le montre ou on le cache d'un geste.
library;

import 'dart:math' as math;

import 'layout_engine.dart';
import 'project.dart';

class DecorItem {
  final String id, name;
  final String? model; // modèle du catalogue libre, sinon volume dessiné (deco_…)
  final int w, h, d;
  final String spot; // 'plan' (plan de travail), 'ilot', 'plaque', 'fenetre', 'sol'
  const DecorItem(this.id, this.name, this.w, this.h, this.d, this.spot, {this.model});
}

const decorItems = <DecorItem>[
  DecorItem('cafe', 'Machine à café', 250, 340, 340, 'plan', model: 'kenney_kitchenCoffeeMachine'),
  DecorItem('blender', 'Blender', 180, 390, 180, 'plan', model: 'kenney_kitchenBlender'),
  DecorItem('toaster', 'Grille-pain', 290, 190, 180, 'plan', model: 'kenney_toaster'),
  DecorItem('bouilloire', 'Bouilloire', 180, 240, 200, 'plan'),
  DecorItem('planches', 'Planches à découper', 340, 420, 70, 'plan'),
  DecorItem('bouteilles', 'Huile et épices', 190, 300, 90, 'plan'),
  DecorItem('plante', 'Plante en pot', 190, 280, 190, 'plan', model: 'kenney_plantSmall2'),
  DecorItem('fruits', 'Corbeille de fruits', 320, 170, 320, 'ilot'),
  DecorItem('vase', 'Vase', 150, 320, 150, 'ilot', model: 'ph_ceramic_vase_01'),
  DecorItem('casserole', 'Casserole', 260, 150, 260, 'plaque'),
  DecorItem('rideau', 'Rideaux', 0, 0, 90, 'fenetre'),
  DecorItem('store', 'Stores', 0, 0, 60, 'fenetre'),
  DecorItem('plante_sol', 'Grande plante', 420, 1050, 420, 'sol', model: 'kenney_pottedPlant'),
];

/// Décor par défaut selon la pièce.
Set<String> defaultDecor(String universe) => switch (universe) {
      'cuisine' => {'cafe', 'blender', 'toaster', 'planches', 'bouteilles', 'plante', 'fruits', 'casserole', 'store'},
      'buanderie' => {'plante', 'store'},
      'bain' => {'store', 'plante_sol'},
      _ => {'rideau', 'plante_sol', 'vase'},
    };

typedef PlacedDecor = ({String uid, DecorItem item, double x, double y, double z, int rot, double w, double h, double d});

/// Place le décor choisi : sur le plan (loin de l'évier et de la plaque), sur l'îlot, aux fenêtres, au sol dans un angle libre.
List<PlacedDecor> placeDecor(LayoutEngine e) {
  final p = e.project, room = p.room;
  final on = p.style.decor;
  final out = <PlacedDecor>[];
  if (on.isEmpty) return out;
  var n = 0;
  void put(DecorItem it, Wall w, double s, double t, double z, {double? width, double? height, double? depth}) {
    final (x, y) = w.toPlan(s, t);
    out.add((uid: 'deco-${it.id}-${n++}', item: it, x: x, y: y, z: z, rot: w.rot, w: width ?? it.w.toDouble(), h: height ?? it.h.toDouble(), d: depth ?? it.d.toDouble()));
  }

  bool busy(PlacedCabinet c) => e.washes(c) || e.cooks(c);
  final th = p.standards.worktopThickness.toDouble();
  // ---- plan de travail des murs
  final plan = [for (final it in decorItems) if (it.spot == 'plan' && on.contains(it.id)) it];
  final free = <(Wall, double, double, double)>[];
  for (final w in room.walls.where((w) => w.enabled && w.orthogonal)) {
    for (final (a, b) in e.runs(w.id, (m) => e.hasWorktop && m.kind.isLow)) {
      final z = e.worktopZ(w.id, a, b) + th;
      final blocked = [
        for (final c in p.items)
          if (c.wallId == w.id && e.modelOf(c).kind.isLow && busy(c)) (c.s - 40, c.right + 40),
        // plan repris par le mur voisin dans l'angle
        if (e.runs(room.prevOf(w.id), (m) => e.hasWorktop && m.kind.isLow).any((r) => r.$2 > room.wall(room.prevOf(w.id)).length - 5)) (0.0, 320.0),
      ]..sort((x, y) => x.$1.compareTo(y.$1));
      var cur = a + 60;
      for (final (x, y) in [...blocked, (b - 60, double.infinity)]) {
        if (x - cur > 160) free.add((w, cur, math.min(x, b - 60), z));
        cur = math.max(cur, y);
        if (cur >= b) break;
      }
    }
  }
  // un peu partout plutôt qu'en file : chaque objet va dans la plus grande place restante
  for (final it in plan) {
    free.sort((x, y) => (y.$3 - y.$2).compareTo(x.$3 - x.$2));
    final i = free.indexWhere((f) => f.$3 - f.$2 >= it.w + 40);
    if (i < 0) continue;
    final (w, a, b, z) = free.removeAt(i);
    // près d'un bout, la moitié du reste libre de l'autre côté
    final s = a + 20 + it.w / 2;
    put(it, w, s, 20 + it.d / 2, z);
    if (b - (s + it.w / 2 + 180) > 150) free.add((w, s + it.w / 2 + 180, b, z));
  }
  // ---- îlot (à défaut : la plus grande place du plan)
  final onIsland = [for (final it in decorItems) if (it.spot == 'ilot' && on.contains(it.id)) it];
  final isl = room.island;
  if (isl != null && e.runs('I', (m) => m.kind.isLow).isNotEmpty) {
    final w = room.wall('I');
    final cabs = p.items.where((c) => c.wallId == 'I' && busy(c));
    var s = isl.length * 0.3;
    for (final it in onIsland) {
      if (cabs.any((c) => s + it.w / 2 > c.s && s - it.w / 2 < c.right)) s = isl.length - it.w;
      put(it, w, s.clamp(it.w / 2, math.max(it.w / 2, isl.length - it.w / 2)).toDouble(), Island.depth / 2, p.standards.worktopTop.toDouble());
      s += it.w + 260;
    }
  } else {
    for (final it in onIsland) {
      free.sort((x, y) => (y.$3 - y.$2).compareTo(x.$3 - x.$2));
      if (free.isEmpty || free.first.$3 - free.first.$2 < it.w + 60) {
        // pièce sans plan : sur le meuble bas le plus large
        final low = p.items.where((c) => c.wallId != 'I' && e.modelOf(c).kind.isLow && !e.hasWorktop && c.top < 1200 && c.depth >= it.d).toList()..sort((a, b) => b.width.compareTo(a.width));
        if (low.isNotEmpty) put(it, room.wall(low.first.wallId), low.first.s + low.first.width * 0.8, low.first.depth / 2, low.first.top);
        continue;
      }
      final (w, a, b, z) = free.removeAt(0);
      put(it, w, (a + b) / 2, 60 + it.d / 2, z);
    }
  }
  // ---- plaque
  if (on.contains('casserole')) {
    final it = decorItems.firstWhere((x) => x.id == 'casserole');
    final hob = p.items.where((c) => e.cooks(c) && e.modelOf(c).kind.isLow).firstOrNull;
    if (hob != null) put(it, room.wall(hob.wallId), hob.s + hob.width * 0.3, 230, p.standards.worktopTop + 12.0);
  }
  // ---- fenêtres : rideaux ou stores
  for (final o in p.openings.where((o) => !o.isDoor && room.order.contains(o.wallId))) {
    final w = room.wall(o.wallId);
    if (!w.straight) continue;
    final s = o.s + o.width / 2;
    if (on.contains('rideau')) {
      final it = decorItems.firstWhere((x) => x.id == 'rideau');
      final top = math.min(room.height - 20, o.z + o.height + 160);
      // jusqu'au sol, sauf au-dessus d'un meuble
      final below = p.items.where((c) => c.wallId == o.wallId && c.s < o.right + 150 && c.right > o.s - 150 && c.z < o.z).map((c) => c.top + th);
      final z = below.isEmpty ? 20.0 : math.max(o.z - 60, below.reduce(math.max) + 60);
      put(it, w, s, 50, z, width: o.width + 300, height: math.max(300, top - z), depth: 90);
    } else if (on.contains('store')) {
      final it = decorItems.firstWhere((x) => x.id == 'store');
      put(it, w, s, 25, o.z, width: o.width - 20, height: o.height, depth: 50);
    }
  }
  // ---- sol : un angle libre
  if (on.contains('plante_sol')) {
    final it = decorItems.firstWhere((x) => x.id == 'plante_sol');
    final obstacles = <Box3>[
      for (final c in p.items)
        for (final tb in e.solidOf(c)) tb.box,
      for (final o in p.openings)
        if (o.isDoor && room.order.contains(o.wallId)) room.wall(o.wallId).strip(o.s - 100, o.width + 200, 900, 0, 2000),
      for (final ob in p.objects)
        if (ob.h > 20)
          () {
            final (x0, y0, x1, y1) = ob.footprint;
            return Box3(x0, y0, ob.z, x1, y1, ob.z + ob.h);
          }(),
      if (room.island != null) Box3(room.island!.x0, room.island!.y0, 0, room.island!.x0 + room.island!.length, room.island!.y0 + Island.depth + room.island!.overhang, 900),
    ];
    const m = 60.0, r = 210.0;
    for (final (x, y) in [(room.width - m - r, room.depth - m - r), (m + r, room.depth - m - r), (room.width - m - r, m + r), (m + r, m + r)]) {
      final b = Box3(x - r, y - r, 0, x + r, y + r, it.h.toDouble());
      if (obstacles.any((o) => o.intersects(b)) || (room.outline != null && !room.contains(x, y))) continue;
      out.add((uid: 'deco-${it.id}', item: it, x: x, y: y, z: 0, rot: 0, w: it.w.toDouble(), h: it.h.toDouble(), d: it.d.toDouble()));
      break;
    }
  }
  return out;
}
