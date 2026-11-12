// Corrections du second audit : numéro de plan gardé en annulant, cote inchangée en pouces,
// une seule optimisation de débit par jeu de pièces.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_settings.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/header.dart';

AppState kitchen() => AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));

void main() {
  final s = AppSettings.instance;
  tearDown(() {
    s
      ..unit = LenUnit.mm
      ..numbering = true;
    for (final k in DocKind.values) {
      s.next[k] = 1;
    }
    AppState.backgroundNest = false;
    AppState.backgroundFrom = 40;
  });

  test('numéro de plan : annuler une modification ne le fait pas perdre (pas de second numéro)', () {
    final st = kitchen();
    st.engine.applyShape(RoomShape.linear);
    st.edit(() => st.engine.add('base_sink', 'A', s: 0, width: 800));
    st.edit(() => st.engine.add('base_drawers_multi', 'A', s: 800, width: 600));
    final n1 = s.numberFor(st.project, DocKind.exec); // PDF émis
    st.undo(); // retour à un état d'avant l'export
    expect(st.project.client.numbers['exec'], n1);
    expect(s.numberFor(st.project, DocKind.exec), n1, reason: 'réédition : même numéro');
    st.redo();
    expect(st.project.client.numbers['exec'], n1);
    expect(s.next[DocKind.exec], 2, reason: 'un seul numéro consommé');
  });

  test('pouces : un champ laissé tel quel ne change pas la cote ; une vraie saisie est lue', () {
    // 601 mm s'affiche « 23 11/16 », qui vaut 601,7 mm : sans précaution la pièce passait à 602
    expect(lenValue(601, unit: LenUnit.inch), '23 11/16');
    expect(parseLen('23 11/16', unit: LenUnit.inch)!.round(), 602);
    s.unit = LenUnit.inch;
    expect(editedLen('23 11/16', 601), 601);
    expect(editedLen(' 23 11/16 ', 601), 601);
    expect(editedLen('24', 601), closeTo(609.6, 1e-9));
    s.unit = LenUnit.mm;
    expect(editedLen('601', 601), 601);
    expect(editedLen('605', 601), 605);
  });

  // avant les tests d'interface : leur horloge simulée bloquerait le calcul en arrière-plan
  test('débit en arrière-plan : la même demande pendant le calcul ne relance rien', () async {
    AppState.backgroundNest = true;
    AppState.backgroundFrom = 0;
    final st = kitchen();
    st.engine.applyShape(RoomShape.linear);
    st.engine.add('base_sink', 'A', s: 0, width: 800);
    st.engine.add('base_drawers_multi', 'A', s: 800, width: 600);
    st.refresh();
    final before = PerformanceProfiler.instance.stats['nesting']?.count ?? 0;
    final a = st.cutPlanReady(), b = st.cutPlanReady();
    final plans = await Future.wait([a, b]);
    expect(identical(plans[0], plans[1]), isTrue);
    expect((PerformanceProfiler.instance.stats['nesting']?.count ?? 0) - before, 1, reason: 'une seule optimisation');
    expect(plans[0].sheets, isNotEmpty);
  });

  testWidgets('pouces : sortir du champ Largeur sans rien taper ne modifie pas la pièce', (t) async {
    s.unit = LenUnit.inch;
    double? submitted;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      MmField(label: 'Largeur', value: 3601, onSubmit: (v) => submitted = v),
      const TextField(key: Key('autre')),
    ]))));
    await t.tap(find.byType(TextField).first);
    await t.pump();
    await t.tap(find.byKey(const Key('autre'))); // perte du focus
    await t.pump();
    expect(submitted, isNull);
    await t.enterText(find.byType(TextField).first, '150');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(submitted, closeTo(3810, 0.5), reason: '150 pouces = 3810 mm');
  });

}
