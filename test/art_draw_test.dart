// Atelier : dessin façon SketchUp sur feuilles de bois — rectangle dans le plan de travail (au sol : tablette),
// cotes tapées, Pousser/Tirer au glisser, raccourcis clavier, rôle du panneau ; usinage affiché en 3D.
import 'dart:io';

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
}

/// Point écran du centre du dessus d'un panneau (par la caméra de la page).
Offset _project(WidgetTester t, ArtPanel p) {
  final s = t.state(find.byType(ArtPage)) as dynamic;
  return s.screenOf(p.x + p.w / 2, p.top, p.z + p.d / 2) as Offset;
}
