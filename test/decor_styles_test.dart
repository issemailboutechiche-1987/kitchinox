// Décor du rendu, présentation sur fond blanc, modèles de façade, formes d'îlot.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/finishes.dart';
import 'package:kitchen_planner/ui/fronts.dart';
import 'package:kitchen_planner/ui/panels.dart';
import 'package:kitchen_planner/ui/scene_export.dart';
import 'package:kitchen_planner/ui/theme.dart';
import 'package:kitchen_planner/ui/toolbar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  AppState kitchen({double w = 4600, double d = 4200}) {
    final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'), handles: f('handles'));
    return AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()), db: db, project: Project(room: Room(width: w, depth: d, height: 2600)))..objectCatalog = CatalogObject.parse(f('objects'));
  }

  AppState filled() {
    final st = kitchen();
    st.engine.applyShape(RoomShape.lShape);
    st.engine.autoFillWall('A', Band.low);
    st.engine.autoFillWall('A', Band.high);
    st.addOpening('window', wall: 'B');
    return st;
  }

  test('décor : aux places libres, hors de l’évier et de la plaque ; ni débit ni devis ; caché d’un geste', () {
    final st = filled();
    final before = st.estimateLines.length, issues = st.issues.length;
    st.toggleDecor();
    expect(st.project.style.decor, isNotEmpty);
    final placed = placeDecor(st.engine);
    expect(placed.length, greaterThan(4));
    final busy = st.project.items.where((c) => st.engine.washes(c) || st.engine.cooks(c));
    for (final q in placed.where((q) => q.item.spot == 'plan')) {
      for (final c in busy) {
        final (s0, _, t0, _) = st.project.room.wall(c.wallId).boxToWall(Box3(q.x, q.y, 0, q.x, q.y, 1));
        expect(t0 < 700 && s0 > c.s && s0 < c.right, isFalse, reason: '${q.item.id} sur ${c.modelId}');
      }
    }
    expect((st.estimateLines.length, st.issues.length), (before, issues));
    expect(KitchenStyle.fromJson(st.project.style.toJson()).decor, st.project.style.decor);
    st.toggleDecor();
    expect(st.project.style.showDecor, isFalse);
    expect(st.project.style.decor, isNotEmpty);
  });

  testWidgets('présentation : fond blanc, trois niveaux', (t) async {
    await t.runAsync(() async {
      final st = filled();
      st.toggleDecor();
      Future<Map<String, dynamic>> scene(String m) {
        st.setStudio(m);
        return SceneExporter().build(st);
      }

      final room = await scene('');
      expect(room['walls'], isNotEmpty);
      expect((room['objects'] as List).where((o) => o['decor'] == true), isNotEmpty);
      final full = await scene('decor');
      expect(full['walls'], isEmpty);
      expect((full['objects'] as List).where((o) => o['decor'] == true), isNotEmpty);
      expect((full['objects'] as List).where((o) => o['type'] == 'deco_store'), isEmpty, reason: 'pas de fenêtre sans mur');
      final apps = await scene('appliances');
      expect((apps['objects'] as List).where((o) => o['decor'] == true), isEmpty);
      expect(apps['kitchenFixtures'], isNotEmpty);
      final bare = await scene('bare');
      expect(bare['kitchenFixtures'], isEmpty);
      st.setView(ViewMode.plan);
      expect(st.studio, '');
    });
  });

  testWidgets('niches ouvertes : étagères, fond, même hauteur que les voisins ; vitrines gardées', (t) async {
    await t.runAsync(() async {
      expect((nicheLevels(300), nicheLevels(750), nicheLevels(800)), (1, 2, 2));
      final st0 = kitchen(w: 3600, d: 3000);
      for (final x in buildTemplates(st0.engine).where((x) => x.$1.uppers == Uppers.open)) {
        final p = x.$2.project;
        final e = LayoutEngine(st0.catalog, p);
        final niches = p.items.where((c) => c.modelId.startsWith('wall_open')).toList();
        expect(niches, isNotEmpty, reason: x.$1.id);
        final others = p.items.where((c) => e.modelOf(c).kind == CabinetKind.wall && !e.modelOf(c).isHoodUnit && !e.modelOf(c).isFreeHood).map((c) => (c.z.round(), c.height)).toSet();
        expect(others, hasLength(1), reason: '${x.$1.id} : hauts alignés $others');
        final st = AppState(st0.catalog, db: st0.db, project: p)..objectCatalog = st0.objectCatalog;
        final sc = await SceneExporter().build(st);
        // côtés, dessus, dessous, dos, plus au moins une étagère et le fond
        for (final c in niches) {
          expect((sc['solids'] as List).where((s) => s['uid'] == c.uid).length, greaterThan(6), reason: x.$1.id);
        }
        // vitrines : toujours un cadre et une vitre
        for (final c in p.items.where((c) => c.modelId == 'wall_glass_door')) {
          expect([for (final fr in sc['fronts'] as List) if (fr['uid'] == c.uid) ...(fr['parts'] as List)].every((q) => q['glass'] == 60.0), isTrue);
        }
        st.project.style.decor.add('vaisselle');
        expect(placeDecor(st.engine).where((q) => q.item.id == 'vaisselle'), isNotEmpty);
      }
    });
  });

  testWidgets('façades à cadre : relief en 3D, croisillons des vitrines', (t) async {
    await t.runAsync(() async {
      final st = filled();
      final g = st.engine.add('wall_glass_door', 'B', s: 2200, width: 600);
      Future<List<Map>> parts(String uid) async => [
            for (final fr in (await SceneExporter().build(st))['fronts'] as List)
              if (fr['uid'] == uid) ...(fr['parts'] as List).cast<Map>()
          ];
      expect((await parts(st.project.items.first.uid)).any((p) => p['frame'] != null), isFalse);
      st.project.style.frontProfile = 'shaker';
      st.refresh();
      expect((await parts(st.project.items.firstWhere((c) => c.modelId == 'base_standard_single_door' || c.modelId == 'base_drawers_multi').uid)).any((p) => p['frame'] != null), isTrue);
      expect((await parts(g.uid)).any((p) => p['muntins'] == true), isTrue);
      expect(profileFrame('shaker', 600, 720), 70);
      expect(profileFrame('shaker', 600, 100), 0);
      expect(profileFrame('lisse', 600, 720), 0);
    });
  });

  test('îlots : chaque forme se pose, reste dans la pièce, devis du plan et des jambages', () {
    for (final id in islandPresets.keys) {
      final st = kitchen();
      st.engine.applyShape(RoomShape.lShape);
      var ok = false;
      st.edit(() => ok = applyIslandPreset(st.engine, id));
      expect(ok, isTrue, reason: id);
      final isl = st.project.room.island!;
      expect(isl.y0 + Island.depth + isl.overhang, lessThanOrEqualTo(st.project.room.depth));
      final items = st.project.items.where((c) => c.wallId == 'I').toList();
      expect(items, isNotEmpty, reason: id);
      expect(items.fold<int>(0, (a, c) => a + c.width), lessThanOrEqualTo(isl.length + 1));
      expect(st.engine.validate().where((i) => i.severity == Severity.error && !i.code.startsWith('zone_')), isEmpty, reason: id);
      if (id == 'cuisson') expect(items.any(st.engine.cooks), isTrue);
      if (id == 'lavage') expect(items.any(st.engine.washes), isTrue);
      if (id == 'tiroirs') {
        expect(isl.flip, isTrue);
        // façades vers la salle : le devant est du côté opposé au mur du fond
        final (_, y0) = st.project.room.wall('I').toPlan(0, 0);
        final (_, y1) = st.project.room.wall('I').toPlan(0, 600);
        expect(y1, greaterThan(y0));
      }
    }
    final st = kitchen();
    st.engine.applyShape(RoomShape.lShape);
    st.engine.autoFillWall('A', Band.low);
    st.edit(() => applyIslandPreset(st.engine, 'cascade'));
    st.edit(() => st.project.style
      ..worktop = 'granit_gris'
      ..islandTop = 'marbre');
    final tops = st.estimateLines.where((l) => l.section == 'Plan de travail' && l.unit == 'm.l.').toList();
    expect(tops, hasLength(2));
    expect(tops.last.detail, contains('jambages'));
    st.edit(() => st.project.style.islandFront = 'ocre');
    final c = st.project.items.firstWhere((c) => c.wallId == 'I');
    expect(frontOfItem(st.project.style, c, st.engine.modelOf(c)).id, 'ocre');
  });

  testWidgets('menu Façades et Décor', (t) async {
    t.view.physicalSize = const Size(700, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = filled();
    Widget panel(StyleSection s) => MaterialApp(
        theme: buildTheme(Brightness.light, googleFonts: false),
        home: Scaffold(body: SizedBox(width: 420, child: ListenableBuilder(listenable: st, builder: (_, _) => StylePanel(key: ValueKey(s), state: st, section: s)))));
    await t.pumpWidget(panel(StyleSection.fronts));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('profile_shaker')));
    await t.pumpAndSettle();
    expect(st.project.style.frontProfile, 'shaker');
    await t.pumpWidget(panel(StyleSection.decor));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('decor_auto')));
    await t.pumpAndSettle();
    expect(st.project.style.decor, contains('cafe'));
    await t.tap(find.byKey(const ValueKey('decor_rideau')));
    await t.pumpAndSettle();
    expect(st.project.style.decor.contains('store'), isFalse);
    await t.tap(find.byKey(const ValueKey('decor_show')));
    await t.pumpAndSettle();
    expect(st.project.style.showDecor, isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('dessin des modèles de façade', (t) async {
    t.view.physicalSize = const Size(900, 340);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, home: CustomPaint(size: Size.infinite, painter: _Profiles(cat))));
    await expectLater(find.byType(CustomPaint).last, matchesGoldenFile('goldens/facades_profils.png'));
  });
}

class _Profiles extends CustomPainter {
  final Catalog cat;
  _Profiles(this.cat);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    var x = 12.0;
    for (final (i, p) in frontProfiles.keys.indexed) {
      final fin = fronts[(i * 5 + 2) % fronts.length];
      canvas.save();
      canvas.translate(x, 12);
      canvas.scale(0.27);
      for (final (y, h, k) in [(0.0, 250.0, CellKind.drawer), (255.0, 750.0, CellKind.door)]) {
        canvas.save();
        canvas.translate(0, y);
        paintFront(canvas, Rect.fromLTWH(0, 0, 600, h), cat['base_standard_single_door'],
            fill: fin.color, stroke: Colors.black, line: Colors.black, cells: [FrontCell(k, 0, h, 'left', -1)], handle: 'cup', profile: p, realistic: true, pxPerMm: 1, opening: 'hinged_left');
        canvas.restore();
      }
      canvas.restore();
      x += 176;
    }
  }

  @override
  bool shouldRepaint(_Profiles o) => false;
}
