// Joues (costados) sur n'importe quel caisson, couleur du profil Gola, buanderie (plan de travail, machines dans leur meuble).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/finishes.dart';
import 'package:kitchen_planner/ui/kx_choices.dart';
import 'package:kitchen_planner/ui/kx_top_bar.dart';
import 'package:kitchen_planner/ui/scene_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  AppState kitchen() {
    final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'), handles: f('handles'));
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()), db: db);
    st.engine.applyShape(RoomShape.linear);
    return st;
  }

  int joues(AppState st) => cutList(st.engine, st.project.cut, {}).where((p) => p.name == 'Joue de finition').fold(0, (a, p) => a + p.qty);

  test('joue ajoutée entre deux caissons : le voisin se décale, débit, plan de travail continu', () {
    final st = kitchen();
    final a = st.engine.add('base_standard_single_door', 'A', s: 600, width: 600);
    final b = st.engine.add('base_standard_single_door', 'A', s: 1200, width: 600);
    final before = joues(st);
    final msg = st.setCheek(a.uid, false, true);
    expect(msg, contains('18 mm'));
    expect(b.s, 1218);
    expect(joues(st), before + 1);
    expect(st.engine.runs('A', (m) => m.kind.isLow), [(600.0, 1818.0)], reason: 'un seul plan de travail');
    expect(st.engine.validate().where((i) => i.severity == Severity.error), isEmpty);
    // le voisin ne revient pas dans la joue
    st.engine.move(b.uid, s: 1200);
    expect(b.s, 1218);
    final back = Project.fromJson(st.project.toJson());
    expect(back.items.first.cheekR, 'oui');
    st.setCheek(a.uid, false, null);
    expect(joues(st), greaterThanOrEqualTo(before));
  });

  test('mur plein : la joue est prise sur le caisson, et rendue quand on la retire ; « sans » retire la joue automatique', () {
    final st = kitchen();
    st.project.room.wall('A');
    final len = st.project.room.wall('A').length;
    final n = (len / 600).floor();
    final a = st.engine.add('base_standard_single_door', 'A', s: 0, width: 600);
    for (var i = 1; i < n; i++) {
      st.engine.add('base_standard_single_door', 'A', s: i * 600.0, width: 600);
    }
    if (len - n * 600 < 18) {
      expect(st.setCheek(a.uid, false, true), contains('582'));
      expect((a.width, a.cheekR), (582, 'pris'));
      expect(st.engine.validate().where((i) => i.code == 'width'), isEmpty);
      st.setCheek(a.uid, false, null);
      expect(a.width, 600);
    }
    final st2 = kitchen();
    final c = st2.engine.add('base_standard_single_door', 'A', s: 900, width: 600);
    expect(joues(st2), 2);
    st2.setCheek(c.uid, true, false);
    expect(joues(st2), 1);
    st2.project.style.endPanels = false;
    expect(joues(st2), 0);
    st2.setCheek(c.uid, true, true);
    expect(joues(st2), 1, reason: 'la joue demandée reste, même sans les automatiques');
  });

  test('côtés visibles : une colonne à côté d’un bas reçoit sa joue ; tous les caissons', () {
    final st = kitchen();
    final tall = st.engine.add('tall_pantry', 'A', s: 0, width: 600);
    st.engine.add('base_standard_single_door', 'A', s: tall.right, width: 600);
    expect(st.engine.cheekCandidates().map((x) => (x.$1.uid, x.$2)), contains((tall.uid, false)), reason: '${[for (final c in st.project.items) (c.modelId, c.s, c.right, c.top, c.depth, st.engine.sideVisible(c, false))]}');
    final (done, refused) = st.addCheeks();
    expect((done > 0, refused), (true, 0));
    expect(tall.cheekR, 'oui');
    expect(st.engine.cheekCandidates().where((x) => x.$1 == tall), isEmpty);
    st.addCheeks(visibleOnly: false);
    expect(st.engine.validate().where((i) => i.severity == Severity.error), isEmpty);
    st.clearCheeks();
    expect(st.project.items.every((c) => c.cheekL == null && c.cheekR == null), isTrue);
  });

  test('profil Gola : couleur choisie, assortie aux façades, au devis', () {
    final st = kitchen();
    st.engine.add('base_standard_single_door', 'A', s: 0, width: 600);
    st.setHandle(HandleCatalog.gola);
    expect(HandleCatalog.gola.finishes.length, greaterThan(6));
    st.setHandle(HandleCatalog.gola, finish: 'Noir mat');
    expect(golaColor(st.project.style, Colors.white), handleFinishColor('Noir mat'));
    expect(st.estimateLines.any((l) => l.detail.contains('Noir mat')), isTrue);
    st.setHandle(HandleCatalog.gola, finish: HandleCatalog.golaLikeFront);
    expect(golaColor(st.project.style, const Color(0xFF3D5A4A)).computeLuminance(), lessThan(0.15));
  });

  testWidgets('buanderie : plan de travail, machines dans leur meuble, meubles hauts au mur', (t) async {
    await t.runAsync(() async {
      final cat = universeCatalog(FurnitureUniverse.parse('buanderie', f('furniture/buanderie')));
      final st = AppState(cat, project: Project(universe: 'buanderie'))..objectCatalog = CatalogObject.parse(f('objects'));
      st.engine.applyShape(RoomShape.linear);
      final all = proposeUniverse(st.engine);
      expect(all, isNotEmpty);
      for (final (_, pr) in all) {
        final e = LayoutEngine(cat, pr.project);
        expect(pr.project.objects.any((o) => o.ref.contains('asher')), isFalse, reason: 'les machines sont dans leurs meubles');
        for (final c in pr.project.items) {
          if (e.modelOf(c).kind.isHigh) expect(c.z, greaterThan(1200));
          for (final mc in e.machinesIn(c)) {
            expect(mc.s - mc.w / 2, greaterThanOrEqualTo(c.s + 17));
            expect(mc.s + mc.w / 2, lessThanOrEqualTo(c.right - 17));
            expect(mc.z + mc.h, lessThan(c.top));
          }
        }
        expect(e.runs('A', (m) => e.hasWorktop && m.kind.isLow), isNotEmpty);
        final sc = await SceneExporter().build(AppState(cat, project: pr.project)..objectCatalog = st.objectCatalog);
        final tops = (sc['solids'] as List).where((s) => s['top'] == true);
        expect(tops, isNotEmpty);
        final low = pr.project.items.where((c) => e.modelOf(c).kind.isLow).map((c) => c.top).reduce((a, b) => a > b ? a : b);
        expect(tops.every((s) => (s['z0'] as num) >= low - 0.5), isTrue);
        expect((sc['objects'] as List).where((o) => '${o['uid']}'.startsWith('machine-')), isNotEmpty);
      }
    });
  });

  testWidgets('logo au milieu de la barre ; choix longs sur plusieurs lignes, mots entiers', (t) async {
    t.view.physicalSize = const Size(1600, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      const KxTopBar(menus: [
        KxMenu('Fichier', 'a', [SizedBox()])
      ]),
      SizedBox(
        width: 260,
        child: KxChoices<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Automatique')),
              ButtonSegment(value: 1, label: Text('Comme les bas')),
              ButtonSegment(value: 2, label: Text('Comme les hauts')),
            ],
            selected: const {0},
            onSelectionChanged: (_) {}),
      ),
    ]))));
    expect(t.getCenter(find.byKey(const ValueKey('kx_logo'))).dx, closeTo(800, 1));
    expect(t.getSize(find.text('Automatique')).height, lessThan(30));
    expect(t.takeException(), isNull);
  });
}
