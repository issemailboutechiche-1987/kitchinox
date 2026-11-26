// Joues : en bout de rangée jusqu'au sol (elles ferment la plinthe), entre deux meubles au bas du caisson (plinthe continue).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  test('joue entre deux meubles bas : pas de « pied » dans la plinthe', () {
    final p = Project(room: Room(width: 4000, depth: 3000, height: 2600));
    final e = LayoutEngine(cat, p);
    e.applyShape(RoomShape.linear);
    final a = e.add('base_standard_single_door', 'A', s: 600, width: 600);
    final b = e.add('base_standard_single_door', 'A', s: 1200, width: 600);
    expect(e.setCheek(a.uid, true, true).$1, isTrue);
    expect(e.setCheek(a.uid, false, true).$1, isTrue);
    final end = e.cheekBox(a, true).box, mid = e.cheekBox(a, false).box;
    expect(end.z0, 0, reason: 'en bout de rangée : jusqu’au sol');
    expect(mid.z0, closeTo(a.z, 0.5), reason: 'entre deux meubles : au bas du caisson');
    expect(a.z, greaterThan(50), reason: 'le caisson est bien posé sur sa plinthe');
    expect(b.s, greaterThanOrEqualTo(a.right));
  });
}
