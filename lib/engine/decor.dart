/// Décor du rendu final : petits appareils, plantes, fruits, rideaux… posés tout seuls aux places libres.
/// Il ne compte ni dans les contrôles, ni dans le débit, ni dans le devis ; on le montre ou on le cache d'un geste.
library;

import 'dart:math' as math;

import 'front_layout.dart';
import 'layout_engine.dart';
import 'project.dart';

class DecorItem {
  final String id, name;
  final String? model; // modèle du catalogue libre, sinon volume dessiné (deco_…)
  final int w, h, d;
  final String spot; // 'plan' (plan de travail ou dessus de meuble), 'ilot', 'plaque', 'niche', 'fenetre', 'sol', 'tapis'
  final Set<String> rooms; // pièces où l'objet a sa place (vide : toutes)
  const DecorItem(this.id, this.name, this.w, this.h, this.d, this.spot, {this.model, this.rooms = const {}});
}

const _cuisine = {'cuisine'};
const _salon = {'tv', 'interieur'};

const decorItems = <DecorItem>[
  // cuisine
  DecorItem('cafe', 'Machine à café', 250, 340, 340, 'plan', model: 'kenney_kitchenCoffeeMachine', rooms: _cuisine),
  DecorItem('blender', 'Blender', 180, 390, 180, 'plan', model: 'kenney_kitchenBlender', rooms: _cuisine),
  DecorItem('toaster', 'Grille-pain', 290, 190, 180, 'plan', model: 'kenney_toaster', rooms: _cuisine),
  DecorItem('bouilloire', 'Bouilloire', 180, 240, 200, 'plan', rooms: _cuisine),
  DecorItem('planches', 'Planches à découper', 340, 420, 70, 'plan', rooms: _cuisine),
  DecorItem('bouteilles', 'Huile et épices', 190, 300, 90, 'plan', rooms: _cuisine),
  DecorItem('vaisselle', 'Vaisselle (niches et vitrines)', 0, 0, 0, 'niche', rooms: _cuisine),
  DecorItem('fruits', 'Corbeille de fruits', 320, 170, 320, 'ilot', rooms: _cuisine),
  DecorItem('casserole', 'Casserole', 260, 150, 260, 'plaque', rooms: _cuisine),
  // buanderie
  DecorItem('lessive', 'Lessive et adoucissant', 260, 270, 110, 'plan', rooms: {'buanderie'}),
  DecorItem('panier', 'Panier de linge plié', 420, 260, 300, 'plan', rooms: {'buanderie'}),
  // salle de bain
  DecorItem('savon', 'Savon et brosses à dents', 210, 200, 90, 'plan', rooms: {'bain'}),
  DecorItem('serviettes', 'Serviettes pliées', 300, 170, 220, 'plan', rooms: {'bain', 'buanderie'}),
  DecorItem('bougies', 'Bougies', 200, 150, 110, 'plan', rooms: {'bain', 'dressing', 'tv', 'interieur'}),
  DecorItem('panier_linge', 'Panier à linge', 400, 580, 400, 'sol', rooms: {'bain', 'buanderie'}),
  DecorItem('tapis_bain', 'Tapis de bain', 800, 14, 500, 'tapis', model: 'kenney_rugDoormat', rooms: {'bain'}),
  // dressing
  DecorItem('vetements', 'Vêtements suspendus', 0, 0, 0, 'niche', rooms: {'dressing'}),
  DecorItem('linge', 'Linge plié et boîtes', 0, 0, 0, 'niche', rooms: {'dressing', 'buanderie', 'bain'}),
  DecorItem('pouf', 'Pouf', 700, 490, 490, 'sol', model: 'ph_Ottoman_01', rooms: {'dressing', 'tv', 'interieur'}),
  // meuble TV et intérieur
  DecorItem('livres', 'Livres', 250, 250, 180, 'plan', model: 'kenney_books', rooms: _salon),
  DecorItem('lampe', 'Lampe à poser', 260, 420, 260, 'plan', model: 'kenney_lampRoundTable', rooms: {'tv', 'interieur', 'dressing'}),
  DecorItem('livres_niche', 'Livres et objets (niches)', 0, 0, 0, 'niche', rooms: _salon),
  DecorItem('lampadaire', 'Lampadaire', 400, 1600, 400, 'sol', model: 'kenney_lampRoundFloor', rooms: _salon),
  DecorItem('tapis', 'Tapis', 2000, 12, 1400, 'tapis', model: 'kenney_rugRounded', rooms: {'dressing', 'tv', 'interieur'}),
  // partout
  DecorItem('plante', 'Plante en pot', 190, 280, 190, 'plan', model: 'kenney_plantSmall2'),
  DecorItem('vase', 'Vase', 150, 320, 150, 'ilot', model: 'ph_ceramic_vase_01', rooms: {'cuisine', 'dressing', 'tv', 'interieur'}),
  DecorItem('rideau', 'Rideaux', 0, 0, 90, 'fenetre'),
  DecorItem('store', 'Stores', 0, 0, 60, 'fenetre'),
  DecorItem('plante_sol', 'Grande plante', 420, 1050, 420, 'sol', model: 'kenney_pottedPlant'),
];

/// Décor proposé dans cette pièce : pas de grille-pain dans une buanderie.
List<DecorItem> decorFor(String universe) => [for (final it in decorItems) if (it.rooms.isEmpty || it.rooms.contains(universe)) it];

/// Décor par défaut selon la pièce.
Set<String> defaultDecor(String universe) => switch (universe) {
      'cuisine' => {'vaisselle', 'cafe', 'blender', 'toaster', 'planches', 'bouteilles', 'plante', 'fruits', 'casserole', 'store'},
      'buanderie' => {'lessive', 'panier', 'serviettes', 'plante', 'linge', 'panier_linge', 'store'},
      'bain' => {'savon', 'serviettes', 'bougies', 'linge', 'tapis_bain', 'panier_linge', 'plante', 'store'},
      'dressing' => {'vetements', 'linge', 'vase', 'pouf', 'tapis', 'plante_sol', 'rideau'},
      _ => {'livres', 'livres_niche', 'lampe', 'vase', 'lampadaire', 'tapis', 'plante_sol', 'rideau'},
    };

typedef PlacedDecor = ({String uid, DecorItem item, double x, double y, double z, int rot, double w, double h, double d});

/// Place le décor choisi : sur le plan (loin de l'évier et de la plaque), sur l'îlot, aux fenêtres, au sol dans un angle libre.
List<PlacedDecor> placeDecor(LayoutEngine e) {
  final p = e.project, room = p.room;
  // seulement ce qui a sa place dans cette pièce (un ancien projet peut contenir autre chose)
  final here = decorFor(p.universe);
  // un modèle a déjà posé son tapis, son pouf ou sa plante : pas de second
  const already = {'pouf': 'ttoman', 'tapis': '_rug', 'tapis_bain': '_rug', 'lampadaire': 'Floor', 'plante_sol': 'otted', 'panier_linge': 'Hamper'};
  bool there(String id) => already[id] != null && p.objects.any((ob) => ob.ref.contains(already[id]!));
  final on = {for (final it in here) if (p.style.decor.contains(it.id) && !there(it.id)) it.id};
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
  final plan = [for (final it in here) if (it.spot == 'plan' && on.contains(it.id) && e.hasWorktop) it];
  final free = <(Wall, double, double, double)>[];
  for (final w in room.walls.where((w) => w.enabled && w.orthogonal)) {
    for (final (a, b) in e.runs(w.id, (m) => e.hasWorktop && m.kind.isLow)) {
      final z = e.worktopZ(w.id, a, b) + th;
      final blocked = [
        for (final c in p.items)
          if (c.wallId == w.id && e.modelOf(c).kind.isLow && busy(c)) (c.s - 40, c.right + 40),
        // sous un chauffe-eau, derrière un objet déjà posé : pas la place
        for (final ob in p.objects)
          if (ob.z < z + 450 && ob.z + ob.h > z + 20)
            () {
              final (x0, y0, x1, y1) = ob.footprint;
              final (s0, s1, t0, _) = w.boxToWall(Box3(x0, y0, ob.z, x1, y1, ob.z + ob.h));
              return t0 < 600 && s1 > a && s0 < b ? (s0 - 40, s1 + 40) : (b, b);
            }(),
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
  // ---- dessus des meubles bas (pièces sans plan de travail)
  void onFurniture(DecorItem it) {
    final low = p.items.where((c) => c.wallId != 'I' && room.order.contains(c.wallId) && e.modelOf(c).isCarcass && !e.modelOf(c).kind.isCorner && c.top < 1200 && c.top > 250 && c.depth >= it.d + 20).toList()..sort((a, b) => b.width.compareTo(a.width));
    for (final frac in [0.82, 0.18, 0.5]) {
      for (final c in low) {
        final w = room.wall(c.wallId);
        if (it.w + 20 > c.width) continue;
        final s = (c.s + c.width * frac).clamp(c.s + it.w / 2 + 10, c.right - it.w / 2 - 10).toDouble();
        final t = math.min(c.depth / 2, 50 + it.d / 2);
        final b = w.stripRange(s - it.w / 2 - 15, it.w + 30.0, t - it.d / 2, t + it.d / 2, c.top, it.h.toDouble());
        final taken = p.items.any((o) => o != c && e.boxesOf(o).any((x) => x.box.intersects(b))) ||
            p.objects.any((ob) {
              final (x0, y0, x1, y1) = ob.footprint;
              return ob.h > 20 && Box3(x0, y0, ob.z - 60, x1, y1, ob.z + ob.h + 60).intersects(b);
            }) ||
            out.any((q) => (q.x - (b.x0 + b.x1) / 2).abs() < (q.w + it.w) / 2 + 30 && (q.y - (b.y0 + b.y1) / 2).abs() < (q.w + it.w) / 2 + 30 && (q.z - c.top).abs() < 300);
        if (taken) continue;
        put(it, w, s, t, c.top);
        return;
      }
    }
  }

  // ---- îlot (à défaut : la plus grande place du plan)
  final onIsland = [for (final it in here) if (on.contains(it.id) && (it.spot == 'ilot' || (it.spot == 'plan' && !e.hasWorktop))) it];
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
        // pièce sans plan : sur les meubles bas, à une place libre
        if (!e.hasWorktop) onFurniture(it);
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
  // ---- niches et vitrines : vaisselle, linge plié, livres… sur chaque niveau ; vêtements sous les tringles
  for (final it in here.where((x) => x.spot == 'niche' && on.contains(x.id))) {
    var k = 0;
    for (final c in p.items) {
      final m = e.modelOf(c);
      if (!m.isCarcass || m.kind.isCorner || c.width < 260 || !room.order.contains(c.wallId) || m.id == 'base_wine_rack' || e.machinesIn(c).isNotEmpty) continue;
      if (it.id == 'vaisselle' && !m.kind.isHigh) continue;
      final cells = cellsOf(rowsOf(m, c) ?? seedRows(m, c), c.height);
      if (cells.isEmpty) continue;
      final kz = c.height / (cells.last.y + cells.last.h);
      final w = room.wall(c.wallId);
      final (x, y) = w.toPlan(c.s + c.width / 2, c.depth / 2 - 10);
      for (final cell in cells) {
        if (cell.kind != CellKind.niche && cell.kind != CellKind.glass) continue;
        final zt = c.top - cell.y * kz, hh = cell.h * kz, zb = zt - hh;
        final hang = cell.kind == CellKind.niche && m.id.contains('hanging') && hh > 700;
        if (it.id == 'vetements') {
          if (!hang) continue;
          // mêmes hauteurs que les tringles de la 3D
          final twice = m.id.contains('double') && hh > 1600;
          final low = zb + (hh - 320) / 2 - 20;
          for (final (rod, floor) in [(zt - 390, twice ? low + 60 : zb + 30), if (twice) (low, zb + 30)]) {
            final len = math.min(rod - floor, 1150.0);
            if (len < 400) continue;
            out.add((uid: 'deco-vetements-${n++}', item: it, x: x, y: y, z: rod - len, rot: w.rot, w: c.width - 80.0, h: len, d: math.min(480.0, c.depth - 80.0)));
          }
          continue;
        }
        if (hang) continue;
        final levels = cell.kind == CellKind.niche ? nicheLevels(hh) : (hh - 36 > 600 ? 3 : (hh - 36 > 330 ? 2 : 1));
        for (var i = 0; i < levels; i++) {
          final z = zb + hh * i / levels + (i == 0 ? 18 : 9), free = hh / levels - 40;
          if (free < 120) continue;
          out.add((uid: 'deco-${it.id}-${n++}', item: it, x: x, y: y, z: z, rot: w.rot, w: c.width - 90.0, h: math.min(free, it.id == 'vaisselle' ? 230.0 : 290.0) + (k++ % 3), d: math.min(it.id == 'vaisselle' ? 230.0 : 320.0, c.depth - 90.0)));
        }
      }
    }
  }
  // ---- sol : un angle libre
  {
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
    for (final it in here.where((x) => x.spot == 'sol' && on.contains(x.id))) {
      const m = 60.0;
      final r = it.w / 2;
      for (final (x, y) in [(room.width - m - r, room.depth - m - r), (m + r, room.depth - m - r), (room.width - m - r, m + r), (m + r, m + r), (room.width - m - r, room.depth / 2), (m + r, room.depth / 2)]) {
        final b = Box3(x - r, y - r, 0, x + r, y + r, it.h.toDouble());
        if (obstacles.any((o) => o.intersects(b)) || (room.outline != null && !room.contains(x, y))) continue;
        out.add((uid: 'deco-${it.id}', item: it, x: x, y: y, z: 0, rot: 0, w: it.w.toDouble(), h: it.h.toDouble(), d: it.d.toDouble()));
        obstacles.add(b);
        break;
      }
    }
    // tapis : au milieu de la pièce (salle de bain : devant le meuble), là où le sol est libre
    for (final it in here.where((x) => x.spot == 'tapis' && on.contains(x.id))) {
      final k = math.min(1.0, math.min(room.width * 0.6 / it.w, room.depth * 0.6 / it.d));
      final tw = it.w * k, td = it.d * k;
      final low = p.items.where((c) => room.order.contains(c.wallId) && room.wall(c.wallId).straight && e.modelOf(c).kind.isLow).firstOrNull;
      final spots = <(double, double, int, double, double)>[
        if (it.id == 'tapis_bain' && low != null)
          () {
            final w = room.wall(low.wallId);
            final (x, y) = w.toPlan(low.s + low.width / 2, low.depth + 120 + td / 2);
            return (x, y, w.rot, w.dx.abs() > 0.5 ? tw : td, w.dx.abs() > 0.5 ? td : tw);
          }(),
        (room.width / 2, room.depth / 2, 0, tw, td),
        (room.width / 2, room.depth * 0.65, 0, tw, td),
      ];
      for (final (x, y, rot, wx, wy) in spots) {
        final b = Box3(x - wx / 2, y - wy / 2, 0, x + wx / 2, y + wy / 2, it.h.toDouble());
        if (b.x0 < 0 || b.y0 < 0 || b.x1 > room.width || b.y1 > room.depth) continue;
        if (obstacles.any((o) => o.intersects(b)) || (room.outline != null && !room.contains(x, y))) continue;
        out.add((uid: 'deco-${it.id}', item: it, x: x, y: y, z: 0, rot: rot, w: tw, h: it.h.toDouble(), d: td));
        break;
      }
    }
  }
  return out;
}
