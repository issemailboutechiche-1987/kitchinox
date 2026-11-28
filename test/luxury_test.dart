// « Luxury Kitchen » : chaque ambiance n'utilise que des finitions connues, et l'appliquer règle tout le projet.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/finishes.dart';
import 'package:kitchen_planner/ui/luxury_styles.dart';

void main() {
  late Catalog cat;
  setUpAll(() => cat = Catalog.parse(File('assets/catalog.json').readAsStringSync()));

  test('chaque ambiance n’utilise que des finitions, luminaires et sols connus', () {
    bool has(List<Finish> l, String? id) => id == null || l.any((f) => f.id == id);
    expect(luxuryStyles.length, greaterThanOrEqualTo(10));
    for (final l in luxuryStyles) {
      for (final id in [l.front, l.upper, l.lower, l.island]) {
        expect(has(fronts, id), isTrue, reason: '${l.id} : façade $id');
      }
      expect(has(worktops, l.worktop), isTrue, reason: '${l.id} : plan ${l.worktop}');
      expect(has(floors, l.floor), isTrue, reason: '${l.id} : sol ${l.floor}');
      expect(has(walls, l.wall), isTrue, reason: '${l.id} : murs ${l.wall}');
      expect(l.splash == null || l.splash == 'plan' || has(splashes, l.splash), isTrue, reason: '${l.id} : crédence ${l.splash}');
      expect(lightSourceById(l.lightGeneral), isNotNull, reason: '${l.id} : ${l.lightGeneral}');
      expect(lightSourceById(l.lightIsland), isNotNull, reason: '${l.id} : ${l.lightIsland}');
      expect(frontProfiles.containsKey(l.profile), isTrue);
    }
  });

  test('appliquer une ambiance règle façades, plan, lumière ; une seule annulation', () {
    final st = AppState(cat, project: Project(room: Room(width: 4000, depth: 3000, height: 2600)));
    st.engine.autoFillWall('A', Band.low);
    final l = luxuryStyles.firstWhere((x) => x.id == 'foret_cannele');
    applyLuxury(st, l);
    final s = st.project.style;
    expect(s.frontUpper, 'noyer');
    expect(s.frontLower, 'vert_foret');
    expect(s.profileByZone['haut'], 'cannelee');
    expect(s.worktop, 'beton');
    expect(st.project.specs.lighting.general, 'rail_magnetique_48v');
    st.undo();
    expect(st.project.style.frontUpper, isNull);
  });

  testWidgets('galerie : une vignette par ambiance', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(cat, project: Project(room: Room(width: 4000, depth: 3000, height: 2600)));
    String? msg;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (ctx) => Center(child: FilledButton(onPressed: () => showLuxuryGallery(ctx, st, (m) => msg = m), child: const Text('ouvrir')))))));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    for (final l in luxuryStyles) {
      expect(find.byKey(ValueKey('luxury_${l.id}')), findsOneWidget);
    }
    await expectLater(find.byKey(const ValueKey('luxury_dialog')), matchesGoldenFile('goldens/luxury_gallery.png'));
    await t.tap(find.byKey(const ValueKey('luxury_nuit_laiton')));
    await t.pumpAndSettle();
    expect(st.project.style.worktop, 'marbre_noir');
    expect(msg, contains('Nuit'));
  });
}
