// Trois panneaux (caissons, façades, fonds) : format, épaisseur et prix propres à chacun, pris en compte dans le
// débit, le devis et les fichiers SketchCut (un par type de panneau) ; réglés dans les paramètres du projet.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/kx_top_bar.dart';
import 'package:kitchen_planner/ui/project_settings_dialog.dart';
import 'package:kitchen_planner/ui/sct_export.dart';
import 'package:kitchen_planner/main.dart';

AppState kitchen() {
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'), handles: f('handles'));
  final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()), db: db);
  st.engine.applyShape(RoomShape.linear);
  st.engine.add('base_sink', 'A', s: 0, width: 800);
  st.engine.add('base_drawers_multi', 'A', s: 800, width: 600);
  st.engine.add('base_standard_2doors', 'A', s: 1400);
  return st;
}

void main() {
  setUpAll(() => PublicPrices.parse(File('assets/data/public_prices.json').readAsStringSync()));

  AppState configured() {
    final st = kitchen();
    st.edit(() {
      st.project.cut
        ..carcassMaterial = 'Latté (Blockboard)'
        ..sheetLength = 2100
        ..sheetWidth = 2020
        ..frontMaterial = 'MDF High Gloss (Brillant)'
        ..frontSheetLength = 2800
        ..frontSheetWidth = 1220
        ..backMaterial = 'HDF 6 mm'
        ..backSheetLength = 2440
        ..backSheetWidth = 1220;
      st.project.specs
        ..sheetPrice = 800
        ..frontSheetPrice = 1500
        ..backSheetPrice = 300;
    });
    return st;
  }

  test('débit et devis : chaque panneau a son format, son épaisseur et son prix', () {
    final st = configured();
    final plan = st.cutPlan;
    for (final sh in plan.sheets) {
      final (l, w) = st.project.cut.sheetDimensionsFor(sh.material);
      expect((sh.length, sh.width), (l, w), reason: sh.material);
    }
    final lines = {for (final l in st.estimateLines.where((l) => l.section == 'Panneaux' && l.unit == 'feuille' && !l.name.startsWith('Découpe'))) l.detail.split(' · ').first: l};
    final bySize = {for (final e in lines.entries) e.key: e.value.unitPrice.min};
    expect(bySize['2100 x 2020 x 18 mm'], 800);
    expect(bySize['2800 x 1220 x 18 mm'], 1500);
    expect(bySize['2440 x 1220 x 6 mm'], 300);
    // prix des panneaux gardés dans le projet
    final back = ProjectSpecs.fromJson(st.project.specs.toJson());
    expect((back.sheetPrice, back.frontSheetPrice, back.backSheetPrice), (800, 1500, 300));
  });

  test('fond au prix public : au prorata du format réglé', () {
    final st = kitchen();
    st.edit(() => st.project.cut
      ..backSheetLength = 2440
      ..backSheetWidth = 1220);
    final ref = PublicPrices.back(6)!;
    final l = st.estimateLines.firstWhere((l) => l.section == 'Panneaux' && l.name.startsWith('HDF'));
    expect(l.unitPrice.min, closeTo(ref.price * 2440 * 1220 / (ref.length * ref.width), 1));
  });

  test('même nom, format différent : caissons et façades dans des feuilles séparées', () {
    final st = kitchen();
    expect(st.cutPlan.materials, isNot(contains('MDF (façades)')));
    st.edit(() => st.project.cut
      ..frontSheetLength = 2800
      ..frontSheetWidth = 1220);
    expect(st.cutPlan.materials, containsAll(['MDF', 'MDF (façades)']));
    expect(st.cutPlan.sheets.where((s) => s.material == 'MDF').every((s) => s.width == 2100), isTrue);
  });

  test('SketchCut : un fichier par type de panneau, à son format', () {
    final st = configured();
    final files = sctFiles(st.cutPlan, name: 'Cuisine été');
    expect(files.map((f) => f.kind).toSet(), containsAll([PanelKind.carcass, PanelKind.front, PanelKind.back]));
    for (final f in files) {
      expect(f.content, contains('${f.sheet.$1}X${f.sheet.$2}_0'));
      expect(f.fileName, startsWith('Cuisine_ete_'));
      expect(f.fileName, endsWith('_${f.sheet.$1}x${f.sheet.$2}_${f.thickness}mm.sct'));
    }
    final back = files.firstWhere((f) => f.kind == PanelKind.back);
    expect((back.sheet, back.thickness), ((2440, 1220), 6));
    expect({for (final f in files) f.fileName}, hasLength(files.length));
    // même panneau partout : un seul fichier caissons + façades
    final same = sctFiles(kitchen().cutPlan, name: 'x');
    expect(same.where((f) => f.fileName.contains('Caissons_Facades')), hasLength(1));
    expect(same.where((f) => f.kind == PanelKind.front), isEmpty);
  });

  testWidgets('paramètres du projet : ouvrir puis enregistrer ne change ni matière ni débit ; prix saisis', (t) async {
    t.view.physicalSize = const Size(1180, 820);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = kitchen();
    final before = st.cutPlan.sheets.length;
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) => Scaffold(body: TextButton(onPressed: () => showProjectSettingsDialog(ctx, st, (_) {}), child: const Text('go')))),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Débit').first);
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('price_frontPriceCtrl')));
    await t.enterText(find.byKey(const ValueKey('price_frontPriceCtrl')), '1200');
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect((st.project.cut.carcassMaterial, st.project.cut.frontMaterial, st.project.cut.backMaterial), ('MDF', 'MDF', 'HDF 6 mm'));
    expect(st.project.specs.frontSheetPrice, 1200);
    expect(st.cutPlan.sheets.length, before);
    expect(t.takeException(), isNull);
  });

  testWidgets('même barre de menus dans la cuisine que dans l’atelier', (t) async {
    t.view.physicalSize = const Size(1180, 820);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = kitchen();
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
    await t.pumpAndSettle();
    expect(find.byType(KxTopBar), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('menu_window')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(MenuItemButton, 'Implantation'));
    await t.pumpAndSettle();
    expect(st.step, PlanStep.layout);
    await t.tap(find.byKey(const ValueKey('menu_insert')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(MenuItemButton, 'Ajouter des meubles'));
    await t.pumpAndSettle();
    expect(st.browse, isNotNull);
    expect(t.takeException(), isNull);
  });
}
