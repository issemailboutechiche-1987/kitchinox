// Rendu d'une proposition en L avec meubles d'angle (contrôle visuel dans test/out).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/scene3d.dart';
import 'package:kitchen_planner/ui/tech_drawings.dart';
import 'package:kitchen_planner/ui/textures.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  testWidgets('proposition en L avec angles', (t) async {
    final e = LayoutEngine(cat, Project(room: Room(width: 4200, depth: 3400, height: 2600)));
    e.addOpening('window', 'A', s: 2100);
    e.addOpening('door', 'D', s: 3100);
    final pr = proposeLayouts(e).firstWhere((p) => p.id.startsWith('l_'));
    final pe = LayoutEngine(cat, pr.project);
    pr.project.style
      ..worktop = 'marbre'
      ..floor = 'carreaux_ciment'
      ..wall = 'vert_sauge_mur'
      ..splash = 'zellige_vert';
    await t.runAsync(() async {
      await TextureBank.instance.init();
      for (final key in ['parquet_oak', 'concrete_smooth']) {
        final img = TextureBank.instance[key]!;
        final d = await img.toByteData(format: ui.ImageByteFormat.png);
        File('test/out/tex_$key.png').writeAsBytesSync(d!.buffer.asUint8List());
      }
      pr.project.style.floor = 'carreaux_ciment';
      File('test/out/angle_l.png').writeAsBytesSync(await renderPng(const Size(1400, 950), (c, s) {
        final yaw = pr.project.room.isWallEnabled('C') ? 0.6 : -0.6;
        final cam = Camera3d.fit(pr.project.room, yaw, s, zoom: 1.5, panX: yaw > 0 ? 150 : -150, panY: 120);
        Scene3dPainter(pe, cam, selectColor: Colors.orange, background: Colors.white).paint(c, s);
      }));
    });
  });
}
