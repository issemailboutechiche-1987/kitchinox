// Fonctions relevées dans les planificateurs du marché : joues de finition automatiques,
// éclairage LED, niche lave-linge, colonne ménage.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  LayoutEngine room() => LayoutEngine(cat, Project(room: Room(width: 4200, depth: 3200, height: 2600)));

  test('joues : seulement aux extrémités libres, jamais contre un mur ou une colonne', () {
    final e = room();
    e.add('base_standard_single_door', 'A', s: 0, width: 600); // contre le mur D : pas de joue à gauche
    e.add('base_drawers_multi', 'A', s: 600, width: 600); // extrémité droite libre
    e.add('wall_standard_single_door', 'A', s: 0, width: 600, z: 1500);
    e.add('wall_standard_single_door', 'A', s: 600, width: 600, z: 1500);
    final j = endPanels(e);
    expect(j.where((x) => !x.high).length, 1);
    expect(j.where((x) => x.high).length, 1);
    final low = j.firstWhere((x) => !x.high);
    expect(low.s, 1200);
    expect(low.z0, 0); // jusqu'au sol, cache la plinthe
    // une colonne à droite des bas : plus de joue basse, et la joue haute disparaît aussi
    e.add('tall_pantry', 'A', s: 1200, width: 600);
    final j2 = endPanels(e);
    expect(j2.where((x) => !x.high && x.s == 1200), isEmpty);
    expect(j2.where((x) => x.high && x.s == 1200), isEmpty);
    // la colonne elle-même reçoit sa joue côté libre
    expect(j2.where((x) => !x.high && x.s == 1800), hasLength(1));
  });

  test('joues et éclairage dans la liste et le débit', () {
    final e = room();
    e.add('base_standard_single_door', 'A', s: 0, width: 600);
    e.add('wall_standard_single_door', 'A', s: 0, width: 600, z: 1500);
    e.project.style.lighting = 'led_hauts_plinthes';
    final bom = buildBom(e);
    expect(bom.lines.where((l) => l.ref == 'cover_panel_side' && l.section == 'Finitions'), isNotEmpty);
    expect(bom.lines.any((l) => l.ref == 'led_strip'), isTrue);
    expect(bom.lines.any((l) => l.ref == 'led_plinth'), isTrue);
    expect(bom.lines.any((l) => l.ref == 'led_driver'), isTrue);
    final parts = cutList(e, e.project.cut, const {});
    expect(parts.where((p) => p.name == 'Joue de finition').fold<int>(0, (s, p) => s + p.qty), 2);
    e.project.style.endPanels = false;
    expect(cutList(e, e.project.cut, const {}).where((p) => p.name == 'Joue de finition'), isEmpty);
    expect(buildBom(e).lines.where((l) => l.ref == 'cover_panel_side').every((l) => l.section == 'À prévoir'), isTrue);
    // réglages enregistrés
    final back = KitchenStyle.fromJson(e.project.style.toJson());
    expect((back.endPanels, back.lighting), (false, 'led_hauts_plinthes'));
  });

  test('niche lave-linge : prise 20 A, robinet et évacuation ; colonne ménage au catalogue', () {
    final e = room();
    final ll = e.add('base_washing_machine', 'A', s: 1200, width: 600);
    expect(defaultAppliances(e.modelOf(ll), ll), ['washing_machine_60']);
    final pts = generateNetworks(e);
    expect(pts.where((x) => x.use == NetUse.washer).map((x) => x.kind).toSet(), containsAll([NetKind.socket20, NetKind.valveMachine, NetKind.drain]));
    expect(cat['tall_cleaning'].kind, CabinetKind.tall);
  });
}
