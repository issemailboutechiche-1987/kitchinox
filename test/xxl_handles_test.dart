// Poignées barre XXL : jamais plus longues que la façade, toujours dessus (portes basses, hautes, tiroirs, colonnes).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/finishes.dart';
import 'package:kitchen_planner/ui/fronts.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  List<GripSpec> grips(CabinetModel m, double w, double h, {String orient = 'auto', double size = 1100, bool tallXxl = false}) {
    final out = <GripSpec>[];
    final look = HandleLook('xxl', size, Colors.black, orient: orient);
    paintFront(Canvas(ui.PictureRecorder()), Rect.fromLTWH(0, 0, w, h), m,
        fill: Colors.white, stroke: Colors.grey, line: Colors.grey, realistic: true, pxPerMm: 1, handles: (door: look, drawer: look), tallXxl: tallXxl, onGrip: out.add);
    return out;
  }

  void inside(List<GripSpec> gs, double w, double h, String what) {
    expect(gs, isNotEmpty, reason: '$what : une poignée au moins');
    for (final g in gs) {
      final hx = g.vertical ? 0 : g.len / 2, hy = g.vertical ? g.len / 2 : 0;
      expect(g.x - hx, greaterThanOrEqualTo(-0.5), reason: '$what : déborde à gauche');
      expect(g.x + hx, lessThanOrEqualTo(w + 0.5), reason: '$what : déborde à droite');
      expect(g.y - hy, greaterThanOrEqualTo(-0.5), reason: '$what : déborde en haut');
      expect(g.y + hy, lessThanOrEqualTo(h + 0.5), reason: '$what : déborde en bas');
    }
  }

  CabinetModel model(bool Function(CabinetModel) f) => cat.models.firstWhere(f);

  test('barre XXL de 1100 : sur la porte basse, la porte haute, les tiroirs et la colonne', () {
    final base = model((m) => m.id == 'base_standard_single_door');
    var gs = grips(base, 600, 720);
    inside(gs, 600, 720, 'porte basse');
    expect(gs.first.vertical, isTrue);
    expect((gs.first.y - 360).abs(), lessThan(1), reason: 'centrée sur la hauteur de la porte');
    expect(gs.first.len, closeTo(640, 5), reason: 'porte de 720 (jeu compris) : barre de 640 environ, 4 cm de marge à chaque bout');

    final wall = model((m) => m.kind == CabinetKind.wall && m.hasDoors);
    inside(grips(wall, 600, 720), 600, 720, 'porte haute');
    inside(grips(wall, 600, 720, orient: 'h'), 600, 720, 'porte haute, barre horizontale');

    final drawers = model((m) => m.kind == CabinetKind.base && m.id.contains('drawer'));
    inside(grips(drawers, 800, 720), 800, 720, 'tiroirs');

    final tall = model((m) => m.kind == CabinetKind.tall && m.hasDoors);
    inside(grips(tall, 600, 2100, size: 1500), 600, 2100, 'colonne');
    inside(grips(tall, 600, 2100, size: 300, tallXxl: true), 600, 2100, 'colonne, XXL des colonnes');
  });
}
