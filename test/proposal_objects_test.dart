// Propositions avec objets : salle de bain avec WC, douche ou baignoire ; salon avec téléviseur et canapé.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/main.dart';
import 'package:kitchen_planner/ui/app_state.dart';

LayoutEngine room(String id, {double w = 3600, double d = 3000}) {
  final u = FurnitureUniverse.parse(id, File('assets/data/furniture/$id.json').readAsStringSync());
  final p = Project(universe: id, room: Room(width: w, depth: d, height: 2600));
  p.openings.add(Opening(uid: 'door', type: 'door', wallId: 'D', s: 300, width: 800, z: 0, height: 2040));
  return LayoutEngine(universeCatalog(u), p);
}

void _check(LayoutEngine e, LayoutProposal pr) {
  final p = pr.project;
  final pe = LayoutEngine(e.catalog, p);
  final boxes = [for (final c in p.items) ...pe.boxesOf(c).map((t) => t.box)];
  final door = p.openings.single.box(p.room);
  for (final o in p.objects) {
    final (x0, y0, x1, y1) = o.footprint;
    expect(x0 >= -1 && y0 >= -1 && x1 <= p.room.width + 1 && y1 <= p.room.depth + 1, isTrue, reason: '${pr.name} ${o.ref} hors pièce');
    if (o.h <= 20) continue; // tapis
    final b = Box3(x0, y0, o.z, x1, y1, o.z + o.h);
    expect(boxes.where((c) => c.intersects(b)), isEmpty, reason: '${pr.name} ${o.ref} dans un meuble');
    expect(door.intersects(b), isFalse, reason: '${pr.name} ${o.ref} devant la porte');
    for (final q in p.objects.where((q) => q != o && q.h > 20)) {
      final (a0, b0, a1, b1) = q.footprint;
      final qb = Box3(a0, b0, q.z, a1, b1, q.z + q.h);
      expect(qb.intersects(b), isFalse, reason: '${pr.name} ${o.ref} / ${q.ref}');
    }
  }
}

void main() {
  for (final (w, d) in [(3600.0, 3000.0), (2600.0, 2200.0)]) {
    test('salle de bain ${w}x$d : chaque proposition pose un WC et une douche ou une baignoire, sans collision', () {
      final e = room('bain', w: w, d: d);
      final props = proposeUniverse(e, withStyle: false);
      expect(props, isNotEmpty);
      for (final (_, pr) in props) {
        final refs = pr.project.objects.map((o) => o.ref).toList();
        // ignore: avoid_print
        print('${pr.name}: $refs');
        expect(refs.any((r) => r.startsWith('fixture:wc') || r == 'fixture:bidet'), isTrue, reason: pr.name);
        if (w > 3000) expect(refs.any((r) => r.contains('douche') || r.contains('baignoire')), isTrue, reason: pr.name);
        _check(e, pr);
      }
    });
  }

  test('meuble TV : téléviseur posé sur le banc, canapé face à l’écran', () {
    final e = room('tv', w: 4500, d: 4000);
    for (final (_, pr) in proposeUniverse(e, withStyle: false)) {
      final tv = pr.project.objects.where((o) => o.ref == 'kenney_televisionModern').firstOrNull;
      final sofa = pr.project.objects.where((o) => o.ref == 'ph_sofa_02').firstOrNull;
      expect(tv, isNotNull, reason: pr.name);
      expect(tv!.z, greaterThan(100), reason: pr.name);
      expect(sofa, isNotNull, reason: pr.name);
      expect((sofa!.rot - tv.rot).abs() % 360, 180, reason: pr.name);
      _check(e, pr);
    }
  });

  test('dressing : objets de décoration posés', () {
    final e = room('dressing');
    final props = proposeUniverse(e, withStyle: false);
    expect(props.where((x) => x.$2.project.objects.isNotEmpty).length, greaterThanOrEqualTo(props.length - 1));
    for (final (_, pr) in props) {
      _check(e, pr);
    }
  });

  testWidgets('capture : salle de bain proposée, plan et vue de face', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final e = room('bain');
    final st = AppState(e.catalog, project: e.project)
      ..objectCatalog = CatalogObject.parse(File('assets/data/objects.json').readAsStringSync());
    final pr = proposeUniverse(st.engine, withStyle: false).firstWhere((x) => x.$2.name == 'Fès').$2;
    st.applyLayoutProposal(pr);
    expect(st.project.objects.length, 4);
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
    await t.pumpAndSettle();
    st.goTo(PlanStep.layout);
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/bain_objets_plan.png'));
    final wc = st.project.objects.firstWhere((o) => o.ref == 'fixture:wc_suspendu');
    st.setView(ViewMode.front);
    st.setWall(const {0: 'A', 90: 'B', 180: 'D', 270: 'C'}[wc.rot]!);
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/bain_objets_face.png'));
    expect(t.takeException(), isNull);
  });

  testWidgets('capture : fenêtre Propositions de la salle de bain (objets dans les vignettes)', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final e = room('bain');
    final st = AppState(e.catalog, project: e.project);
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
    await t.pumpAndSettle();
    st.goTo(PlanStep.layout);
    await t.pumpAndSettle();
    await t.tap(find.text('Propositions'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/propositions_bain.png'));
    expect(t.takeException(), isNull);
  });
}
