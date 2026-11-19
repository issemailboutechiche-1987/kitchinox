// Marques et prix (Maroc) et dimensions types des pièces : catalogues, devis, contrôles, fenêtres.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/main.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/brands_ui.dart';

MaterialsDb db() {
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  return MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'), handles: f('handles'));
}

AppState kitchen() => AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()), db: db());

void main() {
  setUpAll(() {
    BrandCatalog.parse(File('assets/data/brands.json').readAsStringSync());
    SizeCatalog.parse(File('assets/data/sizes.json').readAsStringSync());
  });

  test('marques : 5 catégories, prix lus, quincaillerie de l\'app reliée aux prix des marques', () {
    expect(BrandCatalog.categories.length, 5);
    expect(BrandCatalog.hardwareBrands, contains('Blum'));
    final hinge = BrandCatalog.hardwarePrice('Blum', 'hinge_110_soft_close')!;
    expect((hinge.min, hinge.max), (34, 48));
    expect(BrandCatalog.hardwarePrice('Samet', 'double_wall_box_casserolier_deep')!.min, 230);
    expect(BrandCatalog.hardwarePrice('Inconnue', 'hinge_110_soft_close'), isNull);
    expect(BrandPrice('charniere_clip_top_blumotion_110_avec_embase', PriceRange.zero).label, startsWith('Charnière clip top'));
  });

  test('devis : la marque choisie donne ses prix ; comparatif chiffré, du moins cher au plus cher', () {
    final st = kitchen();
    st.engine.add('base_drawers_multi', 'A', s: 0, width: 600);
    st.engine.add('base_standard_single_door', 'A', s: 600, width: 600);
    final qty = projectHardwareQty(st);
    expect(qty['hinge_110_soft_close'], greaterThan(0));
    final est = BrandCatalog.hardwareEstimate(qty);
    expect(est.length, greaterThanOrEqualTo(4));
    for (var i = 1; i < est.length; i++) {
      expect(est[i].$2.min, greaterThanOrEqualTo(est[i - 1].$2.min));
    }
    st.setHardwareBrand('Blum');
    final lines = estimate(st.engine, st.db!, st.project.specs, st.cutPlan, st.bom).where((l) => l.section == 'Quincaillerie' && l.detail.startsWith('Blum'));
    expect(lines, isNotEmpty);
    final hinges = lines.firstWhere((l) => l.unitPrice.min == 34);
    expect(hinges.unitPrice.max, 48);
  });

  test('dimensions types : cuisine, salle de bain, dressing ; appliquer une pièce et sa disposition', () {
    expect(SizeCatalog.presets['cuisine']!.length, 5);
    expect(SizeCatalog.presets['bain']!.length, 5);
    expect(SizeCatalog.presets['dressing']!.length, 5);
    final studio = SizeCatalog.presets['cuisine']!.first;
    expect(studio.minWidth, 2400); // clé « min_viable_ dimensions » (avec une espace) bien lue
    final st = kitchen();
    final u = SizeCatalog.presets['cuisine']!.firstWhere((p) => p.layout == 'U_shape');
    st.applyRoomPreset(u);
    expect((st.project.room.width, st.project.room.depth), (3600, 3200));
    expect(st.project.shape, RoomShape.uShape);
  });

  test('normes : pièce trop petite pour la disposition, évier collé à la plaque, passage du dressing', () {
    final st = kitchen();
    st.updateRoom(width: 2200, depth: 2000);
    st.engine.applyShape(RoomShape.uShape);
    expect(st.issues.any((i) => i.code == 'room_small'), isTrue);
    st.updateRoom(width: 3600, depth: 3000);
    st.engine.applyShape(RoomShape.linear);
    st.engine.add('base_sink', 'A', s: 0, width: 800);
    st.engine.add('base_cooktop_oven', 'A', s: 1000, width: 600);
    expect(st.issues.any((i) => i.code == 'sink_hob_close'), isTrue);
    final u = FurnitureUniverse.parse('dressing', File('assets/data/furniture/dressing.json').readAsStringSync());
    final d = AppState(universeCatalog(u), project: Project(universe: 'dressing', room: Room(width: 2400, depth: 1500, height: 2600)));
    d.engine.add('wardrobe_long_hanging', 'A', s: 0);
    d.engine.add('wardrobe_long_hanging', 'D', s: 0);
    expect(d.issues.any((i) => i.code == 'dressing_passage'), isTrue);
  });

  testWidgets('fenêtres : marques et prix (récapitulatif), dimensions types (votre espace)', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = kitchen();
    st.engine.add('base_drawers_multi', 'A', s: 0, width: 600);
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Dimensions types'));
    await t.pumpAndSettle();
    await t.tap(find.text('Dimensions types'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Cuisine en L Standard'));
    await t.pumpAndSettle();
    expect(st.project.shape, RoomShape.lShape);
    st.goTo(PlanStep.summary);
    await t.pumpAndSettle();
    // « Marques et tarifs » s'ouvre depuis l'accueil : même fenêtre
    showBrandsDialog(t.element(find.byType(Scaffold).first), st, (_) {});
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Quincaillerie').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Quincaillerie').last);
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/marques_quincaillerie.png'));
    await t.tap(find.widgetWithText(OutlinedButton, 'Choisir').first);
    await t.pumpAndSettle();
    expect(BrandCatalog.hardwareBrands, contains(st.project.specs.hardwareBrand));
    expect(t.takeException(), isNull);
  });
}
