// Style d'un meuble : appliqué à toute sa zone (hauts / bas / colonnes) ou recopié au pinceau sur les meubles touchés.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';

void main() {
  test('appliquer à tous : seulement la zone du meuble ; pinceau : chaque meuble touché', () {
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    final e = st.engine;
    e.applyShape(RoomShape.linear);
    final b1 = e.add('base_standard_single_door', 'A', s: 0, width: 600);
    final b2 = e.add('base_standard_single_door', 'A', s: 600, width: 600);
    final b3 = e.add('base_standard_single_door', 'A', s: 1200, width: 600);
    final wallModel = st.catalog.models.firstWhere((m) => m.kind == CabinetKind.wall && m.hasDoors);
    final h1 = e.add(wallModel.id, 'A', s: 0, width: 600);
    b1
      ..front = 'vert_sauge'
      ..profile = 'cannelee';
    final msg = st.applyStyleToZone(b1.uid);
    expect(msg, contains('2'));
    expect([b2.profile, b3.profile], ['cannelee', 'cannelee']);
    expect(b2.front, 'vert_sauge');
    expect(h1.profile, isNull, reason: 'un meuble haut ne change pas quand on applique aux bas');

    // pinceau : du haut vers un bas
    h1
      ..profile = 'shaker'
      ..capBottom = true;
    st.select(h1.uid);
    st.toggleStyleBrush(h1.uid);
    st.select(b3.uid);
    expect(b3.profile, 'shaker');
    expect(b3.capBottom, isFalse, reason: 'pas de panneau dessous sur un meuble bas');
    st.select(null);
    expect(st.styleSource, isNull, reason: 'toucher le vide arrête le pinceau');
    st.select(b2.uid);
    expect(b2.profile, 'cannelee');
  });
}
