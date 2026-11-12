// Bases matériaux (électroménager, plans de travail, panneaux, quincaillerie) et calculs dérivés.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'));

  test('lecture des 4 bases', () {
    expect(db.appliances.length, 15);
    expect(db.appliances['oven_standard_60']!.niche, (560, 585, 560));
    expect(db.appliances['cooktop_4_burners_60']!.cutout, (560, 490));
    expect(db.appliances['oven_standard_60']!.offers.length, 3);
    expect(db.worktops.length, 5); // marbre, granit, quartz, céramique, solid surface
    expect(db.worktop('granit_naturel')!.variants.length, 4);
    expect(db.panels.length, 8);
    expect(db.panel('mdf_melamine_hydrofuge')!.sheets, contains((2800, 2100)));
    expect(db.edgeBands.map((e) => e.thickness), [0.4, 1.0, 2.0]);
    expect(db.kerf, 3.2);
    expect(db.hingesFor(747), 2);
    expect(db.hingesFor(1100), 3);
    expect(db.hingesFor(2197), 5);
    expect(db.hardware['hinge_110_soft_close']!.offer('Blum').label, 'Blum');
    expect(db.hardware['adjustable_cabinet_legs']!.offers, isNotEmpty);
  });

  test('prix d\'une feuille proportionnel à la surface (prix donné en 2440 x 1220)', () {
    final p = db.panel('mdf_melamine_hydrofuge')!.sheetPrice(2800, 2100);
    expect(p.min, closeTo(480 * 2800 * 2100 / (2440 * 1220), 1));
  });

  test('électroménager par défaut, quincaillerie et estimation', () {
    final p = Project(room: Room(width: 3600, depth: 3000, height: 2500));
    final e = LayoutEngine(cat, p);
    e.add('tall_integrated_fridge', 'A', s: 0);
    e.add('base_sink', 'A', s: 600, width: 800);
    e.add('base_integrated_dishwasher_door', 'A', s: 1400, width: 600);
    e.add('base_cooktop_oven', 'A', s: 2000, width: 600);
    e.add('base_drawers_multi', 'A', s: 2600, width: 600, variant: '1_low_2_deep');
    e.add('wall_integrated_hood', 'A', s: 2000, width: 600, z: 1550);
    e.add('wall_standard_single_door', 'A', s: 600, width: 600);
    final sink = p.items[1];
    expect(appliancesOf(e.modelOf(sink), sink), ['sink_2_bowls']);
    expect(applianceChecks(e, db), isEmpty);

    final cs = p.cut;
    final plan = nest(cutList(e, cs, {}), cs);
    final bom = buildBom(e);
    final hw = hardwareList(e, db, p.specs, plan.parts, bom.plinthLength);
    double qty(String name) => hw.where((l) => l.name.startsWith(name)).fold(0, (a, l) => a + l.qty);
    expect(qty('Charnière Droite'), greaterThanOrEqualTo(2 + 2 + 2)); // évier 2 portes, haut, frigo...
    expect(qty('Kit Casserolier'), 2); // 1 tiroir bas + 2 casseroliers
    expect(qty('Kit Tiroir Double Paroi'), greaterThanOrEqualTo(1));
    expect(qty('Pieds Vérins'), 4 * 4); // frigo, évier, plaque, tiroirs (la façade LV n'a pas de caisson)
    expect(qty('Boîtiers de Suspension'), 2);
    expect(hw.any((l) => l.name.startsWith('Égouttoir')), isTrue); // haut au-dessus de l'évier

    final est = estimate(e, db, p.specs, plan, bom);
    final sections = est.map((l) => l.section).toSet();
    expect(sections, containsAll(['Panneaux', 'Chants', 'Plan de travail', 'Quincaillerie', 'Électroménager']));
    final total = totalOf(est);
    expect(total.min, greaterThan(0));
    expect(total.max, greaterThan(total.min));
  });

  test('évier 2 bacs dans un caisson de 600 : erreur', () {
    final p = Project();
    final e = LayoutEngine(cat, p);
    final c = e.add('base_sink', 'A', s: 0, width: 600)..appliances = ['sink_2_bowls'];
    expect(applianceChecks(e, db).any((i) => i.code == 'appliance_width' && i.uids.contains(c.uid)), isTrue);
  });

  test('tarifs de l\'atelier : 5 feuilles + 18,63 m de chant ≈ 4700 MAD (facture réelle)', () {
    final specs = ProjectSpecs();
    final cs = CutSettings();
    // plan fictif : 5 feuilles et des pièces totalisant 18,63 m de chant
    final parts = [CutPart('MDF', 'Côté', 'x', 1863, 500, 10, edgeLong: 1)];
    final sheets = [for (var i = 1; i <= 5; i++) CutSheet(i, 'MDF', 2800, 2100, 4)];
    final plan = CutPlan(cs, parts, sheets, const []);
    final lines = estimate(LayoutEngine(cat, Project()), db, specs, plan, const Bom([], 0, 0, 0))
        .where((l) => l.section == 'Panneaux' || l.section == 'Chants');
    final t = totalOf(lines);
    expect(t.min, closeTo(4250 + 265 + 18.63 * 9, 1));
    expect(t.max, closeTo(4250 + 265 + 18.63 * 10, 1)); // chant au tarif public : 9 (blanc) à 10 MAD/m (décor)
    expect(4700, inInclusiveRange(t.min, t.max));
  });
}
