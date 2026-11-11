// Rendu 3D de quelques modèles de la collection (contrôle visuel dans test/out).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/scene3d.dart';
import 'package:kitchen_planner/ui/tech_drawings.dart';
import 'package:kitchen_planner/ui/textures.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  testWidgets('rendus de la collection', (t) async {
    final e = LayoutEngine(cat, Project(room: Room(width: 4600, depth: 4200, height: 2600)));
    e.addOpening('window', 'A', s: 2300);
    e.addOpening('door', 'D', s: 3500);
    final col = buildTemplates(e);
    await t.runAsync(() async {
      await TextureBank.instance.init();
      for (final id in ['chefchaouen', 'fes', 'atlas', 'essaouira']) {
        final (tp, pr) = col.firstWhere((x) => x.$1.id == id);
        final pe = LayoutEngine(cat, pr.project);
        final yaw = pr.project.room.isWallEnabled('C') && !pr.project.room.isWallEnabled('B') ? 0.6 : -0.6;
        File('test/out/modele_${tp.id}.png').writeAsBytesSync(await renderPng(const Size(1000, 680), (c, s) {
          final cam = Camera3d.fit(pr.project.room, yaw, s, zoom: 1.25);
          Scene3dPainter(pe, cam, selectColor: Colors.orange, background: Colors.white).paint(c, s);
        }));
      }
    });
  });
}
