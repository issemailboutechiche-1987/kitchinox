// Dressing, bain, TV, intérieur dans le planificateur de la cuisine : catalogue converti, pose sur les murs,
// hauteurs et hauteur de pose du catalogue, pas de règles de cuisine, débit, 3D, écran complet.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/main.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/scene_export.dart';
import 'package:kitchen_planner/ui/textures.dart';

FurnitureUniverse uni(String id) => FurnitureUniverse.parse(id, File('assets/data/furniture/$id.json').readAsStringSync());

void main() {
  for (final id in ['dressing', 'bain', 'tv', 'interieur']) {
    test('$id : chaque module se pose, garde ses hauteurs, se débite ; aucune règle de cuisine', () {
      final u = uni(id);
      final cat = universeCatalog(u);
      expect(cat.models.length, u.models.length);
      for (final m in u.models) {
        final e = LayoutEngine(cat, Project(universe: id, room: Room(width: 8000, depth: 4000, height: 2800)));
        final c = e.add(m.id, 'A');
        final cm = cat[m.id];
        expect(cm.heights.values, containsAll(m.heights.where((h) => cm.heights.values.contains(h))), reason: m.id);
        if (m.setup.wallHung) expect(c.z, m.setup.z, reason: m.id);
        final issues = [...e.validate(), ...designChecks(e), ...waterChecks(e)];
        expect(issues.where((i) => i.code.startsWith('zone_') || i.code.startsWith('triangle') || i.code.startsWith('water')), isEmpty, reason: m.id);
        expect(cutList(e, e.project.cut, const {}), isNotEmpty, reason: m.id);
      }
    });
  }

  test('meuble vasque bas : hauteur du catalogue (pas la hauteur de cuisine), pas de plan de travail', () {
    final cat = universeCatalog(uni('tv'));
    final e = LayoutEngine(cat, Project(universe: 'tv'));
    final c = e.add('tv_low_bench_floor_standing', 'A');
    expect(c.height, 400);
    expect(buildBom(e).lines.where((l) => l.ref == 'worktop'), isEmpty);
  });

  testWidgets('3D et écran du planificateur pour un dressing', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final cat = universeCatalog(uni('dressing'));
    final st = AppState(cat, project: Project(universe: 'dressing', name: 'Dressing'));
    st.edit(() {
      st.engine.add('wardrobe_long_hanging', 'A', s: 0);
      st.engine.add('wardrobe_double_hanging', 'A', s: 800);
      st.engine.add('wardrobe_linen_drawers_tower', 'A', s: 1700);
    });
    await t.runAsync(() async {
      await TextureBank.instance.init();
      final scene = await SceneExporter().build(st);
      expect((scene['solids'] as List).where((s) => s['top'] == true), isEmpty); // pas de plan de travail
      expect(scene['fronts'], isNotEmpty);
    });
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
    await t.pumpAndSettle();
    st.goTo(PlanStep.layout);
    await t.pumpAndSettle();
    expect(find.text('Propositions / remplir'), findsNothing);
    expect(find.text('Réseaux'), findsOneWidget); // réseaux : pour toutes les pièces (plomberie de la salle de bain, prises TV)
    st.goTo(PlanStep.summary);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('capture : fenêtre Propositions du dressing', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final cat = universeCatalog(uni('dressing'));
    final st = AppState(cat, project: Project(universe: 'dressing', name: 'Dressing', room: Room(width: 4000, depth: 3000, height: 2600)));
    await t.runAsync(() => TextureBank.instance.init());
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
    await t.pumpAndSettle();
    st.goTo(PlanStep.layout);
    await t.pumpAndSettle();
    await t.tap(find.text('Propositions'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/propositions_dressing.png'));
    await t.tap(find.text('Collection kitchinox'));
    await t.pump(const Duration(milliseconds: 100));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/propositions_dressing_collection.png'));
    expect(t.takeException(), isNull);
  });
}
