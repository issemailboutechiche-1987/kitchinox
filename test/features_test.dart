// Remplacer un meuble, façades composées et niches, électroménager ↔ largeur, finitions,
// et rendu 3D réaliste (textures) enregistré dans test/out pour contrôle visuel.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/finishes.dart';
import 'package:kitchen_planner/ui/scene3d.dart';
import 'package:kitchen_planner/ui/tech_drawings.dart';
import 'package:kitchen_planner/ui/textures.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'));

  LayoutEngine fresh() => LayoutEngine(cat, Project(room: Room(width: 3600, depth: 3000, height: 2500)));

  test('remplacer : même place, largeur catalogue la plus proche, refus sans place', () {
    final e = fresh();
    final a = e.add('base_standard_single_door', 'A', s: 0, width: 600);
    e.add('base_standard_single_door', 'A', s: 600, width: 600);
    final r = e.replace(a.uid, 'base_door_drawer');
    expect(r.moved, isTrue);
    final c = e.project.byUid(a.uid)!;
    expect(c.modelId, 'base_door_drawer');
    expect((c.s, c.width), (0.0, 600));
    // 2 portes + tiroir : 800 mini, le voisin bloque → refus, rien ne change
    final r2 = e.replace(a.uid, 'base_door_drawer_double');
    expect(r2.moved, isFalse);
    expect(e.project.byUid(a.uid)!.modelId, 'base_door_drawer');
    // un haut ne propose que des hauts
    final h = e.add('wall_standard_single_door', 'A', s: 0, width: 600);
    expect(e.replacementsFor(h).every((m) => m.kind.isHigh), isTrue);
    expect(e.replacementsFor(h).map((m) => m.id), contains('wall_glass_door'));
  });

  test('façade composée : débit tiroir + porte, niche sans façade', () {
    final e = fresh();
    final c = e.add('base_door_drawer', 'A', s: 0, width: 600);
    final cs = e.project.cut;
    var parts = cutList(e, cs, {});
    CutPart? part(String name) => parts.where((p) => p.name == name).firstOrNull;
    expect(part('Façade tiroir')!.length, 596);
    expect(part('Façade tiroir')!.width, 146);
    expect(part('Porte')!.length, 750 - 150 - 4);
    expect(part('Tablette de séparation'), isNotNull);

    // composition personnalisée : 3 tiroirs égaux
    c.layout = [FrontRow(CellKind.drawer), FrontRow(CellKind.drawer), FrontRow(CellKind.drawer)];
    parts = cutList(e, cs, {});
    expect(parts.where((p) => p.name == 'Façade tiroir').fold<int>(0, (a, p) => a + p.qty), 3);
    expect(part('Porte'), isNull);

    final n = e.add('base_open_niche', 'A', s: 600, width: 300);
    parts = cutList(e, cs, {});
    expect(parts.where((p) => p.cabinet.contains('niche') && (p.name.startsWith('Porte') || p.name.startsWith('Façade'))), isEmpty);
    expect(cellsOf(rowsOf(e.modelOf(n), n)!, n.height).single.kind, CellKind.niche);

    // hauteurs : fixes puis « reste » partagé
    final cells = cellsOf([FrontRow(CellKind.door, 0), FrontRow(CellKind.niche, 450), FrontRow(CellKind.door, 0)], 2150);
    expect(cells.map((x) => x.h), [850, 450, 850]);
  });

  test('abattants : un compas par porte relevable', () {
    final e = fresh();
    e.add('wall_double_flap', 'A', s: 0, width: 800, z: 1450);
    final plan = nest(cutList(e, e.project.cut, {}), e.project.cut);
    final hw = hardwareList(e, db, e.project.specs, plan.parts, 0);
    expect(hw.where((l) => l.name == db.hardware['lift_stay_single_door_heavy']!.name).single.qty, 2);
  });

  test('lave-vaisselle 45 : le caisson passe à 450 ; retour à 600', () {
    final st = AppState(cat, db: db, project: Project(room: Room(width: 3600, depth: 3000, height: 2500)));
    final c = st.engine.add('base_integrated_dishwasher_door', 'A', s: 0, width: 600);
    expect(appliancesOf(st.engine.modelOf(c), c), ['dishwasher_60_standard']);
    st.setAppliance(c.uid, 0, 'dishwasher_45_compact');
    expect(st.project.byUid(c.uid)!.width, 450);
    st.setAppliance(c.uid, 0, 'dishwasher_60_standard');
    expect(st.project.byUid(c.uid)!.width, 600);
    expect(applianceChecks(st.engine, db).where((i) => i.code == 'dishwasher_width'), isEmpty);
  });

  test('styles de façade : général, hauts / bas, propre au caisson ; sauvegarde', () {
    final p = Project();
    final e = LayoutEngine(cat, p);
    final low = e.add('base_standard_single_door', 'A', s: 0);
    final high = e.add('wall_standard_single_door', 'A', s: 0);
    p.style.front = 'blanc_mat';
    expect(p.style.frontOf(high, high: true), 'blanc_mat');
    p.style
      ..frontUpper = 'chene'
      ..frontLower = 'bleu_nuit';
    expect(p.style.frontOf(high, high: true), 'chene');
    expect(p.style.frontOf(low, high: false), 'bleu_nuit');
    low.front = 'terracotta';
    low.layout = [FrontRow(CellKind.drawer, 150), FrontRow(CellKind.door, 0, 'right')];
    p.style.textures.add(CustomTexture(id: 'x1', name: 'Zellige', target: 'front', data: 'AAAA', tile: 300));
    final back = Project.fromJson(p.toJson());
    final l2 = back.byUid(low.uid)!;
    expect(l2.front, 'terracotta');
    expect(l2.layout!.map((r) => '$r'), ['drawer:150', 'door:0']);
    expect(l2.layout![1].hinge, 'right');
    expect(back.style.frontUpper, 'chene');
    expect(back.style.textures.single.name, 'Zellige');
    expect(frontFinishes(back.style).last.id, 'tex:x1');
  });

  testWidgets('rendu 3D réaliste avec textures', (t) async {
    final p = Project(room: Room(width: 4200, depth: 3400, height: 2600));
    final e = LayoutEngine(cat, p);
    e.applyShape(RoomShape.lShape);
    e.addOpening('window', 'A', s: 1500);
    for (final w in ['A', 'B']) {
      e.autoFillWall(w, Band.low);
      e.autoFillWall(w, Band.high);
    }
    // de la variété : vitrine, tiroir + porte, niche
    for (final c in [...p.items]) {
      final m = e.modelOf(c);
      if (m.id == 'wall_standard_single_door' && c.wallId == 'B') e.replace(c.uid, 'wall_glass_door');
      if (m.id == 'base_standard_single_door' && c.wallId == 'B') e.replace(c.uid, 'base_door_drawer');
    }
    try {
      e.add('tall_pantry', 'B', s: p.room.depth - 600, height: 2200);
    } on PlacementException {
      // pas la place : sans colonne
    }
    p.style
      ..frontUpper = 'blanc_mat'
      ..frontLower = 'chene'
      ..worktop = 'marbre'
      ..handle = 'bar';
    expect(p.items.length, greaterThan(8));
    await t.runAsync(() async {
      await TextureBank.instance.init();
      expect(TextureBank.instance['wood_oak'], isNotNull);
      const size = Size(1800, 1200);
      File('test/out/3d_realiste.png').writeAsBytesSync(await renderPng(size, (c, s) {
        final cam = Camera3d.fit(p.room, -0.55, s);
        Scene3dPainter(e, cam, selectColor: Colors.orange, background: Colors.white).paint(c, s);
      }));
      final open = {for (final c in p.items) c.uid: 1.0};
      File('test/out/3d_ouvert.png').writeAsBytesSync(await renderPng(size, (c, s) {
        final cam = Camera3d.fit(p.room, -0.55, s, zoom: 1.5, panX: 100, panY: 150);
        Scene3dPainter(e, cam, selectColor: Colors.orange, background: Colors.white, open: open).paint(c, s);
      }));
      final half = {for (final c in p.items) c.uid: 0.45};
      File('test/out/3d_mi_ouvert.png').writeAsBytesSync(await renderPng(size, (c, s) {
        final cam = Camera3d.fit(p.room, -0.55, s, zoom: 1.5, panX: 100, panY: 150);
        Scene3dPainter(e, cam, selectColor: Colors.orange, background: Colors.white, open: half).paint(c, s);
      }));
      final hc = HandleCatalog.parse(File('assets/data/handles.json').readAsStringSync());
      p.style
        ..handleId = 'handle_d_pull_flat'
        ..handle = 'bar'
        ..handleSize = 256
        ..handleFinish = 'Or brossé'
        ..tallXxl = true;
      File('test/out/3d_poignees.png').writeAsBytesSync(await renderPng(const Size(1400, 900), (c, s) {
        final cam = Camera3d.fit(p.room, -0.55, s, zoom: 1.7, panX: 250, panY: 120);
        Scene3dPainter(e, cam, selectColor: Colors.orange, background: Colors.white, handles: hc).paint(c, s);
      }));
      p.style
        ..handleId = null
        ..handle = 'bar'
        ..handleSize = null
        ..handleFinish = null
        ..tallXxl = false;
      File('test/out/3d_realiste_zoom.png').writeAsBytesSync(await renderPng(size, (c, s) {
        final cam = Camera3d.fit(p.room, -0.45, s, zoom: 2.1, panX: 150, panY: 520, pitch: 0.42);
        Scene3dPainter(e, cam, selectColor: Colors.orange, background: Colors.white).paint(c, s);
      }));
    });
  });
}
