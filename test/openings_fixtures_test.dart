// Portes et fenêtres du catalogue, pose sur un espace libre, guides d'alignement, point d'eau exigé,
// éviers et mitigeurs, appareillage électrique, avancement du plan d'exécution.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/main.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/canvas_view.dart';
import 'package:kitchen_planner/ui/pdf_export.dart';

AppState kitchen() => AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));

void main() {
  setUpAll(() {
    OpeningModel.parse(File('assets/data/openings.json').readAsStringSync());
    KitchenFixtures.parse(File('assets/data/accessories.json').readAsStringSync());
  });

  test('catalogue : 10 portes, 10 fenêtres, cotes standard, mécanismes', () {
    final all = OpeningModel.byId.values;
    expect(all.where((m) => m.door).length, 10);
    expect(all.where((m) => !m.door).length, 10);
    final pocket = OpeningModel.byId['door_sliding_pocket']!;
    expect(pocket.sliding && pocket.pocket, isTrue);
    expect(pocket.swing(830), 0); // coulissante : pas de débattement
    expect(OpeningModel.byId['door_french_double']!.twoLeaves, isTrue);
    expect(OpeningModel.byId['window_awning_hopper']!.defaultSill, 1600); // soufflet de salle de bain : en hauteur
    expect(OpeningModel.byId['window_sliding']!.defaultSill, 0); // baie : au sol
  });

  test('une porte ne se pose jamais sur un caisson : espace libre du mur, sinon un autre mur', () {
    final st = kitchen();
    st.engine.add('base_drawers_multi', 'A', s: 0, width: 800);
    st.engine.add('base_sink', 'A', s: 800, width: 1000);
    st.engine.add('base_drawers_multi', 'A', s: 1800, width: 800);
    st.setWall('A');
    expect(st.addOpening('door', model: 'door_interior_flush'), isNull);
    final d = st.project.openings.single;
    expect(d.model, 'door_interior_flush');
    expect(d.width, 830);
    // le mur A (3600) est occupé de 0 à 2600 : la porte est dans les 1000 mm restants
    expect(d.wallId, 'A');
    expect(d.s, greaterThanOrEqualTo(2600));
    // une deuxième porte : plus de place sur A, elle part sur un autre mur
    final msg = st.addOpening('door');
    expect(msg, contains('occupé'));
    expect(st.project.openings.last.wallId, isNot('A'));
    // glisser la première sur les caissons : elle reste au bord libre
    st.beginDrag();
    st.dragOpeningTo(d.uid, s: 300);
    st.endDrag();
    expect(d.s, greaterThanOrEqualTo(2600));
  });

  test('fenêtre au-dessus des caissons bas : autorisée ; derrière un élément haut : non', () {
    final st = kitchen();
    st.engine.add('base_sink', 'A', s: 1300, width: 1000);
    st.setWall('A');
    expect(st.addOpening('window', model: 'window_casement_french'), isNull);
    final w = st.project.openings.single;
    expect(w.z, 1050);
    // guide : glissée près du centre de l'évier, elle s'y centre
    st.beginDrag();
    st.dragOpeningTo(w.uid, s: 1300 + 500 - w.width / 2 + 25);
    expect(w.s + w.width / 2, closeTo(1800, 0.5));
    expect(st.guides.single.label, contains('centré sur'));
    st.endDrag();
    expect(st.guides, isEmpty);
  });

  test('point d\'eau exigé en cuisine et salle de bain avant l\'implantation', () {
    final st = kitchen();
    expect(st.next(), contains('arrivée d’eau'));
    expect(st.step, PlanStep.space);
    st.addExistingWater(NetKind.waterCold);
    st.addExistingWater(NetKind.waterCold); // plusieurs possibles
    expect(st.existingCount(false), 2);
    expect(st.next(), isNull);
    expect(st.step, PlanStep.layout);
  });

  test('évier et mitigeur choisis : récapitulatif ; appareillage électrique dans les réseaux', () {
    final st = kitchen();
    st.engine.add('base_sink', 'A', s: 0, width: 1000);
    st.edit(() => st.project.style
      ..sink = 'sink_2_bowls'
      ..faucet = 'faucet_mixer_pullout'
      ..sinkMount = 'undermount');
    final lines = st.bom.lines.where((l) => l.section == 'Équipements cuisine').toList();
    expect(lines.map((l) => l.name), containsAll(['Évier 2 Bacs', 'Mitigeur avec Douchette Extractible']));
    expect(lines.first.details, contains('sous plan'));
    expect(KitchenFixtures.brands, contains('Legrand'));
    for (final k in [NetKind.switchDouble, NetKind.usb, NetKind.rj45, NetKind.tvSat]) {
      st.addPoint(k);
    }
    expect(st.project.points.where((x) => x.kind == NetKind.rj45).single.z, 300);
    expect(st.project.points.where((x) => x.kind == NetKind.usb).single.z, NetHeights.switchZ);
  });

  testWidgets('plan d\'exécution : avancement de 0 à 100 %', (t) async {
    final st = kitchen();
    st.engine.add('base_sink', 'A', s: 0, width: 1000);
    st.engine.addOpening('door', 'D', s: 2000, model: 'door_french_double');
    final steps = <double>[];
    await t.runAsync(() => buildExecutionPdf(st.engine, pixelRatio: 0.4, onProgress: (f, _) => steps.add(f)));
    expect(steps.first, lessThan(0.1));
    expect(steps.last, 1);
    for (var i = 1; i < steps.length; i++) {
      expect(steps[i], greaterThanOrEqualTo(steps[i - 1]));
    }
    expect(st.bom.lines.where((l) => l.section == 'Menuiseries').single.name, contains('Double Vitrée'));
  });

  for (final tab in ['Portes', 'Fenêtres']) {
    testWidgets('capture : catalogue des $tab', (t) async {
      t.view.physicalSize = const Size(1180, 820);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final st = kitchen();
      await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
      await t.pumpAndSettle();
      await t.tap(find.text('Portes et fenêtres'));
      await t.pumpAndSettle();
      if (tab == 'Fenêtres') {
        await t.tap(find.text('Fenêtres'));
        await t.pumpAndSettle();
      }
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/menuiseries_${tab == 'Portes' ? 'portes' : 'fenetres'}.png'));
    });
  }

  test("îlot : refusé s'il n'a pas 1 m de passage tout autour ; ancien îlot mal placé : « Retirer l'îlot »", () {
    final st = kitchen(); // 3600 x 3000
    st.engine.applyShape(RoomShape.uShape);
    st.engine.addOpening('door', 'D', s: 1200);
    expect(st.addIsland(), contains('Pas assez de place pour un îlot'));
    expect(st.project.room.island, isNull);
    // îlot d'un ancien projet, coincé : la correction propose de le retirer
    st.project.room.island = Island(x0: 1200, y0: 1150, length: 1200);
    final issue = st.issues.firstWhere((i) => i.code == 'island_aisle');
    final fix = fixFor(st.engine, issue);
    expect(fix.label, contains('Retirer'));
    expect(st.applyFix(issue), isNotNull);
    expect(st.project.room.island, isNull);
  });

  testWidgets("îlot : un toucher sur le plan ouvre ses réglages (passages, replacer, supprimer)", (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = kitchen();
    st.updateRoom(width: 5400, depth: 4200);
    st.engine.applyShape(RoomShape.lShape);
    expect(st.addIsland(), isNull);
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
    await t.pumpAndSettle();
    st.goTo(PlanStep.layout);
    st.setView(ViewMode.plan);
    await t.pumpAndSettle();
    // centre de l'îlot à l'écran : rapport entre le plan (mm) et la zone de dessin
    final isl = st.project.room.island!;
    final c = t.getRect(find.byType(PlannerCanvas));
    final k = (c.height - 160) / (st.project.room.depth + 240);
    final center = c.center + Offset((isl.x0 + isl.length / 2 - st.project.room.width / 2) * k, (isl.y0 + 450 - st.project.room.depth / 2) * k);
    await t.tapAt(center);
    await t.pumpAndSettle();
    expect(find.text('Replacer automatiquement'), findsOneWidget);
    expect(find.textContaining('fond '), findsWidgets);
  });
}
