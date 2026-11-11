// Tarif fournisseur (devis réel) : les formules retrouvent les prix des lignes du devis.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

void main() {
  final t = SupplierTariff.parse(File('assets/data/supplier_prices.json').readAsStringSync());
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  test('formules calées sur le devis (à 5 % près)', () {
    void near(double got, double want) => expect((got - want).abs() / want, lessThan(0.05), reason: '$got ≠ $want');
    near(t.wallA + t.wallB * 0.6, 749);
    near(t.wallA + t.wallB * 0.4, 610);
    near(t.baseA + t.baseB * 0.6, 1020);
    near(t.baseA + t.baseB * 0.4, 820);
    near(t.front(0.42, gloss: false), 153);
    near(t.front(0.28, gloss: false), 108);
    near(t.front(0.42, gloss: true), 194);
    near(t.front(1.2, gloss: true), 524);
  });

  test('devis d\'une petite cuisine : caissons, façades, tiroirs, remise 15 %', () {
    final e = LayoutEngine(cat, Project(room: Room(width: 4200, depth: 3200, height: 2600)));
    e.add('base_standard_single_door', 'A', s: 0, width: 600);
    e.add('base_drawers_multi', 'A', s: 600, width: 600);
    e.add('wall_standard_single_door', 'A', s: 0, width: 600, z: 1500);
    final q = supplierQuote(e, t);
    expect(q.lines.where((l) => l.section == 'Caissons').fold<double>(0, (s, l) => s + l.qty), 3);
    expect(q.lines.any((l) => l.section == 'Tiroirs'), isTrue);
    expect(q.net, closeTo(q.gross * 0.85, q.gross * 0.01));
    expect(q.net, greaterThan(2500));
  });

  test('gamme luxe : caissons et façades à l’article, plus de panneaux à la feuille', () {
    String f(String n) => File('assets/data/$n.json').readAsStringSync();
    final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'));
    final e = LayoutEngine(cat, Project(room: Room(width: 4200, depth: 3200, height: 2600)));
    e.add('base_standard_single_door', 'A', s: 0, width: 600);
    e.add('wall_standard_single_door', 'A', s: 0, width: 600, z: 1500);
    final plan = nest(cutList(e, e.project.cut, const {}), e.project.cut);
    final bom = buildBom(e);
    final std = quoteLines(e, db, e.project.specs, plan, bom, t);
    expect(std.any((l) => l.section == 'Panneaux'), isTrue);
    expect(std.any((l) => l.section == 'Caissons'), isFalse);
    e.project.specs.gamme = 'luxe';
    final lux = quoteLines(e, db, e.project.specs, plan, bom, t);
    expect(lux.any((l) => l.section == 'Panneaux' || l.section == 'Chants'), isFalse);
    expect(lux.where((l) => l.section == 'Caissons').length, 2);
    expect(ProjectSpecs.fromJson(e.project.specs.toJson()).gamme, 'luxe');
  });
}
