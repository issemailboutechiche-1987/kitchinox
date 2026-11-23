// Ouverture d'une seule porte, lave-vaisselle, Gola dans les angles, recentrage, vue après Suivant, décor par pièce.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/header.dart';
import 'package:kitchen_planner/ui/presentation_bar.dart';
import 'package:kitchen_planner/ui/scene_export.dart';
import 'package:kitchen_planner/ui/textures.dart';
import 'package:kitchen_planner/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  AppState kitchen() => AppState(cat, project: Project(room: Room(width: 4200, depth: 3200, height: 2600)));

  testWidgets('double clic : une seule porte ou un seul tiroir', (t) async {
    final st = kitchen();
    final c = st.engine.add('base_drawers_multi', 'A', s: 600);
    await t.runAsync(() async {
      await TextureBank.instance.init();
      Future<Map<String, dynamic>> scene() => SceneExporter().build(st);
      final parts = [for (final f in (await scene())['fronts'] as List) if (f['uid'] == c.uid) ...(f['parts'] as List).where((p) => p['kind'] != 'static')];
      expect(parts.length, greaterThan(1));
      expect([for (final p in parts) p['k']], [for (var k = 0; k < parts.length; k++) k], reason: 'numérotées dans l’ordre');
      st.togglePart(c.uid, 1, parts.length);
      expect((await scene())['open'], {'${c.uid}#1': 1.0});
      expect(st.isOpen(c.uid), isTrue);
      st.togglePart(c.uid, 1, parts.length);
      expect(st.anyOpen, isFalse);
      // tout ouvert, puis une seule refermée
      st.toggleOpen(c.uid);
      st.togglePart(c.uid, 0, parts.length);
      expect((await scene())['open'].keys, [for (var k = 1; k < parts.length; k++) '${c.uid}#$k']);
      st.toggleOpen(c.uid);
      expect(st.anyOpen, isFalse);
    });
  });

  testWidgets('lave-vaisselle : la façade bascule et la machine est là', (t) async {
    final st = kitchen();
    st.project.style.handle = 'gola';
    final c = st.engine.add('base_integrated_dishwasher_door', 'A', s: 600);
    await t.runAsync(() async {
      await TextureBank.instance.init();
      final sc = await SceneExporter().build(st);
      final f = (sc['fronts'] as List).firstWhere((x) => x['uid'] == c.uid);
      expect((f['parts'] as List).single['kind'], 'flapDown');
      expect((f['parts'] as List).single['z1'], closeTo(c.top - 30, 0.01), reason: 'sous la gorge, comme ses voisins');
      expect(f['machine'], isNotNull);
      // pas de caisson en bois autour : la machine, et la gorge qui passe devant
      expect((sc['solids'] as List).where((s) => s['uid'] == c.uid && ((s['mat'] as Map)['metal'] as num? ?? 0) > 0.5), hasLength(3));
    });
  });

  testWidgets('Gola : la gorge suit les meubles d’angle, bas et hauts', (t) async {
    await t.runAsync(() async {
      await TextureBank.instance.init();
      var seen = 0;
      for (final m in cat.models.where((m) => m.kind == CabinetKind.cornerBase || m.kind == CabinetKind.cornerWall)) {
        final st = kitchen();
        st.project.style.handle = 'gola';
        final PlacedCabinet c;
        try {
          c = st.engine.add(m.id, 'A');
        } catch (_) {
          continue;
        }
        if (!m.isCarcass || !st.engine.golaOn(m)) continue;
        seen++;
        final sc = await SceneExporter().build(st);
        final metal = (sc['solids'] as List).where((s) => s['uid'] == c.uid && ((s['mat'] as Map)['metal'] as num? ?? 0) > 0.5).toList();
        expect(metal.length, 3 * st.engine.boxesOf(c).length, reason: m.id);
        for (final f in sc['fronts'] as List) {
          if (f['uid'] != c.uid) continue;
          for (final q in f['parts'] as List) {
            expect(q['z1'] - q['z0'], closeTo(c.height - 30, 0.01), reason: '${m.id} : la façade laisse la gorge libre');
          }
        }
      }
      expect(seen, greaterThan(2));
    });
  });

  test('« Tout afficher » recentre aussi la 3D ; après le point d’eau, « Suivant » revient à la vue du dessus', () {
    final st = kitchen();
    st.setView(ViewMode.view3d);
    final n = st.fit3d;
    st.setZoom(2);
    st.fitView();
    expect((st.fit3d, st.zoom, st.panX), (n + 1, 1.0, 0.0));
    // point d'eau placé (vue de face), puis Suivant : vue du dessus
    st.goTo(PlanStep.space);
    st.addExistingWater(NetKind.waterCold);
    st.setView(ViewMode.front);
    expect(st.next(), isNull);
    expect((st.step, st.view), (PlanStep.layout, ViewMode.plan));
    // en 3D, on y reste
    st.goTo(PlanStep.space);
    st.setView(ViewMode.view3d);
    st.next();
    expect(st.view, ViewMode.view3d);
  });

  testWidgets('outils : carrés alignés quel que soit le libellé', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(
        body: Row(children: [
          ToolTile(icon: Icons.add, label: 'Porte'),
          ToolTile(icon: Icons.add, label: 'Un libellé nettement plus long'),
        ]),
      ),
    ));
    final boxes = find.byType(AnimatedContainer);
    expect(boxes, findsNWidgets(2));
    expect(t.getRect(boxes.at(0)).top, t.getRect(boxes.at(1)).top);
  });

  test('décor : chaque pièce a le sien', () {
    Set<String> ids(String u) => {for (final it in decorFor(u)) it.id};
    for (final u in ['buanderie', 'bain', 'dressing', 'tv', 'interieur']) {
      expect(ids(u).intersection({'cafe', 'toaster', 'blender', 'casserole', 'planches', 'fruits', 'vaisselle'}), isEmpty, reason: u);
      expect(ids(u), containsAll(defaultDecor(u)), reason: u);
    }
    expect(ids('cuisine'), containsAll(defaultDecor('cuisine')));
    expect(ids('cuisine').intersection({'lessive', 'savon', 'vetements'}), isEmpty);
    // un ancien projet de buanderie décoré comme une cuisine : rien ne sort
    final st = kitchen();
    st.project.universe = 'buanderie';
    st.project.style.decor.addAll(['cafe', 'toaster']);
    expect(placeDecor(st.engine), isEmpty);
  });

  testWidgets('fiche Décor : les objets de la pièce', (t) async {
    final st = kitchen();
    st.project.universe = 'bain';
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: DecorPanel(state: st)))));
    expect(find.byKey(const ValueKey('decor_savon')), findsOneWidget);
    expect(find.byKey(const ValueKey('decor_cafe')), findsNothing);
    expect(find.text('Sur la plaque'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
