// Casquettes : droites et d'angle en L, colonne d'angle garde-manger.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';

void main() {
  AppState kitchen() => AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()), project: Project(room: Room(width: 3600, depth: 3000, height: 2800)));

  for (final depth in [370, 600]) {
    test('U : casquettes de $depth mm sur tout le tour, angles en L', () {
      final st = kitchen();
      st.engine.applyShape(RoomShape.uShape);
      for (final w in ['C', 'A', 'B']) {
        st.engine.autoFillWall(w, Band.low);
      }
      for (final w in ['C', 'A', 'B']) {
        st.engine.autoFillWall(w, Band.high);
      }
      final e = st.engine;
      final before = e.validate().where((i) => i.severity == Severity.error).length;
      final (n, c) = placeTopBoxes(e, height: 360, depth: depth);
      expect(c, 2, reason: 'deux angles');
      expect(n, greaterThan(2));
      final boxes = st.project.items.where((x) => isTopBox(e.modelOf(x))).toList();
      final top = boxes.map((x) => x.top.round()).toSet();
      expect(top, hasLength(1), reason: 'une seule ligne en haut');
      expect(e.validate().where((i) => i.severity == Severity.error).length, lessThanOrEqualTo(before), reason: '${e.validate().where((i) => i.severity == Severity.error).toList()}');
      // le mur du fond est couvert d'un bout à l'autre par les casquettes (là où il y a des hauts)
      for (final (a, b) in e.runs('A', (m) => m.kind.isHigh && !isTopBox(m) && !m.isFreeHood)) {
        final cover = e.runs('A', isTopBox);
        expect(cover.any((r) => r.$1 <= a + 1 && r.$2 >= b - 1), isTrue, reason: 'hauts $a–$b, casquettes $cover');
      }
      // rappel : on remplace, on n'empile pas
      final again = placeTopBoxes(e, height: 400, depth: depth);
      expect(st.project.items.where((x) => isTopBox(e.modelOf(x))).length, again.$1 + again.$2);
      expect(cutList(e, st.project.cut, {}).where((p) => p.cabinet.contains('Casquette')), isNotEmpty);
    });
  }

  test('colonne d’angle garde-manger : deux bras, six niveaux, tailles', () {
    final st = kitchen();
    st.engine.applyShape(RoomShape.lShape);
    final c = st.engine.add('corner_tall_pantry', 'A');
    expect((st.engine.modelOf(c).kind, st.engine.modelOf(c).shape), (CabinetKind.cornerTall, CabinetShape.lShape));
    expect(st.engine.boxesOf(c), hasLength(2));
    expect(cutList(st.engine, st.project.cut, {}).firstWhere((p) => p.name.startsWith('Étagère en L')).qty, 5);
    expect(st.setCornerSize(c.uid, cornerSizes['corner_tall_pantry']!.last), isNull);
    expect((c.width, c.widthRight), (1200, 1200));
    final (_, corners) = placeTopBoxes(st.engine, height: 360, depth: 600);
    expect(corners, 1);
  });
}
