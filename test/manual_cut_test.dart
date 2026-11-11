// Débit manuel (comme SketchCut) et rotation selon la matière.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/finishes.dart';
import 'package:kitchen_planner/ui/manual_cut_page.dart';

import 'compare_sketchcut_test.dart' as c;

void main() {
  ManualCut essai() => ManualCut(order: 'essai', parts: [
        for (final p in c.essai) ManualPart(length: p.length, width: p.width, qty: p.qty, edgeLong: p.edgeLong, edgeShort: p.edgeShort, desc: p.name),
      ]);

  test('les trois méthodes placent tout ; par longueur : 2 feuilles comme SketchCut', () {
    final job = essai();
    for (final m in [1, 2, 3]) {
      job.method = m;
      final plan = job.plan();
      expect(plan.notPlaced, isEmpty, reason: 'méthode $m');
      expect(plan.partCount, 36);
    }
    job.method = 1;
    expect(job.plan().sheets.length, 2);
    job.method = 3;
    expect(job.plan().sheets.length, lessThanOrEqualTo(2));
  });

  test('matière à fil : aucune pièce ne pivote ; couleur unie : rotation selon la case', () {
    final job = essai()..grain = true;
    expect(job.cutParts.every((p) => !p.canRotate), isTrue);
    final plan = job.plan();
    expect(plan.sheets.expand((s) => s.placements).every((p) => !p.rotated), isTrue);
    job.grain = false;
    job.parts.first.rotate = false;
    expect(job.cutParts.first.canRotate, isFalse);
    expect(job.cutParts[1].canRotate, isTrue);
  });

  test('enregistré avec le projet', () {
    final p = Project(name: 'x')..manual = essai();
    p.manual.method = 2;
    final back = Project.fromJson(p.toJson());
    expect(back.manual.parts.length, c.essai.length);
    expect(back.manual.method, 2);
    expect(back.manual.parts.first.desc, 'Côté colonne');
  });

  test('cuisine : façades bois ou marbre et caissons chêne ne pivotent pas, couleurs unies oui', () {
    installCutHooks();
    final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
    final e = LayoutEngine(cat, Project(room: Room(width: 4200, depth: 3200, height: 2600)));
    e.add('base_standard_single_door', 'A', s: 0, width: 600);
    List<CutPart> parts() => cutList(e, e.project.cut, const {});
    expect(parts().every((p) => p.canRotate), isTrue); // blanc mat, caisson blanc
    final textured = fronts.firstWhere((f) => f.tex != null);
    e.project.style.front = textured.id;
    expect(parts().where((p) => p.name.contains('Porte')).every((p) => !p.canRotate), isTrue);
    e.project.style.carcass = 'chene';
    expect(parts().where((p) => p.material == e.project.cut.carcassMaterial).every((p) => !p.canRotate), isTrue);
  });

  testWidgets('écran du débit manuel : saisie, méthode, calcul', (t) async {
    t.view.physicalSize = const Size(1600, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
    final st = AppState(cat, project: Project()..manual = essai());
    await t.pumpWidget(MaterialApp(home: ManualCutPage(state: st)));
    expect(find.text('Par largeur'), findsOneWidget);
    await t.tap(find.text('Optimal'));
    await t.pump();
    expect(st.project.manual.method, 3);
    await t.tap(find.text('Calculer'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100)); // écran d'attente, calcul, fermeture
    }
    expect(find.textContaining('Feuille 1'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
