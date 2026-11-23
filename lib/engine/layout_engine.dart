/// Moteur de placement : poser, déplacer, redimensionner, aimanter, éviter les chevauchements,
/// et fournir les données des deux vues (face et dessus) ainsi que les contrôles.
library;

import 'i18n_hook.dart';
import 'dart:math' as math;

import 'catalog.dart';
import 'end_panels.dart';
import 'openings_catalog.dart';
import 'home_appliances.dart';
import 'project.dart';
import 'standards.dart';

class PlacementException implements Exception {
  final String message;
  PlacementException(this.message);
  @override
  String toString() => message;
}

/// Volume d'un caisson rattaché à un mur (un angle en L a deux volumes, un par mur).
class TaggedBox {
  final Box3 box;
  final String wallId;
  final String uid;
  const TaggedBox(this.box, this.wallId, this.uid);
}

/// Rectangle de la vue de face d'un mur (s = position le long du mur, z = hauteur).
class ElevationRect {
  final String uid;
  final CabinetModel model;
  final double s0, s1, z0, z1;

  /// Distance au mur du devant (façade) et de l'arrière.
  final double t0, t1;

  /// false : caisson d'un mur voisin vu de profil, au bord de ce mur.
  final bool onThisWall;
  const ElevationRect(this.uid, this.model, this.s0, this.s1, this.z0, this.z1, this.t0, this.t1, this.onThisWall);
  double get width => s1 - s0;
  double get height => z1 - z0;
}

/// Contour d'un caisson en vue de dessus (polygone fermé, sens horaire).
class PlanShape {
  final String uid;
  final CabinetModel model;
  final List<(double, double)> points;
  final double z0, z1;
  const PlanShape(this.uid, this.model, this.points, this.z0, this.z1);
}

enum Severity { error, warning, info }

class Issue {
  final Severity severity;
  final String code;
  final String message;
  final List<String> uids;
  const Issue(this.severity, this.code, this.message, [this.uids = const []]);
  @override
  String toString() => '[${severity.name}] $code : $message';
}

enum Band { low, high }

/// Espace vide entre deux éléments (ou entre un élément et l'extrémité du mur).
class Gap {
  final String wallId;
  final Band band;
  final double s0, s1;
  final bool fillable; // ≤ fileur max : à combler par un fileur
  const Gap(this.wallId, this.band, this.s0, this.s1, this.fillable);
  double get width => s1 - s0;
  @override
  String toString() => 'mur $wallId ${band.name} ${s0.round()}–${s1.round()} (${width.round()} mm)';
}

class MoveResult {
  final bool moved;
  final bool snapped;
  final String? reason;
  const MoveResult(this.moved, {this.snapped = false, this.reason});
}

class LayoutEngine {
  final Catalog catalog;
  final Project project;

  LayoutEngine(this.catalog, this.project);

  KitchenStandards get std => project.standards;
  Room get room => project.room;

  CabinetModel modelOf(PlacedCabinet c) => catalog[c.modelId];

  // ------------------------------------------------------------------------
  // Géométrie
  // ------------------------------------------------------------------------

  /// Volumes occupés par un caisson.
  List<TaggedBox> boxesOf(PlacedCabinet c) {
    final m = modelOf(c);
    final w = room.wall(c.wallId);
    final main = TaggedBox(w.strip(c.s, c.width.toDouble(), c.depth.toDouble(), c.z, c.height.toDouble()), c.wallId, c.uid);
    if (m.shape == CabinetShape.lShape || m.shape == CabinetShape.diagonal) {
      final nid = room.nextOf(c.wallId);
      final n = room.wall(nid);
      final arm = n.strip(0, (c.widthRight ?? c.width).toDouble(), c.depth.toDouble(), c.z, c.height.toDouble());
      return [main, TaggedBox(arm, nid, c.uid)];
    }
    return [main];
  }

  /// Caisson qui peut recevoir des joues (costados).
  bool canHaveCheeks(CabinetModel m) => !(m.kind.isFiller || m.kind == CabinetKind.coverPanel || m.kind == CabinetKind.islandPanel || m.isFreeHood || m.isHoodUnit);

  /// Volume de la joue d'un caisson, à gauche ou à droite (un meuble d'angle finit à droite sur le mur suivant).
  TaggedBox cheekBox(PlacedCabinet c, bool left) {
    final m = modelOf(c);
    final z0 = m.kind.isHigh ? c.z : 0.0; // une joue de bas ou de colonne descend jusqu'au sol (elle cache la plinthe)
    if (!left && (m.shape == CabinetShape.lShape || m.shape == CabinetShape.diagonal)) {
      final n = room.wall(room.nextOf(c.wallId));
      return TaggedBox(n.strip((c.widthRight ?? c.width).toDouble(), cheekT, c.depth.toDouble(), z0, c.top - z0), n.id, c.uid);
    }
    return TaggedBox(room.wall(c.wallId).strip(left ? c.s - cheekT : c.right, cheekT, c.depth.toDouble(), z0, c.top - z0), c.wallId, c.uid);
  }

  /// Volumes d'un caisson avec ses joues ajoutées.
  List<TaggedBox> solidOf(PlacedCabinet c) => [
        ...boxesOf(c),
        for (final left in [true, false])
          if (c.hasCheek(left)) cheekBox(c, left),
      ];

  /// Ce côté du caisson se voit : ni mur, ni voisin aussi haut et aussi profond.
  bool sideVisible(PlacedCabinet c, bool left) {
    final m = modelOf(c);
    if (!canHaveCheeks(m)) return false;
    if (!left && (m.shape == CabinetShape.lShape || m.shape == CabinetShape.diagonal)) {
      final n = room.nextOf(c.wallId);
      final edge = (c.widthRight ?? c.width).toDouble();
      return !project.items.any((o) => o != c && o.wallId == n && (o.s - edge).abs() < 15 && o.top >= c.top - 50 && o.z <= c.z + 50 && o.depth >= c.depth - 50);
    }
    final w = room.wall(c.wallId);
    if (left ? c.s < 15 : c.right > w.length - 15) return w.id == 'I';
    return !project.items.any((o) {
      if (o == c || modelOf(o).isFreeHood || o.z > c.z + 50 || o.top < c.top - 50 || o.depth < c.depth - 50) return false;
      for (final tb in solidOf(o)) {
        if (tb.wallId != c.wallId) continue;
        final (s0, s1, _, _) = w.boxToWall(tb.box);
        if ((left ? s1 - c.s : s0 - c.right).abs() < 15) return true;
      }
      return false;
    });
  }

  /// Côtés visibles qui n'ont pas encore de joue ajoutée (et qui ne sont pas réglés sur « sans »).
  List<(PlacedCabinet, bool)> cheekCandidates() {
    final auto = project.style.endPanels ? endPanels(this) : const <EndPanel>[];
    return [
      for (final c in project.items)
        for (final left in [true, false])
          if (c.cheek(left) == null && sideVisible(c, left))
            if (!auto.any((j) => j.wallId == c.wallId && j.depth >= c.depth - 1 && j.z1 >= c.top - 1 && (j.s - (left ? c.s - cheekT : c.right)).abs() < 1)) (c, left),
    ];
  }

  /// Règle la joue d'un côté : null automatique, true avec, false sans.
  /// Avec : les voisins se décalent de 18 mm ; s'il n'y a pas la place, la joue est prise sur la largeur du caisson.
  /// Renvoie ce qui a été fait (ou pourquoi c'est impossible, sans rien changer).
  (bool, String?) setCheek(String uid, bool left, bool? on) {
    final c = _get(uid);
    final m = modelOf(c);
    void put(String? v) => left ? c.cheekL = v : c.cheekR = v;
    if (on != true) {
      if (c.cheek(left) == 'pris') {
        c.width += cheekT.round();
        if (left) c.s -= cheekT;
      }
      put(on == false ? 'non' : null);
      return (true, null);
    }
    if (c.hasCheek(left)) return (true, null);
    if (!canHaveCheeks(m)) return (false, L('pas de joue sur cet élément'));
    final before = c.cheek(left);
    final saved = [for (final o in project.items) (o, o.s, o.width)];
    put('oui');
    if (_makeRoom(c, left)) {
      final moved = saved.where((x) => x.$1.s != x.$2 || x.$1.width != x.$3).length;
      return (true, moved == 0 ? null : L('Joue ajoutée : {0} voisin(s) décalé(s) de 18 mm', [moved]));
    }
    for (final (o, s, w) in saved) {
      o.s = s;
      o.width = w;
    }
    // prise sur la largeur du caisson, sauf s'il porte un appareil à encastrer
    final fixed = m.kind.isCorner || m.requiresAppliance != null || isCooking(m) || m.id.contains('oven') || m.id.contains('fridge') || m.id.contains('dishwasher');
    if (!fixed && c.width >= 250) {
      c.width -= cheekT.round();
      if (left) c.s += cheekT;
      put('pris');
      if (!_clashes(c)) return (true, L('Pas de place à côté : la joue est prise sur le caisson ({0} mm)', [c.width]));
      c.width += cheekT.round();
      if (left) c.s -= cheekT;
    }
    put(before);
    return (false, L('Pas la place pour la joue : il faut 18 mm libres de ce côté'));
  }

  /// Décale les voisins pour loger la joue de [c] ; un fileur rétrécit et absorbe le décalage.
  bool _makeRoom(PlacedCabinet c, bool left) {
    final cb = cheekBox(c, left);
    final w = room.wall(cb.wallId);
    final (c0, c1, _, _) = w.boxToWall(cb.box);
    if (c0 < -0.5 || c1 > w.length + 0.5) return false;
    final dir = cb.wallId == c.wallId ? (left ? -1 : 1) : 1;
    final blockers = [cb];
    final order = [
      for (final o in project.items)
        if (o.uid != c.uid && o.wallId == cb.wallId) o
    ]..sort((a, b) => dir > 0 ? a.s.compareTo(b.s) : b.right.compareTo(a.right));
    for (final o in order) {
      var need = 0.0;
      for (final mine in solidOf(o)) {
        for (final b in blockers) {
          if (!mine.box.intersects(b.box)) continue;
          final (o0, o1, _, _) = w.boxToWall(mine.box);
          final (b0, b1, _, _) = w.boxToWall(b.box);
          final d = dir > 0 ? b1 - o0 : o1 - b0;
          if (d > need) need = d;
        }
      }
      if (need <= 0.5) continue;
      final m = modelOf(o);
      if (m.kind.isCorner || need > 400) return false;
      if (m.kind.isFiller && m.widths.allows(o.width - need.ceil())) {
        o.width -= need.ceil();
        if (dir > 0) o.s += need.ceil();
      } else {
        o.s += dir * need;
      }
      blockers.addAll(solidOf(o));
    }
    return !project.items.any((o) => (o.uid == c.uid || o.wallId == cb.wallId) && _clashes(o));
  }

  static const cheekT = EndPanel.thickness;

  /// Endroit d'une façade pour le choix de la poignée.
  static String handleZone(CabinetKind k, {bool drawer = false}) => drawer ? 'tiroir' : (k.isHigh ? 'haut' : (k == CabinetKind.tall || k == CabinetKind.cornerTall ? 'colonne' : 'bas'));

  /// Meuble à profil Gola : le choix général, sauf un haut qui a sa propre poignée.
  bool golaOn(CabinetModel m) => project.style.handle == 'gola' && project.style.handleAt(handleZone(m.kind)).kind == 'gola';

  /// Contour en vue de dessus.
  PlanShape planShape(PlacedCabinet c) {
    final m = modelOf(c);
    final w = room.wall(c.wallId);
    final d = c.depth.toDouble();
    List<(double, double)> pts;
    switch (m.shape) {
      case CabinetShape.lShape:
      case CabinetShape.diagonal:
        // bras 1 le long du mur (s de c.s à la longueur du mur), bras 2 sur le mur suivant
        final n = room.wall(room.nextOf(c.wallId));
        final wr = (c.widthRight ?? c.width).toDouble();
        final a = w.toPlan(c.s, 0);
        final b = w.toPlan(w.length, 0); // coin
        final e = n.toPlan(wr, 0);
        final f = n.toPlan(wr, d);
        final inner = w.toPlan(w.length - d, d); // coin intérieur
        final g = w.toPlan(c.s, d);
        pts = m.shape == CabinetShape.lShape ? [a, b, e, f, inner, g] : [a, b, e, f, g];
      default:
        pts = [w.toPlan(c.s, 0), w.toPlan(c.right, 0), w.toPlan(c.right, d), w.toPlan(c.s, d)];
    }
    return PlanShape(c.uid, m, pts, c.z, c.top);
  }

  List<PlanShape> planView() => [for (final c in project.items) planShape(c)];

  /// Vue de face d'un mur : ses caissons, plus ceux des murs voisins vus de profil au bord.
  List<ElevationRect> elevation(String wallId) {
    final w = room.wall(wallId);
    final res = <ElevationRect>[];
    for (final c in project.items) {
      final m = modelOf(c);
      for (final tb in boxesOf(c)) {
        final (s0, s1, t0, t1) = w.boxToWall(tb.box);
        if (t0 > _touch || s1 <= 0 || s0 >= w.length) continue; // ne touche pas ce mur
        res.add(ElevationRect(c.uid, m, s0, s1, tb.box.z0, tb.box.z1, t0, t1, tb.wallId == wallId));
      }
    }
    // les éléments de profil d'abord, ceux du mur par-dessus
    res.sort((a, b) => (a.onThisWall ? 1 : 0).compareTo(b.onThisWall ? 1 : 0));
    return res;
  }

  static const _touch = 1.0;

  // ------------------------------------------------------------------------
  // Hauteurs de pose
  // ------------------------------------------------------------------------

  /// Ligne du dessus des éléments hauts d'un mur (les hauts sont alignés par le haut).
  double wallTopLine(String wallId) {
    var top = 0.0;
    for (final c in project.items.where((c) => c.wallId == wallId)) {
      final m = modelOf(c);
      if (m.kind.isHigh && !m.kind.isFiller && !m.isHoodUnit && !m.isFreeHood) top = math.max(top, c.top);
    }
    return top > 0 ? top : std.wallBottomDefault + 800.0;
  }

  /// Caisson de hotte : dessus aligné sur les autres hauts, hauteur choisie pour rester à
  /// au moins [hoodAboveHobMin] mm au-dessus de la plaque (750 → 650 mm sous une ligne à 2300).
  (double, int) hoodPlacement(CabinetModel hood, String wallId) {
    final line = wallTopLine(wallId);
    final minBottom = std.worktopTop + hoodAboveHobMin.toDouble();
    final hs = hood.heights.isRange ? [hood.heights.max!, hood.heights.min!] : ([...hood.heights.values]..sort((a, b) => b.compareTo(a)));
    for (final h in hs) {
      if (line - h >= minBottom - 0.5) return (line - h, h);
    }
    final h = hs.last;
    return (math.max(minBottom, line - h), h);
  }

  /// Projet de cuisine (plan de travail, triangle d'activité, réseaux) ou autre univers.
  bool get kitchen => project.universe == 'cuisine';

  /// Les meubles bas reçoivent un plan de travail (cuisine, buanderie).
  bool get hasWorktop => kitchen || project.universe == 'buanderie';

  /// Dessous du plan de travail sur un linéaire : hauteur normalisée en cuisine, dessus des meubles ailleurs.
  double worktopZ(String wallId, double a, double b) {
    if (kitchen) return std.baseTop.toDouble();
    var z = 0.0;
    for (final c in project.items) {
      if (c.wallId == wallId && modelOf(c).kind.isLow && c.s < b - 1 && a < c.right - 1) z = math.max(z, c.top);
    }
    return z == 0 ? std.baseTop.toDouble() : z;
  }

  /// Machines à laver logées dans un meuble de buanderie (et colonnes machine de salle de bain) : place de chacune.
  List<({double s, double z, double w, double h, double d, String ref, String cap})> machinesIn(PlacedCabinet c) {
    final slots = machineSlots(c);
    final stacked = c.modelId.endsWith('column');
    final out = <({double s, double z, double w, double h, double d, String ref, String cap})>[];
    var z = c.z + 18;
    for (var i = 0; i < slots.length; i++) {
      final key = c.machines != null && i < c.machines!.length ? c.machines![i] : slots[i].def;
      final (f, v) = machineOf(key) ?? machineOf(slots[i].def)!;
      // sous un plan, le dessus de la machine se retire : elle rentre dans la hauteur du meuble
      final h = math.min(v.h.toDouble(), stacked ? 860.0 : c.height - 40.0);
      out.add((
        s: stacked ? c.s + c.width / 2 : c.s + 18 + (c.width - 36.0) * (i + 0.5) / slots.length,
        z: z,
        w: math.min(v.w.toDouble(), slots[i].w),
        h: h,
        d: math.min(v.d.toDouble(), c.depth - 30.0),
        ref: 'fixture:${f.id}',
        cap: v.label,
      ));
      if (stacked) z += h + 12;
    }
    return out;
  }

  double defaultZ(CabinetModel m) {
    if (m.mountZ != null) return m.mountZ!.toDouble();
    switch (m.kind) {
      case CabinetKind.base:
      case CabinetKind.cornerBase:
      case CabinetKind.cornerTall:
      case CabinetKind.fillerBase:
      case CabinetKind.tall:
        return std.plinthHeight.toDouble();
      case CabinetKind.wall:
      case CabinetKind.cornerWall:
      case CabinetKind.fillerWall:
        return std.wallBottomDefault.toDouble();
      case CabinetKind.coverPanel:
      case CabinetKind.islandPanel:
        return 0;
    }
  }

  /// Les éléments posés au sol ont une hauteur imposée ; seuls les hauts se déplacent en Z.
  bool canMoveVertically(CabinetModel m) => m.kind.isHigh;

  // ------------------------------------------------------------------------
  // Opérations
  // ------------------------------------------------------------------------

  /// Pose un nouveau caisson. [s] est la position souhaitée le long du mur (le moteur l'aimante
  /// et la décale si besoin). Lève [PlacementException] s'il n'y a pas la place.
  PlacedCabinet add(String modelId, String wallId,
      {double? s, double? z, int? width, int? height, String? opening, String? variant}) {
    final m = catalog[modelId];
    if (wallId == 'I' && (m.kind.isHigh || m.kind.isCorner || m.kind == CabinetKind.tall)) {
      throw PlacementException(L('« {0} » ne se pose pas sur l\'îlot (éléments bas uniquement)', [L(m.name)]));
    }
    final w = room.wall(wallId);
    if (!w.enabled) throw PlacementException(L('{0} désactivé', [Room.wallNames[wallId]]));
    // caisson de hotte posé sans hauteur imposée : aligné sur les autres hauts
    if (m.isHoodUnit && z == null && height == null && wallId != 'I') {
      final (hz, hh) = hoodPlacement(m, wallId);
      z = hz;
      height = hh;
    }
    // hotte posée librement : 650 mm au-dessus du plan de travail, cheminée jusqu'au plafond
    if (m.isFreeHood && z == null && wallId != 'I') {
      z = (std.worktopTop + 650).toDouble();
      final room0 = room.height - z; // place jusqu'au plafond : la plus grande hauteur qui tient
      final fit = m.heights.isRange ? [room0.round().clamp(m.heights.min!, m.heights.max!)] : m.heights.values.where((v) => v <= room0).toList();
      height ??= fit.isEmpty ? m.heights.values.reduce(math.min) : fit.reduce(math.max);
    }
    final c = PlacedCabinet(
      uid: project.newUid(),
      modelId: modelId,
      wallId: wallId,
      s: 0,
      z: z ?? defaultZ(m),
      width: width == null ? m.defaultWidth : m.widths.nearest(width),
      height: height == null ? m.defaultHeight : m.heights.nearest(height),
      depth: m.depth,
      widthRight: m.widthRight,
      opening: opening ?? (m.openingOptions.isEmpty ? null : m.openingOptions.first),
      variant: variant ?? (m.variants.isEmpty ? null : m.variants.first),
    );
    if (m.kind.isCorner && m.shape != CabinetShape.blind) {
      if (!room.wall(room.nextOf(wallId)).enabled) {
        throw PlacementException(L('angle impossible : {0} désactivé', [Room.wallNames[room.nextOf(wallId)]]));
      }
    }
    final pos = _resolve(c, s ?? 0);
    if (pos == null) {
      throw PlacementException(L('pas de place pour « {0} » ({1} mm) sur {2}', [L(m.name), c.width, Room.wallNames[wallId]]));
    }
    c.s = pos.$1;
    project.items.add(c);
    return c;
  }

  /// Déplace un caisson (glisser-déposer). [wallId] permet de changer de mur.
  MoveResult move(String uid, {String? wallId, double? s, double? z}) {
    final c = _get(uid);
    final m = modelOf(c);
    final backup = c.copy();
    if (wallId != null && wallId != c.wallId) {
      if (!room.wall(wallId).enabled) return MoveResult(false, reason: '${Room.wallNames[wallId]} désactivé');
      c.wallId = wallId;
    }
    if (z != null && canMoveVertically(m)) c.z = _snapZ(c, z);
    final pos = _resolve(c, s ?? c.s);
    if (pos == null) {
      _restore(c, backup);
      return const MoveResult(false, reason: 'pas de place à cet endroit');
    }
    c.s = pos.$1;
    return MoveResult(true, snapped: pos.$2);
  }

  /// Change la largeur / hauteur (ramenées à la valeur catalogue la plus proche).
  MoveResult resize(String uid, {int? width, int? height}) {
    final c = _get(uid);
    final m = modelOf(c);
    final backup = c.copy();
    if (width != null) c.width = m.widths.nearest(width);
    if (height != null) c.height = m.heights.nearest(height);
    final pos = _resolve(c, c.s);
    if (pos == null) {
      _restore(c, backup);
      return const MoveResult(false, reason: 'pas de place pour cette dimension');
    }
    c.s = pos.$1;
    return MoveResult(true, snapped: pos.$2);
  }

  void remove(String uid) => project.items.removeWhere((c) => c.uid == uid);

  /// Famille de pose : 0 bas, 1 haut, 2 colonne (on n'échange qu'à l'intérieur d'une famille).
  int _family(CabinetModel m) => m.kind == CabinetKind.tall ? 2 : (m.kind.isHigh ? 1 : 0);

  /// Le caisson touche-t-il un autre volume, une ouverture, ou sort-il du mur ?
  bool clashes(PlacedCabinet c) => _clashes(c);

  bool _clashes(PlacedCabinet c) {
    final mine = solidOf(c);
    for (final o in project.items) {
      if (o.uid == c.uid) continue;
      for (final b in solidOf(o)) {
        if (mine.any((x) => x.box.intersects(b.box))) return true;
      }
    }
    for (final ob in openingBoxes()) {
      if (mine.any((x) => x.box.intersects(ob.box))) return true;
    }
    final w = room.wall(c.wallId);
    return c.s - (c.hasCheek(true) ? cheekT : 0) < -0.5 || c.right + (c.hasCheek(false) && !modelOf(c).kind.isCorner ? cheekT : 0) > w.length + 0.5;
  }

  /// Duplique un caisson (mêmes réglages) : posé juste à droite, sinon à gauche, sinon à la
  /// première place libre du mur. Lève [PlacementException] s'il n'y a pas de place.
  PlacedCabinet duplicate(String uid) {
    final src = _get(uid);
    final m = modelOf(src);
    if (m.kind.isCorner) throw PlacementException(L('un meuble d\'angle ne se duplique pas'));
    final copy = PlacedCabinet.fromJson({...src.toJson(), 'uid': project.newUid()});
    project.items.add(copy);
    final w = room.wall(src.wallId);
    final tries = <double>[src.right, src.s - src.width];
    for (final (a, b) in freeIntervals(src.wallId, m.kind.isHigh ? Band.high : Band.low)) {
      if (b - a >= src.width) tries.add(a);
    }
    for (final s in tries) {
      if (s < 0 || s + copy.width > w.length) continue;
      copy.s = s;
      if (!_clashes(copy)) return copy;
    }
    project.items.remove(copy);
    throw PlacementException(L('pas de place libre sur {0} pour dupliquer « {1} »', [Room.wallNames[src.wallId]?.toLowerCase(), L(m.name)]));
  }

  /// Glisser un caisson sur son voisin (même mur, même famille) : ils échangent leurs places.
  /// [s] est la position souhaitée du caisson tiré. Renvoie null si aucun échange.
  MoveResult? trySwap(String uid, double s) {
    final c = _get(uid);
    final m = modelOf(c);
    if (m.kind.isCorner || m.kind.isFiller) return null;
    final center = s + c.width / 2;
    for (final b in project.items) {
      if (b.uid == c.uid || b.wallId != c.wallId) continue;
      final mb = modelOf(b);
      if (mb.kind.isCorner || mb.kind.isFiller || _family(mb) != _family(m)) continue;
      if (center <= b.s || center >= b.right) continue;
      final (cs, bs) = (c.s, b.s);
      if (bs >= cs) {
        // voisin à droite : il prend la place de gauche, le caisson tiré finit à son bord droit
        b.s = cs;
        c.s = bs + b.width - c.width;
      } else {
        b.s = c.right - b.width;
        c.s = bs;
      }
      if (_clashes(c) || _clashes(b)) {
        c.s = cs;
        b.s = bs;
        return null;
      }
      return const MoveResult(true, snapped: true);
    }
    return null;
  }

  /// Modèles qui peuvent remplacer [c] au même endroit (même famille : bas, haut ou colonne).
  List<CabinetModel> replacementsFor(PlacedCabinet c) {
    final m = modelOf(c);
    int fam(CabinetModel x) => x.kind.isCorner
        ? (x.kind == CabinetKind.cornerBase ? 3 : x.kind == CabinetKind.cornerTall ? 6 : 4)
        : x.kind.isFiller || x.kind == CabinetKind.coverPanel || x.kind == CabinetKind.islandPanel
            ? 5
            : x.kind.isLow
                ? 0
                : x.kind.isHigh
                    ? 1
                    : 2;
    return [
      for (final x in catalog.models)
        if (x.id != m.id && fam(x) == fam(m) && !(c.wallId == 'I' && (x.kind.isHigh || x.kind == CabinetKind.tall))) x
    ];
  }

  /// Remplace le modèle d'un caisson posé en gardant sa place (et sa largeur si le nouveau modèle l'accepte).
  MoveResult replace(String uid, String modelId) {
    final c = _get(uid);
    final m = catalog[modelId];
    final backup = c.copy();
    c
      ..modelId = modelId
      ..width = m.widths.nearest(c.width)
      ..height = m.heights.nearest(c.height)
      ..depth = m.depth
      ..widthRight = m.widthRight
      ..opening = m.openingOptions.isEmpty ? null : m.openingOptions.first
      ..variant = m.variants.isEmpty ? null : m.variants.first
      ..internal = null
      ..appliances = null
      ..layout = null;
    if (m.kind.isHigh != modelOf(backup).kind.isHigh || m.kind == CabinetKind.tall) c.z = defaultZ(m);
    final pos = _resolve(c, c.s);
    // le nouvel élément doit rester à sa place (petit décalage toléré si plus large)
    if (pos == null || (pos.$1 - backup.s).abs() > (c.width - backup.width).abs() + 20) {
      final i = project.items.indexOf(c);
      project.items[i] = backup;
      return MoveResult(false, reason: 'pas de place pour « ${m.name} » (${c.width} mm) à cet endroit');
    }
    c.s = pos.$1;
    return MoveResult(true, snapped: pos.$2);
  }

  // ------------------------------------------------------------------------
  // Portes et fenêtres
  // ------------------------------------------------------------------------

  List<TaggedBox> openingBoxes() => [for (final o in project.openings) TaggedBox(o.box(room), o.wallId, o.uid)];

  /// Ajoute une porte (830 × 2040) ou une fenêtre (1000 × 1150, allège 1050) centrée sur [s].
  Opening addOpening(String type, String wallId, {double? s, double? width, double? height, double? z, String? model}) {
    final w = room.wall(wallId);
    final door = type == 'door';
    final mdl = model == null ? null : OpeningModel.byId[model];
    final wd = width ?? mdl?.defaultWidth.toDouble() ?? (door ? 830.0 : 1000.0);
    if (wd > w.length) throw PlacementException(L('{0} plus large que le mur', [door ? 'porte' : 'fenêtre']));
    final o = Opening(
      uid: project.newUid('o'),
      type: type,
      wallId: wallId,
      s: ((s ?? w.length / 2) - wd / 2).clamp(0.0, w.length - wd),
      width: wd,
      z: z ?? mdl?.defaultSill.toDouble() ?? (door ? 0 : 1050),
      height: height ?? mdl?.defaultHeight.toDouble() ?? (door ? 2040 : 1150),
      model: model,
    );
    if (o.z + o.height > room.height) o.height = math.max(300, room.height - o.z);
    project.openings.add(o);
    return o;
  }

  /// Intervalles (début, fin) déjà occupés sur un mur à la hauteur [z0]..[z1] : caissons, ouvertures, objets
  /// adossés (sanitaires, mobilier). [skip] : l'ouverture à ignorer (celle qu'on déplace).
  List<(double, double)> occupiedOnWall(String wallId, double z0, double z1, {String? skip}) {
    final w = room.wall(wallId);
    final out = <(double, double)>[];
    for (final c in project.items) {
      for (final tb in solidOf(c)) {
        final b = tb.box;
        if (b.z1 <= z0 + 1 || b.z0 >= z1 - 1) continue;
        final (s0, s1, t0, _) = w.boxToWall(b);
        if (t0 > 700) continue; // loin du mur (îlot, caisson du mur d'en face)
        out.add((s0, s1));
      }
    }
    for (final o in project.openings) {
      if (o.uid == skip || o.wallId != wallId) continue;
      out.add((o.s - 50, o.right + 50)); // 5 cm de trumeau entre deux ouvertures
    }
    for (final o in project.objects) {
      if (o.z >= z1 - 1 || o.z + o.h <= z0 + 1) continue;
      final (x0, y0, x1, y1) = o.footprint;
      final (s0, s1, t0, _) = w.boxToWall(Box3(x0, y0, o.z, x1, y1, o.z + o.h));
      if (t0 > 300) continue;
      out.add((s0, s1));
    }
    return out;
  }

  /// Position libre la plus proche de [want] pour une ouverture de largeur [width] (null : le mur est plein).
  double? freeOpeningSpot(String wallId, double width, double z0, double z1, {double? want, String? skip}) {
    final w = room.wall(wallId);
    if (width > w.length) return null;
    final occ = occupiedOnWall(wallId, z0, z1, skip: skip);
    bool free(double s) => !occ.any((r) => s < r.$2 - 0.5 && s + width > r.$1 + 0.5);
    final start = ((want ?? (w.length - width) / 2)).clamp(0.0, w.length - width);
    if (free(start)) return start;
    // on s'écarte de plus en plus du point voulu, des deux côtés, puis on teste les bords d'obstacles
    final cands = <double>{0, w.length - width, for (final r in occ) ...[r.$2, r.$1 - width]}
        .where((s) => s >= 0 && s <= w.length - width)
        .toList()
      ..sort((a, b) => (a - start).abs().compareTo((b - start).abs()));
    for (final s in cands) {
      if (free(s)) return s;
    }
    return null;
  }

  /// Déplace une ouverture le long d'un mur (ou vers un autre mur).
  void moveOpening(String uid, {String? wallId, double? s, double? width, double? height, double? z}) {
    final o = project.openingByUid(uid) ?? (throw PlacementException(L('ouverture inconnue : {0}', [uid])));
    if (wallId != null) o.wallId = wallId;
    if (width != null) o.width = width;
    if (height != null) o.height = height;
    if (z != null) o.z = z;
    final len = room.wall(o.wallId).length;
    o.width = o.width.clamp(300.0, len);
    o.s = (s ?? o.s).clamp(0.0, len - o.width);
    if (o.z + o.height > room.height) o.height = room.height - o.z;
  }

  void removeOpening(String uid) => project.openings.removeWhere((o) => o.uid == uid);

  // ------------------------------------------------------------------------
  // Déplacement d'un mur (glisser à la main)
  // ------------------------------------------------------------------------

  static const roomMin = 1500.0;

  // ------------------------------------------------------------------------
  // Îlot
  // ------------------------------------------------------------------------

  /// Style des caissons de remplissage : 'portes' (classique), 'tiroirs' (bas à tiroirs),
  /// 'mixte' (tiroir + porte en bas, vitrines en bout de linéaire haut).
  String fillStyle = 'portes';

  String _styledModel(Band band, int width, String fallback) {
    String pick(List<String> ids) => ids.firstWhere((id) => catalog.tryGet(id)?.widths.allows(width) ?? false, orElse: () => fallback);
    if (band == Band.low) {
      return switch (fillStyle) {
        'tiroirs' => pick(['base_drawers_multi', 'base_wide_drawers', 'base_door_drawer', fallback]),
        'mixte' => pick(['base_door_drawer', 'base_door_drawer_double', fallback]),
        _ => fallback,
      };
    }
    return fillStyle == 'mixte' && width >= 400 && width <= 600 ? pick(['wall_glass_door', fallback]) : fallback;
  }

  /// Rectangles occupés au sol (caissons posés au sol et passage devant les portes).
  List<Box3> floorObstacles() => [
        for (final c in project.items.where((c) => c.wallId != 'I'))
          for (final b in boxesOf(c))
            if (b.box.z0 < std.baseTop) b.box,
        for (final o in project.openings.where((o) => o.isDoor)) room.wall(o.wallId).strip(o.s - 100, o.width + 200, 1000, 0, 2100),
      ];

  /// Place l'îlot dans l'espace libre de la pièce : passages d'au moins [aisleMin] (idéalement
  /// [aisleAdvised]) vers les meubles, 900 mm vers les murs nus, hors du passage des portes ;
  /// le plus long possible, centré dans l'espace libre, près du linéaire principal.
  Island? bestIslandSpot({double? length}) {
    final r = room;
    // murs équipés encore vides : on réserve la place du futur linéaire (600 mm)
    // meubles au sol et murs équipés : 1 m de passage ; zone devant les portes : simplement libre
    final doorZones = [for (final o in project.openings.where((o) => o.isDoor)) r.wall(o.wallId).strip(o.s - 100, o.width + 200, 1000, 0, 2100)];
    final obstacles = [
      for (final c in project.items.where((c) => c.wallId != 'I'))
        for (final b in boxesOf(c))
          if (b.box.z0 < std.baseTop) b.box,
      for (final w in r.walls)
        if (w.enabled && !project.items.any((c) => c.wallId == w.id && modelOf(c).floorSupport)) w.strip(0, w.length, 600, 0, 900),
    ];
    final wallGap = aisleMin.toDouble(); // passage vers les murs nus (contrôle de l'îlot)
    final depth = Island.depth + 300;
    double gapTo(Box3 a, double x0, double y0, double x1, double y1) {
      final dx = math.max(0.0, math.max(a.x0 - x1, x0 - a.x1));
      final dy = math.max(0.0, math.max(a.y0 - y1, y0 - a.y1));
      return math.sqrt(dx * dx + dy * dy);
    }

    Island? best;
    var bestScore = -double.infinity;
    final lengths = length != null ? [length] : [3000.0, 2700.0, 2400.0, 2100.0, 1800.0, 1500.0, 1200.0];
    for (final len in lengths) {
      for (var y0 = wallGap; y0 + depth <= r.depth - wallGap + 0.5; y0 += 50) {
        for (var x0 = wallGap; x0 + len <= r.width - wallGap + 0.5; x0 += 50) {
          final x1 = x0 + len, y1 = y0 + depth;
          var minGap = double.infinity;
          var ok = true;
          for (final b in obstacles) {
            final g = gapTo(b, x0, y0, x1, y1);
            if (g < aisleMin - 0.5) {
              ok = false;
              break;
            }
            minGap = math.min(minGap, g);
          }
          if (ok && doorZones.any((z) => gapTo(z, x0, y0, x1, y1) < 100)) ok = false;
          if (ok && r.outline != null) {
            // pièce à contour libre : l'îlot et ses passages restent dans la pièce
            for (final (px, py) in [(x0 - aisleMin, y0 - aisleMin), (x1 + aisleMin, y0 - aisleMin), (x1 + aisleMin, y1 + aisleMin), (x0 - aisleMin, y1 + aisleMin)]) {
              if (!r.contains(px.clamp(1, r.width - 1).toDouble(), py.clamp(1, r.depth - 1).toDouble())) ok = false;
            }
          }
          if (!ok) continue;
          // centrage : écarts gauche / droite et avant / arrière équilibrés dans l'espace libre
          double free(double Function(Box3) toward, double wallDist) {
            var d = wallDist;
            for (final b in obstacles) {
              d = math.min(d, toward(b));
            }
            return d;
          }

          bool overlapX(Box3 b) => b.x0 < x1 && x0 < b.x1;
          bool overlapY(Box3 b) => b.y0 < y1 && y0 < b.y1;
          final left = free((b) => overlapY(b) && b.x1 <= x0 ? x0 - b.x1 : double.infinity, x0);
          final right = free((b) => overlapY(b) && b.x0 >= x1 ? b.x0 - x1 : double.infinity, r.width - x1);
          final front = free((b) => overlapX(b) && b.y1 <= y0 ? y0 - b.y1 : double.infinity, y0);
          final back = free((b) => overlapX(b) && b.y0 >= y1 ? b.y0 - y1 : double.infinity, r.depth - y1);
          // côté travail (vers le mur du fond) : idéalement 1200 mm ; côté repas : de la place pour les tabourets
          final score = len / 10 - (left - right).abs() / 20 - (front - aisleAdvised).abs() / 8 - (back < 1000 ? 200 : 0) + minGap / 100;
          if (score > bestScore) {
            bestScore = score;
            best = Island(x0: x0, y0: y0, length: len);
          }
        }
      }
      if (best != null && length == null) break; // la plus grande longueur qui tient
    }
    return best;
  }

  /// Crée un îlot dans l'espace libre : passages d'au moins 1 m tout autour (meubles, murs nus, portes).
  /// S'il n'y a pas cette place, pas d'îlot (jamais un îlot qui bloque la circulation).
  Island addIsland({double? length}) {
    if (room.island != null) throw PlacementException(L('il y a déjà un îlot'));
    final spot = bestIslandSpot(length: length);
    if (spot == null) {
      throw PlacementException(L('Pas assez de place pour un îlot : il faut {0} mm de passage tout autour (meubles, murs et portes). Agrandissez la pièce ou retirez un linéaire.', [aisleMin]));
    }
    room.island = spot;
    return spot;
  }

  /// Passages libres autour de l'îlot (mm) : côté fond, avant, gauche, droite.
  Map<String, double> islandAisles() {
    final isl = room.island;
    if (isl == null) return const {};
    final obstacles = floorObstacles();
    final x0 = isl.x0, x1 = isl.x0 + isl.length, y0 = isl.y0, y1 = isl.y0 + Island.depth + isl.overhang;
    bool ox(Box3 b) => b.x0 < x1 && x0 < b.x1;
    bool oy(Box3 b) => b.y0 < y1 && y0 < b.y1;
    double side(double wall, double Function(Box3) d) => obstacles.fold(wall, (m, b) => math.min(m, d(b)));
    return {
      'fond': side(y0, (b) => ox(b) && b.y1 <= y0 + 0.5 ? y0 - b.y1 : double.infinity),
      'avant': side(room.depth - y1, (b) => ox(b) && b.y0 >= y1 - 0.5 ? b.y0 - y1 : double.infinity),
      'gauche': side(x0, (b) => oy(b) && b.x1 <= x0 + 0.5 ? x0 - b.x1 : double.infinity),
      'droite': side(room.width - x1, (b) => oy(b) && b.x0 >= x1 - 0.5 ? b.x0 - x1 : double.infinity),
    };
  }

  /// Déplace / redimensionne l'îlot ; ses caissons gardent leur place sur l'îlot (depuis le côté gauche
  /// vu de face). Refuse si l'îlot sort de la pièce ou touche un autre élément.
  void setIsland({double? x0, double? y0, double? length, double? overhang}) {
    final isl = room.island ?? (throw PlacementException(L('pas d\'îlot')));
    final backup = (isl.x0, isl.y0, isl.length, isl.overhang);
    final items = [for (final c in project.items.where((c) => c.wallId == 'I')) (c, c.s)];
    final oldLen = isl.length;
    if (x0 != null) isl.x0 = x0;
    if (y0 != null) isl.y0 = y0;
    if (overhang != null) isl.overhang = overhang;
    if (length != null) {
      isl.length = length;
      // l'origine du linéaire est l'extrémité droite (vue de face) : on garde les caissons à gauche en place
      for (final (c, s) in items) {
        c.s = s + (length - oldLen);
      }
    }
    String? problem;
    if (isl.length < 600) problem = 'îlot trop court (600 mm minimum)';
    if (isl.x0 < 0 || isl.y0 < 0 || isl.x0 + isl.length > room.width + 0.5 || isl.y0 + Island.depth + isl.overhang > room.depth + 0.5) {
      problem = 'l\'îlot sortirait de la pièce';
    }
    for (final (c, _) in items) {
      if (c.s < -0.5 || c.right > isl.length + 0.5) problem = 'un caisson dépasserait de l\'îlot';
    }
    if (problem == null) {
      final mine = project.items.where((c) => c.wallId == 'I').expand(boxesOf).toList();
      final foot = islandFootprint()!;
      for (final o in project.items.where((c) => c.wallId != 'I')) {
        for (final b in boxesOf(o)) {
          if (b.box.intersects(foot) || mine.any((x) => x.box.intersects(b.box))) problem = 'l\'îlot toucherait « ${modelOf(o).name} »';
        }
      }
    }
    if (problem != null) {
      isl
        ..x0 = backup.$1
        ..y0 = backup.$2
        ..length = backup.$3
        ..overhang = backup.$4;
      for (final (c, s) in items) {
        c.s = s;
      }
      throw PlacementException(L('îlot : {0}', [problem]));
    }
  }

  void removeIsland() {
    project.items.removeWhere((c) => c.wallId == 'I');
    room.island = null;
  }

  /// Emprise au sol de l'îlot (caissons + plan de travail débordant), hauteur plan de travail.
  Box3? islandFootprint() {
    final i = room.island;
    if (i == null) return null;
    return Box3(i.x0, i.y0, 0, i.x0 + i.length, i.y0 + Island.depth + i.overhang, std.worktopTop.toDouble());
  }

  List<Issue> _islandChecks() {
    final out = <Issue>[];
    final foot = islandFootprint();
    if (foot == null) return out;
    // passages tout autour : jusqu'aux meubles posés au sol, ou jusqu'au mur
    final others = project.items.where((c) => c.wallId != 'I' && modelOf(c).floorSupport).expand(boxesOf).map((b) => b.box).toList();
    double free(String side) {
      switch (side) {
        case 'A':
          var d = foot.y0;
          for (final b in others) {
            if (b.x0 < foot.x1 && foot.x0 < b.x1 && b.y1 <= foot.y0 + 0.5) d = math.min(d, foot.y0 - b.y1);
          }
          return d;
        case 'D':
          var d = room.depth - foot.y1;
          for (final b in others) {
            if (b.x0 < foot.x1 && foot.x0 < b.x1 && b.y0 >= foot.y1 - 0.5) d = math.min(d, b.y0 - foot.y1);
          }
          return d;
        case 'C':
          var d = foot.x0;
          for (final b in others) {
            if (b.y0 < foot.y1 && foot.y0 < b.y1 && b.x1 <= foot.x0 + 0.5) d = math.min(d, foot.x0 - b.x1);
          }
          return d;
        default:
          var d = room.width - foot.x1;
          for (final b in others) {
            if (b.y0 < foot.y1 && foot.y0 < b.y1 && b.x0 >= foot.x1 - 0.5) d = math.min(d, b.x0 - foot.x1);
          }
          return d;
      }
    }

    for (final o in project.openings.where((o) => o.isDoor)) {
      if (room.wall(o.wallId).strip(o.s - 100, o.width + 200, 1000, 0, 2100).intersects(Box3(foot.x0, foot.y0, 0, foot.x1, foot.y1, 900))) {
        out.add(Issue(Severity.error, 'island_aisle', L('Îlot devant la porte du {0} : l’entrée doit rester libre', [Room.wallNames[o.wallId]?.toLowerCase()]), [o.uid]));
      }
    }
    const names = {'A': 'côté mur du fond', 'B': 'côté mur droit', 'C': 'côté mur gauche', 'D': 'côté mur avant'};
    for (final side in ['A', 'B', 'D', 'C']) {
      final d = free(side);
      if (d < aisleMin) {
        out.add(Issue(Severity.error, 'island_aisle', L('Îlot : passage de {0} mm {1} ({2} mm minimum)', [d.round(), names[side], aisleMin])));
      } else if (d < aisleAdvised && side != 'D') {
        out.add(Issue(Severity.info, 'island_aisle_tight',
            L('Îlot : passage de {0} mm {1} ({2} mm conseillés)', [d.round(), names[side], aisleAdvised])));
      }
    }
    return out;
  }

  /// Déplace le mur [wallId] de [delta] mm vers l'extérieur (négatif = vers l'intérieur).
  /// Les éléments posés contre ce mur le suivent ; ceux des autres murs gardent leur place réelle.
  /// Refuse (exception) si un élément ou une ouverture se retrouverait hors de la pièce ou en conflit.
  /// Décalage de l'origine du plan dû au dernier déplacement de mur (x, y en mm) : la vue le compense.
  (double, double) lastWallShift = (0, 0);

  void moveWall(String wallId, double delta) {
    lastWallShift = (0, 0);
    if (delta == 0) return;
    if (room.outline != null) return _moveOutlineWall(wallId, delta);
    final r = room;
    if (wallId == 'A') lastWallShift = (0, delta);
    if (wallId == 'C') lastWallShift = (delta, 0);
    final horizontal = wallId == 'A' || wallId == 'D'; // le mur se déplace en Y
    final newSize = (horizontal ? r.depth : r.width) + delta;
    if (newSize < roomMin) throw PlacementException(L('pièce trop petite ({0} mm minimum)', [roomMin.round()]));

    // mur dont l'origine (s = 0) est du côté qui bouge : ses éléments doivent glisser de delta
    final shifted = switch (wallId) { 'A' => 'B', 'B' => 'D', 'D' => 'C', _ => 'A' };
    final backupItems = [for (final c in project.items) c.copy()];
    final backupOpenings = [for (final o in project.openings) Opening.fromJson(o.toJson())];
    final (bw, bd) = (r.width, r.depth);

    if (horizontal) {
      r.depth = newSize;
    } else {
      r.width = newSize;
    }
    for (final c in project.items) {
      if (c.wallId == shifted) c.s += delta;
    }
    for (final o in project.openings) {
      if (o.wallId == shifted) o.s += delta;
    }
    final pointsBackup = [for (final x in project.points) (x, x.s, x.z)];
    for (final x in project.points) {
      if (x.wallId == shifted) x.s += delta;
      if (x.wallId == 'P' && wallId == 'C') x.s += delta;
      if (x.wallId == 'P' && wallId == 'A') x.z += delta;
    }
    final isl = r.island;
    final islBackup = isl == null ? null : (isl.x0, isl.y0);
    if (isl != null && wallId == 'A') isl.y0 += delta;
    if (isl != null && wallId == 'C') isl.x0 += delta;

    String? problem;
    if (isl != null && (isl.x0 < 0 || isl.y0 < 0 || isl.x0 + isl.length > r.width || isl.y0 + Island.depth + isl.overhang > r.depth)) {
      problem = 'l\'îlot sortirait de la pièce';
    }
    for (final c in project.items) {
      if (problem != null) break;
      final w = room.wall(c.wallId);
      if (c.s < -0.5 || c.right > w.length + 0.5) {
        problem = '« ${modelOf(c).name} » sortirait du mur ${c.wallId}';
        break;
      }
    }
    for (final o in project.openings) {
      if (problem != null) break;
      if (o.s < -0.5 || o.right > room.wall(o.wallId).length + 0.5) {
        problem = '${o.isDoor ? 'la porte' : 'la fenêtre'} du mur ${o.wallId} sortirait du mur';
      }
    }
    if (problem == null) {
      final boxes = project.items.expand(boxesOf).toList();
      outer:
      for (var i = 0; i < boxes.length; i++) {
        for (var j = i + 1; j < boxes.length; j++) {
          if (boxes[i].uid != boxes[j].uid && boxes[i].box.intersects(boxes[j].box)) {
            problem = 'des éléments se chevaucheraient dans l\'angle';
            break outer;
          }
        }
      }
    }
    if (problem != null) {
      r.width = bw;
      r.depth = bd;
      if (isl != null && islBackup != null) {
        isl.x0 = islBackup.$1;
        isl.y0 = islBackup.$2;
      }
      project.items
        ..clear()
        ..addAll(backupItems);
      project.openings
        ..clear()
        ..addAll(backupOpenings);
      for (final (x, s0, z0) in pointsBackup) {
        x
          ..s = s0
          ..z = z0;
      }
      throw PlacementException(L('impossible de déplacer le mur : {0}', [problem]));
    }
  }

  /// Pièce à contour libre : un mur droit glisse vers l'extérieur de [delta] mm (vers l'intérieur si négatif) ;
  /// ses deux voisins s'allongent ou se raccourcissent. Les meubles, ouvertures et points restent à leur place dans la pièce.
  void _moveOutlineWall(String wallId, double delta) {
    final r = room, ol = r.outline!;
    final i = r.order.indexOf(wallId);
    if (i < 0) throw PlacementException(L('mur inconnu : {0}', [wallId]));
    final w = r.wall(wallId);
    final prev = r.wall(r.prevOf(wallId)), next = r.wall(r.nextOf(wallId));
    if (!w.orthogonal || !prev.straight || !next.straight) throw PlacementException(L('seuls les murs droits se déplacent à la main'));
    final a = ol[i], b = ol[(i + 1) % ol.length];
    final tx = -w.nx * delta, ty = -w.ny * delta;
    // sauvegarde
    final backupPts = [for (final p in ol) (p.x, p.y)];
    final backupItems = [for (final c in project.items) c.copy()];
    final backupOpenings = [for (final o in project.openings) Opening.fromJson(o.toJson())];
    final backupPoints = [for (final x in project.points) (x, x.s, x.z)];
    final backupObjects = [for (final o in project.objects) (o, o.x, o.y)];
    final isl = r.island;
    final islBackup = isl == null ? null : (isl.x0, isl.y0);
    final (bw, bd) = (r.width, r.depth);
    // le mur suivant commence au sommet déplacé : ses éléments gardent leur place dans la pièce
    final shiftNext = -(tx * next.dx + ty * next.dy);
    a
      ..x += tx
      ..y += ty;
    b
      ..x += tx
      ..y += ty;
    for (final c in project.items) {
      if (c.wallId == next.id) c.s += shiftNext;
    }
    for (final o in project.openings) {
      if (o.wallId == next.id) o.s += shiftNext;
    }
    for (final x in project.points) {
      if (x.wallId == next.id) x.s += shiftNext;
    }
    // origine au coin haut-gauche de l'encombrement
    final pts = [for (final ww in r.walls) ...ww.points(16)];
    final minX = pts.map((p) => p.$1).reduce(math.min), minY = pts.map((p) => p.$2).reduce(math.min);
    for (final p in ol) {
      p
        ..x -= minX
        ..y -= minY;
    }
    for (final o in project.objects) {
      o
        ..x -= minX
        ..y -= minY;
    }
    if (isl != null) {
      isl
        ..x0 -= minX
        ..y0 -= minY;
    }
    final pts2 = [for (final ww in r.walls) ...ww.points(16)];
    r.width = pts2.map((p) => p.$1).reduce(math.max);
    r.depth = pts2.map((p) => p.$2).reduce(math.max);
    lastWallShift = (-minX, -minY);

    String? problem;
    for (final ww in r.walls) {
      if (ww.length < 300) problem = 'le mur ${ww.id} deviendrait trop court';
    }
    if (r.width < roomMin || r.depth < roomMin) problem ??= 'pièce trop petite (${roomMin.round()} mm minimum)';
    for (final c in project.items) {
      if (problem != null) break;
      if (c.wallId == 'I') continue;
      final ww = r.wall(c.wallId);
      if (c.s < -0.5 || c.right > ww.length + 0.5) problem = '« ${modelOf(c).name} » sortirait du mur ${c.wallId}';
    }
    for (final o in project.openings) {
      if (problem != null) break;
      if (o.s < -0.5 || o.right > r.wall(o.wallId).length + 0.5) problem = '${o.isDoor ? 'la porte' : 'la fenêtre'} du mur ${o.wallId} sortirait du mur';
    }
    if (problem == null) {
      final boxes = project.items.expand(boxesOf).toList();
      outer:
      for (var p = 0; p < boxes.length; p++) {
        for (var q = p + 1; q < boxes.length; q++) {
          if (boxes[p].uid != boxes[q].uid && boxes[p].box.intersects(boxes[q].box)) {
            problem = 'des éléments se chevaucheraient dans l\'angle';
            break outer;
          }
        }
      }
    }
    if (problem != null) {
      for (var k = 0; k < ol.length; k++) {
        ol[k]
          ..x = backupPts[k].$1
          ..y = backupPts[k].$2;
      }
      r.width = bw;
      r.depth = bd;
      if (isl != null && islBackup != null) {
        isl
          ..x0 = islBackup.$1
          ..y0 = islBackup.$2;
      }
      project.items
        ..clear()
        ..addAll(backupItems);
      project.openings
        ..clear()
        ..addAll(backupOpenings);
      for (final (x, s0, z0) in backupPoints) {
        x
          ..s = s0
          ..z = z0;
      }
      for (final (o, x, y) in backupObjects) {
        o
          ..x = x
          ..y = y;
      }
      lastWallShift = (0, 0);
      throw PlacementException(L('impossible de déplacer le mur : {0}', [problem]));
    }
  }

  /// Choisit une forme de cuisine (murs utilisés).
  void applyShape(RoomShape shape) {
    for (final id in room.order) {
      room.setWallEnabled(id, shape.walls.contains(id));
    }
  }

  // ------------------------------------------------------------------------
  // Linéaires (plan de travail, plinthes) et remplissage automatique
  // ------------------------------------------------------------------------

  /// Tronçons continus le long d'un mur, pour les caissons dont le type vérifie [test].
  List<(double, double)> runs(String wallId, bool Function(CabinetModel m) test) {
    final w = room.wall(wallId);
    final iv = <(double, double)>[];
    for (final c in project.items) {
      final m = modelOf(c);
      if (!test(m)) continue;
      for (final tb in boxesOf(c)) {
        if (tb.wallId != wallId) continue;
        final (s0, s1, _, _) = w.boxToWall(tb.box);
        iv.add((math.max(0, s0), math.min(w.length, s1)));
      }
      // le plan de travail, les plinthes… passent sur les joues ajoutées
      for (final left in [true, false]) {
        if (!c.hasCheek(left)) continue;
        final tb = cheekBox(c, left);
        if (tb.wallId != wallId) continue;
        final (s0, s1, _, _) = w.boxToWall(tb.box);
        iv.add((math.max(0, s0), math.min(w.length, s1)));
      }
    }
    iv.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(double, double)>[];
    for (final x in iv) {
      if (merged.isNotEmpty && x.$1 <= merged.last.$2 + 0.5) {
        merged[merged.length - 1] = (merged.last.$1, math.max(merged.last.$2, x.$2));
      } else {
        merged.add(x);
      }
    }
    return merged;
  }

  /// Espaces libres d'un mur dans une bande (tout ce qui est posé et les ouvertures comptent).
  List<(double, double)> freeIntervals(String wallId, Band band) {
    final w = room.wall(wallId);
    final (z0, z1, depth) = band == Band.low
        ? (std.plinthHeight.toDouble(), std.baseTop.toDouble(), 600.0)
        : (std.wallBottomDefault.toDouble(), std.wallBottomDefault + 800.0, 370.0);
    final occ = <(double, double)>[];
    for (final tbs in [...project.items.map(solidOf), openingBoxes()]) {
      for (final tb in tbs) {
        final b = tb.box;
        if (!(b.z0 < z1 - 0.5 && z0 < b.z1 - 0.5)) continue;
        final (s0, s1, t0, t1) = w.boxToWall(b);
        if (t0 >= depth - 0.5 || t1 <= 0.5 || s1 <= 0 || s0 >= w.length) continue;
        occ.add((math.max(0, s0), math.min(w.length, s1)));
      }
    }
    occ.sort((a, b) => a.$1.compareTo(b.$1));
    final free = <(double, double)>[];
    var cur = 0.0;
    for (final (a, b) in occ) {
      if (a > cur + 0.5) free.add((cur, a));
      cur = math.max(cur, b);
    }
    if (cur < w.length - 0.5) free.add((cur, w.length));
    return free;
  }

  /// Combinaison de largeurs (somme maximale ≤ [space], puis le moins de caissons).
  static List<int> bestModules(double space, List<int> widths) {
    final n = space.floor();
    final best = List<int?>.filled(n + 1, null)..[0] = 0;
    final from = List<int>.filled(n + 1, 0);
    final ws = [...widths]..sort((a, b) => b.compareTo(a));
    for (var x = 1; x <= n; x++) {
      for (final w in ws) {
        if (w <= x && best[x - w] != null && (best[x] == null || best[x - w]! + 1 < best[x]!)) {
          best[x] = best[x - w]! + 1;
          from[x] = w;
        }
      }
    }
    var x = n;
    while (x > 0 && best[x] == null) {
      x--;
    }
    final res = <int>[];
    while (x > 0) {
      res.add(from[x]);
      x -= from[x];
    }
    res.sort((a, b) => b.compareTo(a));
    return res;
  }

  /// Pose ce qui manque du trio de travail et l'électroménager associé, en cherchant la meilleure
  /// place sur tous les murs équipés (le mur [wallId] est préféré à score égal) :
  /// colonne frigo en bout de mur loin de la porte, évier sous une fenêtre avec le lave-vaisselle
  /// collé, plaque + four là où le triangle d'activité est le mieux respecté, tiroirs à côté.
  /// Renvoie le nombre d'éléments posés.
  int placeWorkTrio(String wallId) {
    var count = 0;
    final walls = [wallId, ...room.order.where((id) => id != wallId && room.isWallEnabled(id))];

    bool tryAdd(String id, String wall, double s, {int? width}) {
      final before = project.items.length;
      try {
        final c = add(id, wall, s: s, width: width);
        if ((c.s - s).abs() > std.snapTolerance + 1) {
          remove(c.uid); // déplacé par le moteur : pas la place voulue
          return false;
        }
      } on PlacementException {
        return false;
      }
      count += project.items.length - before;
      return true;
    }

    bool freeAt(String wall, double s, double width) {
      for (final (a, b) in freeIntervals(wall, Band.low)) {
        if (s >= a - 0.5 && s + width <= b + 0.5) return true;
      }
      return false;
    }

    var (wash, cook, cool) = workZones();

    // 1. froid : colonne en bout de mur, loin de la porte
    if (cool == null) {
      final cands = <(String, double, double)>[];
      for (final id in walls) {
        final w = room.wall(id);
        for (final s in [0.0, w.length - 600]) {
          if (!freeAt(id, s, 600)) continue;
          var score = id == wallId ? 0.0 : 50.0;
          for (final o in project.openings.where((o) => o.isDoor)) {
            final (ox, oy) = room.wall(o.wallId).toPlan(o.s + o.width / 2, 0);
            final (fx, fy) = w.toPlan(s + 300, 0);
            score -= math.sqrt(math.pow(ox - fx, 2) + math.pow(oy - fy, 2)) * 0.5; // plus loin = mieux
          }
          // pas devant une fenêtre
          if (project.openings.any((o) => !o.isDoor && o.wallId == id && o.s < s + 600 && s < o.right)) score += 1e6;
          // l'évier ira sous une fenêtre : viser ~1500 mm entre le frigo et cette fenêtre (triangle)
          for (final o in project.openings.where((o) => !o.isDoor)) {
            final (ox, oy) = room.wall(o.wallId).toPlan(o.s + o.width / 2, 600);
            final (fx, fy) = w.toPlan(s + 300, 600);
            final dist = math.sqrt(math.pow(ox - fx, 2) + math.pow(oy - fy, 2));
            score += (dist - 1500).abs() * 0.8;
          }
          cands.add((id, s, score));
        }
      }
      cands.sort((a, b) => a.$3.compareTo(b.$3));
      for (final (id, s, _) in cands) {
        if (tryAdd('tall_integrated_fridge', id, s, width: 600)) break;
      }
      (wash, cook, cool) = workZones();
    }

    // 2. lavage : évier sous une fenêtre si possible, sinon vers le milieu d'un mur ; lave-vaisselle collé
    if (wash == null) {
      final cands = <(String, double, int)>[];
      for (final id in walls) {
        final w = room.wall(id);
        final sinkW = w.length >= 3000 ? 800 : 600;
        for (final win in project.openings.where((o) => !o.isDoor && o.wallId == id)) {
          cands.add((id, (win.s + win.width / 2 - sinkW / 2).clamp(0.0, w.length - sinkW), sinkW));
        }
      }
      for (final id in walls) {
        final w = room.wall(id);
        final sinkW = w.length >= 3000 ? 800 : 600;
        for (final f in [0.45, 0.3, 0.6, 0.2, 0.75]) {
          cands.add((id, (w.length * f - sinkW / 2).clamp(0.0, w.length - sinkW), sinkW));
        }
      }
      for (final (id, s, sw) in cands) {
        if (freeAt(id, s, sw.toDouble()) && tryAdd('base_sink', id, s, width: sw)) break;
      }
      (wash, cook, cool) = workZones();
      if (wash != null) {
        if (freeAt(wash.wallId, wash.right, 600)) {
          tryAdd('base_integrated_dishwasher_door', wash.wallId, wash.right, width: 600);
        } else if (freeAt(wash.wallId, wash.s - 600, 600)) {
          tryAdd('base_integrated_dishwasher_door', wash.wallId, wash.s - 600, width: 600);
        }
      }
    }

    // 3. cuisson : meilleure place sur tous les murs
    if (cook == null) {
      String? bestWall;
      double? bestS;
      var bestScore = double.infinity;
      for (final id in walls) {
        final w = room.wall(id);
        for (var s = 0.0; s <= w.length - 600; s += 50) {
          if (!freeAt(id, s, 600)) continue;
          if (project.openings.any((o) => !o.isDoor && o.wallId == id && o.s < s + 600 && s < o.right)) continue;
          final cx = w.toPlan(s + 300, 600.0);
          var score = id == wallId ? 0.0 : 10.0;
          final tallNear = project.items.any((c) =>
              c.wallId == id && modelOf(c).kind == CabinetKind.tall && math.max(c.s - (s + 600), s - c.right) < hobSideClearance);
          if (tallNear) score += 5000;
          // 300 mm d'un mur latéral (un angle compte comme un mur)
          if (math.min(s, w.length - s - 600) < hobSideClearance + 600 && math.min(s, w.length - s - 600) < hobSideClearance) {
            score += 1500;
          }
          // éviter de laisser un vide impossible à combler (ni fileur 50-200, ni caisson >= 300 + fileur)
          final cornerL = room.isWallEnabled(room.prevOf(id)) ? 600.0 : 0.0;
          final cornerR = room.isWallEnabled(room.nextOf(id)) ? w.length - 600 : w.length;
          if (s < cornerL - 0.5 || s + 600 > cornerR + 0.5) continue; // l'angle sera pris par le mur voisin
          for (final (fa0, fb0) in freeIntervals(id, Band.low)) {
            if (s < fa0 - 0.5 || s + 600 > fb0 + 0.5) continue;
            final fa = math.max(fa0, cornerL), fb = math.min(fb0, cornerR);
            for (final g in [s - fa, fb - (s + 600)]) {
              if ((g > 0.5 && g < cornerFillerMin) || (g > std.fillerMax && g < 350)) score += 800;
            }
          }
          final leftCorner = room.isWallEnabled(room.prevOf(id)) && s < 600 + hobSideClearance;
          final rightCorner = room.isWallEnabled(room.nextOf(id)) && s + 600 > w.length - 600 - hobSideClearance;
          if (leftCorner || rightCorner) score += 1500;
          double leg(PlacedCabinet? o) {
            if (o == null) return 1800;
            final (ox, oy) = workPoint(o);
            return math.sqrt(math.pow(cx.$1 - ox, 2) + math.pow(cx.$2 - oy, 2));
          }

          for (final l in [leg(wash), leg(cool)]) {
            if (l < triangleLegMin) score += (triangleLegMin - l) * 3;
            if (l > triangleLegMax) score += (l - triangleLegMax) * 3;
            score += (l - 1800).abs() * 0.1;
          }
          if (score < bestScore) {
            bestScore = score;
            bestWall = id;
            bestS = s;
          }
        }
      }
      if (bestWall != null && tryAdd('base_cooktop_oven', bestWall, bestS!, width: 600)) {
        final hob = workZones().$2!;
        if (freeAt(hob.wallId, hob.right, 600)) {
          tryAdd('base_drawers_multi', hob.wallId, hob.right, width: 600);
        } else if (freeAt(hob.wallId, hob.s - 600, 600)) {
          tryAdd('base_drawers_multi', hob.wallId, hob.s - 600, width: 600);
        }
      }
    }
    return count;
  }

  /// Hotte au-dessus de chaque plaque du mur qui n'en a pas (650 mm au-dessus du plan de travail).
  /// Meubles d'angle (en L) aux angles du mur [wallId] dont le mur voisin est utilisé :
  /// bas en L 900 x 900 (tourniquet, porte pliante), haut en L 680 x 680.
  int placeCorners(String wallId, Band band) {
    if (wallId == 'I') return 0;
    var count = 0;
    final id = band == Band.low ? 'corner_base_l_shaped' : 'corner_wall_l_shaped';
    final m = catalog.tryGet(id);
    if (m == null) return 0;
    // angle de fin du mur (vers le mur suivant) et angle de début (fin du mur précédent)
    for (final w in [wallId, room.prevOf(wallId)]) {
      final next = room.nextOf(w);
      if (!room.isWallEnabled(w) || !room.isWallEnabled(next)) continue;
      final len = room.wall(w).length;
      final already = project.items.any((c) {
        final cm = modelOf(c);
        if (cm.kind.isLow != (band == Band.low) || cm.kind.isFiller) return false;
        return (c.wallId == w && c.right > len - m.defaultWidth - 0.5) || (c.wallId == next && c.s < (m.widthRight ?? 600) + 0.5);
      });
      if (already) continue;
      try {
        final c = add(id, w, s: len - m.defaultWidth, height: band == Band.high ? 800 : null);
        if ((c.s - (len - m.defaultWidth)).abs() > 1) {
          remove(c.uid);
        } else {
          count++;
        }
      } on PlacementException {
        // fenêtre, porte ou colonne dans l'angle : on garde les linéaires simples
      }
    }
    return count;
  }

  int placeHoods(String wallId) => _placeHoods(wallId);

  int _placeHoods(String wallId) {
    var count = 0;
    for (final hob in [...project.items.where((c) => c.wallId == wallId && cooks(c))]) {
      final has = project.items.any((c) => _isHood(modelOf(c)) && c.wallId == wallId && _overlapS(c, hob));
      if (has) continue;
      try {
        final h = add('wall_integrated_hood', wallId,
            s: hob.s, width: math.min(hob.width, 600));
        if (!_overlapS(h, hob) || (h.s - hob.s).abs() > std.snapTolerance + 1) {
          remove(h.uid);
        } else {
          count++;
        }
      } on PlacementException {
        // pas de place (fenêtre, colonne) : le contrôle le signalera
      }
    }
    return count;
  }

  /// Remplit les espaces libres d'un mur avec des caissons standards (et un fileur pour le reste).
  /// Renvoie le nombre d'éléments posés.
  int autoFillWall(String wallId, Band band) {
    if (!room.wall(wallId).enabled) throw PlacementException(L('{0} désactivé', [Room.wallNames[wallId]]));
    final modelId = band == Band.low ? 'base_standard_single_door' : 'wall_standard_single_door';
    final fillerId = band == Band.low ? 'filler_panel_base' : 'filler_panel_wall';
    final m = catalog[modelId];
    // d'abord le trio (froid, lavage, cuisson) et l'électroménager, puis le reste
    var count = placeCorners(wallId, band);
    count += band == Band.low ? placeWorkTrio(wallId) : 0;
    count += _placeHoods(wallId);
    for (var (a, b) in freeIntervals(wallId, band)) {
      // angle occupé par le mur voisin : fileur de 50 mm pour les poignées et tiroirs
      if (band == Band.low) {
        final wl = room.wall(wallId).length;
        bool neighbourAt(String other, bool atEnd) => project.items.any((o) =>
            o.wallId == other &&
            modelOf(o).kind.isLow &&
            !modelOf(o).kind.isFiller &&
            (atEnd ? o.right > room.wall(other).length - 600.5 : o.s < 600.5));
        if ((a - 600).abs() < 1 && room.isWallEnabled(room.prevOf(wallId)) && neighbourAt(room.prevOf(wallId), true) && b - a >= 350) {
          add(fillerId, wallId, s: a, width: cornerFillerMin);
          count++;
          a += cornerFillerMin;
        }
        if ((b - (wl - 600)).abs() < 1 && room.isWallEnabled(room.nextOf(wallId)) && neighbourAt(room.nextOf(wallId), false) && b - a >= 350) {
          add(fillerId, wallId, s: b - cornerFillerMin, width: cornerFillerMin);
          count++;
          b -= cornerFillerMin;
        }
      }
      final space = b - a;
      if (space < std.fillerMax && space >= 50) {
        // trop petit pour un caisson : fileur entre deux éléments, ou contre le mur à côté d'un élément
        final wl = room.wall(wallId).length;
        final touchesItem = project.items.any((o) =>
            o.wallId == wallId && ((o.right - a).abs() < 0.5 || (o.s - b).abs() < 0.5) && (modelOf(o).kind.isHigh == (band == Band.high)));
        if ((a > 0.5 && b < wl - 0.5) || touchesItem) {
          add(fillerId, wallId, s: a, width: space.floor());
          count++;
        }
        continue;
      }
      // trop grand pour un fileur, trop petit pour un caisson : deux fileurs
      if (space > std.fillerMax && space < m.widths.values.reduce(math.min)) {
        final half = (space / 2).floor();
        add(fillerId, wallId, s: a, width: half);
        add(fillerId, wallId, s: a + half, width: (space - half).floor());
        count += 2;
        continue;
      }
      // modules choisis pour que le reste soit nul ou comblable par un fileur (50 à 200 mm)
      var mods = bestModules(space, m.widths.values);
      var valid = false;
      for (var extra = 0; extra <= std.fillerMax && extra <= space; extra += 10) {
        final cand = bestModules(space - extra, m.widths.values);
        final rest = space - cand.fold<int>(0, (x, y) => x + y);
        if (rest < 0.5 || (rest >= cornerFillerMin && rest <= std.fillerMax)) {
          mods = cand;
          valid = true;
          break;
        }
      }
      if (!valid && space <= 2 * std.fillerMax) {
        // aucune combinaison juste : deux fileurs plutôt qu'un vide
        final half = (space / 2).floor();
        add(fillerId, wallId, s: a, width: half);
        add(fillerId, wallId, s: a + half, width: (space - half).floor());
        count += 2;
        continue;
      }
      var pos = a;
      for (final wd in mods) {
        add(_styledModel(band, wd, modelId), wallId, s: pos, width: wd);
        pos += wd;
        count++;
      }
      final rest = b - pos;
      if (rest >= 50 && rest <= std.fillerMax) {
        add(fillerId, wallId, s: pos, width: rest.floor());
        count++;
      }
    }
    return count;
  }

  /// Comble un vide par un fileur de la bonne largeur.
  PlacedCabinet fillGap(Gap g) {
    final id = g.band == Band.low ? 'filler_panel_base' : 'filler_panel_wall';
    final m = catalog[id];
    final w = g.width.round();
    if (!m.widths.allows(w)) throw PlacementException(L('vide de {0} mm hors de la plage du fileur ({1})', [w, m.widths]));
    return add(id, g.wallId, s: g.s0, width: w);
  }

  PlacedCabinet _get(String uid) =>
      project.byUid(uid) ?? (throw PlacementException(L('caisson inconnu : {0}', [uid])));

  void _restore(PlacedCabinet c, PlacedCabinet b) {
    c
      ..wallId = b.wallId
      ..s = b.s
      ..z = b.z
      ..width = b.width
      ..height = b.height;
  }

  // ------------------------------------------------------------------------
  // Aimantation et collisions
  // ------------------------------------------------------------------------

  /// Intervalles [s0, s1] du mur déjà occupés dans la bande de [c] (même profondeur et hauteur).
  List<(double, double)> occupied(PlacedCabinet c) {
    final w = room.wall(c.wallId);
    final res = <(double, double)>[];
    final boxes = [
      for (final o in project.items)
        if (o.uid != c.uid) ...solidOf(o),
      ...openingBoxes(),
    ];
    {
      for (final tb in boxes) {
        final b = tb.box;
        if (!(b.z0 < c.top - 0.5 && c.z < b.z1 - 0.5)) continue;
        final (s0, s1, t0, t1) = w.boxToWall(b);
        if (t0 >= c.depth - 0.5 || t1 <= 0.5) continue;
        if (s1 <= 0 || s0 >= w.length) continue;
        res.add((s0, s1));
      }
    }
    res.sort((a, b) => a.$1.compareTo(b.$1));
    return res;
  }

  bool _collides(PlacedCabinet c, double s, List<(double, double)> occ) {
    for (final (a, b) in occ) {
      if (s < b - 0.5 && a < s + c.width - 0.5) return true;
    }
    return false;
  }

  /// Position finale (s, aimantée ?) la plus proche de [desired], ou null si aucune place.
  (double, bool)? _resolve(PlacedCabinet c, double desired) {
    final m = modelOf(c);
    final w = room.wall(c.wallId);
    final len = w.length;
    final width = c.width.toDouble();
    // joues ajoutées : leur place compte avec celle du caisson
    final padL = c.hasCheek(true) ? cheekT : 0.0, padR = c.hasCheek(false) && !m.kind.isCorner ? cheekT : 0.0;
    if (width + padL + padR > len + 0.5) return null;
    final occ = [
      if (padL > 0) (-1.0, padL),
      for (final (a, b) in occupied(c)) (a - padR, b + padL),
      if (padR > 0) (len - padR, len + 1),
    ];

    // angles en L / pan coupé : toujours collés au coin (extrémité droite du mur)
    if (m.shape == CabinetShape.lShape || m.shape == CabinetShape.diagonal) {
      final s = len - width;
      final saved = c.s;
      c.s = s;
      final others = [...project.items.where((o) => o.uid != c.uid).expand(boxesOf), ...openingBoxes()];
      final hit = boxesOf(c).any((mine) => others.any((o) => mine.box.intersects(o.box)));
      c.s = saved;
      return hit ? null : (s, true);
    }

    // angle avec fileur : calé à l'une des extrémités du mur
    if (m.shape == CabinetShape.blind) {
      final ends = [0.0, len - width]..sort((a, b) => (a - desired).abs().compareTo((b - desired).abs()));
      for (final s in ends) {
        if (!_collides(c, s, occ)) return (s, true);
      }
      return null;
    }

    var s = desired.clamp(0.0, len - width);
    var snapped = false;

    // aimantation : bord gauche ou droit sur un bord voisin / extrémité du mur
    final edges = <double>{0, len, for (final (a, b) in occ) ...[a, b]};
    var best = std.snapTolerance + 1.0;
    double? snapS;
    for (final e in edges) {
      for (final cand in [e, e - width]) {
        final dlt = (cand - s).abs();
        if (dlt <= std.snapTolerance && dlt < best && cand >= -0.5 && cand + width <= len + 0.5) {
          best = dlt;
          snapS = cand;
        }
      }
    }
    if (snapS != null) {
      s = snapS;
      snapped = true;
    }
    if (!_collides(c, s, occ)) return (s, snapped);

    // collision : place libre la plus proche (collée à un voisin)
    final cands = <double>[0, len - width, for (final (a, b) in occ) ...[b, a - width]]
        .where((x) => x >= -0.5 && x + width <= len + 0.5 && !_collides(c, x, occ))
        .toList()
      ..sort((a, b) => (a - desired).abs().compareTo((b - desired).abs()));
    return cands.isEmpty ? null : (cands.first, true);
  }

  /// Aimantation verticale des caissons hauts : aligne le dessus sur les colonnes ou le bas /
  /// dessus sur les autres hauts, et respecte le plafond.
  double _snapZ(PlacedCabinet c, double z) {
    final targets = <double>[std.wallBottomDefault.toDouble(), std.wallBottomMin.toDouble()];
    for (final o in project.items) {
      if (o.uid == c.uid) continue;
      final k = modelOf(o).kind;
      if (k == CabinetKind.tall) targets.add(o.top - c.height);
      if (k.isHigh) targets.addAll([o.z, o.top - c.height]);
    }
    targets.add(room.height - c.height);
    double? best;
    for (final t in targets) {
      if ((t - z).abs() <= std.snapTolerance && (best == null || (t - z).abs() < (best - z).abs())) best = t;
    }
    return (best ?? z).clamp(0.0, math.max(0.0, room.height - c.height));
  }

  // ------------------------------------------------------------------------
  // Contrôles
  // ------------------------------------------------------------------------

  /// Vides entre les éléments, par mur et par bande (bas / haut).
  List<Gap> gaps() {
    final res = <Gap>[];
    for (final w in room.walls.where((w) => w.enabled)) {
      for (final band in Band.values) {
        final (z0, z1) = band == Band.low
            ? (std.plinthHeight.toDouble(), std.baseTop.toDouble())
            : (std.wallBottomMin.toDouble(), room.height);
        final depth = band == Band.low ? 600.0 : 370.0;
        final iv = <(double, double)>[];
        for (final tbs in [...project.items.map(solidOf), openingBoxes()]) {
          for (final tb in tbs) {
            final b = tb.box;
            if (!(b.z0 < z1 && z0 < b.z1)) continue;
            final (s0, s1, t0, t1) = w.boxToWall(b);
            if (t0 >= depth || t1 <= 0 || t0 > _touch) continue;
            iv.add((math.max(0, s0), math.min(w.length, s1)));
          }
        }
        if (iv.isEmpty) continue;
        iv.sort((a, b) => a.$1.compareTo(b.$1));
        // fusion
        final merged = <(double, double)>[];
        for (final x in iv) {
          if (merged.isNotEmpty && x.$1 <= merged.last.$2 + 0.5) {
            merged[merged.length - 1] = (merged.last.$1, math.max(merged.last.$2, x.$2));
          } else {
            merged.add(x);
          }
        }
        // vide en début de mur, entre éléments, en fin de mur
        final bounds = <(double, double, bool)>[];
        if (merged.first.$1 > 0.5) bounds.add((0, merged.first.$1, false));
        for (var i = 0; i + 1 < merged.length; i++) {
          bounds.add((merged[i].$2, merged[i + 1].$1, true));
        }
        if (merged.last.$2 < w.length - 0.5) bounds.add((merged.last.$2, w.length, false));
        for (final (a, b, between) in bounds) {
          final fillable = b - a <= std.fillerMax;
          // un grand vide en bout de mur n'est pas un défaut : on ne le signale pas
          if (!between && !fillable) continue;
          res.add(Gap(w.id, band, a, b, fillable));
        }
      }
    }
    return res;
  }

  List<Issue> validate() {
    final issues = <Issue>[];
    final items = project.items;

    for (final c in items) {
      final m = modelOf(c);
      final w = room.wall(c.wallId);
      if (!w.enabled) {
        issues.add(Issue(Severity.error, 'wall_disabled', L('{0} est sur un mur désactivé', [L(m.name)]), [c.uid]));
      }
      if (!m.widths.allows(c.width + c.cheekTaken)) {
        issues.add(Issue(Severity.error, 'width', L('{0} : largeur {1} hors catalogue ({2})', [L(m.name), c.width, m.widths]), [c.uid]));
      }
      if (!m.heights.allows(c.height)) {
        issues.add(Issue(Severity.error, 'height', L('{0} : hauteur {1} hors catalogue ({2})', [L(m.name), c.height, m.heights]), [c.uid]));
      }
      for (final tb in boxesOf(c)) {
        final b = tb.box;
        if (b.x0 < -0.5 || b.y0 < -0.5 || b.x1 > room.width + 0.5 || b.y1 > room.depth + 0.5) {
          issues.add(Issue(Severity.error, 'outside', L('{0} dépasse de la pièce', [L(m.name)]), [c.uid]));
          break;
        }
      }
      if (c.top > room.height + 0.5) {
        issues.add(Issue(Severity.error, 'ceiling', L('{0} dépasse le plafond ({1} > {2} mm)', [L(m.name), c.top.round(), room.height.round()]), [c.uid]));
      }
      // hauteur des éléments hauts au-dessus du plan : règle de cuisine (en salle de bain, l'armoire de toilette suit la vasque)
      if (kitchen && m.kind.isHigh && c.z < std.wallBottomMin - 0.5) {
        final above = (c.z - std.worktopTop).round();
        issues.add(Issue(Severity.warning, 'wall_too_low',
            L('{0} : {1} mm au-dessus du plan de travail (minimum {2})', [L(m.name), above, std.wallClearanceMin]), [c.uid]));
      }
      if (m.requiresAppliance != null) {
        const names = {'integrated_dishwasher': 'un lave-vaisselle tout intégrable'};
        issues.add(Issue(Severity.info, 'appliance',
            L('{0} : à monter sur {1}', [L(m.name), names[m.requiresAppliance] ?? "l'appareil prévu"]), [c.uid]));
      }
      if (m.ventilationGapRequired) {
        issues.add(Issue(Severity.info, 'ventilation', L('{0} : prévoir l\'espace de ventilation de l\'appareil', [L(m.name)]), [c.uid]));
      }
      if (m.shape == CabinetShape.blind) {
        final atEnd = c.s.abs() < 0.5 || (c.right - w.length).abs() < 0.5;
        if (!atEnd) issues.add(Issue(Severity.warning, 'blind_not_corner', L('{0} doit être calé dans un coin', [L(m.name)]), [c.uid]));
      }
    }

    // chevauchements
    for (final o in project.openings) {
      final ob = o.box(room);
      final kind = o.isDoor ? 'la porte' : 'la fenêtre';
      if (o.s < -0.5 || o.right > room.wall(o.wallId).length + 0.5) {
        issues.add(Issue(Severity.error, 'opening_outside', L('{0} hors du mur', [o.isDoor ? 'Porte' : 'Fenêtre']), [o.uid]));
      }
      for (final c in items) {
        if (boxesOf(c).any((tb) => tb.box.intersects(ob))) {
          issues.add(Issue(Severity.error, 'opening_blocked', L('{0} bloque {1}', [L(modelOf(c).name), kind]), [c.uid, o.uid]));
        }
      }
    }

    final boxes = items.expand(boxesOf).toList();
    final seen = <String>{};
    for (var i = 0; i < boxes.length; i++) {
      for (var j = i + 1; j < boxes.length; j++) {
        final a = boxes[i], b = boxes[j];
        if (a.uid == b.uid || !a.box.intersects(b.box)) continue;
        final key = ([a.uid, b.uid]..sort()).join('|');
        if (!seen.add(key)) continue;
        issues.add(Issue(Severity.error, 'overlap',
            L('{0} et {1} se chevauchent', [L(modelOf(project.byUid(a.uid)!).name), L(modelOf(project.byUid(b.uid)!).name)]), [a.uid, b.uid]));
      }
    }

    // vides entre éléments : à combler en cuisine ; ailleurs ils laissent la place au WC, à la douche, au canapé…
    for (final g in kitchen ? gaps() : const <Gap>[]) {
      issues.add(g.fillable
          ? Issue(Severity.warning, 'filler_gap',
              L('vide de {0} mm ({1}, {2}) : à combler par un fileur', [g.width.round(), Room.wallNames[g.wallId], g.band == Band.low ? 'bas' : 'haut']))
          : Issue(Severity.info, 'free_space',
              L('espace libre de {0} mm ({1}, {2})', [g.width.round(), Room.wallNames[g.wallId], g.band == Band.low ? 'bas' : 'haut'])));
    }
    if (kitchen) issues.addAll(_normChecks());
    return issues;
  }

  // ------------------------------------------------------------------------
  // Règles d'implantation (cuisson, passages, angles, eau)
  // ------------------------------------------------------------------------

  /// Distances minimales utilisées par les contrôles (mm).
  static const hoodAboveHobMin = 650;
  static const worktopThicknessMin = 28;
  static const hobSideClearance = 300;
  static const aisleMin = 1000;
  static const aisleAdvised = 1200;
  static const cornerFillerMin = 50;

  bool _isHob(CabinetModel m) => m.id == 'base_cooktop_oven';
  bool _isHood(CabinetModel m) => m.isHoodUnit || m.isFreeHood;

  /// Écart horizontal entre deux caissons du même mur (négatif = recouvrement).
  double _gapBetween(PlacedCabinet a, PlacedCabinet b) => math.max(b.s - a.right, a.s - b.right);

  bool _overlapS(PlacedCabinet a, PlacedCabinet b) => a.s < b.right - 0.5 && b.s < a.right - 0.5;

  // ------------------------------------------------------------------------
  // Zones de travail, triangle d'activité et forme de la cuisine
  // ------------------------------------------------------------------------

  /// Bornes du triangle d'activité (mm) : chaque côté et le périmètre.
  static const triangleLegMin = 1200, triangleLegMax = 2700, trianglePerimeterMin = 4000, trianglePerimeterMax = 7900;

  bool isWashing(CabinetModel m) => m.id.startsWith('base_sink') || m.id.contains('sink') || m.id.contains('evier') || m.zone == 'wash';
  bool isCooking(CabinetModel m) => m.id.startsWith('base_cooktop') || m.id.contains('cooktop') || m.id.contains('oven') || m.zone == 'cook';
  bool isCooling(CabinetModel m) => m.id.contains('fridge') || m.id.contains('refrigerateur') || m.zone == 'cool';

  /// Meuble posé : évier, cuisson ou froid d'après son modèle OU l'électroménager ajouté en option
  /// (un caisson simple avec une plaque, un four ou un évier compte comme zone de cuisson ou de lavage).
  bool washes(PlacedCabinet c) => isWashing(modelOf(c)) || (c.appliances?.any((a) => a.contains('sink')) ?? false);
  bool cooks(PlacedCabinet c) =>
      isCooking(modelOf(c)) || (c.appliances?.any((a) => a.contains('cooktop') || a.contains('hob') || a.contains('oven')) ?? false);
  bool cools(PlacedCabinet c) => isCooling(modelOf(c)) || (c.appliances?.any((a) => a.contains('fridge')) ?? false);
  /// Plaque de cuisson sur un meuble bas (modèle ou option).
  bool hasHob(PlacedCabinet c) =>
      modelOf(c).kind.isLow && (isCooking(modelOf(c)) && !modelOf(c).id.contains('oven_') || (c.appliances?.any((a) => a.contains('cooktop') || a.contains('hob')) ?? false) || modelOf(c).id.contains('cooktop'));

  /// Point de travail d'un élément : milieu de sa façade, au sol (vue de dessus).
  (double, double) workPoint(PlacedCabinet c) {
    final w = room.wall(c.wallId);
    return w.toPlan(c.s + c.width / 2, c.depth.toDouble());
  }

  /// Les trois zones trouvées (null si absente) : lavage, cuisson, froid.
  (PlacedCabinet?, PlacedCabinet?, PlacedCabinet?) workZones() {
    PlacedCabinet? find(bool Function(PlacedCabinet) f) {
      for (final c in project.items) {
        if (f(c)) return c;
      }
      return null;
    }

    return (find(washes), find(cooks), find(cools));
  }

  /// Côtés du triangle (mm) : évier-plaque, plaque-froid, froid-évier ; null s'il manque une zone.
  (double, double, double)? triangleLegs() {
    final (wash, cook, cool) = workZones();
    if (wash == null || cook == null || cool == null) return null;
    double d(PlacedCabinet a, PlacedCabinet b) {
      final (ax, ay) = workPoint(a);
      final (bx, by) = workPoint(b);
      return math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));
    }

    return (d(wash, cook), d(cook, cool), d(cool, wash));
  }

  List<Issue> _workTriangle() {
    final out = <Issue>[];
    final carcasses = project.items.where((c) => modelOf(c).isCarcass).length;
    if (carcasses < 3) return out; // cuisine pas encore commencée
    final (wash, cook, cool) = workZones();
    if (wash == null) out.add(Issue(Severity.error, 'zone_wash', L('Zone de lavage manquante : ajouter un bas sous-évier')));
    if (cook == null) out.add(Issue(Severity.error, 'zone_cook', L('Zone de cuisson manquante : ajouter un bas pour plaque et four')));
    if (cool == null) {
      out.add(Issue(Severity.error, 'zone_cool', L('Zone de froid manquante : ajouter une colonne réfrigérateur')));
    }
    final legs = triangleLegs();
    if (legs == null) return out;
    final (a, b, c) = legs;
    final names = ['évier - plaque', 'plaque - froid', 'froid - évier'];
    final uids = [wash!.uid, cook!.uid, cool!.uid];
    final values = [a, b, c];
    for (var i = 0; i < 3; i++) {
      final v = values[i];
      if (v < triangleLegMin) {
        out.add(Issue(Severity.warning, 'triangle_short',
            L('Triangle d\'activité : {0} = {1} mm ({2} mm minimum)', [names[i], v.round(), triangleLegMin]), [uids[i], uids[(i + 1) % 3]]));
      } else if (v > triangleLegMax) {
        out.add(Issue(Severity.warning, 'triangle_long',
            L('Triangle d\'activité : {0} = {1} mm ({2} mm maximum)', [names[i], v.round(), triangleLegMax]), [uids[i], uids[(i + 1) % 3]]));
      }
    }
    final p = a + b + c;
    if (p < trianglePerimeterMin || p > trianglePerimeterMax) {
      out.add(Issue(Severity.warning, 'triangle_perimeter',
          L('Triangle d\'activité : périmètre {0} mm (entre {1} et {2} mm)', [p.round(), trianglePerimeterMin, trianglePerimeterMax]), uids));
    } else {
      out.add(Issue(Severity.info, 'triangle_ok',
          L('Triangle d\'activité respecté : {0} + {1} + {2} = {3} mm', [a.round(), b.round(), c.round(), p.round()]), uids));
    }
    return out;
  }

  /// Forme de la cuisine d'après les murs réellement équipés.
  String layoutShape() {
    final used = [
      for (final id in room.order)
        if (project.items.any((c) => c.wallId == id && modelOf(c).isCarcass)) id
    ];
    final withIsland = project.items.any((c) => c.wallId == 'I' && modelOf(c).isCarcass);
    if (withIsland) {
      final base = used.isEmpty ? 'îlot seul' : _shapeOf(used);
      return used.isEmpty ? base : '$base avec îlot';
    }
    return _shapeOf(used);
  }

  String _shapeOf(List<String> used) {
    switch (used.length) {
      case 0:
        return 'vide';
      case 1:
        return 'linéaire';
      case 2:
        final opposite = (used.contains('A') && used.contains('D')) || (used.contains('B') && used.contains('C'));
        return opposite ? 'parallèle' : 'en L';
      case 3:
        return 'en U';
      default:
        return 'en C';
    }
  }

  List<Issue> _normChecks() {
    final out = <Issue>[];
    final items = project.items;
    String name(PlacedCabinet c) => modelOf(c).name;

    if (std.worktopThickness < worktopThicknessMin) {
      out.add(Issue(Severity.error, 'worktop_thin',
          L('plan de travail de {0} mm : {1} mm minimum au-dessus d\'une plaque', [std.worktopThickness, worktopThicknessMin])));
    }

    for (final hob in items.where((c) => _isHob(modelOf(c)))) {
      final w = room.wall(hob.wallId);
      // hotte au-dessus, à au moins 650 mm du plan de travail
      final hoods = items.where((c) => _isHood(modelOf(c)) && c.wallId == hob.wallId && _overlapS(c, hob)).toList();
      if (hoods.isEmpty) {
        out.add(Issue(Severity.warning, 'hob_no_hood', L('{0} sans hotte au-dessus', [name(hob)]), [hob.uid]));
      }
      for (final h in hoods) {
        final d = (h.z - std.worktopTop).round();
        if (d < hoodAboveHobMin) {
          out.add(Issue(Severity.error, 'hood_low', L('hotte à {0} mm de la plaque de cuisson ({1} mm minimum)', [d, hoodAboveHobMin]), [h.uid, hob.uid]));
        }
      }
      // pas de colonne ni de mur trop près de la plaque
      for (final t in items.where((c) => c.wallId == hob.wallId && modelOf(c).kind == CabinetKind.tall)) {
        final g = _gapBetween(hob, t);
        if (g >= 0 && g < hobSideClearance) {
          out.add(Issue(Severity.warning, 'hob_near_tall',
              L('plaque à {0} mm de « {1} » ({2} mm conseillés)', [g.round(), name(t), hobSideClearance]), [hob.uid, t.uid]));
        }
      }
      final toWall = math.min(hob.s, w.length - hob.right);
      final sideWallEnd = hob.s < w.length - hob.right ? room.prevOf(hob.wallId) : room.nextOf(hob.wallId);
      if (toWall < hobSideClearance && room.isWallEnabled(sideWallEnd)) {
        out.add(Issue(Severity.warning, 'hob_near_wall',
            L('plaque à {0} mm du mur latéral ({1} mm conseillés)', [toWall.round(), hobSideClearance]), [hob.uid]));
      }
      // pas de plaque sous une fenêtre
      for (final o in project.openings.where((o) => !o.isDoor && o.wallId == hob.wallId)) {
        if (o.s < hob.right && hob.s < o.right) {
          out.add(Issue(Severity.warning, 'hob_window', L('plaque de cuisson sous une fenêtre (projections, rideaux)'), [hob.uid, o.uid]));
        }
      }
    }

    // lave-vaisselle près de l'évier (raccordement et égouttage)
    final sinks = items.where((c) => modelOf(c).id == 'base_sink').toList();
    for (final dw in items.where((c) => modelOf(c).requiresAppliance == 'integrated_dishwasher')) {
      final near = sinks.any((s) => s.wallId == dw.wallId && _gapBetween(dw, s) <= 600);
      if (sinks.isNotEmpty && !near) {
        out.add(Issue(Severity.warning, 'dishwasher_far', L('lave-vaisselle à plus de 600 mm de l\'évier'), [dw.uid]));
      }
    }

    // angles : un fileur d'au moins 50 mm évite que poignées et tiroirs se heurtent
    for (final c in items) {
      final m = modelOf(c);
      if (!m.kind.isLow || m.kind.isCorner || m.kind.isFiller || !m.isCarcass) continue;
      final w = room.wall(c.wallId);
      for (final (atStart, wallEnd) in [(true, room.prevOf(c.wallId)), (false, room.nextOf(c.wallId))]) {
        final edge = atStart ? c.s : c.right;
        // le caisson voisin de l'autre mur occupe le coin sur ~600 mm
        final cornerZone = atStart ? (0.0, 600.0) : (w.length - 600, w.length);
        final touching = atStart ? (edge - cornerZone.$2).abs() < 0.5 : (edge - cornerZone.$1).abs() < 0.5;
        if (!touching) continue;
        final hasNeighbour = items.any((o) =>
            o.wallId == wallEnd &&
            modelOf(o).kind.isLow &&
            !modelOf(o).kind.isFiller &&
            (atStart ? o.right > room.wall(wallEnd).length - 600.5 : o.s < 600.5));
        if (hasNeighbour) {
          out.add(Issue(Severity.warning, 'corner_filler',
              L('« {0} » arrive contre l\'angle : prévoir un fileur de {1} mm minimum', [name(c), cornerFillerMin]), [c.uid]));
        }
      }
    }

    // passages entre deux linéaires face à face
    for (final (a, b) in [('A', 'D'), ('B', 'C')]) {
      if (!room.isWallEnabled(a) || !room.isWallEnabled(b)) continue;
      final wa = room.wall(a);
      final ia = items.where((c) => c.wallId == a && modelOf(c).floorSupport);
      final ib = items.where((c) => c.wallId == b && modelOf(c).floorSupport);
      for (final x in ia) {
        for (final y in ib) {
          final bx = boxesOf(x).first.box, by = boxesOf(y).first.box;
          final (s0, s1, _, tx) = wa.boxToWall(bx);
          final (u0, u1, ty0, _) = wa.boxToWall(by);
          if (!(s0 < u1 && u0 < s1)) continue;
          final aisle = ty0 - tx;
          if (aisle < aisleMin) {
            out.add(Issue(Severity.error, 'aisle', L('passage de {0} mm entre les murs {1} et {2} ({3} mm minimum)', [aisle.round(), a, b, aisleMin]),
                [x.uid, y.uid]));
          } else if (aisle < aisleAdvised) {
            out.add(Issue(Severity.info, 'aisle_tight',
                L('passage de {0} mm entre les murs {1} et {2} ({3} mm conseillés)', [aisle.round(), a, b, aisleAdvised]), [x.uid, y.uid]));
          }
        }
      }
    }

    // les trois zones d'une cuisine et le triangle d'activité (évier - plaque - froid)
    if (kitchen) out.addAll(_workTriangle());
    out.addAll(_islandChecks());

    // dédoublonnage (mêmes code + éléments)
    final seen = <String>{};
    return [for (final i in out) if (seen.add('${i.code}|${i.uids.join(',')}')) i];
  }

  // ------------------------------------------------------------------------
  // Mode position : distances aux voisins
  // ------------------------------------------------------------------------

  /// Distances libres à gauche et à droite du caisson (jusqu'au voisin ou à l'extrémité du mur).
  (double left, double right) neighbourGaps(String uid) {
    final c = _get(uid);
    final w = room.wall(c.wallId);
    var left = c.s, right = w.length - c.right;
    for (final (a, b) in occupied(c)) {
      if (b <= c.s + 0.5) left = math.min(left, c.s - b);
      if (a >= c.right - 0.5) right = math.min(right, a - c.right);
    }
    return (left, right);
  }

  /// Place le caisson à [mm] de son voisin de gauche (ou de droite si [fromRight]).
  MoveResult setNeighbourGap(String uid, double mm, {bool fromRight = false}) {
    final c = _get(uid);
    final (l, r) = neighbourGaps(uid);
    final ds = fromRight ? r - mm : mm - l;
    return move(uid, s: c.s + ds);
  }
}
