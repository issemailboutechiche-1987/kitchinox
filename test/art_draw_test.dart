// Atelier : dessin façon SketchUp sur feuilles de bois — rectangle dans le plan de travail (au sol : tablette),
// cotes tapées, Pousser/Tirer au glisser, raccourcis clavier, rôle du panneau ; usinage affiché en 3D.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/art_page.dart';
import 'package:kitchen_planner/ui/theme.dart';

void main() {
  testWidgets('rectangle au sol → tablette ; cotes tapées ; Pousser/Tirer au glisser ; raccourcis', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: ArtPage(state: st)));
    await t.pumpAndSettle();
    final art = st.project.art;
    final vp = t.getRect(find.byKey(const Key('art-viewport')));

    // R : outil rectangle ; deux clics au sol
    await t.sendKeyEvent(LogicalKeyboardKey.keyR);
    await t.pumpAndSettle();
    await t.tapAt(vp.center + const Offset(-120, 40));
    await t.pumpAndSettle();
    await t.tapAt(vp.center + const Offset(80, 120));
    await t.pumpAndSettle();
    expect(art.free, hasLength(1));
    final a = art.free.single;
    expect(a.role, ArtRole.tablette, reason: 'dessiné au sol : panneau horizontal');
    expect(a.h, 18);
    expect(a.w, greaterThan(50));
    expect(a.d, greaterThan(50));

    // cotes exactes : 1er coin, puis « 600;400 » + Entrée au clavier
    await t.tapAt(vp.center + const Offset(150, -60));
    await t.pumpAndSettle();
    for (final k in [
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.semicolon,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit0,
    ]) {
      await t.sendKeyEvent(k);
    }
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(art.free, hasLength(2));
    final b = art.free.last;
    expect((b.w, b.h, b.d), (600, 18, 400));

    // P : Pousser/Tirer ; glisser la face du dessus vers le haut épaissit le panneau
    await t.sendKeyEvent(LogicalKeyboardKey.keyP);
    await t.pumpAndSettle();
    final h0 = b.h;
    // centre de la face du dessus de b, à l'écran : on vise le centre du panneau
    final top = vp.topLeft + _project(t, b);
    await t.dragFrom(top, const Offset(0, -60));
    await t.pumpAndSettle();
    expect(b.h, greaterThan(h0), reason: 'la face du dessus monte');
    // une cote tapée ensuite règle la poussée exactement
    await t.enterText(find.byKey(const ValueKey('cad_measure')), '100');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(b.h, 118);
    expect(t.takeException(), isNull);
  });

  testWidgets('caisson posé : usinage affiché (tourillons, vis, charnières, poignées, chants)', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    st.project.art.addBox(0, 100, 800, 720, depth: 560, doors: 2);
    st.project.art.addDrawn(18, 460, 764, 18, depth: 540, role: ArtRole.tablette);
    st.project.art.free.last
      ..x = 19
      ..w = 762;
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: ArtPage(state: st)));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Activer le Mode Usinage (Tourillons, Vis, Perçages 32mm, Chants)'));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/art_usinage.png'));
    expect(t.takeException(), isNull);
  });

  testWidgets('tablette : appuyer, glisser, lâcher → la forme se voit pendant le tracé, avec ses points et sa cote', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: ArtPage(state: st)));
    await t.pumpAndSettle();
    final vp = t.getRect(find.byKey(const Key('art-viewport')));
    await t.sendKeyEvent(LogicalKeyboardKey.keyR);
    await t.pumpAndSettle();
    final g = await t.startGesture(vp.center + const Offset(-150, 20), kind: PointerDeviceKind.touch);
    await t.pump();
    for (var i = 1; i <= 6; i++) {
      await g.moveBy(const Offset(40, 20));
      await t.pump();
    }
    final s = t.state(find.byType(ArtPage)) as dynamic;
    expect((s.activePoints as List).length, 1, reason: 'le 1er coin est posé dès l’appui');
    expect(s.previewShape, isNotNull, reason: 'le rectangle se dessine pendant le glisser');
    await expectLater(find.byKey(const Key('art-viewport')), matchesGoldenFile('goldens/art_trace_en_cours.png'));
    await g.up();
    await t.pumpAndSettle();
    expect(st.project.art.free, hasLength(1));
    expect(st.project.art.free.single.role, ArtRole.tablette);
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 6)); // enregistrement automatique différé et message
  });

  testWidgets('sélection : propriétés ouvertes, Ctrl+clic ajoute, Suppr efface ; chants et rainures visibles', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    final art = st.project.art;
    art.addBox(0, 100, 800, 720, depth: 560, doors: 0);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: ArtPage(state: st)));
    await t.pumpAndSettle();
    await expectLater(find.byKey(const Key('art-viewport')), matchesGoldenFile('goldens/art_chants_rainures.png'));
    final vp = t.getRect(find.byKey(const Key('art-viewport')));
    final s = t.state(find.byType(ArtPage)) as dynamic;
    Offset at(ArtPanel q) => vp.topLeft + (s.screenOf(q.x + math.min(q.w / 2, 60), q.top, q.z + 40) as Offset);
    final left = art.free[0], right = art.free[3]; // côté gauche et dessus
    // clic : le panneau est sélectionné et ses propriétés s'ouvrent
    await t.tapAt(at(left));
    await t.pumpAndSettle();
    expect(s.selectedPanel, same(left));
    expect(find.byKey(const ValueKey('art_props')), findsOneWidget);
    // Ctrl + clic : on ajoute le dessus
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.tapAt(at(right));
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect((s.selection as Set).length, 2);
    // Suppr : les deux disparaissent ; Ctrl+Z les remet
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.pumpAndSettle();
    expect(art.free.contains(left) || art.free.contains(right), isFalse);
    expect(art.free, hasLength(3));
    expect(find.byKey(const ValueKey('art_props')), findsNothing);
    await t.pump(const Duration(seconds: 6));
    expect(t.takeException(), isNull);
  });

  testWidgets('feuille entière : poser, couper en X à 600 puis en Y à 400, trait de scie déduit', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    PublicPrices.parse(File('assets/data/public_prices.json').readAsStringSync());
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    final art = st.project.art;
    final kerf = st.project.cut.kerf.toDouble();
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: ArtPage(state: st)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('start_sheet')));
    await t.pumpAndSettle();
    expect(art.free, hasLength(1));
    final sheet = art.free.single;
    final trim = st.project.cut.trim;
    expect((sheet.w, sheet.h, sheet.d), (2800 - 2 * trim, 18, 2100 - 2 * trim), reason: 'MDF blanc 18 du tarif, à plat, bords recoupés');
    // la feuille est la cible : coupe X tapée
    final s = t.state(find.byType(ArtPage)) as dynamic;
    expect(s.activeTool.toString(), contains('cut'));
    await t.enterText(find.byKey(const ValueKey('cad_measure')), '600');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(art.free, hasLength(2));
    final a = art.free[0], b = art.free[1];
    expect(a.w, 600);
    expect(b.x, 600 + kerf);
    expect(a.w + b.w + kerf, 2800 - 2 * trim);
    // coupe Y sur la grande chute : 400 depuis son bord
    await t.tap(find.text('Coupe Y'));
    await t.pumpAndSettle();
    s.selectedPanel = b;
    await t.enterText(find.byKey(const ValueKey('cad_measure')), '400');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(art.free, hasLength(3));
    final c = art.free.firstWhere((q) => q.x == b.x && q.d == 400);
    expect(c.w, b.w);
    expect(art.free.where((q) => q.x == b.x).fold<double>(0, (sum, q) => sum + q.d) + kerf, 2100 - 2 * trim);
    // le débit retrouve les pièces sur une seule feuille
    final plan = art.plan(st.project.cut);
    expect(plan.sheets, hasLength(1));
    await t.pump(const Duration(seconds: 6));
    expect(t.takeException(), isNull);
  });
}

/// Point écran du centre du dessus d'un panneau (par la caméra de la page).
Offset _project(WidgetTester t, ArtPanel p) {
  final s = t.state(find.byType(ArtPage)) as dynamic;
  return s.screenOf(p.x + p.w / 2, p.top, p.z + p.d / 2) as Offset;
}
