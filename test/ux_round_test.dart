// Retours d'usage : recherche multilingue sans accents, favoris, panneau d'ajout épinglé, mur choisi pour « + »,
// barre de menus du mode Art, figures des accessoires.
import 'dart:io';

import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/engine/furniture_accessories.dart';
import 'package:kitchen_planner/ui/app_settings.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/art_page.dart';
import 'package:kitchen_planner/ui/favorites.dart';
import 'package:kitchen_planner/ui/furniture_accessories_ui.dart';
import 'package:kitchen_planner/ui/i18n.dart';
import 'package:kitchen_planner/ui/panels.dart';
import 'package:kitchen_planner/ui/theme.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  test('recherche : sans accents, par mots, dans la langue affichée et en français', () {
    final st = AppState(cat);
    expect(AppState.fold('Évier Château'), 'evier chateau');
    st.openBrowse(const CatalogBrowse(Shelf.base));
    st.setSearch('evier');
    expect(st.browseModels().map((m) => m.id), contains('base_sink'));
    st.setSearch('bas porte');
    expect(st.browseModels(), isNotEmpty);
    expect(st.browseModels().every((m) => AppState.fold('${m.name} ${m.id}').contains('bas') || m.id.contains('base')), isTrue);
    // interface en anglais : « base » trouve les éléments bas (traduits « Base … »)
    final before = langOverride;
    langOverride = AppLang.en;
    try {
      st.setSearch('base');
      expect(st.browseModels().length, greaterThan(5));
    } finally {
      langOverride = before;
    }
  });

  test('favoris : étoile gardée, favoris en tête', () {
    final f = Favorites.instance;
    if (f.has('cuisine:wall_standard_single_door')) f.toggle('cuisine:wall_standard_single_door');
    f.toggle('cuisine:wall_standard_single_door');
    expect(f.has('cuisine:wall_standard_single_door'), isTrue);
    final sorted = f.sorted(['a', 'wall_standard_single_door', 'b'], (x) => 'cuisine:$x');
    expect(sorted.first, 'wall_standard_single_door');
    f.toggle('cuisine:wall_standard_single_door');
    expect(f.has('cuisine:wall_standard_single_door'), isFalse);
  });

  test('panneau épinglé : il reste ouvert quand on touche un meuble', () {
    final st = AppState(cat);
    st.goTo(PlanStep.layout);
    st.openBrowse(const CatalogBrowse(Shelf.base));
    st.addModel('base_standard_single_door');
    st.select(st.project.items.single.uid);
    expect(st.browse, isNull, reason: 'non épinglé : la fiche remplace le panneau');
    st.openBrowse(const CatalogBrowse(Shelf.base));
    st.browsePinned = true;
    st.select(null);
    st.select(st.project.items.single.uid);
    expect(st.browse, isNotNull, reason: 'épinglé : le panneau reste');
  });

  testWidgets('panneau d’ajout : mur choisi pour « + », filtre Favoris, épingle', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(cat);
    st.goTo(PlanStep.layout);
    st.openBrowse(const CatalogBrowse(Shelf.base));
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: Scaffold(body: SizedBox(width: 380, child: CatalogPanel(state: st, onMessage: (_) {})))));
    await t.pumpAndSettle();
    final wallB = find.descendant(of: find.byKey(const ValueKey('add_wall')), matching: find.text('B'));
    await t.ensureVisible(wallB);
    await t.pumpAndSettle();
    await t.tap(wallB);
    await t.pumpAndSettle();
    expect(st.wallId, 'B');
    await t.tap(find.byTooltip('Ajouter Bas 1 porte'));
    await t.pumpAndSettle();
    expect(st.project.items.single.wallId, 'B');
    await t.ensureVisible(find.byKey(const ValueKey('catalog_pin')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('catalog_pin')));
    await t.pumpAndSettle();
    expect(st.browsePinned, isTrue);
    await t.ensureVisible(find.byKey(const ValueKey('fav_only')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('fav_only')));
    await t.pumpAndSettle();
    expect(st.favoritesOnly, isTrue);
  });

  testWidgets('mode Art : mêmes menus que la cuisine', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(cat);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: ArtPage(state: st)));
    await t.pumpAndSettle();
    for (final k in ['menu_file', 'menu_edit', 'menu_view', 'menu_insert', 'menu_tools', 'menu_window', 'menu_help', 'menu_help']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    final f = find.byKey(const ValueKey('welcome_close'));
    if (f.evaluate().isNotEmpty) {
      await t.tap(f);
      await t.pumpAndSettle();
    }
    await t.tap(find.byKey(const ValueKey('menu_insert')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('menu_tool_rectangle')));
    await t.pumpAndSettle();
    expect((t.state(find.byType(ArtPage)) as dynamic).activeTool.toString(), contains('rectangle'));
    await t.tap(find.byKey(const ValueKey('menu_file')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu_save')), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('accessoires : une figure pour chacun', (t) async {
    FurnitureAccessories.parse(File('assets/data/furniture_accessories.json').readAsStringSync());
    final st = AppState(cat);
    await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light, googleFonts: false),
        home: Builder(builder: (ctx) => Scaffold(body: Center(child: FilledButton(onPressed: () => showFurnitureAccessoriesDialog(ctx, st), child: const Text('go')))))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    final first = FurnitureAccessories.categories.first.items;
    for (final a in first.take(3)) {
      expect(find.byKey(ValueKey('acc_fig_${a.id}')), findsOneWidget, reason: a.id);
    }
    // toutes les figures se dessinent sans erreur
    for (final c in FurnitureAccessories.categories) {
      for (final a in c.items) {
        final rec = PictureRecorder();
        AccessoryFigure(a.id, Colors.black).paint(Canvas(rec), const Size(44, 44));
        rec.endRecording();
      }
    }
  });
}
