// Accès à la cuisine depuis la porte : passage d'au moins 800 mm jusqu'à la zone de travail.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  /// Pièce de la capture : 3600 x 3000, fenêtre sur A à gauche, porte sur D contre le mur B.
  LayoutEngine room() {
    final e = LayoutEngine(cat, Project(room: Room(width: 3600, depth: 3000, height: 2600)));
    e.addOpening('window', 'A', s: 0);
    final wd = e.project.room.wall('D');
    // porte de 800 à 100 mm du mur B (quel que soit le sens de lecture du mur D)
    final (x0, _) = wd.toPlan(0, 0);
    final s = x0 < 1 ? 3600 - 100 - 800.0 : 100.0;
    e.addOpening('door', 'D', s: s);
    return e;
  }

  test('le passage entre la porte et la cuisine est mesuré', () {
    final e = room();
    expect(doorAccess(e), isEmpty); // pièce vide : rien à contrôler
    e.add('base_sink', 'A', s: 600, width: 800);
    final open = doorAccess(e).single;
    expect(open.width, greaterThanOrEqualTo(780));
    expect(accessChecks(e).where((i) => i.code == 'door_access'), isEmpty);
  });

  test('U de la capture : le bout du mur B qui ferme l’entrée est signalé', () {
    final e = room();
    e.add('base_sink', 'A', s: 600, width: 800);
    // linéaire du mur B jusqu'à ~150 mm de la porte, et linéaire du mur D jusqu'au chambranle
    final wb = e.project.room.wall('B');
    for (var s = 0.0; s + 600 <= 2300; s += 600) {
      e.add('base_standard_single_door', 'B', s: s, width: 600);
    }
    final wd = e.project.room.wall('D');
    final (x0, _) = wd.toPlan(0, 0);
    final fromC = x0 < 1; // s = 0 côté mur C
    for (var k = 0; k < 4; k++) {
      final s = fromC ? k * 600.0 : 3600 - 900 - 600.0 * (k + 1) - 0;
      if (s < 0) break;
      e.add('base_standard_single_door', 'D', s: fromC ? s + 0 : s, width: 600);
    }
    expect(wb.length, greaterThan(0));
    final a = doorAccess(e).single;
    expect(a.width, lessThan(800), reason: 'passage ${a.width}');
    final issue = accessChecks(e).firstWhere((i) => i.code == 'door_access');
    // bouton « Corriger » : dégage l'entrée, garde l'évier
    final fix = fixFor(e, issue);
    expect(fix.label, 'Dégager l’entrée');
    expect(fix.apply!(), isTrue);
    expect(doorAccess(e).single.width, greaterThanOrEqualTo(accessMin - 25));
    expect(e.project.items.any((c) => e.isWashing(e.modelOf(c))), isTrue);
  });

  test('les propositions laissent toujours l’entrée praticable', () {
    final e = room();
    final props = proposeLayouts(e, distinct: false, max: 40);
    expect(props, isNotEmpty);
    for (final pr in props) {
      final pe = LayoutEngine(cat, pr.project);
      for (final a in doorAccess(pe)) {
        expect(a.width, greaterThanOrEqualTo(accessMin - 25), reason: '${pr.name} : passage ${a.width.round()} mm');
      }
    }
  });
}
