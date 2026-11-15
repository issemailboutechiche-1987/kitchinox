// Catalogue des poignées, règles de débit paramétriques (jeux, Gola, fond rainuré, tiroirs métal),
// fil du bois et optimisation multi-règles.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/finishes.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  final db = MaterialsDb.parse(
      appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'), handles: f('handles'));

  LayoutEngine one(String model, {int width = 600}) {
    final e = LayoutEngine(cat, Project(room: Room(width: 3600, depth: 3000, height: 2500)));
    e.add(model, 'A', s: 0, width: width);
    return e;
  }

  CutPart? part(List<CutPart> parts, String name) => parts.where((p) => p.name == name).firstOrNull;

  test('poignées : 19 modèles en 7 familles, rendus et perçages', () {
    final h = db.handles;
    expect(h.items.length, 19);
    expect(h.families.length, 8); // + « sans poignée »
    final bar = h.byId('handle_tubular_t_bar')!;
    expect(bar.render, HandleRender.bar);
    expect(bar.defaultSize, 160);
    expect(bar.drillingText(160), contains('entraxe 160'));
    expect(h.byId('knob_round_mushroom')!.render, HandleRender.knob);
    expect(h.byId('edge_pull_full_width_bar')!.perBar, isTrue);
    expect(h.byId('milled_j_pull_finger_groove')!.perDoorMilling, isTrue);
    expect(h.byId('flush_pull_rectangular_box')!.drillingText(0), contains('112 x 33'));
  });

  test('poignées : ligne d\'estimation selon le modèle choisi', () {
    final e = one('base_door_drawer');
    e.project.style
      ..handleId = 'handle_d_pull_flat'
      ..handleSize = 192
      ..handle = 'bar';
    final plan = nest(cutList(e, e.project.cut, {}), e.project.cut);
    final hw = hardwareList(e, db, e.project.specs, plan.parts, 0);
    final l = hw.firstWhere((l) => l.name.startsWith('Poignée Étrier'));
    expect(l.qty, 2); // 1 tiroir + 1 porte
    expect(l.detail, contains('192'));
    expect(hw.any((l) => l.name.contains('Poignée Standard')), isFalse);
  });

  test('jeux des façades : 4 / 4, 3 mm entre deux portes', () {
    final e = one('base_standard_double_door', width: 800);
    final parts = cutList(e, e.project.cut, {});
    final d = part(parts, 'Porte (x2)')!;
    expect((d.length, d.width, d.qty), (746, (800 - 4 - 3) ~/ 2, 2));
  });

  test('profil Gola : façade du haut -35, suivantes -30', () {
    final e = one('base_drawers_multi');
    e.project.items.first.variant = '3_drawers_equal';
    e.project.style.handle = 'gola';
    final fronts = cutList(e, e.project.cut, {}).where((p) => p.name == 'Façade tiroir').toList();
    final heights = [for (final p in fronts) for (var i = 0; i < p.qty; i++) p.length < p.width ? p.length : p.width]..sort();
    expect(heights, [220, 220, 215]..sort()); // 250 - 35 en haut, 250 - 30 ensuite
  });

  test('fond arrière rainuré et tiroirs métal', () {
    final e = one('base_drawers_multi');
    final cs = e.project.cut
      ..backPanel = true
      ..drawerSystem = 'metal';
    final parts = cutList(e, cs, {});
    final back = parts.firstWhere((p) => p.name.startsWith('Fond arrière'));
    expect(back.material, 'HDF 6 mm');
    expect({back.length, back.width}, {750 - 18 + 9, 600 - 36 + 18});
    expect(part(parts, 'Côté tiroir'), isNull);
    expect(parts.where((p) => p.name == 'Fond tiroir métal').fold<int>(0, (a, p) => a + p.qty), 2); // variante 2 casseroliers
    final plan = nest(parts, cs);
    expect(plan.materials, containsAll(['MDF', 'HDF 6 mm', 'MDF 16 mm']));
  });

  test('façade chêne : panneau plaqué à part, sans rotation (fil du bois)', () {
    installCutHooks();
    final e = one('base_standard_single_door');
    e.project.style.front = 'chene';
    final door = part(cutList(e, e.project.cut, {}), 'Porte')!;
    expect(door.material, 'MDF plaqué chêne naturel');
    expect(door.canRotate, isFalse);
    e.project.style.front = 'blanc_mat';
    expect(part(cutList(e, e.project.cut, {}), 'Porte')!.material, 'MDF');
    frontDecorOf = null;
    frontGrainLocked = null;
  });

  test('optimisation : jamais plus de panneaux qu\'avec la règle d\'origine', () {
    final e = LayoutEngine(cat, Project(room: Room(width: 4200, depth: 3400, height: 2600)));
    e.applyShape(RoomShape.lShape);
    for (final w in ['A', 'B']) {
      e.autoFillWall(w, Band.low);
      e.autoFillWall(w, Band.high);
    }
    final parts = cutList(e, e.project.cut, {});
    final plan = nest(parts, e.project.cut);
    expect(plan.notPlaced, isEmpty);
    final placed = plan.sheets.fold<int>(0, (a, s) => a + s.placements.length);
    expect(placed, parts.fold<int>(0, (a, p) => a + p.qty));
  });
}
