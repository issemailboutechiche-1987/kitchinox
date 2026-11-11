// Accueil (logo animé, univers, débitage), lecture du logo SVG, ouverture de fichiers .sct / kitchinox.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/main.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/home_screen.dart';
import 'package:kitchen_planner/ui/logo.dart';
import 'package:kitchen_planner/ui/manual_cut_page.dart';

import 'compare_sketchcut_test.dart' as c;

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  test('logo : 4 tracés lus, tous dans le viewBox', () {
    final logo = LogoShape.parse(File('assets/logo.svg').readAsStringSync());
    expect(logo.paths.length, 4);
    expect(logo.viewBox, const Size(276.7, 228.1));
    for (final p in logo.paths) {
      final b = p.getBounds();
      expect(b.left, greaterThanOrEqualTo(-1));
      expect(b.right, lessThanOrEqualTo(278));
      expect(b.bottom, lessThanOrEqualTo(230));
      expect(b.width, greaterThan(1));
    }
  });

  test('fichier .sct : relu à l’identique (feuille, méthode, pièces, chants, rotation)', () {
    final plan = nest(c.essai, CutSettings(method: 3));
    final sct = toSct(plan, 'MDF 18', order: 'essai', thickness: '18');
    final job = ManualCut.fromSct(sct);
    expect((job.sheetLength, job.sheetWidth, job.method, job.kerf, job.trim), (2800, 2100, 3, 4, 4));
    expect(job.material, 'MDF 18');
    expect(job.parts.length, c.essai.length);
    expect(job.parts.first.length, 2000);
    expect(job.parts.first.qty, 2);
    expect(job.parts.first.desc, startsWith('Côté colonne'));
    expect(job.plan().sheets.length, 2);
  });

  test('projet kitchinox : les pièces de la cuisine passent au débitage', () {
    final e = LayoutEngine(cat, Project(name: 'Essai', room: Room(width: 4200, depth: 3200, height: 2600)));
    e.add('base_standard_single_door', 'A', s: 0, width: 600);
    e.add('base_drawers_multi', 'A', s: 600, width: 600);
    final st = AppState(cat);
    final r = manualCutFromFile('essai.cuisine.json', utf8.encode(jsonEncode(e.project.toJson())), st);
    expect(r, isNotNull);
    expect(r!.$1.parts, isNotEmpty);
    expect(r.$1.order, 'Essai');
    expect(manualCutFromFile('x.json', utf8.encode('pas un projet'), st), isNull);
  });

  testWidgets('accueil : logo puis les univers ; Cuisine ouvre le planificateur', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var opened = false;
    await t.runAsync(() async => LogoShape.load());
    await t.pumpWidget(MaterialApp(home: HomeScreen(state: AppState(cat), onKitchen: () => opened = true)));
    await t.pump(const Duration(milliseconds: 3000));
    for (final s in ['Cuisine', 'Dressing', 'Salle de bain et WC', 'Meuble TV', 'Intérieur', 'Art', 'Débitage']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    expect(find.text('Bientôt'), findsNothing);
    await t.tap(find.text('Cuisine'));
    expect(opened, isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('bouton Accueil dans la cuisine : retour à l’accueil', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(() async => LogoShape.load());
    await t.pumpWidget(KitchenApp(state: AppState(cat), googleFonts: false, showHome: true));
    await t.pump(const Duration(milliseconds: 3000));
    await t.tap(find.text('Cuisine'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Accueil'), findsOneWidget);
    await t.tap(find.byTooltip('Accueil'));
    await t.pumpAndSettle();
    expect(find.text('Débitage'), findsOneWidget);
    expect(find.byTooltip('Accueil'), findsNothing);
  });
}
