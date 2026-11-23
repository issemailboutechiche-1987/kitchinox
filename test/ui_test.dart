// Tests de l'interface : pilotent l'écran comme un utilisateur (clic, glisser, clavier) et
// enregistrent des captures dans test/goldens (flutter test --update-goldens).

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/main.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/canvas_view.dart';
import 'package:kitchen_planner/ui/scene3d.dart';

Future<void> _loadFonts() async {
  final flutterRoot = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final dir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final file = File('$dir/$f');
      if (file.existsSync()) l.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await l.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Future<AppState> pumpApp(WidgetTester t, {Size size = const Size(1440, 900)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
  await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
  await t.pumpAndSettle();
  return st;
}

/// Position écran d'un point (s, z) de la vue de face du mur courant (zoom 1).
Offset frontPoint(WidgetTester t, AppState st, double s, double z) {
  final c = t.getRect(find.byType(PlannerCanvas));
  final room = st.project.room;
  final len = room.wall(st.wallId).length;
  // mêmes marges que la vue de face : 72 px autour, 120 px pour les étiquettes, 70 px sous le sol
  final k = [(c.width - 144 - 120) / len, (c.height - 144 - 70) / room.height].reduce((a, b) => a < b ? a : b);
  final ox = c.left + (c.width - len * k) / 2;
  final oy = c.top + c.height - (c.height - room.height * k) / 2 - 35;
  return Offset(ox + s * k, oy - z * k);
}

void sampleKitchen(AppState st) {
  final e = st.engine;
  st.edit(() {
    e.applyShape(RoomShape.lShape);
    e.addOpening('door', 'D', s: 1200);
    e.addOpening('window', 'A', s: 1700, width: 900);
    e.add('tall_integrated_fridge', 'A', s: 0, height: 2200);
    e.add('base_drawers_multi', 'A', s: 600, width: 600);
    e.add('base_sink', 'A', s: 1200, width: 1000);
    e.add('base_integrated_dishwasher_door', 'A', s: 2200, width: 450);
    e.add('corner_base_l_shaped', 'A');
    e.add('wall_integrated_hood', 'A', s: 600, width: 600, z: 1500, height: 800);
    e.add('base_cooktop_oven', 'B', s: 900, width: 600);
    e.add('base_standard_single_door', 'B', s: 1500, width: 600);
    e.add('tall_oven_microwave', 'B', s: 2400, height: 2200);
    e.add('wall_standard_double_door', 'B', s: 900, width: 1000, z: 1500, height: 800);
  });
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('parcours : étapes, catalogue, ajout, glisser, clavier, annuler', (t) async {
    final st = await pumpApp(t);
    expect(st.step, PlanStep.space);

    // Suivant sans point d'eau : refusé, message ; avec une arrivée d'eau : implantation
    await t.tap(find.text('Suivant'));
    await t.pumpAndSettle();
    expect(st.step, PlanStep.space);
    expect(find.textContaining('arrivée d’eau existante'), findsOneWidget);
    await t.tap(find.text('Point d’eau (obligatoire)'));
    await t.pumpAndSettle();
    expect(st.existingCount(false), 1);
    st.setView(ViewMode.plan);
    await t.tap(find.text('Suivant'));
    await t.pumpAndSettle();
    expect(st.step, PlanStep.layout);

    // « Ajouter des meubles » ouvre le panneau à vignettes (un seul chemin)
    await t.tap(find.text('Ajouter des meubles'));
    await t.pumpAndSettle();
    expect(st.browse, isNotNull);
    expect(st.megaMenu, isFalse);
    // « + » pose tout de suite à la première place libre ; le panneau reste ouvert
    await t.tap(find.byTooltip('Ajouter Bas 1 porte'));
    await t.pumpAndSettle();
    expect(st.project.items.single.modelId, 'base_standard_single_door');
    expect(st.browse, isNotNull, reason: 'le panneau reste ouvert pour poser en série');
    await t.tap(find.byTooltip('Ajouter Bas 2 portes'));
    await t.pumpAndSettle();
    expect(st.project.items.length, 2);
    final b = st.project.items[1];
    expect(b.s, 600);
    // toucher une carte arme le meuble (taille au choix), puis toucher le plan le pose là
    st.setView(ViewMode.front);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('thumb_base_standard_single_door')));
    await t.pumpAndSettle();
    expect(st.armedModel, 'base_standard_single_door');
    expect(find.byKey(const ValueKey('armed_banner')), findsOneWidget);
    final chip = find.byKey(const ValueKey('w_base_standard_single_door_450'));
    if (chip.evaluate().isNotEmpty) {
      await t.tap(chip);
      await t.pumpAndSettle();
      expect(st.armedWidth, 450);
    }
    final canvasRect = t.getRect(find.byType(PlannerCanvas));
    await t.tapAt(Offset(canvasRect.right - 120, canvasRect.center.dy));
    await t.pumpAndSettle();
    expect(st.project.items.length, 3, reason: 'posé au toucher');
    expect(st.armedModel, isNull, reason: 'un seul meuble par toucher : un toucher de plus n’en ajoute pas');
    await t.tapAt(Offset(canvasRect.right - 120, canvasRect.center.dy));
    await t.pumpAndSettle();
    expect(st.project.items.length, 3);
    st.select(st.project.items.last.uid);
    st.deleteSelected();
    st.openBrowse(const CatalogBrowse(Shelf.base));
    st.setView(ViewMode.plan);
    await t.pumpAndSettle();

    // recherche
    await t.enterText(find.byType(TextField).first, 'évier');
    await t.pumpAndSettle();
    expect(st.browseModels().map((m) => m.id), containsAll(['base_sink', 'base_sink_1door', 'base_sink_2doors']));
    expect(st.browseModels().every((m) => m.id.startsWith('base_sink')), isTrue);
    st.openBrowse(null);

    // glisser en vue de face
    st.setView(ViewMode.front);
    await t.pumpAndSettle();
    final from = frontPoint(t, st, b.s + b.width / 2, b.z + b.height / 2);
    final to = frontPoint(t, st, b.s + b.width / 2 + 1000, b.z + b.height / 2);
    await t.dragFrom(from, to - from);
    await t.pumpAndSettle();
    expect(b.s, closeTo(1600, 60));
    final afterDrag = b.s;

    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(b.s, afterDrag + 10);

    for (var i = 0; i < 2; i++) {
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
    }
    expect(st.project.byUid(b.uid)!.s, 600);
  });

  testWidgets('glisser le mur droit à la main', (t) async {
    final st = await pumpApp(t);
    expect(st.step, PlanStep.space);
    expect(st.view, ViewMode.plan);
    final c = t.getRect(find.byType(PlannerCanvas));
    // même calcul que la vue du dessus : 72 px de marge, murs de 120 mm, 30 px réservés en bas
    final room = st.project.room;
    final k = [(c.width - 144) / (room.width + 240), (c.height - 144 - 30) / (room.depth + 240)].reduce((a, b) => a < b ? a : b);
    final ox = c.left + (c.width - room.width * k) / 2;
    final oy = c.top + (c.height - room.depth * k) / 2 - 15;
    final wallB = Offset(ox + (room.width + 60) * k, oy + room.depth / 2 * k);
    await t.dragFrom(wallB, Offset(500 * k, 0));
    await t.pumpAndSettle();
    expect(st.project.room.width, closeTo(4100, 20));
    st.undo();
    await t.pumpAndSettle();
    expect(st.project.room.width, 3600);
  });

  testWidgets('capture : mur en cours de déplacement', (t) async {
    final st = await pumpApp(t);
    sampleKitchen(st);
    st.goTo(PlanStep.space);
    await t.pumpAndSettle();
    final c = t.getRect(find.byType(PlannerCanvas));
    final room = st.project.room;
    final k = [(c.width - 144) / (room.width + 240), (c.height - 144 - 30) / (room.depth + 240)].reduce((a, b) => a < b ? a : b);
    final ox = c.left + (c.width - room.width * k) / 2;
    final oy = c.top + (c.height - room.depth * k) / 2 - 15;
    final wallB = Offset(ox + (room.width + 60) * k, oy + room.depth * 0.6 * k);
    final g = await t.startGesture(wallB, kind: PointerDeviceKind.mouse);
    await g.moveBy(Offset(300 * k, 0));
    await t.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/10_mur_glisse.png'));
    await g.up();
  });

  testWidgets('remplir le mur et récapitulatif', (t) async {
    final st = await pumpApp(t);
    st.goTo(PlanStep.layout);
    expect(st.autoFill(Band.low), contains('ajouté'));
    await t.pumpAndSettle();
    expect(st.project.items, isNotEmpty);
    st.goTo(PlanStep.summary);
    await t.pumpAndSettle();
    expect(find.textContaining('plan de travail'), findsWidgets);
    expect(find.textContaining('pièces à débiter'), findsOneWidget);
  });

  Future<void> shot(WidgetTester t, String name) => expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

  testWidgets('captures des étapes', (t) async {
    final st = await pumpApp(t);
    sampleKitchen(st);

    st.goTo(PlanStep.space);
    st.selectOpening(st.project.openings.first.uid);
    await t.pumpAndSettle();
    await shot(t, '1_espace');

    st.selectOpening(null);
    st.goTo(PlanStep.layout);
    st.setView(ViewMode.plan);
    st.select(st.project.items[2].uid);
    await t.pumpAndSettle();
    await shot(t, '2_implantation_dessus');

    st.setView(ViewMode.front);
    await t.pumpAndSettle();
    await shot(t, '3_implantation_face');

    st.select(null);
    st.toggleMegaMenu(true);
    await t.pumpAndSettle();
    await shot(t, '4_catalogue');

    st.openBrowse(const CatalogBrowse(Shelf.base, 'base_cabinets'));
    await t.pumpAndSettle();
    await shot(t, '5_produits');

    st.goTo(PlanStep.style);
    st.setStyle(front: 'vert_sauge', worktop: 'marbre', handle: 'bar');
    await t.pumpAndSettle();
    await shot(t, '6_style_3d');

    st.goTo(PlanStep.summary);
    await t.pumpAndSettle();
    await shot(t, '7_recapitulatif');
  });

  testWidgets('capture forme de la pièce', (t) async {
    final st = await pumpApp(t);
    st.goTo(PlanStep.layout);
    await t.pumpAndSettle();
    await t.tap(find.text('Disposition des meubles'));
    await t.pumpAndSettle();
    await shot(t, '8_forme');
  });

  testWidgets('propositions de cuisine : fenêtre avec aperçus, choix appliqué', (t) async {
    final st = await pumpApp(t);
    st.edit(() {
      st.project.room
        ..width = 4600
        ..depth = 4200;
      st.engine.addOpening('window', 'A', s: 2300);
      st.engine.addOpening('door', 'D', s: 3500);
    });
    st.goTo(PlanStep.layout);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Propositions de cuisine ou remplissage du mur A'));
    await t.pumpAndSettle();
    await t.tap(find.text('Propositions de cuisine'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100)); // écran d'attente puis fenêtre
    }
    await t.pumpAndSettle();
    expect(find.text('Recommandée'), findsOneWidget);
    await shot(t, '11_propositions');
    await t.tap(find.text('Recommandée'));
    await t.pumpAndSettle();
    expect(st.project.items, isNotEmpty);
  });

  testWidgets('3D : glisser un meuble le déplace ; double clic ouvre puis ferme', (t) async {
    final st = await pumpApp(t);
    st.goTo(PlanStep.layout);
    st.edit(() => st.engine.add('base_standard_single_door', 'A', s: 600, width: 600));
    final c = st.project.items.first;
    st.setView(ViewMode.view3d);
    await t.pumpAndSettle();
    final rect = t.getRect(find.byType(PlannerCanvas));
    final cam = Camera3d.fit(st.project.room, st.yaw, rect.size, zoom: st.zoom, panX: st.panX, panY: st.panY);
    final front = rect.topLeft + cam.p(c.s + 300, 600, 450);
    // double clic : ouvre
    await t.tapAt(front);
    await t.pump(const Duration(milliseconds: 100));
    await t.tapAt(front);
    await t.pump(const Duration(milliseconds: 100));
    expect(st.isOpen(c.uid), isTrue);
    await t.pump(const Duration(seconds: 1));
    await t.tapAt(front);
    await t.pump(const Duration(milliseconds: 100));
    await t.tapAt(front);
    await t.pump(const Duration(seconds: 1));
    expect(st.isOpen(c.uid), isFalse);
    // glisser le long du mur : 800 mm vers la droite
    final along = cam.v(1, 0, 0) * 800;
    final g = await t.startGesture(front, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(front + along * (i / 8));
      await t.pump();
    }
    await g.up();
    await t.pumpAndSettle();
    expect(st.project.byUid(c.uid)!.s, greaterThan(1200));
  });
}
