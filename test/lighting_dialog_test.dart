// Menu « Lumière de la pièce » : miniatures, calcul automatique, aperçu du plafond (capture).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/lighting_ui.dart';

void main() {
  testWidgets('menu Lumière : miniatures, Auto pose les luminaires, aperçu à jour', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
    final st = AppState(cat, project: Project(room: Room(width: 4000, depth: 3000, height: 2600)));
    st.engine.autoFillWall('A', Band.low);
    st.engine.autoFillWall('A', Band.high);
    String? msg;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (ctx) => Center(child: FilledButton(onPressed: () => showLightingDialog(ctx, st, (m) => msg = m), child: const Text('ouvrir'))))),
    ));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('lighting_dialog')), findsOneWidget);
    expect(find.text('Spot anti-éblouissement'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('lighting_auto')));
    await t.pumpAndSettle();
    expect(msg, contains('points lumineux'));
    expect(st.project.points.where((x) => x.kind == NetKind.light && x.onCeiling), isNotEmpty);
    expect(find.text('La pièce est bien éclairée'), findsOneWidget);
    await expectLater(find.byKey(const ValueKey('lighting_dialog')), matchesGoldenFile('goldens/lighting_dialog.png'));
    // un plafonnier seul : pas assez de lumière ou trop peu réparti → le verdict suit le choix
    await t.tap(find.byKey(const ValueKey('light_src_spot_halogene_gu10_mr16')));
    await t.pumpAndSettle();
    expect(find.textContaining('éblouir').evaluate().isNotEmpty || find.textContaining('fois plus').evaluate().isNotEmpty, isTrue);
  });
}
