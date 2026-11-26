// Panneaux de finition dessous / dessus : un seul panneau continu le long de la rangée, joues comprises,
// les joues le rejoignent ; au débit.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';

void main() {
  test('3 hauts côte à côte, joues aux deux bouts : un panneau dessous de bout en bout, raccordé aux joues', () {
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    final e = st.engine;
    e.applyShape(RoomShape.linear);
    final model = st.catalog.models.firstWhere((m) => m.kind == CabinetKind.wall && m.hasDoors);
    final a = e.add(model.id, 'A', s: 600, width: 600);
    e.add(model.id, 'A', s: 1200, width: 600);
    final c = e.add(model.id, 'A', s: 1800, width: 600);
    expect(e.setCheek(a.uid, true, true).$1, isTrue);
    expect(e.setCheek(c.uid, false, true).$1, isTrue);
    st.setCap(a.uid, bottom: true, on: true, run: true);

    final caps = capPanels(e);
    expect(caps, hasLength(1), reason: 'les trois dessous forment un seul panneau');
    final cp = caps.single;
    expect(cp.top, isFalse);
    expect(cp.items, hasLength(3));
    expect(cp.s0, closeTo(a.s - 18, 0.5), reason: 'il passe sous la joue gauche');
    expect(cp.s1, closeTo(c.right + 18, 0.5), reason: 'et sous la joue droite');
    expect(cp.z1, closeTo(a.z, 0.5), reason: 'collé sous les caissons');
    // les joues descendent de son épaisseur : l'angle est fermé
    expect(e.cheekBox(a, true).box.z0, closeTo(a.z - 18, 0.5));
    expect(e.cheekBox(c, false).box.z0, closeTo(c.z - 18, 0.5));
    // au débit
    expect(cutList(e, e.project.cut, const {}).any((p) => p.name == 'Panneau de finition' && p.length == cp.length.round()), isTrue);

    // un trou au milieu : deux panneaux
    st.setCap(cp.items[1].uid, bottom: true, on: false);
    expect(capPanels(e), hasLength(2));
  });
}
