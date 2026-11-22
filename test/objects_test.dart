// Bibliothèque d'objets : sanitaires paramétriques et objets CC0 ; pose, mur, dégagements, panneau et fiche.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/main.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/objects_panel.dart';

AppState _state() => AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()))
  ..objectCatalog = CatalogObject.parse(File('assets/data/objects.json').readAsStringSync());

void main() {
  test('catalogue libre : fichiers présents, cotes réelles, licence CC0', () {
    final cat = CatalogObject.parse(File('assets/data/objects.json').readAsStringSync());
    expect(cat.length, greaterThan(100));
    expect(File('web/objects/kenney/LICENSE.txt').readAsStringSync(), contains('CC0'));
    for (final o in cat) {
      expect(File('web/${o.file}').existsSync(), isTrue, reason: o.file);
      expect(o.w > 0 && o.h > 0 && o.d > 0, isTrue, reason: o.id);
    }
    expect(cat.where((o) => o.category == 'Salle de bain').length, greaterThanOrEqualTo(10));
    // modèles réalistes Poly Haven (CC0) ; les modèles Kenney qu'ils remplacent sont masqués du catalogue
    expect(cat.where((o) => o.source == 'Poly Haven' && !o.hidden).length, greaterThanOrEqualTo(20));
    expect(File('web/objects/polyhaven/LICENSE.txt').readAsStringSync(), contains('CC0'));
    expect(cat.where((o) => o.hidden).every((o) => o.source == 'Kenney'), isTrue);
  });

  test('sanitaire posé contre le mur A, glissé vers le mur B : dos au mur, tourné', () {
    final st = _state();
    st.addObject('fixture:wc_suspendu');
    final o = st.project.objects.single;
    expect(o.rot, 0);
    expect(o.y, o.d / 2); // dos contre le mur A
    st.dragObjectTo(o.uid, st.project.room.width - 200, 1500);
    expect(o.rot, 90);
    expect(o.x, st.project.room.width - o.d / 2);
    // sauvegarde / relecture
    final back = Project.fromJson(jsonDecode(jsonEncode(st.project.toJson())) as Map<String, dynamic>);
    expect(back.objects.single.ref, 'fixture:wc_suspendu');
    expect(back.objects.single.rot, 90);
  });

  test('dégagement devant un WC encombré : avertissement', () {
    final st = _state();
    st.addObject('fixture:wc_sol');
    final wc = st.project.objects.single;
    st.addObject('kenney_bathroomCabinet');
    final cab = st.project.objects.last;
    st.editObject(cab.uid, (c) {
      c
        ..x = wc.x
        ..y = wc.y + wc.d / 2 + 200
        ..rot = 0;
    });
    expect(st.issues.any((i) => i.code == 'fixture_clearance'), isTrue);
    st.deleteObject(cab.uid);
    expect(st.issues.any((i) => i.code == 'fixture_clearance'), isFalse);
  });

  test('points d\'eau d\'un lavabo : froide, chaude, évacuation sur le mur du lavabo', () {
    final st = _state();
    st.addObject('fixture:lavabo');
    final pts = fixtureWaterPoints(st.project.room, st.project.objects);
    expect(pts.map((p) => p.$4).toSet(), {'froide', 'chaude', 'evac'});
    expect(pts.every((p) => p.$1 == 'A'), isTrue);
  });

  testWidgets('panneau Objets : un clic pose l\'objet, la fiche remplace le panneau', (t) async {
    t.view.physicalSize = const Size(1180, 820);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = _state();
    st.project.universe = 'bain'; // les sanitaires ne sont proposés que dans la salle de bain
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
    await t.pumpAndSettle();
    st.goTo(PlanStep.layout);
    await t.pumpAndSettle();
    await t.tap(find.text('Objets').first);
    await t.pumpAndSettle();
    expect(find.byType(ObjectsPanel), findsOneWidget);
    await t.tap(find.text('Baignoire').first);
    await t.pumpAndSettle();
    expect(st.project.objects.single.ref, 'fixture:baignoire');
    expect(find.byType(ObjectsPanel), findsNothing);
    expect(find.byType(ObjectCard), findsOneWidget);
    await t.tap(find.text('Tourner'));
    await t.pumpAndSettle();
    expect(st.project.objects.single.rot, 90);
    // ouvrir le menu des éléments ferme le panneau Objets
    st.openObjects(true);
    st.toggleMegaMenu(true);
    expect(st.objectsPanel, isFalse);
    expect(t.takeException(), isNull);
  });
}
