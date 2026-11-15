// La fiche de l'élément doit s'afficher sans erreur pour chaque modèle du catalogue
// (et pour un point de réseau), à l'étape Implantation comme à l'étape Style.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/main.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/theme.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'));

  testWidgets('fiche de chaque modèle, puis d\'un point de réseau', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(cat, db: db, project: Project(room: Room(width: 6000, depth: 4000, height: 2600)));
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light, googleFonts: false),
      darkTheme: buildTheme(Brightness.dark, googleFonts: false),
      themeMode: ThemeMode.dark,
      home: PlannerScreen(state: st, themeMode: ThemeMode.dark, onThemeMode: (_) {}),
    ));
    await t.pumpAndSettle();
    st.goTo(PlanStep.layout);
    await t.pumpAndSettle();
    final failures = <String>[];
    for (final m in cat.models) {
      st.edit(() => st.project.items.clear());
      final err = st.edit(() => st.engine.add(m.id, 'A', s: 1000));
      if (err != null) continue;
      for (final v in [null, ...m.variants, ...m.openingOptions]) {
        if (v != null) {
          st.edit(() {
            final c = st.project.items.first;
            if (m.variants.contains(v)) c.variant = v;
            if (m.openingOptions.contains(v)) c.opening = v;
          });
        }
        for (final step in [PlanStep.layout, PlanStep.style]) {
          st.goTo(step);
          st.select(st.project.items.first.uid);
          for (final view in ViewMode.values) {
            st.setView(view);
            await t.pumpAndSettle();
            final ex = t.takeException();
            if (ex != null) failures.add('${m.id} $v (${step.name}, ${view.name}) : $ex');
            if (find.byType(ErrorWidget).evaluate().isNotEmpty) failures.add('${m.id} $v (${step.name}) : ErrorWidget');
          }
        }
      }
      // composition personnalisée : le volet s'ouvre avec ses cases
      final c0 = st.project.items.first;
      if (rowsOf(m, c0) != null || (m.isCarcass && !m.kind.isCorner && !m.kind.isFiller)) {
        st.setItemLayout(c0.uid, seedRows(m, c0));
        st.goTo(PlanStep.layout);
        st.select(c0.uid);
        st.setView(ViewMode.front);
        await t.pumpAndSettle();
        final ex = t.takeException();
        if (ex != null) failures.add('${m.id} composition : $ex');
      }
      st.goTo(PlanStep.layout);
    }
    // cuisine complète avec réseaux, chaque élément sélectionné
    st.goTo(PlanStep.layout);
    st.autoKitchen();
    st.setNetworks(true);
    for (final c in [...st.project.items]) {
      st.select(c.uid);
      st.setView(ViewMode.front);
      await t.pumpAndSettle();
      final ex = t.takeException();
      if (ex != null) failures.add('cuisine ${c.modelId} : $ex');
    }
    // point de réseau
    st.edit(() => st.project.items.clear());
    st.addPoint(NetKind.waterCold);
    await t.pumpAndSettle();
    final ex = t.takeException();
    if (ex != null) failures.add('point : $ex');
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  testWidgets('volet Composition : fermer puis rouvrir ne casse pas le champ H mm', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(cat, db: db, project: Project(room: Room(width: 6000, depth: 4000, height: 2600)));
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
    await t.pumpAndSettle();
    st.goTo(PlanStep.layout);
    st.edit(() => st.engine.add('base_door_drawer', 'A', s: 1000));
    final c = st.project.items.first;
    st.setItemLayout(c.uid, seedRows(st.engine.modelOf(c), c));
    st.select(c.uid);
    await t.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await t.ensureVisible(find.text('Composition de la façade'));
      await t.tap(find.text('Composition de la façade'));
      await t.pumpAndSettle();
    }
    expect(t.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('H mm'), findsWidgets);
  });
}
