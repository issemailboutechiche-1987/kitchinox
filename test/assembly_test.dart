// Visserie, fixations et pose : diamètres x longueurs, quantités d'après les caissons et le débit.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  test('cuisine : Confirmat 7 x 50, vis de charnière 3,5 x 16, rail mural, anti-basculement, équerres de plan', () {
    final e = LayoutEngine(cat, Project(room: Room(width: 4200, depth: 3200, height: 2600)));
    e.add('base_standard_single_door', 'A', s: 0, width: 600);
    e.add('base_drawers_multi', 'A', s: 600, width: 600);
    e.add('wall_standard_single_door', 'A', s: 0, width: 600);
    e.add('tall_pantry', 'A', s: 2000, width: 600);
    final parts = cutList(e, e.project.cut, const {});
    final a = assemblyList(e, parts);
    AssemblyItem item(String start) => a.firstWhere((x) => x.name.startsWith(start));
    expect(item('Vis d’assemblage Confirmat Ø7 x 50').qty, greaterThan(20));
    expect(item('Cache-vis Confirmat').qty, greaterThan(0));
    expect(item('Vis aggloméré Ø3,5 x 16').qty, greaterThanOrEqualTo(4 * 2));
    expect(item('Vis de liaison de caissons').qty, greaterThan(0));
    expect(item('Rail de suspension mural').qty, 1);
    expect(item('Chevilles nylon Ø8 x 50').qty, greaterThan(0));
    expect(item('Équerre anti-basculement').qty, 2);
    expect(item('Équerres de fixation de plan de travail').qty, 6);
    expect(a.every((x) => x.usage.isNotEmpty && x.qty > 0), isTrue);
    // dans l'estimation (fournitures du plan d'exécution), non chiffré
    final lines = assemblySupplyLines(e, parts);
    expect(lines.map((l) => l.section).toSet(), {'Visserie et fixations', 'Pose'});
    expect(lines.every((l) => l.unitPrice.isZero), isTrue);
  });

  test('salle de bain : pas d’équerres de plan de travail, silicone anti-moisissure', () {
    final u = FurnitureUniverse.parse('bain', File('assets/data/furniture/bain.json').readAsStringSync());
    final e = LayoutEngine(universeCatalog(u), Project(universe: 'bain'));
    e.add('bath_vanity_single_basin_wall_hung', 'A');
    final a = assemblyList(e, cutList(e, e.project.cut, const {}));
    expect(a.any((x) => x.name.startsWith('Équerres de fixation de plan')), isFalse);
    expect(a.any((x) => x.name.contains('anti-moisissure')), isTrue);
    expect(a.any((x) => x.name.startsWith('Rail de suspension')), isTrue);
  });
}
