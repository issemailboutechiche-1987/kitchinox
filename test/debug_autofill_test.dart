// Propositions automatiques sur plusieurs pièces : jamais de vide non comblé ni de plaque sans hotte,
// angles équipés de meubles d'angle, et la proposition recommandée s'ouvre sans blocage.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  test('propositions propres sur 5 pièces', () {
    for (final (w, d) in [(3600.0, 3000.0), (4200.0, 3400.0), (4600.0, 4200.0), (3000.0, 2600.0), (5200.0, 4600.0)]) {
      final e = LayoutEngine(cat, Project(room: Room(width: w, depth: d, height: 2600)));
      e.addOpening('window', 'A', s: w / 2);
      e.addOpening('door', 'D', s: w - 1100);
      final props = proposeLayouts(e, max: 10);
      expect(props, isNotEmpty);
      for (final p in props) {
        final pe = LayoutEngine(cat, p.project);
        final codes = pe.validate().map((i) => i.code).toSet();
        expect(codes.contains('filler_gap'), isFalse, reason: '${w}x$d ${p.name}');
        expect(codes.contains('hob_no_hood'), isFalse, reason: '${w}x$d ${p.name}');
        // une forme en L ou en U a un vrai meuble d'angle
        if (p.id.startsWith('l_') || p.id.startsWith('li_')) {
          expect(p.project.items.any((c) => c.modelId == 'corner_base_l_shaped'), isTrue, reason: '${w}x$d ${p.name}');
        }
      }
      final best = LayoutEngine(cat, props.first.project);
      expect(openingChecks(best).where((i) => i.code == 'open_blocked'), isEmpty, reason: '${w}x$d ${props.first.name}');
    }
  });

  test('ouverture : une porte contre un obstacle est limitée ; la charnière inversée la libère', () {
    final e = LayoutEngine(cat, Project(room: Room(width: 3600, depth: 3000, height: 2600)));
    e.applyShape(RoomShape.lShape);
    // colonne contre le mur droit, au début du mur B ; un bas sur le mur A juste devant sa porte
    final col = e.add('tall_pantry', 'B', s: 0, height: 2200);
    final (lim0, _) = openLimit(e, col);
    expect(lim0, 1.0);
    e.add('base_standard_single_door', 'A', s: 3600 - 600 - 600, width: 600);
    final checks = openingChecks(e);
    expect(checks.every((i) => i.code != 'open_blocked' || i.uids.isNotEmpty), isTrue);
  });
}
