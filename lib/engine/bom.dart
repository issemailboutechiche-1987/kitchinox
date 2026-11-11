/// Récapitulatif (nomenclature) : caissons regroupés, plan de travail, plinthes, joues à prévoir.
library;

import 'catalog.dart';
import 'end_panels.dart';
import 'kitchen_fixtures.dart';
import 'layout_engine.dart';
import 'openings_catalog.dart';
import 'project.dart';
import 'room_objects.dart';

class BomLine {
  final String section;
  final String ref;
  final String name;
  final String dims;
  final String details;
  final int qty;
  final String unit;
  const BomLine(this.section, this.ref, this.name, this.dims, this.details, this.qty, [this.unit = 'pce']);
}

class Bom {
  final List<BomLine> lines;
  final double worktopLength; // mm
  final double plinthLength; // mm
  final int cabinetCount;
  const Bom(this.lines, this.worktopLength, this.plinthLength, this.cabinetCount);

  String toCsv() {
    String cell(Object v) {
      final s = '$v';
      return s.contains(';') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final rows = [
      ['section', 'reference', 'designation', 'dimensions_mm', 'details', 'quantite', 'unite'],
      for (final l in lines) [l.section, l.ref, l.name, l.dims, l.details, l.qty, l.unit],
    ];
    return '﻿${rows.map((r) => r.map(cell).join(';')).join('\r\n')}\r\n';
  }
}

const _optionLabels = {
  'hinged_left': 'charnières à gauche',
  'hinged_right': 'charnières à droite',
  'double_hinged': '2 portes',
  'pullout': 'coulissant',
  'gas_strut_lift': 'vérins à gaz',
  'bifold_lift': 'relevant pliant',
  '2_deep_drawers': '2 casseroliers',
  '3_drawers_equal': '3 tiroirs égaux',
  '1_low_2_deep': '1 tiroir + 2 casseroliers',
  '4_drawers': '4 tiroirs',
  '50_50': 'portes 50/50',
  '70_30': 'portes 70/30',
  'single_door': 'porte unique',
};

String optionLabel(String? k) => k == null ? '' : (_optionLabels[k] ?? k.replaceAll('_', ' '));

/// Profondeur du plan de travail (caisson 600 + débord de 20 en façade).
const worktopDepth = 620;

Bom buildBom(LayoutEngine e) {
  final p = e.project;
  final std = p.standards;
  final lines = <BomLine>[];

  // ---- caissons et finitions posés, regroupés
  final groups = <String, (PlacedCabinet, int)>{};
  for (final c in p.items) {
    final key = [c.modelId, c.width, c.widthRight, c.height, c.opening, c.variant].join('|');
    final g = groups[key];
    groups[key] = (g?.$1 ?? c, (g?.$2 ?? 0) + 1);
  }
  const order = [
    CabinetKind.base,
    CabinetKind.cornerBase,
    CabinetKind.tall,
    CabinetKind.wall,
    CabinetKind.cornerWall,
    CabinetKind.fillerBase,
    CabinetKind.fillerWall,
    CabinetKind.coverPanel,
    CabinetKind.islandPanel,
  ];
  final sorted = groups.values.toList()
    ..sort((a, b) {
      final ka = order.indexOf(e.modelOf(a.$1).kind), kb = order.indexOf(e.modelOf(b.$1).kind);
      if (ka != kb) return ka.compareTo(kb);
      final n = e.modelOf(a.$1).name.compareTo(e.modelOf(b.$1).name);
      return n != 0 ? n : a.$1.width.compareTo(b.$1.width);
    });
  var cabinets = 0;
  for (final (c, n) in sorted) {
    final m = e.modelOf(c);
    final dims = m.shape == CabinetShape.lShape || m.shape == CabinetShape.diagonal
        ? '${c.width}×${c.widthRight} H${c.height} P${c.depth}'
        : '${c.width} × ${c.height} × ${c.depth}';
    final det = [optionLabel(c.opening), optionLabel(c.variant)].where((s) => s.isNotEmpty).join(', ');
    lines.add(BomLine(m.categoryName, m.id, m.name, dims, det, n));
    if (m.isCarcass) cabinets += n;
  }

  // ---- plan de travail et plinthes, mur par mur (l'angle n'est compté qu'une fois)
  double worktop = 0, plinth = 0;
  final worktopParts = <String>[];
  for (final w in p.room.walls.where((w) => w.enabled)) {
    final prev = p.room.prevOf(w.id);
    final prevLow = p.room.isWallEnabled(prev) ? e.runs(prev, (m) => e.kitchen && m.kind.isLow) : const <(double, double)>[];
    final prevLen = p.room.wall(prev).length;
    final prevReachesCorner = prevLow.any((r) => r.$2 >= prevLen - 0.5);

    for (final (a, b) in e.runs(w.id, (m) => e.kitchen && m.kind.isLow)) {
      var len = b - a;
      if (a < 0.5 && prevReachesCorner) len -= worktopDepth; // le plan du mur précédent couvre l'angle
      if (len > 0) {
        worktop += len;
        worktopParts.add('${w.id} ${len.round()}');
      }
    }
    final prevFloor = p.room.isWallEnabled(prev) ? e.runs(prev, (m) => m.floorSupport) : const <(double, double)>[];
    final prevFloorCorner = prevFloor.any((r) => r.$2 >= prevLen - 0.5);
    for (final (a, b) in e.runs(w.id, (m) => m.floorSupport)) {
      var len = b - a;
      if (a < 0.5 && prevFloorCorner) len -= 600;
      if (len > 0) plinth += len;
    }
  }
  final isl = p.room.island;
  if (isl != null) {
    for (final (a, b) in e.runs('I', (m) => e.kitchen && m.kind.isLow)) {
      worktop += b - a;
      worktopParts.add('îlot ${(b - a).round()} x ${(Island.depth + isl.overhang).round()}');
    }
    for (final (a, b) in e.runs('I', (m) => m.floorSupport)) {
      plinth += (b - a) + 2 * Island.depth; // façade + deux côtés
    }
    final islLen = e.runs('I', (m) => e.kitchen && m.kind.isLow).fold<double>(0, (s, r) => s + r.$2 - r.$1);
    if (islLen > 0) {
      lines.add(BomLine('Îlot', 'island_back_panel', 'Habillage arrière d\'îlot', '${islLen.round()} x ${std.baseTop}', '', 1));
      lines.add(BomLine('Îlot', 'cover_panel_side', 'Joue de finition d\'îlot', '${Island.depth.round()} x ${std.baseTop}', 'deux côtés', 2));
    }
  }
  if (worktop > 0) {
    lines.add(BomLine('Plan de travail', 'worktop', 'Plan de travail ${std.worktopThickness} mm',
        '${worktop.round()} × $worktopDepth × ${std.worktopThickness}', 'tronçons : ${worktopParts.join(', ')}', 1, 'lot'));
  }
  if (plinth > 0) {
    lines.add(BomLine('Plinthes', 'plinth', 'Plinthe H${std.plinthHeight}', '${plinth.round()} mm linéaires', '', 1, 'lot'));
  }

  // ---- joues de finition : posées automatiquement aux extrémités visibles (sinon : à prévoir)
  final joues = endPanels(e);
  if (joues.isNotEmpty) {
    final byDims = <String, int>{};
    for (final j in joues) {
      final k = '${j.height.round()} x ${j.depth.round()}|${j.high ? 'haut' : 'bas / colonne'}';
      byDims[k] = (byDims[k] ?? 0) + 1;
    }
    for (final MapEntry(:key, :value) in byDims.entries) {
      final [dims, kind] = key.split('|');
      lines.add(BomLine(p.style.endPanels ? 'Finitions' : 'À prévoir', 'cover_panel_side', 'Joue de finition $kind', '$dims x 18',
          p.style.endPanels ? 'extrémité de linéaire visible, finition des façades' : 'extrémités de linéaire visibles', value));
    }
  }

  // ---- éclairage sous les éléments hauts (et dans les plinthes)
  if (p.style.lighting != 'aucun') {
    var under = 0.0, plinthLed = 0.0;
    for (final w in p.room.walls.where((w) => w.enabled)) {
      for (final (a, b) in e.runs(w.id, (m) => m.kind.isHigh && m.id != 'wall_integrated_hood')) {
        under += b - a;
      }
      for (final (a, b) in e.runs(w.id, (m) => m.floorSupport)) {
        plinthLed += b - a;
      }
    }
    if (p.style.lighting != 'led_hauts_plinthes') plinthLed = 0;
    if (under > 0) {
      lines.add(BomLine('Éclairage', 'led_strip', 'Ruban LED sous éléments hauts (profilé alu + diffuseur)', '${under.round()} mm linéaires',
          'blanc chaud 3000 K, 24 V', 1, 'lot'));
    }
    if (plinthLed > 0) {
      lines.add(BomLine('Éclairage', 'led_plinth', 'Ruban LED de plinthe (étanche IP65)', '${plinthLed.round()} mm linéaires', 'blanc chaud 3000 K, 24 V', 1, 'lot'));
    }
    final watts = (under + plinthLed) / 1000 * 10; // ~10 W par mètre
    if (watts > 0) {
      lines.add(BomLine('Éclairage', 'led_driver', 'Alimentation 24 V et interrupteur / détecteur', '${(watts * 1.25 / 10).ceil() * 10} W', 'marge de 25 %', 1));
    }
  }

  // évier et mitigeur choisis (un par meuble évier)
  final sinks = p.items.where((c) => e.modelOf(c).id == 'base_sink').length;
  if (sinks > 0) {
    final sk = KitchenFixtures.sink(p.style.sink), fc = KitchenFixtures.faucet(p.style.faucet);
    lines.add(BomLine('Équipements cuisine', sk.id, sk.name, '${sk.length} x ${sk.depth} x ${sk.height}',
        p.style.sinkMount == 'undermount' ? 'pose sous plan (découpe polie du plan de travail)' : 'pose à encastrer', sinks));
    lines.add(BomLine('Équipements cuisine', fc.id, fc.name, 'hauteur ${fc.height} mm', 'perçage Ø${fc.hole} mm', sinks));
  }

  // portes et fenêtres : modèle, cotes, composition et quincaillerie (pour la commande au menuisier)
  for (final o in p.openings) {
    final m = openingModelOf(o);
    lines.add(BomLine('Menuiseries', m?.id ?? o.type, openingName(o), '${o.width.round()} x ${o.height.round()}${o.z > 0 ? ' (allège ${o.z.round()})' : ''}',
        [if (m != null) m.mechanismLabel, if (m != null && m.composition['finish'] != null) m.composition['finish']!, 'mur ${o.wallId}', if (m != null && m.hardware.isNotEmpty) m.hardware.join(', ')].join(' · '),
        1));
  }

  // sanitaires et objets posés dans la pièce (fournis à part, pour la pose et la commande)
  final objs = <String, (RoomObject, int)>{};
  for (final o in p.objects) {
    final key = '${o.ref}|${o.w}x${o.d}x${o.h}';
    objs[key] = (objs[key]?.$1 ?? o, (objs[key]?.$2 ?? 0) + 1);
  }
  for (final (o, n) in objs.values) {
    final f = o.fixture;
    lines.add(BomLine(f != null ? 'Sanitaires' : 'Mobilier et décoration', o.ref, objectName(o), '${o.w} x ${o.d} x ${o.h}',
        f != null ? [if (o.z > 0) 'pose à ${o.z.round()} mm du sol', if (f.clearance > 0) '${f.clearance} mm libres devant'].join(', ') : 'mobilier du client, pour l\'implantation',
        n));
  }

  return Bom(lines, worktop, plinth, cabinets);
}
