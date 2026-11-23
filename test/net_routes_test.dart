// Réseaux tracés en 3D : du tableau à chaque point, conduits plaqués contre les murs, dans la pièce.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  test('tableau près de la porte, trois conducteurs par prise, eau, évacuation et gaz jusqu’aux points', () {
    final p = Project(room: Room(width: 4200, depth: 3400, height: 2600));
    p.specs.hobEnergy = 'gas';
    final e = LayoutEngine(cat, p);
    e.applyShape(RoomShape.lShape);
    e.addOpening('door', 'D', s: 2400);
    for (final w in ['A', 'B']) {
      e.autoFillWall(w, Band.low);
      e.autoFillWall(w, Band.high);
    }
    applyNetworks(e);
    p.networks = true;
    final l = netLayout(p);
    expect(l.board, isNotNull);
    final (bx, by, bz) = l.board!;
    expect(by, closeTo(3400 - 60, 1), reason: 'tableau sur le mur de la porte (D)');
    expect(bx, inInclusiveRange(0, 4200));
    expect(bz, 1400);

    final pts = visiblePoints(p).toList();
    final sockets = pts.where((x) => x.kind.isSocket && x.wallId != 'I' && x.wallId != 'P').length;
    expect(l.runs.where((r) => r.wire == 'PE').length, greaterThanOrEqualTo(sockets));
    for (final w in ['L', 'N', 'PE', 'cold', 'drain', 'gas']) {
      expect(l.runs.any((r) => r.wire == w), isTrue, reason: 'réseau $w tracé');
    }
    // tout reste dans la pièce, sous le plafond
    for (final r in l.runs) {
      expect(r.pts.length, greaterThanOrEqualTo(2));
      for (final (x, y, z) in r.pts) {
        expect(x, inInclusiveRange(-1, 4201));
        expect(y, inInclusiveRange(-1, 3401));
        expect(z, inInclusiveRange(0, 2600));
      }
    }
    // une descente électrique arrive juste au-dessus de sa prise
    final s = pts.firstWhere((x) => x.kind.isSocket && x.wallId == 'A');
    final ends = l.runs.where((r) => r.wire == 'L').map((r) => r.pts.last);
    expect(ends.any((q) => (q.$1 - s.s).abs() < 40 && (q.$3 - s.z).abs() < 60), isTrue);
    // évacuation en pente vers la descente
    final d = l.runs.firstWhere((r) => r.wire == 'drain');
    expect(d.pts[1].$3, greaterThanOrEqualTo(d.pts[d.pts.length - 2].$3));
  });
}
