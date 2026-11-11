// Remplissage automatique : le trio (froid, lavage, cuisson) et l'électroménager sont posés.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  for (final shape in [RoomShape.linear, RoomShape.lShape, RoomShape.uShape]) {
    test('remplissage ${shape.label}', () {
      final p = Project(room: Room(width: 3600, depth: 3000, height: 2500));
      final e = LayoutEngine(cat, p);
      e.applyShape(shape);
      e.addOpening('window', 'A', s: 1900, width: 1000);
      e.addOpening('door', 'D', s: 1800);
      for (final w in Room.wallOrder.where(shape.walls.contains)) {
        e.autoFillWall(w, Band.low);
      }
      for (final w in Room.wallOrder.where(shape.walls.contains)) {
        e.autoFillWall(w, Band.high);
      }
      final (wash, cook, cool) = e.workZones();
      expect(wash, isNotNull);
      expect(cook, isNotNull);
      expect(cool, isNotNull);
      expect(p.items.any((c) => c.modelId == 'base_integrated_dishwasher_door'), isTrue);
      expect(p.items.any((c) => c.modelId == 'wall_integrated_hood'), isTrue);
      final hard = e.validate().where((i) => i.severity == Severity.error).toList();
      expect(hard, isEmpty, reason: hard.join('\n'));
      final buf = StringBuffer('== ${shape.label}\n');
      for (final c in [...p.items]..sort((a, b) => a.wallId == b.wallId ? a.s.compareTo(b.s) : a.wallId.compareTo(b.wallId))) {
        buf.writeln('  ${c.wallId} ${c.s.round().toString().padLeft(5)} ${c.width} ${e.modelOf(c).id}'
            '${e.modelOf(c).kind.isHigh ? ' z=${c.z.round()}' : ''}');
      }
      buf.writeln('  triangle ${e.triangleLegs()}');
      for (final i in e.validate().where((i) => i.severity != Severity.info)) {
        buf.writeln('  ! $i');
      }
      // ignore: avoid_print
      print(buf);
    });
  }
}
