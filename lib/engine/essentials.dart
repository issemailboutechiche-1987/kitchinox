/// L'indispensable d'une pièce : une porte partout, l'eau et l'évacuation dans une salle de bain (et les pièces d'eau),
/// et des meubles dont la façade n'est jamais cachée par un autre.
library;

import 'dart:math' as math;

import 'fixes.dart';
import 'i18n_hook.dart';
import 'catalog.dart';
import 'clearance.dart';
import 'layout_engine.dart';
import 'networks.dart';
import 'project.dart';
import 'room_objects.dart';

/// Pièces où l'arrivée d'eau est obligatoire.
const waterUniverses = {'bain', 'cuisine', 'buanderie'};

/// Pose une porte si la pièce n'en a pas : sur un mur sans meubles si possible, sinon là où rien ne gêne.
/// [avoid] : murs réservés aux meubles. Renvoie la porte posée (null : il y en avait une, ou aucun mur ne convient).
Opening? ensureDoor(LayoutEngine e, {Set<String> avoid = const {}, String? on}) {
  final p = e.project, room = p.room;
  if (p.openings.any((o) => o.isDoor)) return null;
  double load(Wall w) => p.items.where((c) => c.wallId == w.id).fold<double>(0, (a, c) => a + c.width);
  final walls = [...room.walls]..removeWhere((w) => w.length < 780);
  int rank(Wall w) => w.id == on ? -2 : (avoid.contains(w.id) ? 3 : 0) + (w.enabled ? 1 : 0) + (w.orthogonal ? 0 : 1);
  // à égalité : le mur avant, puis le moins chargé
  walls.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final l = load(a).compareTo(load(b));
    if (l != 0) return l;
    if (a.id == 'D' || b.id == 'D') return a.id == 'D' ? -1 : 1;
    return room.order.indexOf(b.id).compareTo(room.order.indexOf(a.id));
  });
  for (final width in const [830.0, 730.0]) {
    for (final w in walls) {
      if (w.length < width + 40) continue;
      // au milieu ; dans une grande salle de bain, à 150 mm d'un angle
      final cands = <double>{
        if (p.universe != 'bain' || w.length <= 2200) w.length / 2, // les murs voisins gardent leurs meubles jusqu'au bout
        if (w.length > 2200) w.length - width / 2 - 150,
        if (w.length > 2200) width / 2 + 150,
        w.length / 2,
        for (var s = width / 2 + 20; s <= w.length - width / 2 - 20; s += 50) s,
      };
      for (final s in cands) {
        final o = Opening(uid: 'essai', type: 'door', wallId: w.id, s: s - width / 2, width: width, z: 0, height: math.min(2040, room.height - 50));
        final box = o.box(room);
        // le débattement et le passage devant la porte restent libres
        final clear = w.strip(o.s - 20, width + 40, 900, 0, 2000);
        if (p.openings.any((x) => x.wallId == w.id && x.s < o.right + 60 && o.s < x.right + 60)) continue;
        if (p.items.any((c) => e.solidOf(c).any((tb) => tb.box.intersects(box) || tb.box.intersects(clear)))) continue;
        if (p.objects.any((ob) {
          final (x0, y0, x1, y1) = ob.footprint;
          return ob.h > 20 && Box3(x0, y0, ob.z, x1, y1, ob.z + ob.h).intersects(clear);
        })) {
          continue;
        }
        return e.addOpening('door', w.id, s: s, width: width);
      }
    }
  }
  return null;
}

/// Place l'arrivée d'eau et l'évacuation de la pièce si elles manquent (pièces d'eau) ; renvoie vrai si on en a posé.
/// Elles vont au mur du meuble qui en a besoin (vasque, évier), sinon au mur le plus long.
bool ensureWater(LayoutEngine e) {
  final p = e.project;
  if (!waterUniverses.contains(p.universe)) return false;
  bool has(bool drain) => p.points.any((x) => x.use == existingUse && (drain ? x.kind == NetKind.drain : (x.kind == NetKind.waterCold || x.kind == NetKind.waterHot)));
  if (has(false) && has(true)) return false;
  final wet = p.items.where((c) => c.modelId.contains('vanity') || e.washes(c)).firstOrNull;
  final (wall, s) = wet != null
      ? (wet.wallId, wet.s + wet.width / 2)
      : () {
          final ex = p.points.where((x) => x.use == existingUse).firstOrNull;
          if (ex != null) return (ex.wallId, ex.s);
          final w = ([...p.room.walls.where((w) => w.enabled)]..sort((a, b) => b.length.compareTo(a.length))).firstOrNull ?? p.room.walls.first;
          return (w.id, w.length / 2);
        }();
  final len = wall == 'I' ? (p.room.island?.length ?? 0) : p.room.wall(wall).length;
  void add(NetKind k, double at, double z) =>
      p.points.add(NetPoint(uid: p.newUid('n'), kind: k, wallId: wall, s: at.clamp(30.0, math.max(30.0, len - 30)), z: z, use: existingUse, auto: false));
  if (!has(false)) {
    add(NetKind.waterCold, s - 80, 500);
    if (p.universe != 'cuisine') add(NetKind.waterHot, s + 80, 500);
  }
  if (!has(true)) add(NetKind.drain, s, 400);
  return true;
}

/// Sanitaires et meubles d'une salle de bain : tous reliés à l'eau (réseaux générés d'après l'implantation).
void ensureBathNetworks(LayoutEngine e) {
  if (e.project.universe != 'bain') return;
  e.project.networks = true;
  applyNetworks(e);
}

/// Largeur de façade encore accessible d'un caisson (mm) : ce qu'un autre meuble posé devant ne cache pas.
double accessibleFront(LayoutEngine e, PlacedCabinet c) {
  final m = e.modelOf(c);
  if (m.kind.isCorner || m.kind.isFiller || !m.isCarcass || c.wallId == 'I') return c.width.toDouble();
  final w = e.room.wall(c.wallId);
  final t0 = c.depth + 5.0;
  final covered = <(double, double)>[];
  void hide(Box3 b) {
    if (b.z0 > c.top - 100 || b.z1 < c.z + 100) return;
    final (s0, s1, d0, d1) = w.boxToWall(b);
    if (d0 > t0 + 350 || d1 < t0) return;
    final a = math.max(c.s, s0), z = math.min(c.right, s1);
    if (z > a) covered.add((a, z));
  }

  for (final o in e.project.items) {
    if (o.uid == c.uid || e.modelOf(o).isFreeHood) continue;
    for (final tb in e.boxesOf(o)) {
      hide(tb.box);
    }
  }
  covered.sort((a, b) => a.$1.compareTo(b.$1));
  var free = c.width.toDouble(), end = c.s;
  for (final (a, b) in covered) {
    final from = math.max(a, end);
    if (b > from) {
      free -= b - from;
      end = b;
    }
  }
  return free;
}

/// Contrôles de l'indispensable.
List<Issue> essentialChecks(LayoutEngine e) {
  final p = e.project;
  final out = <Issue>[];
  if (p.items.isEmpty && p.objects.isEmpty) return out;
  if (!p.openings.any((o) => o.isDoor)) {
    out.add(Issue(Severity.error, 'no_door', L('La pièce n’a pas de porte')));
  }
  if (p.universe == 'bain') {
    final cold = p.points.any((x) => x.kind == NetKind.waterCold || x.kind == NetKind.waterHot), drain = p.points.any((x) => x.kind == NetKind.drain);
    if (!cold || !drain) out.add(Issue(Severity.error, 'no_water', L('Salle de bain sans arrivée d’eau ou sans évacuation')));
  }
  for (final c in p.items) {
    final m = e.modelOf(c);
    final niche = m.isCarcass && !m.kind.isCorner && !m.kind.isFiller;
    if (!niche || (openableCells(m, c).isEmpty && m.kind != CabinetKind.tall && !m.kind.isLow)) continue;
    final free = accessibleFront(e, c);
    if (free < math.min(250.0, c.width * 0.6)) {
      out.add(Issue(Severity.error, 'front_hidden', L('« {0} » : façade cachée par un autre meuble, inaccessible. Mettez un meuble d’angle en L.', [L(m.name)]), [c.uid]));
    }
  }
  return out;
}

/// Une composition n'est proposée que si elle est utilisable : porte, eau, façades accessibles.
bool essentialOk(LayoutEngine e) => essentialChecks(e).isEmpty;

/// Objet du projet qui demande l'eau (sanitaire).
bool needsWaterPoint(RoomObject o) => o.fixture?.water.isNotEmpty ?? false;
