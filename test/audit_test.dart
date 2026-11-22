// Audit de cohérence : chaque modèle du catalogue et chaque composition proposée respectent les
// règles de fabrication (types de cases par meuble, nombre de cases, tailles minimales) ;
// aucun élément haut ne porte d'appareil ; les compositions de départ sont valides.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  test('catalogue : compositions conformes, pas d\'appareil dans un haut', () {
    final problems = <String>[];
    for (final m in cat.models) {
      if (m.kind.isHigh) {
        if (m.appliances.isNotEmpty && !m.isHoodUnit && !m.isFreeHood) problems.add('${m.id} : appareil dans un haut');
        if (m.frontLayout?.any((r) => r.kind == CellKind.appliance || r.kind == CellKind.drawer) ?? false) {
          problems.add('${m.id} : appareil ou tiroir dans un haut');
        }
      }
      for (final h in m.heights.isRange ? [m.heights.min!] : m.heights.values) {
        if (m.kind.isHigh && h < 600) continue; // niches basses : pas de composition
        final c = PlacedCabinet(uid: 'x', modelId: m.id, wallId: 'A', s: 0, z: 0, width: m.defaultWidth, height: h, depth: m.depth);
        final rows = rowsOf(m, c);
        if (rows != null) {
          final why = layoutProblem(m.kind, rows, h);
          if (why != null) problems.add('${m.id} H$h : $why');
        }
        // la composition de départ (bouton « Personnaliser ») doit être acceptée
        if (m.isCarcass && !m.kind.isCorner && !m.kind.isFiller) {
          final seed = seedRows(m, c);
          final why = layoutProblem(m.kind, seed, h);
          if (why != null) problems.add('${m.id} H$h (départ) : $why');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('compositions proposées : valides aux hauteurs standard', () {
    final problems = <String>[];
    for (final (kind, heights) in [
      (CabinetKind.wall, [600, 750, 800, 1000]),
      (CabinetKind.base, [750]),
      (CabinetKind.tall, [2000, 2200, 2400]),
    ]) {
      for (final h in heights) {
        for (final (name, rows) in frontPresets(kind, h)) {
          final why = layoutProblem(kind, rows, h);
          if (why != null) problems.add('${kind.name} H$h « $name » : $why');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('règles : un haut refuse tiroir et appareil, 3 portes dans un haut sont refusées', () {
    expect(layoutProblem(CabinetKind.wall, [FrontRow(CellKind.appliance)], 800), isNotNull);
    expect(layoutProblem(CabinetKind.wall, [FrontRow(CellKind.drawer)], 800), isNotNull);
    expect(layoutProblem(CabinetKind.wall, [FrontRow(CellKind.door), FrontRow(CellKind.door), FrontRow(CellKind.door)], 1000), isNotNull);
    expect(layoutProblem(CabinetKind.wall, [FrontRow(CellKind.door), FrontRow(CellKind.door)], 800), isNull);
    expect(layoutProblem(CabinetKind.base, [FrontRow(CellKind.flap)], 750), isNotNull);
    expect(layoutProblem(CabinetKind.base, [FrontRow(CellKind.appliance), FrontRow(CellKind.drawer, 210)], 750), isNotNull); // four de 540
  });

  test('contrôles de pro : évier collé à la plaque, four contre le frigo, hotte décentrée', () {
    final e = LayoutEngine(cat, Project(room: Room(width: 4200, depth: 3000, height: 2600)));
    e.add('tall_integrated_fridge', 'A', s: 0, height: 2200);
    e.add('tall_oven_microwave', 'A', s: 600, height: 2200);
    e.add('base_sink', 'A', s: 1200, width: 800);
    e.add('base_cooktop_oven', 'A', s: 2000, width: 600);
    e.add('wall_integrated_hood', 'A', s: 2100, width: 600);
    final codes = designChecks(e).map((i) => i.code).toSet();
    expect(codes, containsAll(['sink_hob_close', 'oven_fridge', 'hood_offset']));
  });
}
