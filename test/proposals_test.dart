// Propositions d'implantation éprouvées et îlot dans l'espace libre.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  LayoutEngine room(double w, double d) {
    final e = LayoutEngine(cat, Project(room: Room(width: w, depth: d, height: 2600)));
    e.addOpening('window', 'A', s: w / 2);
    e.addOpening('door', 'D', s: w - 1100);
    return e;
  }

  test('propositions : plusieurs formes, trio complet, sans erreur, une par forme', () {
    final e = room(4600, 4200);
    final props = proposeLayouts(e);
    for (final p in props) {
      // ignore: avoid_print
      print('${p.score.toStringAsFixed(1).padLeft(6)}  ${p.name.padRight(42)} err ${p.errors}  plan ${p.worktop.round()}  rgt ${p.storage}  tri ${p.triangle?.round()}  ${p.strengths.join(' | ')}');
    }
    expect(props.length, greaterThanOrEqualTo(4));
    expect(props.map((p) => p.id.split('_').first).toSet().length, props.length);
    expect(props.first.errors, 0);
    // le projet d'origine n'est pas touché
    expect(e.project.items, isEmpty);
    // appliquer
    applyProposal(e, props.first);
    expect(e.project.items, isNotEmpty);
    final (wash, cook, cool) = e.workZones();
    expect([wash, cook, cool].every((x) => x != null), isTrue);
  });

  test('petite pièce : pas d\'îlot en tête', () {
    final props = proposeLayouts(room(2800, 2600));
    expect(props, isNotEmpty);
    expect(props.first.project.room.island, isNull);
  });

  test('îlot : dans l\'espace libre, passages d\'au moins 1 m, loin des murs nus', () {
    final e = room(5200, 4600);
    e.applyShape(RoomShape.lShape);
    e.autoFillWall('A', Band.low);
    e.autoFillWall('B', Band.low);
    final isl = e.addIsland();
    // pas collé au mur avant (D) ni au mur gauche (C)
    expect(isl.x0, greaterThanOrEqualTo(900));
    expect(isl.y0 + Island.depth + isl.overhang, lessThanOrEqualTo(4600 - 900));
    // passage d'au moins 1000 mm vers les meubles du fond
    expect(isl.y0 - 600, greaterThanOrEqualTo(1000 - 0.5));
    final islIssues = e.validate().where((i) => i.code.startsWith('island'));
    expect(islIssues.where((i) => i.severity == Severity.error), isEmpty, reason: islIssues.join('\n'));
  });
}
