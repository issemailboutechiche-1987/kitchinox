// Dupliquer, échanger deux caissons en les glissant, corrections proposées pour chaque problème,
// arrivée d'eau et évacuation existantes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  LayoutEngine room() => LayoutEngine(cat, Project(room: Room(width: 4200, depth: 3200, height: 2600)));

  test('dupliquer : à droite, sinon ailleurs sur le mur, mêmes réglages', () {
    final e = room();
    final a = e.add('base_door_drawer', 'A', s: 0, width: 500)..front = 'chene';
    final b = e.duplicate(a.uid);
    expect(b.uid, isNot(a.uid));
    expect((b.modelId, b.width, b.front), (a.modelId, a.width, 'chene'));
    expect(b.s, a.right);
    e.add('base_standard_single_door', 'A', s: 1000, width: 600);
    final c = e.duplicate(a.uid); // à droite occupé : première place libre
    expect(e.validate().where((i) => i.code == 'overlap'), isEmpty);
    expect(c.s, isNot(a.right));
  });

  test('glisser un caisson sur son voisin : ils échangent leurs places', () {
    final e = room();
    final a = e.add('base_standard_single_door', 'A', s: 0, width: 600);
    final b = e.add('base_drawers_multi', 'A', s: 600, width: 400);
    final r = e.trySwap(a.uid, 500); // centre de A (800) sur B (600..1000)
    expect(r?.moved, isTrue);
    expect(b.s, 0);
    expect(a.s, 400);
    // un haut ne s'échange pas avec un bas
    final h = e.add('wall_standard_single_door', 'A', s: 0, width: 600);
    expect(e.trySwap(h.uid, 300), isNull);
  });

  test('corrections : vide comblé, hotte posée et recentrée, composition rétablie', () {
    final st = AppState(cat, project: Project(room: Room(width: 4200, depth: 3200, height: 2600)));
    final e = st.engine;
    st.edit(() {
      e.add('base_standard_single_door', 'A', s: 0, width: 600);
      e.add('base_standard_single_door', 'A', s: 700, width: 600); // vide de 100
      e.add('base_cooktop_oven', 'A', s: 2000, width: 600);
    });
    Issue issue(String code) => st.issues.firstWhere((i) => i.code == code);
    expect(st.applyFix(issue('filler_gap')), startsWith('Corrigé'));
    expect(st.issues.any((i) => i.code == 'filler_gap'), isFalse);
    expect(st.applyFix(issue('hob_no_hood')), startsWith('Corrigé'));
    final hood = st.project.items.firstWhere((c) => c.modelId == 'wall_integrated_hood');
    expect(hood.s, 2000);
    expect(hood.top, e.wallTopLine('A'));
    // hotte décalée → recentrée
    st.edit(() => e.move(hood.uid, s: 2100));
    expect(st.applyFix(issue('hood_offset')), startsWith('Corrigé'));
    expect(st.project.byUid(hood.uid)!.s, 2000);
    // indice quand aucune action automatique n'existe
    expect(fixFor(e, const Issue(Severity.warning, 'oven_fridge', 'x')).apply, isNull);
  });

  test('eau existante : avertissement si l\'évier est loin de l\'évacuation, propositions qui s\'en rapprochent', () {
    final e = room();
    final sink = e.add('base_sink', 'A', s: 3200, width: 800);
    expect(waterChecks(e).single.code, 'water_unknown');
    e.project.points.add(NetPoint(uid: 'd1', kind: NetKind.drain, wallId: 'A', s: 200, z: 400, use: existingUse, auto: false));
    final far = waterChecks(e).where((i) => i.code == 'drain_far').single;
    expect(far.severity, Severity.warning);
    expect(far.uids, [sink.uid]);
    // propositions : l'évacuation est conservée et l'évier en tient compte
    final e2 = room();
    e2.addOpening('door', 'D', s: 3000);
    e2.project.points.add(NetPoint(uid: 'd1', kind: NetKind.drain, wallId: 'A', s: 300, z: 400, use: existingUse, auto: false));
    final best = proposeLayouts(e2).first;
    expect(best.project.points.any((x) => x.use == existingUse), isTrue);
    expect(sinkDrainDistance(LayoutEngine(cat, best.project))!, lessThan(3000));
  });
}
