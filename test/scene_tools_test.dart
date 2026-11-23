// Murs d'une pièce libre, catalogue sans pose en trop, scène fixe, angles borgnes, Stratidécor et MDF luxe, boutons flottants.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  List<RoomVertex> lShape() => [
        RoomVertex(0, 0), RoomVertex(3600, 0), RoomVertex(3600, 1650), RoomVertex(1980, 1650), RoomVertex(1980, 3000), RoomVertex(0, 3000),
      ];

  test('pièce libre : chaque mur droit se déplace, les voisins suivent, les meubles restent en place', () {
    final st = AppState(cat);
    st.setRoomOutline(lShape());
    final e = st.engine;
    final c = e.add('base_standard_single_door', 'D', s: 600, width: 600); // mur D : vertical de l'encoche (1650 → 3000)
    final (x0, y0) = e.room.wall('D').toPlan(c.s, 0);
    // mur C (horizontal de l'encoche, 1620 mm) : 300 mm vers l'extérieur, c'est-à-dire vers le bas
    e.moveWall('C', 300);
    expect(e.room.wall('C').length, closeTo(1620, 0.5));
    expect(e.room.wall('B').length, closeTo(1950, 0.5), reason: 'le voisin d’avant s’allonge');
    expect(e.room.wall('D').length, closeTo(1050, 0.5), reason: 'le voisin d’après raccourcit');
    final w = e.room.wall('D'), it = st.project.byUid(c.uid)!;
    final (x1, y1) = w.toPlan(it.s, 0);
    expect((x1 - x0).abs() + (y1 - y0).abs(), lessThan(1), reason: 'le meuble reste au même endroit de la pièce');
    // mur du haut (A) vers l'extérieur : l'origine bouge, la pièce grandit
    e.moveWall('A', 200);
    expect(e.room.depth, closeTo(3200, 0.5));
    expect(e.lastWallShift, (0.0, 200.0));
    // trop court : refusé, rien ne bouge
    final before = e.room.wall('D').length;
    expect(() => e.moveWall('C', 800), throwsA(isA<PlacementException>()), reason: 'le meuble du mur D en sortirait');
    expect(e.room.wall('D').length, before);
  });

  test('catalogue : angles borgnes bas, hauts et colonnes en plusieurs largeurs ; colonnes de 300 à 600', () {
    for (final id in ['corner_base_blind', 'corner_wall_blind', 'corner_tall_blind']) {
      expect(cat.tryGet(id)!.widths.values.length, greaterThan(1), reason: id);
    }
    for (final id in ['tall_pantry', 'tall_cleaning', 'tall_glass', 'tall_open_niche', 'tall_pullout']) {
      expect(cat.tryGet(id)!.widths.values, containsAll([300, 400, 450, 500]), reason: id);
    }
    final st = AppState(cat);
    for (final w in cat.tryGet('corner_wall_blind')!.widths.values) {
      final p = AppState(cat);
      expect(p.addModel('corner_wall_blind', wall: 'A', width: w), isNull, reason: '$w');
    }
    expect(st.addModel('corner_base_blind', wall: 'A', width: 1000), isNull);
  });

  test('Stratidécor et MDF laqué luxe 22 mm : formats, épaisseur, prix', () {
    expect(carcassMaterialChoices, contains(stratidecor));
    expect(frontMaterialChoices, containsAll([stratidecor, mdfLuxe22]));
    expect(woodSheetPresets[sheetCategoryOf(stratidecor)]!.first.length, 2800);
    expect(woodSheetPresets[sheetCategoryOf(mdfLuxe22)]!.first.width, 2070);
    expect(thicknessOf(mdfLuxe22), 22);
    final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'));
    final strati = db.panel('agglo_stratidecor')!.sheetPrice(2440, 1220), mdf = db.panel('mdf_melamine_hydrofuge')!.sheetPrice(2440, 1220);
    expect(strati.max, lessThan(mdf.max), reason: 'entrée de gamme : moins cher que le MDF');
    expect(db.panel('mdf_luxe_22')!.sheetPrice(2440, 1220).min, greaterThan(mdf.max));
    // devis : la matière choisie donne son panneau
    final st = AppState(cat, db: db);
    st.engine.add('base_standard_single_door', 'A', s: 0, width: 600);
    st.edit(() => st.project.cut
      ..carcassMaterial = stratidecor
      ..frontMaterial = mdfLuxe22
      ..doorThickness = 22);
    final panels = estimate(st.engine, db, st.project.specs, st.cutPlan, st.bom).where((l) => l.section == 'Panneaux').map((l) => l.name).join(' | ');
    expect(panels, contains('Stratidécor'));
    expect(panels, contains('luxe 22 mm'));
  });

  test('pivoter : un meuble passe sur le mur voisin, un objet tourne ; dupliquer et supprimer', () {
    final st = AppState(cat);
    final c = st.engine.add('base_standard_single_door', 'A', s: 3000, width: 600);
    st.select(c.uid);
    expect(st.rotateSelected(), isNotNull);
    expect(st.project.byUid(c.uid)!.wallId, 'B');
    st.undo();
    expect(st.project.byUid(c.uid)!.wallId, 'A');
    st.select(c.uid);
    st.duplicateAny();
    expect(st.project.items, hasLength(2));
    st.deleteAny();
    expect(st.project.items, hasLength(1));
    st.addObject('fixture:chauffe_eau');
    final o = st.project.objects.single;
    final r0 = o.rot;
    st.rotateSelected();
    expect(st.project.objects.single.rot, (r0 + 90) % 360);
  });
}
