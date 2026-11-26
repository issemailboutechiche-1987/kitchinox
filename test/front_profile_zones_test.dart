// Modèle de façade : pour toute la cuisine, pour une zone (hauts, bas, colonnes), ou meuble par meuble.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';

void main() {
  test('priorité : le meuble, puis sa zone, puis la cuisine ; gardé dans le projet', () {
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    final e = st.engine;
    e.applyShape(RoomShape.linear);
    final low = e.add('base_standard_single_door', 'A', s: 0, width: 600);
    final wallModel = st.catalog.models.firstWhere((m) => m.kind == CabinetKind.wall && m.hasDoors);
    final high = e.add(wallModel.id, 'A', s: 0, width: 600);
    final style = st.project.style;

    st.setProfile('shaker'); // partout
    expect(style.profileOf(low, CabinetKind.base), 'shaker');
    expect(style.profileOf(high, CabinetKind.wall), 'shaker');

    st.setProfileScope('haut');
    st.setProfile('cannelee'); // les hauts seulement
    expect(style.profileOf(high, CabinetKind.wall), 'cannelee');
    expect(style.profileOf(low, CabinetKind.base), 'shaker');

    st.setItemProfile(low.uid, 'mouluree'); // un seul meuble
    expect(style.profileOf(low, CabinetKind.base), 'mouluree');

    final back = Project.fromJson(st.project.toJson());
    final low2 = back.byUid(low.uid)!;
    expect(back.style.profileOf(low2, CabinetKind.base), 'mouluree');
    expect(back.style.profileOf(back.byUid(high.uid), CabinetKind.wall), 'cannelee');

    st.setProfileScope('tout');
    st.setProfile('lisse'); // partout : les réglages par zone s'effacent, pas ceux des meubles
    expect(style.profileOf(high, CabinetKind.wall), 'lisse');
    expect(style.profileOf(low, CabinetKind.base), 'mouluree');
  });
}
