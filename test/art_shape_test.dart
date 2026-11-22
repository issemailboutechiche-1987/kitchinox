// Formes de l'atelier (rond, polygone, rectangle arrondi, arc, main levée) et cotes attachées aux pièces.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/art_cad.dart';
import 'package:kitchen_planner/engine/art_machining.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/art_blueprint_pdf.dart';
import 'package:kitchen_planner/ui/art_camera.dart';
import 'package:kitchen_planner/ui/art_page.dart';
import 'package:kitchen_planner/ui/theme.dart';

void main() {
  ArtPanel flat(String id, {double w = 600, double d = 600, double x = 0, double z = 0}) => ArtPanel(id: id, role: ArtRole.tablette, x: x, y: 0, z: z, w: w, h: 18, d: d);

  test('plan de fabrication avec des pièces de forme', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final art = ArtProject()..free.addAll([flat('a')..shape = 'rond', flat('b', x: 700, w: 800, d: 400)..shape = 'arrondi'..radius = 60]);
    final bytes = await buildArtBlueprint(art, CutSettings(), projectName: 'Formes');
    expect(bytes.length, greaterThan(5000));
  });

  test('rond : contour, surface, chant, débit et relecture', () {
    final p = flat('a')..shape = 'rond';
    expect(isShaped(p), isTrue);
    expect(shapeArea(p), closeTo(math.pi * 300 * 300, 900));
    expect(perimeterOf(p), closeTo(math.pi * 600, 3));
    expect(insideOutline(p, [300, 9, 300]), isTrue);
    expect(insideOutline(p, [20, 9, 20]), isFalse, reason: 'le coin de la boîte est hors du rond');
    final back = ArtPanel.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
    expect(outlineOf(back).length, outlineOf(p).length);
    final art = ArtProject()..free.add(p);
    final cut = art.cutParts().single;
    expect((cut.length, cut.width, cut.edgeLong, cut.edgeShort), (600, 600, 0, 0));
    expect(cut.name, contains('rond Ø 600'));
    final m = computeMachiningElements(art.panels, fittings: art.fittings, jointCuts: art.jointCuts, jointFits: art.jointFits);
    expect(m.totalEdgeMeters, closeTo(math.pi * 0.6, 0.01));
  });

  test('bords : côtés droits du polygone, rayon des cercles, des arcs et des coins arrondis', () {
    final hexa = flat('h', w: 1200, d: 1040);
    setOutline(hexa, [for (var i = 0; i < 6; i++) [600 + 600 * math.cos(math.pi / 3 * i), 18, 520 + 519.6 * math.sin(math.pi / 3 * i) / 0.8660254 * 0.8660254]]);
    hexa.shape = 'polygone';
    expect(shapeEdges(hexa).where((e) => e.curved), isEmpty);
    expect(shapeEdges(hexa), hasLength(6));
    final rond = flat('r', w: 800, d: 800)..shape = 'rond';
    expect(shapeEdges(rond).every((e) => e.curved && (e.radius - 400).abs() < 1), isTrue);
    final coins = flat('c', w: 800, d: 400)
      ..shape = 'arrondi'
      ..radius = 60;
    final ec = shapeEdges(coins);
    expect(ec.where((e) => !e.curved), hasLength(4));
    expect(ec.where((e) => e.curved).every((e) => (e.radius - 60).abs() < 1), isTrue);
    // demi-disque : la corde et un arc R 500
    final arc = flat('a', w: 1000, d: 500);
    setOutline(arc, [for (var i = 0; i <= 30; i++) [500 - 500 * math.cos(math.pi * i / 30), 18, 500 * math.sin(math.pi * i / 30)]]);
    final ea = shapeEdges(arc);
    expect(ea.where((e) => !e.curved).length, 1);
    expect(ea.where((e) => e.curved).every((e) => (e.radius - 500).abs() < 2), isTrue);
    expect(shapeLabel(arc), 'arc R 500');
    // cote de rayon : suit la pièce, relue
    final e = ea.firstWhere((e) => e.curved);
    final c = V3(e.center![0], e.center![1], e.center![2]);
    final dim = CadDimension(id: 'd', p1: c, p2: c + const V3(0, 0, 500), radius: true)
      ..h1 = anchorOn(arc, e.center!)
      ..h2 = anchorOn(arc, [c.x, c.y, c.z + 500]);
    expect(dim.text, 'R 500');
    arc.x += 250;
    final back = CadDimension.fromJson(jsonDecode(jsonEncode(dim.toJson())) as Map<String, dynamic>).resolve({'a': arc})!;
    expect((back.radius, back.text), (true, 'R 500'));
    expect(back.p1.x, closeTo(750, 1));
  });

  test('coins arrondis : le rayon reste en mm quand la pièce change de taille', () {
    final p = flat('a', w: 800, d: 400)
      ..shape = 'arrondi'
      ..radius = 50;
    expect(shapeArea(p), closeTo(800 * 400 - (4 - math.pi) * 2500, 60));
    p.w = 1200;
    expect(shapeArea(p), closeTo(1200 * 400 - (4 - math.pi) * 2500, 60));
    p.radius = 0;
    expect(isShaped(p), isFalse);
  });

  test('la forme suit la pièce montée debout, se coupe avec elle et se retourne en miroir', () {
    final p = flat('a', w: 800, d: 400);
    setOutline(p, [[0, 18, 0], [800, 18, 0], [800, 18, 400]]); // triangle
    expect(shapeArea(p), closeTo(160000, 1));
    // debout : longueur en hauteur
    p
      ..w = 18
      ..h = 800
      ..d = 400;
    expect(worldOutline(p).every((q) => q[0] == p.right), isTrue);
    expect(shapeArea(p), closeTo(160000, 1));
    // coupe
    final art = ArtProject();
    final c = flat('c', w: 600, d: 600)..shape = 'rond';
    art.free.add(c);
    final (l, r) = art.splitPanel(c, 0, 300, 4);
    expect((l.w.round(), r.w.round()), (298, 298));
    expect(shapeArea(l) + shapeArea(r), closeTo(math.pi * 300 * 300 - 4 * 600, 1200));
    // miroir
    final t = flat('t', w: 800, d: 400);
    setOutline(t, [[0, 18, 0], [800, 18, 0], [800, 18, 400]]);
    expect(insideOutline(t, [700, 18, 300]), isTrue);
    flipOutline(t, 0);
    expect(insideOutline(t, [700, 18, 300]), isFalse);
    expect(insideOutline(t, [100, 18, 300]), isTrue);
  });

  test('arc par trois points ; main levée lissée', () {
    final pts = arcThrough([0, 0, 0], [500, 0, 250], [1000, 0, 0], 0, 2)!;
    expect(pts.map((q) => q[2]).reduce(math.max), closeTo(250, 1));
    expect((pts.last[0] - 1000).abs() < 0.01, isTrue);
    expect(arcThrough([0, 0, 0], [1, 0, 0], [2, 0, 0], 0, 2), isNull);
    final rnd = math.Random(3);
    final raw = [for (var i = 0; i < 200; i++) [400 * math.cos(2 * math.pi * i / 200) + rnd.nextDouble() * 4, 0.0, 300 * math.sin(2 * math.pi * i / 200) + rnd.nextDouble() * 4]];
    final ring = smoothStroke(raw);
    expect(ring.length, inInclusiveRange(12, 120));
  });

  test('cote attachée : suit la pièce déplacée, montée, redimensionnée ; disparaît avec elle', () {
    final p = flat('a', w: 1519, d: 604);
    final d = CadDimension(id: 'd', p1: const V3(0, 18, -120), p2: const V3(1519, 18, -120), a1: const V3(0, 18, 0), a2: const V3(1519, 18, 0), text: '1519 mm')..attach([p]);
    CadDimension? at() => CadDimension.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>).resolve({p.id: p});
    expect(at()!.text, '1519 mm');
    p
      ..x = 2000
      ..z = 700;
    expect((at()!.a1!.x, at()!.p1.z), (2000, 580));
    // montée debout : la cote suit la longueur
    p
      ..w = 18
      ..h = 1519
      ..d = 604
      ..y = 0;
    final up = at()!;
    expect((up.a2!.y - up.a1!.y).abs(), 1519);
    expect(up.text, '1519 mm');
    p.h = 1200;
    expect(at()!.text, '1200 mm');
    expect(d.resolve({}), isNull, reason: 'pièce effacée : plus de cote');
    // ancienne cote restée au sol après le montage : plus affichée
    final orphan = CadDimension(id: 'o', p1: const V3(0, 0, 0), p2: const V3(604, 0, 0), a1: const V3(0, 0, 40), a2: const V3(604, 0, 40));
    expect(orphan.resolve({p.id: p}), isNull);
  });

  testWidgets('palette : rond, polygone, rectangle arrondi, arc et main levée donnent de vraies formes', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: ArtPage(state: st)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('welcome_close')));
    await t.pumpAndSettle();
    final s = t.state(find.byType(ArtPage)) as dynamic;
    final art = st.project.art;
    final vp = t.getRect(find.byKey(const Key('art-viewport')));
    s.cam.view('dessus');
    s.snapAlign = false;
    Future<void> tap(double x, double z) async {
      await t.tapAt(vp.topLeft + (s.screenOf(x, 0.0, z) as Offset));
      await t.pumpAndSettle();
    }

    void use(CadTool x) => (s as dynamic).setState(() => s.activeTool = x);
    final c = s.cam.target;
    final cx = (c.x as double).roundToDouble(), cz = (c.z as double).roundToDouble();

    use(CadTool.circle);
    await t.pumpAndSettle();
    await tap(cx - 700, cz);
    await tap(cx - 400, cz);
    expect(art.free.single.shape, 'rond');
    use(CadTool.polygon);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('poly_5')));
    await t.pumpAndSettle();
    await tap(cx + 100, cz);
    await tap(cx + 350, cz);
    expect(art.free.last.outline, hasLength(5));
    use(CadTool.roundedRectangle);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('corner_100')));
    await t.pumpAndSettle();
    await tap(cx - 900, cz + 500);
    await tap(cx - 200, cz + 900);
    expect((art.free.last.shape, art.free.last.radius), ('arrondi', 100));
    use(CadTool.arc);
    await t.pumpAndSettle();
    await tap(cx + 100, cz + 800);
    await tap(cx + 900, cz + 800);
    await tap(cx + 500, cz + 500);
    expect(art.free.last.shape, 'libre');
    use(CadTool.freehand);
    await t.pumpAndSettle();
    final g = await t.startGesture(vp.topLeft + (s.screenOf(cx + 900, 0.0, cz) as Offset));
    for (var i = 1; i <= 40; i++) {
      await g.moveTo(vp.topLeft + (s.screenOf(cx + 700 + 200 * math.cos(2 * math.pi * i / 41), 0.0, cz + 260 * math.sin(2 * math.pi * i / 41)) as Offset));
      await t.pump();
    }
    await g.up();
    await t.pumpAndSettle();
    expect(art.free, hasLength(5));
    expect(art.free.last.outline!.length, greaterThan(8));
    expect(art.sketches, isEmpty);
    use(CadTool.select);
    s.cam.view('iso');
    s.cam.fit(art.panels);
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    await expectLater(find.byKey(const Key('art-viewport')), matchesGoldenFile('goldens/art_formes.png'));
    // toucher le coin de la boîte du rond ne le choisit pas ; son milieu, si
    s.cam.view('dessus');
    await t.pumpAndSettle();
    final r = art.free.first;
    final tl = vp.topLeft;
    s.selectedPanel = null;
    (s.selection as Set).clear();
    await t.tapAt(tl + (s.screenOf(r.x + 12, r.top, r.z + 12) as Offset));
    await t.pumpAndSettle();
    expect(s.selectedPanel, isNull);
    await t.tapAt(tl + (s.screenOf(r.x + r.w / 2, r.top, r.z + r.d / 2) as Offset));
    await t.pumpAndSettle();
    expect((s.selectedPanel as ArtPanel).id, r.id);
    // arrondir une pièce depuis ses infos
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 6));
  });
}
