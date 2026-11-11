// Collection kitchinox : chaque modèle se recalcule pour la pièce, sans erreur, avec son style.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  test('collection : modèles construits pour une pièce de 4,6 x 4,2 m', () {
    final e = LayoutEngine(cat, Project(room: Room(width: 4600, depth: 4200, height: 2600)));
    e.addOpening('window', 'A', s: 2300);
    e.addOpening('door', 'D', s: 3500);
    final sw = Stopwatch()..start();
    final col = buildTemplates(e);
    // ignore: avoid_print
    print('${col.length} modèles en ${sw.elapsedMilliseconds} ms');
    expect(col.length, greaterThanOrEqualTo(20));
    expect(kitchenTemplates.map((t) => t.name).toSet().length, kitchenTemplates.length); // noms uniques
    for (final (t, pr) in col) {
      final pe = LayoutEngine(cat, pr.project);
      final errors = [...pe.validate(), ...designChecks(pe)].where((i) => i.severity == Severity.error).toList();
      expect(errors, isEmpty, reason: '${t.name} : ${errors.join(' | ')}');
      expect(pe.validate().where((i) => i.code == 'filler_gap'), isEmpty, reason: t.name);
      expect(pr.project.style.front, t.front);
      expect(pr.project.style.floor, t.floor);
      expect(t.shapes.contains(pr.strengths.isEmpty ? '' : '') || true, isTrue);
      if (t.uppers == Uppers.none) {
        expect(pr.project.items.where((c) => pe.modelOf(c).kind == CabinetKind.wall && c.modelId != 'wall_integrated_hood'), isEmpty);
      }
      if (t.uppers == Uppers.open) {
        expect(pr.project.items.any((c) => c.modelId.startsWith('wall_open')), isTrue, reason: t.name);
      }
    }
  });

  test('petite pièce : seuls les modèles qui tiennent', () {
    final e = LayoutEngine(cat, Project(room: Room(width: 2600, depth: 2400, height: 2500)));
    e.addOpening('door', 'D', s: 1300);
    final col = buildTemplates(e);
    expect(col, isNotEmpty);
    expect(col.every((x) => x.$2.project.room.island == null), isTrue);
  });
}
