// Pièce à contour libre : traits et arcs, murs générés, surface, caissons gardés sur leur mur, 3D et plans.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/main.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/pdf_export.dart';
import 'package:kitchen_planner/ui/scene_export.dart';
import 'package:kitchen_planner/ui/tech_drawings.dart';

AppState kitchen() => AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));

List<RoomVertex> lShape() => [
      RoomVertex(0, 0), RoomVertex(4000, 0), RoomVertex(4000, 2000), RoomVertex(2500, 2000), RoomVertex(2500, 3500), RoomVertex(0, 3500),
    ];

void main() {
  test('contour en L : 6 murs droits, surface, intérieur, sauvegarde', () {
    final r = Room()..setOutline(lShape());
    expect(r.order, ['A', 'B', 'C', 'D', 'E', 'F']);
    expect(r.walls.every((w) => w.orthogonal), isTrue);
    expect((r.width, r.depth), (4000, 3500));
    expect(r.area, closeTo((4000 * 2000 + 2500 * 1500) / 1e6, 1e-6));
    expect(r.contains(1000, 3000), isTrue);
    expect(r.contains(3500, 3000), isFalse); // l'encoche du L
    expect(r.wall('A').rot, 0);
    expect(r.wall('B').rot, 90);
    expect(r.nextOf('F'), 'A');
    final back = Room.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
    expect(back.outline!.length, 6);
    expect(back.area, closeTo(r.area, 1e-9));
  });

  test('sens inverse et origine : le contour est remis dans le sens du tour, coin haut-gauche à l\'origine', () {
    final pts = [for (final p in lShape().reversed) RoomVertex(p.x + 500, p.y + 300)];
    final r = Room();
    final (ox, oy) = r.setOutline(pts);
    expect((ox, oy), (500, 300));
    expect(r.outline!.first.x, 0);
    expect(r.outline!.first.y, 0);
    expect(r.wall('A').dx, 1); // premier mur : en haut, de gauche à droite
  });

  test('mur arrondi : arc dessiné, pas de caissons dessus ; surface plus grande que la corde', () {
    final r = Room()..setOutline([RoomVertex(0, 0), RoomVertex(4000, 0), RoomVertex(4000, 3000, 600), RoomVertex(0, 3000)]);
    final arc = r.wall('C');
    expect(arc.straight, isFalse);
    expect(r.isWallEnabled('C'), isFalse);
    expect(arc.developed, greaterThan(arc.length));
    expect(r.depth, closeTo(3600, 1)); // la flèche sort de l'encombrement
    expect(r.area, greaterThan(12.0));
    final pts = arc.points(10);
    expect(pts.first.$1, closeTo(4000, 0.01));
    expect(pts.last.$1, closeTo(0, 0.01));
  });

  test('passer du rectangle au L : les caissons restent sur leur mur, ceux d\'un mur disparu partent', () {
    final st = kitchen();
    st.updateRoom(width: 4000, depth: 3500);
    st.engine.add('base_drawers_multi', 'A', s: 0, width: 600); // mur du haut : gardé
    st.engine.add('base_drawers_multi', 'B', s: 2600, width: 600); // bas du mur droit : disparaît (encoche du L)
    st.engine.addOpening('window', 'A', s: 2000);
    final msg = st.setRoomOutline(lShape());
    expect(msg, contains('6 murs'));
    expect(msg, contains('1 élément(s) retiré(s)'));
    expect(st.project.items.single.wallId, 'A');
    expect(st.project.openings.single.wallId, 'A');
    // propositions et contrôles sur une pièce en L
    final props = proposeLayouts(st.engine);
    expect(props, isNotEmpty);
    expect(() => st.issues, returnsNormally);
    // revenir au rectangle
    final back = st.setRoomOutline([RoomVertex(0, 0), RoomVertex(4000, 0), RoomVertex(4000, 3500), RoomVertex(0, 3500)]);
    expect(back, contains('rectangulaire'));
    expect(st.project.room.outline, isNull);
  });

  testWidgets('3D, plan d\'exécution et dessins d\'une pièce à mur arrondi', (t) async {
    final st = kitchen();
    st.setRoomOutline([RoomVertex(0, 0), RoomVertex(4000, 0), RoomVertex(4000, 1800), RoomVertex(3000, 2800, 500), RoomVertex(0, 2800)]);
    st.engine.add('base_drawers_multi', 'A', s: 0, width: 800);
    await t.runAsync(() async {
      final scene = await SceneExporter().build(st);
      expect(scene['floorPoly'], isNotNull);
      expect((scene['walls'] as List).where((w) => '${w['id']}'.contains('~')), isNotEmpty); // arc découpé
      final d = TechDrawer(st.engine);
      File('test/out/forme_libre_plan.png').writeAsBytesSync(await renderPng(const Size(1600, 1000), d.paintPlan));
      final pdf = await buildExecutionPdf(st.engine, pixelRatio: 0.5);
      expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
    });
  });

  testWidgets('éditeur : forme en L, validée ; plan affiché', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = kitchen();
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
    await t.pumpAndSettle();
    await t.tap(find.text('Forme de la pièce'));
    await t.pumpAndSettle();
    await t.tap(find.text('En L'));
    await t.pumpAndSettle();
    // toucher le premier mur : sa fiche (trait / arc, longueur)
    final c = t.getRect(find.byKey(const Key('room-shape-canvas')));
    await t.tapAt(Offset(c.center.dx, c.top + (c.height - (c.height - 140)) / 2 + 2));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/forme_editeur.png'));
    await t.tap(find.text('Valider'));
    await t.pumpAndSettle();
    expect(st.project.room.order.length, 6);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/forme_plan.png'));
    expect(t.takeException(), isNull);
  });
}
