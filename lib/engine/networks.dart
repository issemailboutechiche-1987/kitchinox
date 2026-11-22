/// Réseaux de la cuisine : prises et sorties électriques, éclairage, eau froide / chaude,
/// évacuations, gaz, sortie de hotte.
///
/// Les points sont posés sur un mur (coordonnées (s, z) du mur, comme les caissons), sur l'îlot
/// (« I ») ou au plafond (« P » : s = x, t = y du plan). Le moteur les génère d'après
/// l'implantation (évier, plaque, four, lave-vaisselle, réfrigérateur, hotte, plan de travail,
/// portes) en suivant les règles usuelles de la NF C 15-100 ; l'utilisateur peut ensuite les
/// déplacer, en ajouter ou en retirer.
library;

import 'i18n_hook.dart';
import 'dart:math' as math;

import 'catalog.dart';
import 'layout_engine.dart';
import 'materials.dart';
import 'project.dart';
import 'room_objects.dart';

enum NetKind {
  socket('Prise 16 A', 'elec'),
  socketDouble('Prise double 16 A', 'elec'),
  socketTriple('Prise triple 16 A', 'elec'),
  socketQuad('Prise quadruple 16 A', 'elec'),
  socket20('Prise 20 A spécialisée', 'elec'),
  out32('Sortie de câble 32 A', 'elec'),
  switch_('Interrupteur', 'elec'),
  switchDouble('Interrupteur double', 'elec'),
  switchTriple('Interrupteur triple', 'elec'),
  usb('Prise chargeur USB-A + USB-C', 'elec'),
  rj45('Prise réseau Ethernet RJ45', 'data'),
  tvSat('Prise TV / satellite', 'data'),
  light('Point lumineux', 'elec'),
  led('Alimentation LED sous meubles', 'elec'),
  waterCold('Arrivée eau froide', 'water'),
  waterHot('Arrivée eau chaude', 'water'),
  drain('Évacuation Ø40', 'drain'),
  drainWc('Évacuation WC Ø100', 'drain'),
  cable('Sortie de câble 16 A (radiateur, chauffe-eau)', 'elec'),
  valveMachine('Robinet machine lave-vaisselle', 'water'),
  gas('Robinet gaz', 'gas'),
  duct('Sortie de hotte Ø125', 'air');

  final String label;
  final String network; // elec | water | drain | gas | air
  const NetKind(this.label, this.network);

  static NetKind parse(String s) => NetKind.values.firstWhere((k) => k.name == s, orElse: () => NetKind.socket);

  bool get isSocket => this == socket || this == socketDouble || this == socketTriple || this == socketQuad || this == socket20;
  bool get isSwitch => this == switch_ || this == switchDouble || this == switchTriple;

  /// Abréviation dessinée dans le symbole.
  String get tag => switch (this) {
        socket => 'P',
        socketDouble => 'P2',
        socketTriple => 'P3',
        socketQuad => 'P4',
        socket20 => '20',
        out32 => '32',
        switch_ => 'I',
        switchDouble => 'I2',
        switchTriple => 'I3',
        usb => 'USB',
        rj45 => 'RJ',
        tvSat => 'TV',
        light => 'L',
        led => 'LED',
        waterCold => 'EF',
        waterHot => 'EC',
        drain => 'EU',
        drainWc => 'EV',
        cable => 'SC',
        valveMachine => 'RM',
        gas => 'G',
        duct => 'VH',
      };
}

/// Usage d'un point (sert aux circuits et aux contrôles).
class NetUse {
  static const plan = 'plan', general = 'general', sink = 'evier', dishwasher = 'lv', oven = 'four', hob = 'plaque';
  static const fridge = 'frigo', hood = 'hotte', microwave = 'micro', lighting = 'eclairage', washer = 'll';
  static const sanitary = 'sanitaire', vanity = 'vasque', tv = 'tv', mirror = 'miroir';
}

class NetPoint {
  final String uid;
  NetKind kind;
  String wallId; // A B C D, I (îlot), P (plafond)
  double s; // le long du mur (ou x au plafond)
  double z; // hauteur depuis le sol (ou y au plafond)
  String use;
  bool auto; // posé par la génération automatique (remplacé à la prochaine génération)
  String? forUid; // caisson concerné
  bool hidden; // point automatique supprimé : garde la place pour qu'il ne revienne pas

  NetPoint(
      {required this.uid,
      required this.kind,
      required this.wallId,
      required this.s,
      required this.z,
      this.use = NetUse.general,
      this.auto = true,
      this.forUid,
      this.hidden = false});

  bool get onCeiling => wallId == 'P';

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'kind': kind.name,
        'wall': wallId,
        's': s,
        'z': z,
        'use': use,
        if (!auto) 'auto': false,
        if (forUid != null) 'for': forUid,
        if (hidden) 'hidden': true,
      };

  factory NetPoint.fromJson(Map<String, dynamic> j) => NetPoint(
        uid: j['uid'] as String,
        kind: NetKind.parse(j['kind'] as String? ?? 'socket'),
        wallId: j['wall'] as String? ?? 'A',
        s: (j['s'] as num).toDouble(),
        z: (j['z'] as num).toDouble(),
        use: j['use'] as String? ?? NetUse.general,
        auto: j['auto'] as bool? ?? true,
        forUid: j['for'] as String?,
        hidden: j['hidden'] as bool? ?? false,
      );

  @override
  String toString() => '${kind.name}@$wallId(${s.round()},${z.round()})';
}

// ---------------------------------------------------------------------------
// Génération
// ---------------------------------------------------------------------------

/// Hauteurs usuelles (mm).
class NetHeights {
  static const waterSupply = 550.0; // arrivées EF / EC derrière le meuble évier
  static const drain = 450.0; // évacuation de l'évier
  static const machine = 300.0; // prise / robinet du lave-vaisselle (dans le meuble voisin)
  static const ovenSocket = 300.0;
  static const hob32 = 600.0; // sortie de câble 32 A sous le plan
  static const gasTap = 500.0;
  static const aboveWorktop = 200.0; // prises du plan de travail : dessus du plan + 200
  static const service = 300.0; // prises de service au sol
  static const switchZ = 1100.0;
}

bool _isDishwasher(CabinetModel m) => m.id == 'base_integrated_dishwasher_door';
bool _isWasher(CabinetModel m) => m.id == 'base_washing_machine';
bool _hasOven(CabinetModel m, PlacedCabinet c) =>
    m.id == 'base_cooktop_oven' || m.id == 'base_oven_only' || m.id == 'tall_oven_microwave' || m.id == 'tall_oven_single' ||
    appliancesOf(m, c).any((a) => a.startsWith('oven'));
bool _hasMicrowave(CabinetModel m, PlacedCabinet c) => appliancesOf(m, c).any((a) => a.startsWith('microwave'));
bool _isFridge(LayoutEngine e, CabinetModel m) => e.isCooling(m);
bool _isHood(CabinetModel m, PlacedCabinet c) => m.id == 'wall_integrated_hood' || appliancesOf(m, c).any((a) => a.startsWith('hood'));

/// Points générés d'après l'implantation. [hobEnergy] : 'gas' ou 'electric'.
List<NetPoint> generateNetworks(LayoutEngine e, {String hobEnergy = 'gas'}) {
  final p = e.project;
  final room = p.room;
  final std = p.standards;
  final out = <NetPoint>[];
  var n = 0;
  NetPoint add(NetKind k, String wall, double s, double z, String use, {String? forUid}) {
    final pt = NetPoint(uid: 'n${++n}', kind: k, wallId: wall, s: s, z: z, use: use, forUid: forUid);
    out.add(pt);
    return pt;
  }

  final items = p.items;
  PlacedCabinet? neighbour(PlacedCabinet c, {bool carcass = true}) {
    PlacedCabinet? best;
    var bestGap = 60.0;
    for (final o in items) {
      if (o.uid == c.uid || o.wallId != c.wallId) continue;
      final m = e.modelOf(o);
      if (!m.kind.isLow && m.kind != CabinetKind.tall) continue;
      if (carcass && (!m.isCarcass || _isDishwasher(m) || m.kind.isFiller)) continue;
      final gap = math.min((o.s - c.right).abs(), (c.s - o.right).abs());
      if (gap < bestGap) {
        bestGap = gap;
        best = o;
      }
    }
    return best;
  }

  /// Position dans [host] du côté de [toward] (à 80 mm du bord).
  double sideOf(PlacedCabinet host, PlacedCabinet toward) => toward.s >= host.right - 1 ? host.right - 80 : host.s + 80;

  // ---- eau, évacuation et lave-vaisselle
  for (final c in items) {
    if (!e.washes(c)) continue;
    final mid = c.s + c.width / 2;
    add(NetKind.waterCold, c.wallId, mid - 120, NetHeights.waterSupply, NetUse.sink, forUid: c.uid);
    add(NetKind.waterHot, c.wallId, mid + 120, NetHeights.waterSupply, NetUse.sink, forUid: c.uid);
    add(NetKind.drain, c.wallId, mid, NetHeights.drain, NetUse.sink, forUid: c.uid);
  }
  for (final c in items) {
    final m = e.modelOf(c);
    if (!_isDishwasher(m) && !_isWasher(m)) continue;
    final use = _isWasher(m) ? NetUse.washer : NetUse.dishwasher;
    // prise et robinet jamais derrière l'appareil : dans le meuble voisin (de préférence l'évier)
    final sink = items.where((o) => o.wallId == c.wallId && e.washes(o) && math.min((o.s - c.right).abs(), (c.s - o.right).abs()) < 60).firstOrNull;
    final host = sink ?? neighbour(c);
    if (host != null) {
      final x = sideOf(host, c);
      add(NetKind.socket20, c.wallId, x, NetHeights.machine, use, forUid: c.uid);
      add(NetKind.valveMachine, c.wallId, x + (x > host.s + host.width / 2 ? -90 : 90), NetHeights.machine + 200, use, forUid: c.uid);
      if (sink == null) add(NetKind.drain, c.wallId, x, NetHeights.drain, use, forUid: c.uid);
    } else {
      add(NetKind.socket20, c.wallId, c.s + 80, 150, use, forUid: c.uid);
      add(NetKind.valveMachine, c.wallId, c.s + 180, 150, use, forUid: c.uid);
      add(NetKind.drain, c.wallId, c.s + 300, 150, use, forUid: c.uid);
    }
  }

  // ---- cuisson, froid, hotte, micro-ondes
  for (final c in items) {
    final m = e.modelOf(c);
    final mid = c.s + c.width / 2;
    if (m.id == 'base_cooktop_oven' || (e.hasHob(c))) {
      if (hobEnergy == 'electric') {
        add(NetKind.out32, c.wallId, mid, NetHeights.hob32, NetUse.hob, forUid: c.uid);
      } else {
        add(NetKind.gas, c.wallId, c.s + 90, NetHeights.gasTap, NetUse.hob, forUid: c.uid);
      }
    }
    if (_hasOven(m, c)) {
      final host = m.kind.isLow ? neighbour(c) : null;
      add(NetKind.socket20, c.wallId, host != null ? sideOf(host, c) : mid + 150, host != null ? NetHeights.ovenSocket : 250, NetUse.oven, forUid: c.uid);
    }
    if (_hasMicrowave(m, c)) {
      add(NetKind.socket, c.wallId, mid + 150, c.z + c.height - 120, NetUse.microwave, forUid: c.uid);
    }
    if (_isFridge(e, m)) {
      add(NetKind.socket20, c.wallId, mid, c.z + c.height - 150, NetUse.fridge, forUid: c.uid);
    }
    if (m.kind.isHigh && _isHood(m, c)) {
      add(NetKind.socket, c.wallId, mid + 120, c.z + c.height - 120, NetUse.hood, forUid: c.uid);
      final top = c.z + c.height;
      add(NetKind.duct, c.wallId, mid, top + 150 < room.height ? top + 100 : c.z + c.height - 80, NetUse.hood, forUid: c.uid);
    }
  }

  // ---- sanitaires posés dans la pièce : eau froide, eau chaude, évacuation (WC en Ø100), câbles
  for (final (wall, s, z, kind, uid) in fixtureWaterPoints(room, p.objects)) {
    final o = p.objects.firstWhere((x) => x.uid == uid);
    final wc = o.ref == 'fixture:wc_suspendu' || o.ref == 'fixture:wc_sol';
    final k = switch (kind) { 'froide' => NetKind.waterCold, 'chaude' => NetKind.waterHot, _ => wc ? NetKind.drainWc : NetKind.drain };
    add(k, wall, s, z.toDouble(), NetUse.sanitary, forUid: uid);
  }
  // électricité des sanitaires : du côté le plus éloigné de la baignoire et de la douche (volumes 0 à 2)
  final wet = wetZones(p.objects);
  double wetAt(String wall, double s) {
    final (px, py) = room.wall(wall).toPlan(s, 0);
    return wetDistance(wet, px, py);
  }

  double beside(String wall, double left, double right) {
    final len = room.wall(wall).length;
    final cands = [if (right + 120 <= len) right + 120, if (left - 120 >= 0) left - 120];
    if (cands.isEmpty) return (left + right) / 2;
    cands.sort((a, b) => wetAt(wall, b).compareTo(wetAt(wall, a)));
    return cands.first;
  }

  for (final o in p.objects) {
    final f = o.fixture;
    if (f == null || !{'seche_serviettes', 'chauffe_eau', 'miroir'}.contains(f.id)) continue;
    final wall = fixtureWall(o, room);
    if (!room.isWallEnabled(wall)) continue;
    final w = room.wall(wall);
    final (_, left, right) = objectOnWall(room, o);
    switch (f.id) {
      case 'chauffe_eau':
        // sortie de câble au-dessus du ballon
        add(NetKind.cable, wall, ((left + right) / 2).clamp(0, w.length).toDouble(), o.z + o.h + 150, NetUse.sanitary, forUid: o.uid);
      case 'seche_serviettes':
        // sortie de câble à 200 mm du sol, à côté, du côté opposé à la douche
        add(NetKind.cable, wall, beside(wall, left, right).clamp(0, w.length).toDouble(), 200, NetUse.sanitary, forUid: o.uid);
      default:
        // miroir LED : sortie de câble derrière le miroir, prise rasoir à côté, loin de la douche
        add(NetKind.cable, wall, ((left + right) / 2).clamp(0, w.length).toDouble(), o.z + o.h - 120, NetUse.mirror, forUid: o.uid);
        final s = beside(wall, left, right);
        if (wetAt(wall, s) >= 600) add(NetKind.socket, wall, s.clamp(0, w.length).toDouble(), 1200, NetUse.mirror, forUid: o.uid);
    }
  }

  // ---- autres pièces : vasques, miroirs, colonnes buanderie, meubles TV
  if (!e.kitchen) {
    for (final c in items) {
      final id = c.modelId;
      final mid = c.s + c.width / 2;
      final len = room.wall(c.wallId).length;
      if (id.contains('vanity')) {
        add(NetKind.waterCold, c.wallId, mid - 100, NetHeights.waterSupply, NetUse.vanity, forUid: c.uid);
        add(NetKind.waterHot, c.wallId, mid + 100, NetHeights.waterSupply, NetUse.vanity, forUid: c.uid);
        add(NetKind.drain, c.wallId, mid, NetHeights.drain, NetUse.vanity, forUid: c.uid);
      }
      if (id.contains('mirror')) {
        // prise rasoir à côté du miroir, du côté le plus loin de la douche, jamais en volume 2
        final s = beside(c.wallId, c.s, c.right);
        if (wetAt(c.wallId, s) >= 600) add(NetKind.socket, c.wallId, s.clamp(0, len).toDouble(), 1200, NetUse.mirror, forUid: c.uid);
        add(NetKind.led, c.wallId, mid, c.z + c.height + 40, NetUse.lighting, forUid: c.uid);
      }
      if (id.startsWith('laundry_sink')) {
        add(NetKind.waterCold, c.wallId, mid - 100, NetHeights.waterSupply, NetUse.sink, forUid: c.uid);
        add(NetKind.waterHot, c.wallId, mid + 100, NetHeights.waterSupply, NetUse.sink, forUid: c.uid);
        add(NetKind.drain, c.wallId, mid, NetHeights.drain, NetUse.sink, forUid: c.uid);
      }
      if (id.contains('washing_machine') || id.contains('washer_dryer')) {
        add(NetKind.socket20, c.wallId, mid - 150, 1100, NetUse.washer, forUid: c.uid);
        add(NetKind.valveMachine, c.wallId, mid + 100, 1100, NetUse.washer, forUid: c.uid);
        add(NetKind.drain, c.wallId, mid, 600, NetUse.washer, forUid: c.uid);
      }
      if (p.universe == 'tv' && (id.contains('bench') || id.contains('fireplace'))) {
        // prises derrière l'écran, juste au-dessus du meuble
        final z = c.z + c.height + 150;
        add(NetKind.socketDouble, c.wallId, mid - 250, z, NetUse.tv, forUid: c.uid);
        add(NetKind.socketDouble, c.wallId, mid + 250, z, NetUse.tv, forUid: c.uid);
        add(NetKind.tvSat, c.wallId, mid - 90, z, NetUse.tv, forUid: c.uid);
        add(NetKind.rj45, c.wallId, mid + 90, z, NetUse.tv, forUid: c.uid);
      }
    }
  }

  // ---- prises du plan de travail (cuisine)
  final zTop = std.worktopTop + NetHeights.aboveWorktop;
  for (final w in room.walls.where((w) => e.kitchen && w.enabled)) {
    final forbid = <(double, double)>[];
    for (final c in items.where((c) => c.wallId == w.id)) {
      final m = e.modelOf(c);
      if (e.washes(c)) forbid.add((c.s - 150, c.right + 150)); // pas de prise au-dessus de l'évier
      if (e.hasHob(c)) forbid.add((c.s - 150, c.right + 150)); // ni au-dessus de la plaque
      if (m.kind == CabinetKind.tall) forbid.add((c.s - 20, c.right + 20));
    }
    for (final o in p.openings.where((o) => o.wallId == w.id)) {
      if (o.z < zTop + 80 && o.z + o.height > zTop - 80) forbid.add((o.s - 60, o.right + 60));
    }
    for (final (a, b) in e.runs(w.id, (m) => m.kind.isLow)) {
      // intervalles autorisés du linéaire
      final allowed = <(double, double)>[];
      var cur = a + 120;
      final sorted = [...forbid]..sort((x, y) => x.$1.compareTo(y.$1));
      for (final (f0, f1) in sorted) {
        if (f1 <= cur || f0 >= b - 120) continue;
        if (f0 > cur + 1) allowed.add((cur, math.min(f0, b - 120)));
        cur = math.max(cur, f1);
      }
      if (cur < b - 120) allowed.add((cur, b - 120));
      final usable = allowed.fold<double>(0, (t, x) => t + (x.$2 - x.$1));
      if (usable <= 0) continue;
      var want = math.max(1, ((b - a) / 1200).round());
      for (final (s0, s1) in allowed) {
        final k = math.max(0, ((s1 - s0) / usable * want).round());
        final count = k == 0 && (s1 - s0) > 250 && want > 0 ? 1 : k;
        for (var i = 0; i < count; i++) {
          add(NetKind.socketDouble, w.id, s0 + (s1 - s0) * (i + 0.5) / count, zTop, NetUse.plan);
        }
        want -= count;
        if (want <= 0) break;
      }
    }
  }
  // îlot : une prise double sur l'habillage côté repas
  final isl = room.island;
  if (e.kitchen && isl != null && e.runs('I', (m) => m.kind.isLow).isNotEmpty) {
    add(NetKind.socketDouble, 'I', isl.length / 2, std.baseTop - 150.0, NetUse.plan);
  }
  // au moins 4 prises au-dessus du plan : on complète sur les plus grands intervalles libres
  int planCount() => out.where((x) => x.use == NetUse.plan).length;
  if (e.kitchen && planCount() < 4) {
    for (final w in room.walls.where((w) => w.enabled)) {
      for (final (a, b) in e.runs(w.id, (m) => m.kind.isLow)) {
        if (planCount() >= 4) break;
        final taken = out.where((x) => x.wallId == w.id && x.use == NetUse.plan).map((x) => x.s).toList();
        for (final s in [a + 200, b - 200]) {
          if (planCount() >= 4) break;
          if (s <= a || s >= b) continue;
          if (taken.any((t) => (t - s).abs() < 300)) continue;
          if (!_socketAllowedAt(e, w.id, s, zTop)) continue;
          add(NetKind.socketDouble, w.id, s, zTop, NetUse.plan);
        }
      }
    }
  }

  // ---- éclairage : plafonnier, alimentation LED sous les hauts, interrupteur près de la porte
  add(NetKind.light, 'P', room.width / 2, room.depth / 2, NetUse.lighting);
  if (isl != null) add(NetKind.light, 'P', isl.x0 + isl.length / 2, isl.y0 + Island.depth / 2, NetUse.lighting);
  for (final w in room.walls.where((w) => e.kitchen && w.enabled)) {
    final runs = e.runs(w.id, (m) => m.kind.isHigh);
    for (final (a, b) in runs) {
      if (b - a < 600) continue;
      final first = items.where((c) => c.wallId == w.id && e.modelOf(c).kind.isHigh && (c.s - a).abs() < 1).firstOrNull;
      if (first != null) add(NetKind.led, w.id, a + 100, first.z + 60, NetUse.lighting);
    }
  }
  final door = p.openings.where((o) => o.isDoor).firstOrNull;
  if (door != null) {
    final len = room.wall(door.wallId).length;
    final s = door.right + 150 <= len - 50 ? door.right + 150 : door.s - 150;
    add(NetKind.switch_, door.wallId, s, NetHeights.switchZ, NetUse.lighting);
  } else {
    final w = room.walls.firstWhere((w) => !w.enabled, orElse: () => room.wall('D'));
    add(NetKind.switch_, w.id, 200, NetHeights.switchZ, NetUse.lighting);
  }

  // ---- 6 prises au moins dans la cuisine : prises de service au sol sur les murs libres
  int sockets() => out.where((x) => x.kind.isSocket && x.use != NetUse.dishwasher && x.use != NetUse.washer && x.use != NetUse.oven && x.use != NetUse.fridge).length;
  if (e.kitchen && sockets() < 6) {
    final free = <(String, double, double)>[];
    for (final w in room.walls) {
      for (final (a, b) in e.freeIntervals(w.id, Band.low)) {
        if (b - a >= 400) free.add((w.id, a, b));
      }
    }
    free.sort((x, y) => (y.$3 - y.$2).compareTo(x.$3 - x.$2));
    var i = 0;
    while (sockets() < 6 && free.isNotEmpty && i < 12) {
      final (wid, a, b) = free[i % free.length];
      final k = i ~/ free.length;
      add(NetKind.socket, wid, a + (b - a) * (0.3 + 0.4 * (k % 2)), NetHeights.service, NetUse.general);
      i++;
    }
  }
  return out;
}

/// Remplace les points automatiques du projet par une nouvelle génération (les points ajoutés à la main restent).
int applyNetworks(LayoutEngine e) {
  final p = e.project;
  final gen = generateNetworks(e, hobEnergy: p.specs.hobEnergy);
  p.points.removeWhere((x) => x.auto);
  // points d'un meuble ou d'un sanitaire qui n'existe plus (nouvel aménagement) : retirés aussi
  p.points.removeWhere((x) => x.forUid != null && p.byUid(x.forUid!) == null && !p.objects.any((o) => o.uid == x.forUid));
  // un point déplacé, modifié ou supprimé à la main remplace le point généré correspondant
  final manual = p.points.where((x) => !x.auto).toList();
  bool replaced(NetPoint g) => manual.any((m) =>
      m.kind == g.kind &&
      m.use == g.use &&
      (g.forUid != null ? m.forUid == g.forUid : m.forUid == null && m.wallId == g.wallId && (m.s - g.s).abs() < 600));
  gen.removeWhere(replaced);
  // identifiants stables (na1, na2...) : une régénération identique ne change rien au projet
  for (var i = 0; i < gen.length; i++) {
    final x = gen[i];
    p.points.add(NetPoint(uid: 'na${i + 1}', kind: x.kind, wallId: x.wallId, s: x.s, z: x.z, use: x.use, forUid: x.forUid));
  }
  return gen.length;
}

bool _socketAllowedAt(LayoutEngine e, String wallId, double s, double z) {
  final std = e.project.standards;
  if (z < std.worktopTop || z > std.worktopTop + 700) return true;
  for (final c in e.project.items.where((c) => c.wallId == wallId)) {
    if (e.washes(c) && s > c.s - 100 && s < c.right + 100) return false;
    if (e.hasHob(c) && s > c.s - 100 && s < c.right + 100) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Contrôles
// ---------------------------------------------------------------------------

Iterable<NetPoint> visiblePoints(Project p) => p.points.where((x) => !x.hidden);

List<Issue> networkChecks(LayoutEngine e) {
  final p = e.project;
  final pts = visiblePoints(p).toList();
  if (pts.isEmpty) return const [];
  final out = <Issue>[];
  final std = p.standards;
  final room = p.room;

  for (final x in pts) {
    if (x.onCeiling) continue;
    if (x.wallId != 'I' && !p.room.order.contains(x.wallId)) continue;
    final len = x.wallId == 'I' ? (room.island?.length ?? 0) : room.wall(x.wallId).length;
    if (x.s < 0 || x.s > len || x.z < 0 || x.z > room.height) {
      out.add(Issue(Severity.error, 'net_outside', L('{0} hors du mur {1}', [L(x.kind.label), x.wallId]), [x.uid]));
      continue;
    }
    for (final o in p.openings.where((o) => o.wallId == x.wallId)) {
      if (x.s > o.s && x.s < o.right && x.z > o.z && x.z < o.z + o.height) {
        out.add(Issue(Severity.error, 'net_opening', L('{0} dans {1} du mur {2}', [L(x.kind.label), o.isDoor ? 'la porte' : 'la fenêtre', x.wallId]), [x.uid]));
      }
    }
    if (x.kind.network == 'elec' && x.kind != NetKind.out32 && x.z > std.worktopTop && x.z < std.worktopTop + 700) {
      for (final c in p.items.where((c) => c.wallId == x.wallId)) {
        if (e.washes(c) && x.s > c.s - 100 && x.s < c.right + 100) {
          out.add(Issue(Severity.error, 'net_sink', L('{0} au-dessus de l\'évier : à éloigner des projections d\'eau', [L(x.kind.label)]), [x.uid, c.uid]));
        }
        if (e.hasHob(c) && x.s > c.s - 100 && x.s < c.right + 100) {
          out.add(Issue(Severity.warning, 'net_hob', L('{0} au-dessus de la plaque : chaleur et graisses', [L(x.kind.label)]), [x.uid, c.uid]));
        }
      }
    }
  }
  final plan = pts.where((x) => x.use == NetUse.plan && x.kind.isSocket).length;
  if (e.kitchen && plan < 4) {
    out.add(Issue(Severity.warning, 'net_plan', L('{0} prise(s) au-dessus du plan de travail : 4 au minimum (NF C 15-100)', [plan])));
  }
  final general = pts.where((x) => x.kind.isSocket && x.use != NetUse.dishwasher && x.use != NetUse.washer && x.use != NetUse.oven && x.use != NetUse.fridge).length;
  if (e.kitchen && general < 6) out.add(Issue(Severity.warning, 'net_count', L('{0} prise(s) dans la cuisine : 6 au minimum (NF C 15-100)', [general])));

  bool has(String use, String uid, bool Function(NetKind) k) => pts.any((x) => x.use == use && x.forUid == uid && k(x.kind));
  // sanitaires : chaque arrivée et évacuation prévue ; pas de prise près de la baignoire ou de la douche
  for (final o in p.objects) {
    final f = o.fixture;
    if (f == null) continue;
    if (f.water.isNotEmpty && !has(NetUse.sanitary, o.uid, (k) => k.network == 'drain')) {
      out.add(Issue(Severity.error, 'net_fixture', L('{0} : évacuation manquante', [L(f.name)]), [o.uid]));
    }
    if (f.water.any((w) => w.$1 != 'evac') && !has(NetUse.sanitary, o.uid, (k) => k.network == 'water')) {
      out.add(Issue(Severity.error, 'net_fixture', L('{0} : arrivée d\'eau manquante', [L(f.name)]), [o.uid]));
    }
    if (f.id == 'baignoire' || f.id.startsWith('douche')) {
      // volume 1 et 2 (NF C 15-100) : 600 mm autour de la baignoire ou de la douche, jusqu'à 2250 mm
      final (x0, y0, x1, y1) = o.footprint;
      for (final x in pts.where((x) => x.kind.isSocket && x.z < 2250)) {
        if (x.wallId == 'I' || x.onCeiling || !p.room.order.contains(x.wallId)) continue;
        final (px, py) = room.wall(x.wallId).toPlan(x.s, 0);
        final dx = math.max(0.0, math.max(x0 - px, px - x1)), dy = math.max(0.0, math.max(y0 - py, py - y1));
        if (math.sqrt(dx * dx + dy * dy) < 600) {
          out.add(Issue(Severity.error, 'net_volume', L('{0} à moins de 60 cm de {1} (volume 2 interdit)', [L(x.kind.label), f.name.toLowerCase()]), [x.uid, o.uid]));
        }
      }
    }
  }
  for (final c in p.items) {
    final m = e.modelOf(c);
    if (e.washes(c)) {
      if (!has(NetUse.sink, c.uid, (k) => k == NetKind.waterCold) || !has(NetUse.sink, c.uid, (k) => k == NetKind.drain)) {
        out.add(Issue(Severity.error, 'net_water', L('{0} : arrivée d\'eau ou évacuation manquante', [L(m.name)]), [c.uid]));
      }
    }
    if (_isWasher(m) && !has(NetUse.washer, c.uid, (k) => k == NetKind.socket20)) {
      out.add(Issue(Severity.warning, 'net_washer', L('Lave-linge sans prise 20 A spécialisée'), [c.uid]));
    }
    if (_isDishwasher(m) && !has(NetUse.dishwasher, c.uid, (k) => k == NetKind.socket20)) {
      out.add(Issue(Severity.warning, 'net_dishwasher', L('Lave-vaisselle sans prise 20 A spécialisée'), [c.uid]));
    }
    if (_hasOven(m, c) && !has(NetUse.oven, c.uid, (k) => k == NetKind.socket20)) {
      out.add(Issue(Severity.warning, 'net_oven', L('{0} : four sans prise 20 A spécialisée', [L(m.name)]), [c.uid]));
    }
    if ((m.id == 'base_cooktop_oven') && !has(NetUse.hob, c.uid, (k) => k == NetKind.out32 || k == NetKind.gas)) {
      out.add(Issue(Severity.warning, 'net_hob_feed', L('Plaque de cuisson sans alimentation (sortie 32 A ou robinet gaz)'), [c.uid]));
    }
    if (e.isCooling(m) && !has(NetUse.fridge, c.uid, (k) => k.isSocket)) {
      out.add(Issue(Severity.warning, 'net_fridge', L('Réfrigérateur sans prise'), [c.uid]));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Circuits et matériel
// ---------------------------------------------------------------------------

class Circuit {
  final String name;
  final String breaker; // calibre du disjoncteur
  final String cable; // section des conducteurs
  final int points;
  final String note;
  const Circuit(this.name, this.breaker, this.cable, this.points, [this.note = '']);
}

/// Circuits à prévoir au tableau, d'après les points posés (règles usuelles NF C 15-100).
List<Circuit> circuitsOf(Project p) {
  final pts = visiblePoints(p);
  int count(bool Function(NetPoint) f) => pts.where(f).length;
  final out = <Circuit>[];
  final hob = count((x) => x.kind == NetKind.out32);
  if (hob > 0) out.add(Circuit('Plaque de cuisson', '32 A', '3G6 mm²', hob, 'circuit dédié, différentiel 30 mA type A'));
  final oven = count((x) => x.use == NetUse.oven && x.kind == NetKind.socket20);
  for (var i = 0; i < oven; i++) {
    out.add(const Circuit('Four', '20 A', '3G2,5 mm²', 1, 'circuit dédié'));
  }
  final lv = count((x) => x.use == NetUse.dishwasher && x.kind == NetKind.socket20);
  for (var i = 0; i < lv; i++) {
    out.add(const Circuit('Lave-vaisselle', '20 A', '3G2,5 mm²', 1, 'circuit dédié, différentiel 30 mA type A'));
  }
  final fr = count((x) => x.use == NetUse.fridge && x.kind.isSocket);
  for (var i = 0; i < fr; i++) {
    out.add(const Circuit('Réfrigérateur / congélateur', '20 A', '3G2,5 mm²', 1, 'circuit spécialisé recommandé'));
  }
  final sockets = count((x) => x.kind.isSocket && x.use != NetUse.oven && x.use != NetUse.dishwasher && x.use != NetUse.washer && x.use != NetUse.fridge);
  for (var i = 0, left = sockets; left > 0; i++, left -= 6) {
    out.add(Circuit('Prises cuisine ${i + 1}', '20 A', '3G2,5 mm²', math.min(6, left), '6 socles au plus par circuit'));
  }
  final lights = count((x) => x.kind == NetKind.light || x.kind == NetKind.led);
  if (lights > 0) out.add(Circuit('Éclairage', '16 A', '3G1,5 mm²', lights, '8 points au plus par circuit'));
  return out;
}

class NetMaterial {
  final String network;
  final String name;
  final int qty;
  final String unit;
  const NetMaterial(this.network, this.name, this.qty, [this.unit = 'pce']);
}

/// Matériel d'électricité et de plomberie (quantités ; prix non renseignés).
List<NetMaterial> networkMaterial(Project p) {
  final pts = visiblePoints(p);
  int count(NetKind k) => pts.where((x) => x.kind == k).length;
  final out = <NetMaterial>[];
  void add(String net, String name, int q, [String unit = 'pce']) {
    if (q > 0) out.add(NetMaterial(net, name, q, unit));
  }

  add('Électricité', 'Prise de courant 16 A 2P+T', count(NetKind.socket));
  add('Électricité', 'Prise double 16 A 2P+T', count(NetKind.socketDouble));
  add('Électricité', 'Prise 20 A 2P+T (circuit spécialisé)', count(NetKind.socket20));
  add('Électricité', 'Boîte de sortie de câble 32 A', count(NetKind.out32));
  add('Électricité', 'Interrupteur', count(NetKind.switch_));
  add('Électricité', 'Point lumineux (DCL)', count(NetKind.light));
  add('Électricité', 'Alimentation LED + transformateur', count(NetKind.led));
  final boxes = pts.where((x) => x.kind.network == 'elec' && x.kind != NetKind.light).length;
  add('Électricité', 'Boîte d\'encastrement', boxes);
  final circuits = circuitsOf(p);
  for (final c in circuits) {
    add('Électricité', 'Disjoncteur ${c.breaker} (${c.name.toLowerCase()})', 1);
  }
  if (circuits.isNotEmpty) add('Électricité', 'Interrupteur différentiel 30 mA type A', 1);
  final water = count(NetKind.waterCold) + count(NetKind.waterHot);
  add('Plomberie', 'Robinet d\'arrêt 1/4 de tour', water);
  add('Plomberie', 'Flexible d\'alimentation de mitigeur', water);
  add('Plomberie', 'Robinet machine (lave-vaisselle)', count(NetKind.valveMachine));
  final sinks = pts.where((x) => x.kind == NetKind.drain && x.use == NetUse.sink).length;
  add('Plomberie', 'Siphon d\'évier avec piquage lave-vaisselle', sinks);
  add('Plomberie', 'Évacuation PVC Ø40 (sortie murale)', count(NetKind.drain));
  add('Gaz', 'Robinet gaz à obturation automatique + flexible', count(NetKind.gas));
  add('Ventilation', 'Sortie de hotte Ø125 + clapet', count(NetKind.duct));
  return out;
}
