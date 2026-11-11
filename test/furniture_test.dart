// Autres univers : catalogues dressing / bain / tv / intérieur, débit paramétrique, écran du concepteur.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/furniture_page.dart';
import 'package:kitchen_planner/ui/theme.dart';

FurnitureUniverse uni(String id) => FurnitureUniverse.parse(id, File('assets/data/furniture/$id.json').readAsStringSync());

FurnitureItem place(FurnitureUniverse u, String id, {int? w, int? h}) {
  final m = u.model(id)!;
  return FurnitureItem(uid: id, modelId: id, width: w ?? m.widths.first, height: h ?? m.heights.first, depth: m.depths.first, setup: m.setup.copy());
}

void main() {
  test('les 4 catalogues : modules avec tailles, accessoires avec prix', () {
    for (final (id, models) in const [('dressing', 14), ('bain', 11), ('tv', 10), ('interieur', 20)]) {
      final u = uni(id);
      expect(u.models.length, models, reason: id);
      expect(u.models.every((m) => m.widths.isNotEmpty && m.heights.isNotEmpty && m.depths.isNotEmpty), isTrue, reason: id);
      expect(u.accessories.where((a) => a.min != null), isNotEmpty, reason: id);
    }
    final d = uni('dressing');
    expect(d.model('wardrobe_corner_L_90')!.widths, [900, 1000, 1100]);
    expect(d.model('wardrobe_double_hanging')!.setup.rods, 2);
    expect(uni('interieur').model('bedroom_storage_bed_base')!.widths, contains(1640));
  });

  test('dressing : penderie double 1000 x 2400 → côtés, étagères, 2 portes de 5 charnières, 2 barres', () {
    final d = uni('dressing');
    final p = FurnitureProject(universe: 'dressing', wallWidth: 3000, wallHeight: 2600)
      ..items.add(place(d, 'wardrobe_double_hanging', w: 1000, h: 2400)..setup.doors = 2)
      ..items.add(place(d, 'wardrobe_linen_drawers_tower', w: 600, h: 2400));
    final (parts, hw) = furnitureCutList(p);
    CutPart part(String name) => parts.firstWhere((x) => x.name == name);
    expect(part('Côté').length, 2400);
    expect(part('Porte').width, ((1000 - 4 - 3) / 2).floor());
    expect(hw['Charnières'], 2 * 5);
    expect(hw['Redresseur de porte'], 2);
    expect(hw['Barre de penderie (m)'], closeTo(2 * 0.964, 0.001));
    expect(hw['Paire de coulisses de tiroir'], 4);
    expect(parts.any((x) => x.material == furnitureBack), isTrue);
    expect(nest(parts, CutSettings()).notPlaced, isEmpty);
    // coulissantes : vantaux sur toute la largeur, plus de portes battantes
    p.doorSystem = 'coulissantes';
    final (sl, hw2) = furnitureCutList(p);
    expect(sl.any((x) => x.name == 'Porte'), isFalse);
    expect(sl.firstWhere((x) => x.name == 'Vantail coulissant').qty, 2);
    expect(hw2['Kit rail coulissant (2 portes)'], 1);
    expect(p.checks().any((c) => c.contains('660')), isTrue);
  });

  test('contrôles : mur trop court, porte battante trop large ; enregistré avec le projet', () {
    final d = uni('dressing');
    final p = FurnitureProject(universe: 'dressing', wallWidth: 1200)..items.add(place(d, 'wardrobe_long_hanging', w: 1000)..setup.doors = 1);
    p.items.add(place(d, 'wardrobe_long_hanging', w: 800));
    expect(p.checks().any((c) => c.contains('mur de 1200')), isTrue);
    expect(p.checks().any((c) => c.contains('600 mm maximum')), isTrue);
    final pr = Project(name: 'x')..furniture['dressing'] = p;
    final back = Project.fromJson(pr.toJson());
    expect(back.furniture['dressing']!.items.length, 2);
    expect(back.furniture['dressing']!.items.first.setup.rods, 1);
  });

  test('chaque module de chaque univers se débite sans erreur', () {
    for (final id in ['dressing', 'bain', 'tv', 'interieur']) {
      final u = uni(id);
      final p = FurnitureProject(universe: id);
      for (final m in u.models) {
        p.items.add(place(u, m.id));
      }
      final (parts, _) = furnitureCutList(p);
      expect(parts, isNotEmpty, reason: id);
      expect(parts.every((x) => x.length > 0 && x.width > 0), isTrue, reason: id);
    }
  });

  testWidgets('écran du concepteur : ajout d’un module, fiche, résumé', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    await t.runAsync(() => loadUniverse('dressing'));
    await t.pumpWidget(MaterialApp(home: FurniturePage(state: st, universe: 'dressing')));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Double Penderie'));
    await t.pumpAndSettle();
    expect(st.project.furniture['dressing']!.items, hasLength(1));
    expect(find.text('Module 1'), findsOneWidget);
    expect(find.textContaining('Feuilles MDF 18'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('capture : dressing composé (tablette 1366 x 1024)', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    final d = uni('dressing');
    st.project.furniture['dressing'] = FurnitureProject(universe: 'dressing', wallWidth: 3200)
      ..items.addAll([
        place(d, 'wardrobe_long_hanging', w: 800, h: 2400),
        place(d, 'wardrobe_double_hanging', w: 1000, h: 2400)..setup.doors = 2,
        place(d, 'wardrobe_linen_drawers_tower', w: 600, h: 2400),
        place(d, 'wardrobe_long_hanging', w: 600, h: 2400)..setup.doors = 1,
      ]);
    await t.runAsync(() => loadUniverse('dressing'));
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: FurniturePage(state: st, universe: 'dressing')));
    await t.pumpAndSettle();
    await t.tapAt(t.getCenter(find.byType(CustomPaint).at(1)));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/furniture_dressing.png'));
  });
}
