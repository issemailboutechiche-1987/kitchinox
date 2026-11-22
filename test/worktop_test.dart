// Plan de travail : un seul choix (rendu, prix, devis, plans d'accord) ; crédence dans la même matière.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/finishes.dart';
import 'package:kitchen_planner/ui/panels.dart';
import 'package:kitchen_planner/ui/toolbar.dart';

void main() {
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  AppState kitchen() {
    final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'), handles: f('handles'));
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()), db: db);
    st.engine.applyShape(RoomShape.linear);
    st.engine.add('base_sink', 'A', s: 0, width: 800);
    st.engine.add('base_standard_2doors', 'A', s: 800);
    return st;
  }

  SupplyLine top(AppState st) => st.estimateLines.firstWhere((l) => l.section == 'Plan de travail' && l.unit == 'm.l.');

  test('chaque coloris a un rendu, une matière du tarif et un prix ; chaque prix du tarif a son coloris', () {
    final st = kitchen();
    for (final e in worktopLooks.entries) {
      expect(worktops.where((x) => x.id == e.key), hasLength(1), reason: e.key);
      final m = st.db!.worktop(e.value.$1);
      expect(m, isNotNull, reason: e.key);
      expect(e.value.$2, lessThan(m!.variants.length), reason: e.key);
    }
    for (final w in worktops) {
      expect(worktopLooks.containsKey(w.id), isTrue, reason: w.id);
    }
    for (final m in st.db!.worktops) {
      for (var i = 0; i < m.variants.length; i++) {
        expect(worktopLooks.values.contains((m.id, i)), isTrue, reason: '${m.id} $i');
      }
    }
  });

  test('choisir le coloris change la matière et le prix du devis ; choisir la matière change le rendu', () {
    final st = kitchen();
    st.setStyle(worktop: 'granit_gris');
    expect(top(st).name, contains('Granit'));
    expect(top(st).unitPrice.min, 650);
    expect((st.project.specs.worktopMaterial, st.project.specs.worktopVariant), ('granit_naturel', 0));
    st.setWorktopMaterial('marbre_naturel');
    expect(worktopLooks[st.project.style.worktop]!.$1, 'marbre_naturel');
    expect(top(st).name, contains('Marbre'));
    // ancien projet incohérent (rendu granit, devis quartz) : le devis suit ce qu'on voit
    st.project.style.worktop = 'granit_noir';
    st.project.specs
      ..worktopMaterial = 'quartz_synthese'
      ..worktopVariant = 0;
    st.refresh();
    final lines = estimate(st.engine, st.db!, st.project.specs, st.cutPlan, st.bom);
    expect(lines.firstWhere((l) => l.section == 'Plan de travail').name, contains('Granit'));
    // épaisseur impossible dans cette matière : la plus courante
    st.project.specs.worktopThickness = 12;
    expect(estimate(st.engine, st.db!, st.project.specs, st.cutPlan, st.bom).firstWhere((l) => l.section == 'Plan de travail').detail, contains('30 mm'));
  });

  test('crédence comme le plan : même rendu, surface au devis ; relevé de 10 cm', () {
    final st = kitchen();
    st.setStyle(worktop: 'marbre_noir');
    expect(st.estimateLines.any((l) => l.name.startsWith('Crédence')), isFalse);
    st.setRoomFinish(splash: splashLikeTop);
    expect(splashFinish(st.project.style).id, 'marbre_noir');
    final line = st.estimateLines.firstWhere((l) => l.name == 'Crédence assortie');
    expect(line.qty, closeTo(splashArea(st.engine), 0.01));
    expect(line.unitPrice.min, closeTo(1700 / 0.6, 0.01));
    final full = splashArea(st.engine);
    st.setRoomFinish(splash: splashUpstand);
    expect(splashArea(st.engine), lessThan(full / 3));
    expect(splashSegments(st.engine).every((s) => s.z1 - s.z0 <= 100.01), isTrue);
    expect(st.estimateLines.any((l) => l.name == 'Relevé assorti 10 cm'), isTrue);
    // le coloris change : la crédence suit
    st.setStyle(worktop: 'granit_gris');
    expect(splashFinish(st.project.style).id, 'granit_gris');
  });

  testWidgets('étape Style : matière, coloris, épaisseur, crédence dans la même fiche', (t) async {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = kitchen();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 420, child: ListenableBuilder(listenable: st, builder: (_, _) => StylePanel(state: st, section: StyleSection.worktop))))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('wt_granit_naturel')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('look_granit_rose')), findsOneWidget);
    expect(find.byKey(const ValueKey('look_marbre')), findsNothing, reason: 'seulement les coloris de la matière');
    await t.tap(find.byKey(const ValueKey('look_granit_rose')));
    await t.pumpAndSettle();
    expect(st.project.style.worktop, 'granit_rose');
    await t.ensureVisible(find.byKey(const ValueKey('splash_plan')));
    await t.tap(find.byKey(const ValueKey('splash_plan')));
    await t.pumpAndSettle();
    expect(st.project.style.splash, splashLikeTop);
    expect(t.takeException(), isNull);
  });
}
