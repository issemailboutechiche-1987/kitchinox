// Session : sauvegarde automatique, reprise, et question « enregistrer / quitter sans enregistrer » en sortant.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'start_helper.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/main.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/logo.dart';
import 'package:kitchen_planner/ui/session.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  test('copie de travail, version enregistrée, modifications en cours', () {
    Session.setEmpty('essai', '{}');
    expect(Session.dirty('essai', '{}'), isFalse);
    Session.saveNow('essai', '{"a":1}');
    expect(Session.work('essai'), '{"a":1}');
    expect(Session.dirty('essai', '{"a":1}'), isTrue);
    Session.commit('essai', '{"a":1}');
    expect(Session.dirty('essai', '{"a":1}'), isFalse);
    expect(Session.dirty('essai', '{"a":2}'), isTrue);
    Session.route = 'dressing';
    expect(Session.route, 'dressing');
    Session.route = 'home';
  });

  testWidgets('quitter la cuisine avec des modifications : la question, puis « Quitter sans enregistrer » annule', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Session.setEmpty('cuisine', projectWorkJson(Project().toJson()));
    final st = AppState(cat);
    await t.runAsync(() async => LogoShape.load());
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false, showHome: true));
    await t.pump(const Duration(milliseconds: 3000));
    await t.tap(find.text('Cuisine'));
    await startNewProject(t);
    st.edit(() => st.engine.add('base_standard_single_door', 'A', s: 0, width: 600));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Accueil'));
    await t.pumpAndSettle();
    expect(find.text('Enregistrer votre travail ?'), findsOneWidget);
    await t.tap(find.text('Quitter sans enregistrer'));
    await t.pumpAndSettle();
    expect(find.text('Débitage'), findsOneWidget); // retour à l'accueil
    expect(st.project.items, isEmpty); // travail abandonné

    // cette fois on enregistre : plus de question au retour suivant
    await t.tap(find.text('Cuisine'));
    await startNewProject(t);
    st.edit(() => st.engine.add('base_standard_single_door', 'A', s: 0, width: 600));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Accueil'));
    await t.pumpAndSettle();
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(st.project.items, hasLength(1));
    final saved = jsonDecode(Session.saved('cuisine')!) as Map<String, dynamic>;
    expect((saved['items'] as List).length, 1);
    await t.tap(find.text('Cuisine'));
    await t.pumpAndSettle();
    await t.tap(find.text('Reprendre le travail en cours'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Accueil'));
    await t.pumpAndSettle();
    expect(find.text('Enregistrer votre travail ?'), findsNothing);
  });
}
