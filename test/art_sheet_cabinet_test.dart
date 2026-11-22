import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart' show Catalog;
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/art_page.dart';
import 'package:kitchen_planner/ui/theme.dart';
import 'package:kitchen_planner/engine/art.dart';
import 'package:kitchen_planner/engine/art_machining.dart';
import 'package:kitchen_planner/engine/art_recipes.dart';
import 'package:kitchen_planner/engine/art_sheet_cabinet.dart';
import 'package:kitchen_planner/engine/cutting.dart';

void main() {
  setUpAll(() => ArtRecipes.parse(File('assets/data/art_recipes.json').readAsStringSync()));

  testWidgets('interface : Nouveau → Meuble « caisson 1 porte » → feuille coupée, aperçu 3D → Usiner', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: ArtPage(state: st)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('welcome_new')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('recipe_simple_1p')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('new_ok')));
    await t.pumpAndSettle();
    final art = st.project.art;
    expect(art.edgeLinks, hasLength(5));
    expect(art.free.where((p) => p.note == 'Porte'), hasLength(1));
    expect(find.byKey(const Key('art-preview3d')), findsOneWidget, reason: 'écran partagé ouvert');
    await expectLater(find.byType(ArtPage), matchesGoldenFile('goldens/art_caisson_feuille_avant_usinage.png'));
    await t.tap(find.byKey(const ValueKey('link_machine')));
    await t.pumpAndSettle();
    expect(art.edgeLinks, isEmpty);
    final door = art.free.firstWhere((p) => p.note == 'Porte');
    expect(door.role, ArtRole.porte);
    expect((door.w, door.h, door.d), (597, 717, 18));
    await expectLater(find.byType(ArtPage), matchesGoldenFile('goldens/art_caisson_feuille_usine.png'));
    // Annuler revient aux pièces à plat avec les liaisons notées
    await t.tap(find.byTooltip('Annuler (Ctrl+Z)').first);
    await t.pumpAndSettle();
    expect(art.edgeLinks, hasLength(5));
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('interface : caisson bas 600 × 750 × 600 sur une feuille de MDF → pieds et plinthe après Usiner', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: ArtPage(state: st)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('welcome_new')));
    await t.pumpAndSettle();
    // recette par défaut : caisson bas 1 porte, 600 × 750 × 600, pieds 100
    expect(find.byKey(const ValueKey('param_pieds')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('new_ok')));
    await t.pumpAndSettle();
    final art = st.project.art;
    expect(art.edgeLinks, hasLength(6));
    expect(art.support, isNotNull);
    expect(art.free.where((p) => p.note != null && p.note != 'Chute'), hasLength(8));
    await expectLater(find.byType(ArtPage), matchesGoldenFile('goldens/art_caisson_bas_avant_usinage.png'));
    await t.tap(find.byKey(const ValueKey('link_machine')));
    await t.pumpAndSettle();
    final bottom = art.free.firstWhere((p) => p.note == 'Dessous');
    final plinth = art.free.firstWhere((p) => p.note == 'Plinthe');
    expect(bottom.y, 100, reason: 'monté sur ses pieds');
    expect(plinth.role, ArtRole.plinthe);
    final m = computeMachiningElements(art.panels, fittings: art.fittings, jointCuts: art.jointCuts, jointFits: art.jointFits);
    expect(m.count(MachiningKind.foot), 4);
    expect(m.hingeCupsCount, 2);
    await expectLater(find.byType(ArtPage), matchesGoldenFile('goldens/art_caisson_bas_usine.png'));
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('SketchUp du bois : accueil, palette, tiroir qui suit l’outil, case des cotes, monter, débit', (t) async {
    t.view.physicalSize = const Size(1180, 820);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: ArtPage(state: st)));
    await t.pumpAndSettle();
    final s = t.state(find.byType(ArtPage)) as dynamic;
    expect(s.home, isTrue);
    await expectLater(find.byType(ArtPage), matchesGoldenFile('goldens/art_accueil.png'));
    await t.tap(find.byKey(const ValueKey('welcome_close')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('art_palette')), findsOneWidget);
    // feuille posée depuis le tiroir : outil Couper, rubrique Pièces
    await t.tap(find.byKey(const ValueKey('start_sheet')));
    await t.pumpAndSettle();
    expect(s.open, 'pieces');
    // cote tapée dans la case du bas : 600 mm
    await t.enterText(find.byKey(const ValueKey('cad_measure')), '600');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    final art = st.project.art;
    expect(art.free, hasLength(2));
    await t.pump(const Duration(seconds: 6));
    await expectLater(find.byType(ArtPage), matchesGoldenFile('goldens/art_decoupe.png'));
    // pièce choisie : ses infos s'ouvrent dans le tiroir
    await t.tap(find.byKey(const ValueKey('tool_select')));
    await t.pumpAndSettle();
    final p = art.free.first;
    s.selectedPanel = null;
    final vp = t.getRect(find.byKey(const Key('art-viewport')));
    await t.tapAt(vp.topLeft + (s.screenOf(p.x + p.w / 2, p.top, p.z + p.d / 2) as Offset));
    await t.pumpAndSettle();
    expect(s.open, 'info');
    expect(find.byKey(const ValueKey('art_props')), findsOneWidget);
    await expectLater(find.byType(ArtPage), matchesGoldenFile('goldens/art_infos.png'));
    // effacer depuis la palette
    await t.tap(find.byKey(const ValueKey('tool_erase')));
    await t.pumpAndSettle();
    expect(art.free, hasLength(1));
    // nouvelle création : tout est effacé, retour à l'accueil
    await t.tap(find.byKey(const ValueKey('menu_file')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('menu_new')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('new_confirm')));
    await t.pumpAndSettle();
    expect(art.isEmpty, isTrue);
    expect(s.home, isTrue);
    // meuble à vos mesures : coupé et lié, puis monté
    await t.tap(find.byKey(const ValueKey('welcome_new')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('new_ok')));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 6));
    await t.tap(find.byKey(const ValueKey('side_reopen')));
    await t.pumpAndSettle();
    expect(find.textContaining('Liaisons notées'), findsOneWidget);
    await expectLater(find.byType(ArtPage), matchesGoldenFile('goldens/art_assemblage.png'));
    await t.tap(find.byKey(const ValueKey('link_machine')));
    await t.pumpAndSettle();
    expect(art.edgeLinks, isEmpty);
    expect(find.byKey(const Key('art-preview3d')), findsNothing, reason: 'monté : une seule vue');
    await t.tap(find.byKey(const ValueKey('tray_make')));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 6));
    await expectLater(find.byType(ArtPage), matchesGoldenFile('goldens/art_debit.png'));
    expect(t.takeException(), isNull);
  });

  testWidgets('découpe : cotes de chaque pièce sur la feuille, pas de ligne hors de la feuille', (t) async {
    t.view.physicalSize = const Size(1180, 820);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    st.project.art.free.addAll([
      ArtPanel(id: 'a', role: ArtRole.decor, x: 0, y: 0, z: 0, w: 1396, h: 18, d: 548),
      ArtPanel(id: 'b', role: ArtRole.decor, x: 1400, y: 0, z: 0, w: 600, h: 18, d: 548),
      ArtPanel(id: 'c', role: ArtRole.decor, x: 0, y: 0, z: 552, w: 2000, h: 18, d: 300)..note = 'Chute',
    ]);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: ArtPage(state: st)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('tool_cut')));
    await t.pumpAndSettle();
    final s = t.state(find.byType(ArtPage)) as dynamic;
    final vp = t.getRect(find.byKey(const Key('art-viewport')));
    final g = await t.startGesture(vp.topLeft + (s.screenOf(700.0, 18.0, 200.0) as Offset));
    await g.moveBy(const Offset(0, 20));
    await t.pump();
    expect(s.cutAtValue, isNotNull);
    await g.moveTo(vp.topLeft + (s.screenOf(-300.0, 18.0, 200.0) as Offset));
    await t.pump();
    expect(s.cutAtValue, isNull, reason: 'à côté de la feuille');
    await g.up();
    await t.pumpAndSettle();
    await expectLater(find.byKey(const Key('art-viewport')), matchesGoldenFile('goldens/art_decoupe_cotes.png'));
    await t.pump(const Duration(seconds: 6));
  });

  test('caisson 1 porte depuis une feuille : coupes, liaisons, usinage', () {
    final art = ArtProject();
    final sheet = ArtPanel(id: art.newId(), role: ArtRole.decor, x: 0, y: 0, z: 0, w: 2792, h: 18, d: 2062);
    art.free.add(sheet);
    final cab = cutSheetCabinet(art, sheet)!;
    // dimensions débitées (à plat : longueur X, largeur Z, épaisseur Y)
    String dims(ArtPanel p) => '${p.w.round()}x${p.d.round()}x${p.h.round()}';
    expect(dims(cab.left), '702x560x18');
    expect(dims(cab.bottom), '600x560x18');
    expect(dims(cab.top), '564x560x18');
    expect(dims(cab.back), '564x684x18');
    expect(dims(cab.door), '597x717x18');
    // aucune pièce ne se chevauche sur la feuille
    for (var i = 0; i < art.free.length; i++) {
      for (var j = i + 1; j < art.free.length; j++) {
        final a = art.free[i], b = art.free[j];
        expect(a.right <= b.x + 0.01 || b.right <= a.x + 0.01 || a.back <= b.z + 0.01 || b.back <= a.z + 0.01, isTrue, reason: '${a.note} / ${b.note}');
      }
    }
    art.edgeLinks.addAll(cab.links);
    expect(art.applyEdgeLinks(), 5);
    final b = cab.bottom;
    // caisson monté : 600 de large, 720 de haut, 560 de profondeur
    final structure = cab.parts.where((p) => p != cab.door).toList();
    double lo(double Function(ArtPanel) f) => structure.map(f).reduce((a, c) => a < c ? a : c);
    double hi(double Function(ArtPanel) f) => structure.map(f).reduce((a, c) => a > c ? a : c);
    expect(hi((p) => p.right) - lo((p) => p.x), closeTo(600, 0.01));
    expect(hi((p) => p.top) - lo((p) => p.y), closeTo(720, 0.01));
    expect(hi((p) => p.back) - lo((p) => p.z), closeTo(560, 0.01));
    expect((cab.left.w, cab.left.h, cab.left.d), (18, 702, 560), reason: 'côté debout');
    expect(cab.left.y, b.top);
    expect(cab.left.x, b.x);
    expect(cab.right.right, b.right);
    expect(cab.top.top, closeTo(b.y + 720, 0.01));
    expect((cab.top.x, cab.top.right), (b.x + 18, b.right - 18));
    expect(cab.back.back, b.back);
    expect((cab.back.x, cab.back.right), (b.x + 18, b.right - 18));
    // porte en applique devant le caisson
    expect(cab.door.role, ArtRole.porte);
    expect(cab.door.back, b.z);
    expect((cab.door.w, cab.door.h, cab.door.d), (597, 717, 18));
    expect(cab.door.y, b.y);
    // pas de chevauchement une fois monté
    final checks = artChecks(art.panels, CutSettings(), jointCuts: art.jointCuts);
    expect(checks.where((c) => c.error), isEmpty, reason: checks.map((c) => c.message).join('\n'));
    final m = computeMachiningElements(art.panels, fittings: art.fittings, jointCuts: art.jointCuts, jointFits: art.jointFits);
    expect(m.dowelsCount, greaterThan(0));
    expect(m.screwsCount, greaterThan(0));
    expect(m.hingeCupsCount, greaterThan(0), reason: 'charnières de la porte');
    expect(m.elements.where((e) => e.panelId == cab.door.id && (e.kind == MachiningKind.dowel || e.kind == MachiningKind.screw)), isEmpty,
        reason: 'la porte n’est pas vissée au caisson');
  });

  test('feuille trop petite : rien n’est coupé', () {
    final art = ArtProject();
    final sheet = ArtPanel(id: art.newId(), role: ArtRole.decor, x: 0, y: 0, z: 0, w: 1200, h: 18, d: 600);
    art.free.add(sheet);
    expect(cutSheetCabinet(art, sheet), isNull);
    expect(art.free, [sheet]);
  });
}
