// Usinage automatique de l'atelier : à partir des panneaux posés (pavés dans l'espace), on déduit
// comment le meuble se fabrique et se monte, comme le ferait un menuisier :
// - jonctions entre panneaux (chant contre face) : tourillons Ø8 x 35 et vis Confirmat Ø7 x 50,
//   répartis le long de la jonction ;
// - fond mince : rainure dans les panneaux où il s'encastre, sinon cloué au dos ;
// - portes : boîtiers de charnière Ø35 (nombre selon la hauteur) et embases sur le montant ;
// - façades de tiroir : paire de coulisses (longueur selon la profondeur) sur les montants voisins ;
// - abattants : compas et charnières ;
// - toutes les façades : poignée (entraxe selon la largeur), placée selon le type de meuble ;
// - tablettes mobiles : taquets et perçages système 32 sur les montants ;
// - fond de caisson surélevé : pieds réglables ;
// - chants : sur chaque arête visible (façades 2 mm sur 4 côtés, caisson 1 mm), jamais au dos ni contre un autre panneau.
library;

import 'dart:math' as math;

import 'art.dart';
import 'art_fittings.dart';
import 'cutting.dart';
import 'i18n_hook.dart';
import '../ui/art_camera.dart' show V3;

/// Types d'usinage et de quincaillerie posés par l'atelier.
enum MachiningKind {
  dowel('Tourillon bois Ø8 x 35 mm'),
  screw('Vis Confirmat Ø7 x 50 mm'),
  nail('Pointe 3 x 20 mm (fond cloué)'),
  groove('Rainure pour fond'),
  shelfHole('Perçage taquet Ø5 (système 32)'),
  shelfPin('Taquet d’étagère Ø5'),
  hingeCup('Boîtier de charnière Ø35'),
  hingePlate('Embase de charnière'),
  flapStay('Compas d’abattant'),
  slide('Coulisse de tiroir'),
  handle('Poignée'),
  foot('Pied réglable'),
  edge('Bande de chant'),
  hanger('Suspension de meuble haut'),
  connector('Jonction entre caissons'),
  latch('Poussoir d’ouverture'),
  drill('Perçage');

  final String label;
  const MachiningKind(this.label);
}

/// Un usinage ou une pièce de quincaillerie, placé dans l'espace (mm).
class MachiningElement {
  final MachiningKind kind;
  final V3 position; // centre (perçage) ou départ (segment)
  final V3 normal; // sens du perçage, ou direction du segment pour les coulisses, poignées, rainures et chants
  final double length; // longueur (segments) ou profondeur de perçage
  final double diameter; // diamètre, largeur de rainure ou épaisseur de chant
  final String? panelId;
  final String? partnerPanelId;
  final String? item; // désignation de la quincaillerie posée (liste à commander)

  const MachiningElement({
    required this.kind,
    required this.position,
    this.normal = const V3(0, 1, 0),
    this.length = 0,
    this.diameter = 0,
    this.panelId,
    this.partnerPanelId,
    this.item,
  });

  /// Fin du segment (coulisse, poignée, rainure, chant).
  V3 get end => position + normal * length;
}

/// Chants et rainures retenus pour un panneau (pour le débit).
class PanelWork {
  int edgeLong = 0, edgeShort = 0; // nombre de chants sur les grands et les petits côtés
  double edgeThickness = 0;
  int grooveLong = 0, grooveShort = 0;
}

/// Résultat de l'analyse d'usinage.
class MachiningSummary {
  final List<MachiningElement> elements;
  final Map<String, PanelWork> work; // par identifiant de panneau
  final List<(String, String, int)> hardware; // (désignation, usage, quantité)

  const MachiningSummary(this.elements, this.work, this.hardware);

  int count(MachiningKind k) => elements.where((e) => e.kind == k).length;
  int get dowelsCount => count(MachiningKind.dowel);
  int get screwsCount => count(MachiningKind.screw);
  int get shelfHolesCount => count(MachiningKind.shelfHole);
  int get hingeCupsCount => count(MachiningKind.hingeCup);
  int get groovesCount => count(MachiningKind.groove);
  double _meters(MachiningKind k) => elements.where((e) => e.kind == k).fold(0.0, (a, e) => a + e.length) / 1000;
  double get totalEdgeMeters => _meters(MachiningKind.edge);
  double get totalGrooveMeters => _meters(MachiningKind.groove);
  double get totalSlideMeters => _meters(MachiningKind.slide);

  /// Mètres de chant par épaisseur (mm).
  Map<double, double> get edgeByThickness {
    final out = <double, double>{};
    for (final e in elements.where((e) => e.kind == MachiningKind.edge)) {
      out[e.diameter] = (out[e.diameter] ?? 0) + e.length / 1000;
    }
    return out;
  }
}

// ------------------------------------------------------------------ géométrie des panneaux

const _tol = 0.6; // contact : faces à moins de 0,6 mm (une tablette mobile a 1 mm de jeu)

double _lo(ArtPanel p, int a) => a == 0 ? p.x : a == 1 ? p.y : p.z;
double _hi(ArtPanel p, int a) => a == 0 ? p.right : a == 1 ? p.top : p.back;
double _size(ArtPanel p, int a) => a == 0 ? p.w : a == 1 ? p.h : p.d;
double _ov(ArtPanel a, ArtPanel b, int ax) => math.max(0, math.min(_hi(a, ax), _hi(b, ax)) - math.max(_lo(a, ax), _lo(b, ax)));

/// Axe de l'épaisseur du panneau (sa plus petite dimension).
int thicknessAxis(ArtPanel p) {
  if (p.w <= p.h && p.w <= p.d) return 0;
  if (p.h <= p.d) return 1;
  return 2;
}

V3 _axisV(int a, [double s = 1]) => V3(a == 0 ? s : 0, a == 1 ? s : 0, a == 2 ? s : 0);

V3 _pt(Map<int, double> c) => V3(c[0]!, c[1]!, c[2]!);

bool _structural(ArtPanel p) => !p.role.isFront && p.thickness >= 10;
bool _thinBack(ArtPanel p) => !p.role.isFront && p.thickness < 10;

/// Positions le long d'une jonction [l0, l1] : tourillons à 32 mm des bouts, vis à 96 mm des bouts
/// puis tous les 400 mm au plus.
(List<double>, List<double>) _jointStations(double l0, double l1) {
  final len = l1 - l0;
  if (len < 60) return (const [], [l0 + len / 2]);
  if (len < 200) return ([l0 + 32, l1 - 32], [l0 + len / 2]);
  final dowels = [l0 + 32, l1 - 32];
  final a = l0 + 96, b = l1 - 96;
  final n = math.max(1, ((b - a) / 400).ceil());
  final screws = [for (var i = 0; i <= n; i++) a + (b - a) * i / n];
  // jonctions longues : un tourillon entre deux vis
  if (len > 600) {
    for (var i = 0; i < screws.length - 1; i++) {
      dowels.add((screws[i] + screws[i + 1]) / 2);
    }
  }
  return (dowels, screws);
}

/// Longueur de coulisse du commerce pour une profondeur utile [depth] (mm).
int slideLength(double depth) {
  const sizes = [250, 300, 350, 400, 450, 500, 550, 600];
  var best = sizes.first;
  for (final s in sizes) {
    if (s <= depth - 10) best = s;
  }
  return best;
}

/// Nombre de charnières pour une porte de hauteur [h].
int hingeCount(double h) => h <= 900 ? 2 : h <= 1600 ? 3 : h <= 2000 ? 4 : 5;

/// Entraxe de poignée selon la largeur de la façade.
int handleSpacing(double width) => width < 250 ? 96 : width < 450 ? 128 : width < 900 ? 160 : 320;

// ------------------------------------------------------------------ analyse

MachiningSummary computeMachiningElements(List<ArtPanel> panels, {ArtFittings? fittings, Map<String, String> jointCuts = const {}, Map<String, String> jointFits = const {}}) {
  final fit = fittings ?? ArtFittings();
  final els = <MachiningElement>[];
  // onglets à 45° : les deux pièces se rejoignent dans l'angle → lamelles collées le long de l'onglet
  for (final e in jointCuts.entries.where((e) => e.value == 'onglet')) {
    final ids = e.key.split('|');
    final a = panels.where((p) => p.id == ids[0]).firstOrNull, b = panels.where((p) => p.id == ids[1]).firstOrNull;
    if (a == null || b == null) continue;
    final ov = [for (var k = 0; k < 3; k++) math.min(_hi(a, k), _hi(b, k)) - math.max(_lo(a, k), _lo(b, k))];
    if (ov.any((v) => v <= 0)) continue;
    final lAx = [0, 1, 2].reduce((m, k) => ov[k] > ov[m] ? k : m);
    final c = {for (var k = 0; k < 3; k++) k: (math.max(_lo(a, k), _lo(b, k)) + math.min(_hi(a, k), _hi(b, k))) / 2};
    final l0 = math.max(_lo(a, lAx), _lo(b, lAx)), l1 = math.min(_hi(a, lAx), _hi(b, lAx));
    final n = math.max(2, ((l1 - l0) / 150).floor());
    for (var k = 0; k < n; k++) {
      c[lAx] = l0 + (l1 - l0) * (k + 0.5) / n;
      els.add(MachiningElement(
          kind: MachiningKind.dowel,
          position: _pt(c),
          normal: _axisV(thicknessAxis(a)),
          length: 56,
          diameter: 4,
          panelId: a.id,
          partnerPanelId: b.id,
          item: 'Lamelle bois n° 20'));
    }
  }
  final work = {for (final p in panels) p.id: PanelWork()};

  // 1. jonctions entre panneaux de structure : chant contre face
  for (var i = 0; i < panels.length; i++) {
    for (var j = i + 1; j < panels.length; j++) {
      final a = panels[i], b = panels[j];
      if (!_structural(a) || !_structural(b)) continue;
      for (var ax = 0; ax < 3; ax++) {
        final aBelow = (_hi(a, ax) - _lo(b, ax)).abs() <= _tol; // a avant b sur cet axe
        final bBelow = (_hi(b, ax) - _lo(a, ax)).abs() <= _tol;
        if (!aBelow && !bBelow) continue;
        final others = [for (var k = 0; k < 3; k++) if (k != ax) k];
        final o1 = _ov(a, b, others[0]), o2 = _ov(a, b, others[1]);
        if (o1 < 12 || o2 < 12) continue;
        // hôte : le panneau qui présente sa face (épaisseur sur cet axe) ; l'autre présente son chant
        final aFace = thicknessAxis(a) == ax, bFace = thicknessAxis(b) == ax;
        if (aFace && bFace) {
          // deux côtés de caissons voisins, face contre face : vis de jonction près des 4 coins
          if (fit.link == LinkType.aucun || o1 < 100 || o2 < 100) continue;
          final plane = aBelow ? _hi(a, ax) : _hi(b, ax);
          final (u, v) = (others[0], others[1]);
          final u0 = math.max(_lo(a, u), _lo(b, u)), u1 = math.min(_hi(a, u), _hi(b, u));
          final v0 = math.max(_lo(a, v), _lo(b, v)), v1 = math.min(_hi(a, v), _hi(b, v));
          final us = (u1 - u0) > 250 ? [u0 + 50, u1 - 50] : [(u0 + u1) / 2];
          final vs = (v1 - v0) > 250 ? [v0 + 50, v1 - 50] : [(v0 + v1) / 2];
          for (final uu in us) {
            for (final vv in vs) {
              els.add(MachiningElement(
                  kind: MachiningKind.connector,
                  position: _pt({ax: plane, u: uu, v: vv}),
                  normal: _axisV(ax, aBelow ? 1 : -1),
                  length: 30,
                  diameter: 5,
                  panelId: a.id,
                  partnerPanelId: b.id,
                  item: fit.link.item));
            }
          }
          continue;
        }
        if (aFace == bFace) continue; // chant contre chant : pas d'assemblage type
        final host = aFace ? a : b, guest = aFace ? b : a;
        final plane = aBelow ? (_hi(a, ax) + _lo(b, ax)) / 2 : (_hi(b, ax) + _lo(a, ax)) / 2;
        // direction du perçage : de l'hôte vers le chant de l'invité
        final sign = (_lo(guest, ax) + _hi(guest, ax)) / 2 > (_lo(host, ax) + _hi(host, ax)) / 2 ? 1.0 : -1.0;
        // longueur de la jonction : la plus grande dimension commune ; l'autre est l'épaisseur de l'invité
        final lAx = o1 >= o2 ? others[0] : others[1];
        final wAx = lAx == others[0] ? others[1] : others[0];
        final l0 = math.max(_lo(a, lAx), _lo(b, lAx)), l1 = math.min(_hi(a, lAx), _hi(b, lAx));
        final wMid = (math.max(_lo(a, wAx), _lo(b, wAx)) + math.min(_hi(a, wAx), _hi(b, wAx))) / 2;
        var (dowels, screws) = _jointStations(l0, l1);
        // assemblage choisi pour cette jonction, sinon le réglage général
        final j = JointType.values.asNameMap()[jointFits[ArtProject.jointKey(a.id, b.id)]] ?? fit.joint;
        if (j == JointType.tourillons) {
          // collé seulement : un tourillon à chaque station
          dowels = [...dowels, ...screws];
          screws = const [];
        }
        if (j == JointType.lamello) {
          // lamelles tous les 150 mm environ, au lieu des tourillons et des vis
          final n = math.max(2, ((l1 - l0) / 150).floor());
          dowels = [for (var k = 0; k < n; k++) l0 + (l1 - l0) * (k + 0.5) / n];
          screws = const [];
        }
        if (j == JointType.pocket) dowels = const []; // la vis de poche tient seule, posée de biais
        final (screwLen, screwDia) = switch (j) {
          JointType.confirmat70 => (70.0, 7.0),
          JointType.minifix => (34.0, 15.0),
          JointType.visBois => (40.0, 4.0),
          JointType.euro => (13.0, 6.3),
          JointType.pocket => (30.0, 4.0),
          _ => (50.0, 7.0),
        };
        for (final s in dowels) {
          els.add(MachiningElement(
              kind: MachiningKind.dowel,
              position: _pt({ax: plane, lAx: s, wAx: wMid}),
              normal: _axisV(ax, sign),
              length: j == JointType.lamello ? 56 : 35,
              diameter: j == JointType.lamello ? 4 : 8,
              panelId: host.id,
              partnerPanelId: guest.id,
              item: j == JointType.lamello ? 'Lamelle bois n° 20' : 'Tourillons bois Ø8 x 35 mm'));
        }
        for (final s in screws) {
          els.add(MachiningElement(
              kind: MachiningKind.screw,
              position: _pt({ax: plane, lAx: s, wAx: wMid}),
              normal: _axisV(ax, sign),
              length: screwLen,
              diameter: screwDia,
              panelId: host.id,
              partnerPanelId: guest.id,
              item: j.screw));
        }
      }
    }
  }

  // 2. fonds minces : encastrés en rainure, sinon cloués au dos
  for (final f in panels.where(_thinBack)) {
    var grooved = false;
    for (final s in panels.where(_structural)) {
      final ix = _ov(f, s, 0), iy = _ov(f, s, 1), iz = _ov(f, s, 2);
      if (ix > 0.5 && iy > 0.5 && iz > 0.5) {
        // le fond pénètre le panneau : rainure le long de l'intersection
        final sizes = [ix, iy, iz];
        final lAx = [0, 1, 2].reduce((m, k) => sizes[k] > sizes[m] ? k : m);
        final depthAx = thicknessAxis(s) == lAx ? [0, 1, 2].firstWhere((k) => k != lAx && k != thicknessAxis(f)) : thicknessAxis(s);
        final start = {
          for (var k = 0; k < 3; k++) k: math.max(_lo(f, k), _lo(s, k)),
        };
        start[thicknessAxis(f)] = (math.max(_lo(f, thicknessAxis(f)), _lo(s, thicknessAxis(f))) +
                math.min(_hi(f, thicknessAxis(f)), _hi(s, thicknessAxis(f)))) /
            2;
        els.add(MachiningElement(
            kind: MachiningKind.groove,
            position: _pt(start),
            normal: _axisV(lAx),
            length: sizes[lAx],
            diameter: (f.thickness + 0.5),
            panelId: s.id,
            partnerPanelId: f.id));
        final w = work[s.id]!;
        final sAx = [0, 1, 2].where((k) => k != thicknessAxis(s)).toList();
        final longAx = _size(s, sAx[0]) >= _size(s, sAx[1]) ? sAx[0] : sAx[1];
        if (lAx == longAx) {
          w.grooveLong = 1;
        } else {
          w.grooveShort = 1;
        }
        assert(depthAx >= 0);
        grooved = true;
      }
    }
    if (grooved) continue;
    // fond appliqué au dos : pointes tous les 150 mm sur les chants des panneaux qu'il couvre
    final ft = thicknessAxis(f);
    for (final s in panels.where(_structural)) {
      final touching = (_lo(f, ft) - _hi(s, ft)).abs() <= _tol || (_hi(f, ft) - _lo(s, ft)).abs() <= _tol;
      if (!touching) continue;
      final others = [for (var k = 0; k < 3; k++) if (k != ft) k];
      final o1 = _ov(f, s, others[0]), o2 = _ov(f, s, others[1]);
      if (o1 < 8 || o2 < 8) continue;
      final lAx = o1 >= o2 ? others[0] : others[1];
      final wAx = lAx == others[0] ? others[1] : others[0];
      final l0 = math.max(_lo(f, lAx), _lo(s, lAx)), l1 = math.min(_hi(f, lAx), _hi(s, lAx));
      final wMid = (math.max(_lo(f, wAx), _lo(s, wAx)) + math.min(_hi(f, wAx), _hi(s, wAx))) / 2;
      final plane = (_lo(f, ft) - _hi(s, ft)).abs() <= _tol ? _lo(f, ft) : _hi(f, ft);
      final n = math.max(2, ((l1 - l0) / 150).ceil());
      for (var k = 0; k < n; k++) {
        els.add(MachiningElement(
            kind: MachiningKind.nail,
            position: _pt({ft: plane, lAx: l0 + 30 + (l1 - l0 - 60) * k / (n - 1), wAx: wMid}),
            normal: _axisV(ft, _lo(f, ft) >= _hi(s, ft) - _tol ? -1 : 1),
            length: 20,
            diameter: 3,
            panelId: f.id,
            partnerPanelId: s.id));
      }
    }
  }

  // panneaux de structure au contact d'une façade (côté intérieur de la façade)
  List<ArtPanel> behind(ArtPanel front) => [
        for (final s in panels.where(_structural))
          if ((s.z - front.back).abs() <= 25 && _ov(s, front, 1) > 20 && _ov(s, front, 0) > 0) s,
      ];
  ArtPanel? sideAt(ArtPanel front, double x, {required bool left}) {
    ArtPanel? best;
    for (final s in panels.where((s) => _structural(s) && thicknessAxis(s) == 0)) {
      if ((s.z - front.back).abs() > 25 || _ov(s, front, 1) < 20) continue;
      if (s.right < front.x - 30 || s.x > front.right + 30) continue;
      final d = left ? (s.right - x).abs() : (s.x - x).abs();
      final bd = best == null ? double.infinity : (left ? (best.right - x).abs() : (best.x - x).abs());
      if (d < bd && d <= 40) best = s;
    }
    return best;
  }

  // 3. façades : charnières, coulisses, compas, poignées
  for (final f in panels.where((p) => p.role.isFront)) {
    final backZ = f.back;
    switch (f.role) {
      case ArtRole.porte:
        final ht = HingeType.values.where((h) => h.name == f.hingeType).firstOrNull ?? fit.hinge;
        if (ht == HingeType.piano) {
          // charnière continue sur toute la hauteur, vissée sur le chant du côté
          els.add(MachiningElement(
              kind: MachiningKind.hingePlate,
              position: V3(f.hinge != 'right' ? f.x : f.right, f.y + 10, backZ),
              normal: const V3(0, 1, 0),
              length: f.h - 20,
              diameter: 3,
              panelId: f.id,
              item: ht.label));
          break;
        }
        if (ht == HingeType.pushOpen) {
          els.add(MachiningElement(
              kind: MachiningKind.latch,
              position: V3(f.hinge != 'right' ? f.right - 40 : f.x + 40, f.y + f.h / 2, backZ + 10),
              normal: const V3(0, 0, 1),
              length: 40,
              diameter: 10,
              panelId: f.id,
              item: 'Poussoir d’ouverture (push-to-open) + butée'));
        }
        final n = hingeCount(f.h);
        final left = f.hinge != 'right';
        final edgeX = left ? f.x + 22.5 : f.right - 22.5;
        final side = sideAt(f, left ? f.x : f.right, left: left);
        for (var k = 0; k < n; k++) {
          final y = f.y + 100 + (f.h - 200) * k / (n - 1);
          els.add(MachiningElement(
              kind: MachiningKind.hingeCup,
              position: V3(edgeX, y, backZ),
              normal: const V3(0, 0, -1),
              length: ht.cup == 0 ? 0 : 13,
              diameter: ht.cup.toDouble(),
              panelId: f.id,
              partnerPanelId: side?.id,
              item: ht.label));
          if (side != null) {
            final faceX = left ? side.right : side.x;
            els.add(MachiningElement(
                kind: MachiningKind.hingePlate,
                position: V3(faceX, y, side.z + 37),
                normal: _axisV(0, left ? 1 : -1),
                length: 12,
                diameter: 5,
                panelId: side.id,
                partnerPanelId: f.id));
          }
        }
      case ArtRole.tiroir:
        final l = sideAt(f, f.x, left: true), r = sideAt(f, f.right, left: false);
        final carcass = behind(f);
        final depth = carcass.isEmpty ? 450.0 : carcass.map((s) => s.back).reduce(math.max) - backZ;
        final sl = slideLength(depth).toDouble();
        final y = f.y + math.min(f.h / 2, 45);
        for (final (s, faceX) in [(l, l?.right ?? f.x + 18), (r, r?.x ?? f.right - 18)]) {
          els.add(MachiningElement(
              kind: MachiningKind.slide,
              position: V3(faceX, y, backZ + 3),
              normal: const V3(0, 0, 1),
              length: sl,
              diameter: 13,
              panelId: s?.id,
              partnerPanelId: f.id));
        }
      case ArtRole.abattant:
        final up = f.top > 1400; // meuble haut : abattant relevable
        for (final x in [f.x + 22.5, f.right - 22.5]) {
          els.add(MachiningElement(
              kind: MachiningKind.hingeCup,
              position: V3(x, up ? f.top - 22.5 : f.y + 22.5, backZ),
              normal: const V3(0, 0, -1),
              length: 13,
              diameter: 35,
              panelId: f.id));
        }
        final l = sideAt(f, f.x, left: true), r = sideAt(f, f.right, left: false);
        for (final (s, x) in [(l, l?.right ?? f.x + 18), (r, r?.x ?? f.right - 18)]) {
          els.add(MachiningElement(
              kind: MachiningKind.flapStay,
              position: V3(x, f.y + f.h / 2, backZ + 60),
              normal: const V3(0, 1, 0),
              length: math.min(250, f.h * 0.6),
              diameter: 10,
              panelId: s?.id,
              partnerPanelId: f.id));
        }
      default:
        break;
    }
    // poignée, côté visible de la façade (sauf porte à poussoir)
    if (f.role == ArtRole.porte &&
        (HingeType.values.where((h) => h.name == f.hingeType).firstOrNull ?? fit.hinge) == HingeType.pushOpen) {
      continue;
    }
    final cc = handleSpacing(f.role == ArtRole.porte ? f.h : f.w).toDouble();
    if (f.role == ArtRole.porte) {
      final x = f.hinge == 'right' ? f.x + 40 : f.right - 40;
      // haut de cuisine : poignée en bas ; bas : en haut ; colonne : à hauteur de main
      final yc = f.y > 1200
          ? f.y + 50 + cc / 2
          : f.top < 1000
              ? f.top - 50 - cc / 2
              : (1050.0).clamp(f.y + cc / 2 + 50, f.top - cc / 2 - 50);
      final c = math.min(cc, f.h - 100);
      els.add(MachiningElement(
          kind: MachiningKind.handle, position: V3(x, yc - c / 2, f.z), normal: const V3(0, 1, 0), length: c, diameter: 4, panelId: f.id));
    } else {
      final c = math.min(cc, f.w - 80);
      final y = f.role == ArtRole.abattant
          ? (f.top > 1400 ? f.y + 40 : f.top - 40)
          : (f.h > 250 ? f.top - 45 : f.y + f.h / 2);
      els.add(MachiningElement(
          kind: MachiningKind.handle,
          position: V3(f.x + f.w / 2 - c / 2, y, f.z),
          normal: const V3(1, 0, 0),
          length: c,
          diameter: 4,
          panelId: f.id));
    }
  }

  // 4. tablettes mobiles (posées entre deux montants sans les toucher) : taquets et perçages système 32
  for (final t in panels.where((p) => _structural(p) && thicknessAxis(p) == 1)) {
    final sides = panels.where((s) => _structural(s) && thicknessAxis(s) == 0 && _ov(s, t, 1) > 0 && _ov(s, t, 2) > 40).toList();
    ArtPanel? l, r;
    for (final s in sides) {
      final gl = t.x - s.right, gr = s.x - t.right;
      if (gl > -0.6 && gl <= 4 && (l == null || gl < t.x - l.right)) l = s;
      if (gr > -0.6 && gr <= 4 && (r == null || gr < r.x - t.right)) r = s;
    }
    if (l == null || r == null) continue;
    final jointed = (t.x - l.right).abs() <= _tol && (r.x - t.right).abs() <= _tol;
    if (jointed) continue; // tablette fixe : déjà assemblée par tourillons et vis
    for (final (s, faceX) in [(l, l.right), (r, r.x)]) {
      for (final zz in [math.max(s.z, t.z) + 37, math.min(s.back, t.back) - 37]) {
        els.add(MachiningElement(
            kind: MachiningKind.shelfPin, position: V3(faceX, t.y, zz), normal: _axisV(0, s == l ? 1 : -1), length: 10, diameter: 5, panelId: t.id, partnerPanelId: s.id));
        // une rangée de 7 trous (± 96 mm) pour régler la hauteur
        for (var k = -3; k <= 3; k++) {
          final y = t.y + k * 32;
          if (y < s.y + 40 || y > s.top - 40) continue;
          els.add(MachiningElement(
              kind: MachiningKind.shelfHole, position: V3(faceX, y, zz), normal: _axisV(0, s == l ? 1 : -1), length: 12, diameter: 5, panelId: s.id));
        }
      }
    }
  }

  // 5. pieds : dessous de caisson surélevé (50 à 250 mm du sol) sans rien dessous
  for (final b in panels.where((p) => fit.foot != FootType.socle && _structural(p) && thicknessAxis(p) == 1 && p.y >= 50 && p.y <= 250)) {
    final under = panels.any((o) => !identical(o, b) && _structural(o) && o.y < b.y - _tol && _ov(o, b, 0) > 40 && _ov(o, b, 2) > 40 && o.top > 30);
    if (under) continue;
    final nx = math.max(2, (b.w / 900).ceil() + 1);
    for (var k = 0; k < nx; k++) {
      final x = b.x + 50 + (b.w - 100) * k / (nx - 1);
      for (final z in [b.z + 50, b.back - 50]) {
        els.add(MachiningElement(
            kind: MachiningKind.foot, position: V3(x, b.y, z), normal: const V3(0, -1, 0), length: b.y, diameter: 30, panelId: b.id, item: fit.foot.item));
      }
    }
  }

  // 5 bis. meubles hauts : côtés en l'air (à plus de 300 mm du sol, rien dessous) → suspension au mur
  final hanging = [
    for (final s in panels.where((p) => _structural(p) && thicknessAxis(p) == 0 && p.y >= 300))
      if (!panels.any((o) => !identical(o, s) && _structural(o) && o.top <= s.y + _tol && o.top >= s.y - 30 && _ov(o, s, 0) > 0 && _ov(o, s, 2) > 40)) s,
  ]..sort((a, b) => a.x.compareTo(b.x));
  for (final s in hanging) {
    // fixation côté intérieur du caisson : à droite d'un côté gauche, à gauche d'un côté droit
    final partner = hanging.where((o) => !identical(o, s) && _ov(o, s, 1) > 100).fold<ArtPanel?>(null, (best, o) {
      final d = (o.x - s.x).abs();
      return best == null || d < (best.x - s.x).abs() ? o : best;
    });
    final inward = partner == null ? 1.0 : (partner.x > s.x ? 1.0 : -1.0);
    els.add(MachiningElement(
        kind: MachiningKind.hanger,
        position: V3(inward > 0 ? s.right : s.x, s.top - 40, s.back - 20),
        normal: _axisV(0, inward),
        length: 40,
        diameter: 20,
        panelId: s.id,
        partnerPanelId: partner?.id,
        item: fit.hang.item));
  }

  // 5 ter. perçages posés à la main
  for (final p in panels) {
    for (final h in p.holes) {
      els.add(MachiningElement(
          kind: MachiningKind.drill,
          position: V3(p.x + h.dx, p.y + h.dy, p.z + h.dz),
          normal: _axisV(h.axis, -h.sign.toDouble()),
          length: h.depth,
          diameter: h.dia,
          panelId: p.id));
    }
  }

  // 6. chants : arêtes visibles
  for (final p in panels) {
    if (_thinBack(p)) continue;
    final ta = thicknessAxis(p);
    final inPlane = [for (var k = 0; k < 3; k++) if (k != ta) k];
    final longAx = _size(p, inPlane[0]) >= _size(p, inPlane[1]) ? inPlane[0] : inPlane[1];
    final th = p.role.isFront || p.role == ArtRole.decor || p.role == ArtRole.plateau ? 2.0 : 1.0;
    final w = work[p.id]!;
    for (final ax in inPlane) {
      for (final s in const [-1.0, 1.0]) {
        if (!p.role.isFront && ax == 2 && s > 0) continue; // arête du dos : contre le mur
        final plane = s > 0 ? _hi(p, ax) : _lo(p, ax);
        // couverte par un autre panneau collé contre elle ?
        final along = inPlane.firstWhere((k) => k != ax);
        var covered = 0.0;
        for (final o in panels) {
          if (identical(o, p) || _thinBack(o) || o.role.isFront) continue; // une porte fermée ne remplace pas le chant
          final touch = s > 0 ? (_lo(o, ax) - plane).abs() <= _tol : (_hi(o, ax) - plane).abs() <= _tol;
          if (!touch) continue;
          if (_ov(o, p, ta) < p.thickness * 0.6) continue;
          covered += _ov(o, p, along);
        }
        if (!p.role.isFront && covered >= _size(p, along) * 0.5) continue;
        final start = <int, double>{ax: plane, ta: (_lo(p, ta) + _hi(p, ta)) / 2, along: _lo(p, along)};
        els.add(MachiningElement(
            kind: MachiningKind.edge,
            position: _pt(start),
            normal: _axisV(along),
            length: _size(p, along),
            diameter: th,
            panelId: p.id));
        if (along == longAx) {
          w.edgeLong++;
        } else {
          w.edgeShort++;
        }
        w.edgeThickness = th;
      }
    }
  }

  return MachiningSummary(els, work, machiningHardware(els, fittings: fit));
}

/// Liste de quincaillerie et visserie déduite des usinages.
List<(String, String, int)> machiningHardware(List<MachiningElement> els, {ArtFittings? fittings}) {
  final fit = fittings ?? ArtFittings();
  final out = <String, (String, int)>{};
  void add(String name, String usage, int q) {
    if (q > 0 && name.isNotEmpty) out[name] = (out[name]?.$1 ?? usage, (out[name]?.$2 ?? 0) + q);
  }

  int n(MachiningKind k) => els.where((e) => e.kind == k).length;
  // pièces posées une à une, par désignation
  const usage = {
    MachiningKind.dowel: 'jonctions entre panneaux, avec colle',
    MachiningKind.screw: 'jonctions entre panneaux',
    MachiningKind.hingeCup: 'portes et abattants',
    MachiningKind.hingePlate: 'portes',
    MachiningKind.foot: 'dessous de caisson',
    MachiningKind.hanger: 'meubles hauts fixés au mur',
    MachiningKind.connector: 'caissons voisins assemblés côte à côte',
    MachiningKind.latch: 'portes sans poignée',
  };
  for (final e in els) {
    final u = usage[e.kind];
    if (u == null) continue;
    final name = e.item ??
        switch (e.kind) {
          MachiningKind.dowel => 'Tourillons bois Ø8 x 35 mm',
          MachiningKind.screw => 'Vis Confirmat Ø7 x 50 mm',
          MachiningKind.hingeCup => 'Charnière 110° frein intégré Ø35 + embase',
          MachiningKind.foot => 'Pieds réglables 100 à 150 mm',
          _ => '',
        };
    if (e.kind == MachiningKind.hingePlate && e.item == null) continue; // embase : livrée avec la charnière
    add(name, u, 1);
  }
  final screws = els.where((e) => e.kind == MachiningKind.screw && (e.item ?? '').startsWith('Vis Confirmat')).length;
  add('Cache-vis Confirmat', 'têtes de vis visibles', screws);
  add('Pointes 3 x 20 mm', 'fonds cloués', n(MachiningKind.nail));
  add('Vis aggloméré Ø3,5 x 16 mm', 'charnières, embases et coulisses', n(MachiningKind.hingeCup) * 2 + n(MachiningKind.hingePlate) * 2 + n(MachiningKind.slide) * 6);
  add('Compas d’abattant freiné', 'abattants', n(MachiningKind.flapStay));
  final slides = <int, int>{};
  for (final e in els.where((e) => e.kind == MachiningKind.slide)) {
    slides[e.length.round()] = (slides[e.length.round()] ?? 0) + 1;
  }
  for (final s in slides.entries) {
    add(L('Paire de coulisses à billes {0} mm', [s.key]), 'tiroirs', (s.value / 2).ceil());
  }
  final handles = <int, int>{};
  for (final e in els.where((e) => e.kind == MachiningKind.handle)) {
    handles[e.length.round()] = (handles[e.length.round()] ?? 0) + 1;
  }
  for (final h in handles.entries) {
    add(L('Poignée entraxe {0} mm + 2 vis M4', [h.key]), 'façades', h.value);
  }
  add('Taquets d’étagère Ø5', 'tablettes mobiles', n(MachiningKind.shelfPin));
  // accessoires liés : clips de plinthe (pieds de devant), rail et vis de suspension, chevilles
  final feet = n(MachiningKind.foot);
  if (fit.foot.clip.isNotEmpty) add(fit.foot.clip, 'plinthe sur les pieds de devant', (feet / 2).ceil());
  final hangers = n(MachiningKind.hanger);
  if (hangers > 0) {
    if (fit.hang.rail.isNotEmpty) add(L('{0} (1 par meuble haut)', [fit.hang.rail]), 'meubles hauts', (hangers / 2).ceil());
    add('Chevilles Ø8 + vis Ø5 x 60 mm', 'fixation murale', hangers * (fit.hang == HangType.tasseau ? 3 : 2));
  }
  return [for (final e in out.entries) (e.key, e.value.$1, e.value.$2)];
}


// ------------------------------------------------------------------ contrôles avant débit

/// Problème relevé sur les panneaux avant de les débiter.
class ArtCheck {
  final bool error; // bloquant (sinon : à vérifier)
  final String message;
  final List<String> panelIds;
  const ArtCheck(this.error, this.message, this.panelIds);
}

/// Contrôles de fabrication : panneaux qui se chevauchent, plus grands que la feuille, épaisseur différente
/// de la matière choisie, pièces trop petites pour la scie, panneaux posés en l'air sans rien qui les tienne.
List<ArtCheck> artChecks(List<ArtPanel> panels, CutSettings cs, {Map<String, String> jointCuts = const {}}) {
  final out = <ArtCheck>[];
  String n(ArtPanel p) => L(p.role.label);
  for (var i = 0; i < panels.length; i++) {
    final a = panels[i];
    for (var j = i + 1; j < panels.length; j++) {
      final b = panels[j];
      final ox = _ov(a, b, 0), oy = _ov(a, b, 1), oz = _ov(a, b, 2);
      if (ox <= 0.5 || oy <= 0.5 || oz <= 0.5) continue;
      // un fond mince encastré dans une rainure (jusqu'à 12 mm) est voulu, comme l'angle commun d'un onglet
      if (jointCuts[ArtProject.jointKey(a.id, b.id)] == 'onglet') continue;
      final thin = _thinBack(a) || _thinBack(b);
      if (thin && math.min(ox, math.min(oy, oz)) <= 12.5) continue;
      out.add(ArtCheck(true, L('{0} et {1} se chevauchent ({2} mm) : ils ne peuvent pas être fabriqués ainsi', [n(a), n(b), math.min(ox, math.min(oy, oz)).round()]),
          [a.id, b.id]));
    }
  }
  for (final p in panels) {
    final dims = [p.w, p.h, p.d]..sort();
    final len = dims[2], wid = dims[1], th = dims[0];
    final pp = ArtProject.panelOf(p);
    final mat = ArtProject.materialOf(p);
    final (sl, sw) = cs.sheetDimensionsFor(mat);
    final maxL = sl - 2 * cs.trim, maxW = sw - 2 * cs.trim;
    final fits = (len <= maxL && wid <= maxW) || (ArtProject.hasGrain(p) ? false : (len <= maxW && wid <= maxL));
    if (!fits) {
      out.add(ArtCheck(true, L('{0} {1} × {2} mm : plus grand que la feuille {3} × {4} (recoupe déduite)', [n(p), len.round(), wid.round(), sl, sw]), [p.id]));
    }
    if (pp != null && (th - pp.thickness).abs() > 0.5) {
      out.add(ArtCheck(true, L('{0} de {1} mm dans une matière de {2} mm ({3})', [n(p), th.round(), pp.thickness, L(pp.name)]), [p.id]));
    }
    if (wid < 50) {
      out.add(ArtCheck(false, L('{0} de {1} mm de large : trop étroit pour la scie à panneaux (50 mm au moins)', [n(p), wid.round()]), [p.id]));
    }
  }
  // panneau isolé : rien ne le touche (ni le sol)
  for (final p in panels) {
    if (p.y < 0.6) continue;
    final touching = panels.any((o) {
      if (identical(o, p)) return false;
      // collé ou encastré : l'écart est nul ou négatif sur les trois axes
      for (var ax = 0; ax < 3; ax++) {
        final gap = math.max(_lo(o, ax) - _hi(p, ax), _lo(p, ax) - _hi(o, ax));
        if (gap > 4) return false; // jusqu'à 4 mm : tablette mobile sur taquets
      }
      return true;
    });
    if (!touching) out.add(ArtCheck(false, L('{0} ne touche aucun autre panneau : comment est-il fixé ?', [n(p)]), [p.id]));
  }
  return out;
}
