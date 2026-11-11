// Îlot : création, règles de passage, déplacement, remplissage complet, rendus.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/cut_pdf.dart';
import 'package:kitchen_planner/ui/tech_drawings.dart';

Future<void> _fonts() async {
  final root = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final l = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    l.addFont(Future.value(ByteData.sublistView(File('$root/bin/cache/artifacts/material_fonts/$f').readAsBytesSync())));
  }
  await l.load();
}

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  LayoutEngine kitchen() {
    final p = Project(name: 'Cuisine en L avec îlot', room: Room(width: 5400, depth: 4200, height: 2500));
    final e = LayoutEngine(cat, p);
    e.applyShape(RoomShape.lShape);
    e.addOpening('window', 'A', s: 2000, width: 1000);
    e.addOpening('door', 'D', s: 3600);
    e.addIsland(length: 2400);
    return e;
  }

  test('îlot : création centrée, 1200 mm devant le linéaire du fond, pas de hauts', () {
    final e = kitchen();
    final isl = e.project.room.island!;
    expect(isl.length, 2400);
    expect(isl.x0, 1200);
    expect(isl.y0, 1800);
    expect(() => e.add('wall_standard_single_door', 'I'), throwsA(isA<PlacementException>()));
    expect(() => e.add('tall_pantry', 'I'), throwsA(isA<PlacementException>()));
    final c = e.add('base_drawers_multi', 'I', s: 0, width: 600);
    // face vers le mur du fond : façade à y0
    expect(e.boxesOf(c).first.box.y0, isl.y0);
  });

  test('îlot : passage trop étroit signalé, déplacement refusé hors pièce', () {
    final e = kitchen();
    e.add('base_standard_single_door', 'A', s: 1800, width: 600);
    e.setIsland(y0: 1300); // 700 mm devant le linéaire du fond
    expect(e.validate().any((i) => i.code == 'island_aisle'), isTrue);
    expect(() => e.setIsland(x0: 4000), throwsA(isA<PlacementException>()));
    expect(e.project.room.island!.x0, 1200); // inchangé
  });

  test('îlot : ses caissons le suivent, longueur modifiable', () {
    final e = kitchen();
    final c = e.add('base_standard_single_door', 'I', s: 0, width: 600);
    final x = e.boxesOf(c).first.box.x0;
    e.setIsland(x0: 1400);
    expect(e.boxesOf(c).first.box.x0, x + 200);
    e.setIsland(length: 3000);
    expect(e.boxesOf(c).first.box.x0, x + 200); // reste en place
  });

  test('îlot : le mur gauche qui bouge déplace l\'îlot avec la pièce', () {
    final e = kitchen();
    e.moveWall('C', 300);
    expect(e.project.room.island!.x0, 1500);
  });

  testWidgets('cuisine complète en L avec îlot : trio, contrôles, rendus, débit', (t) async {
    await _fonts();
    final e = kitchen();
    final runs = e.project.room.runIds.where(e.project.room.isWallEnabled).toList();
    for (final id in runs) {
      e.autoFillWall(id, Band.low);
    }
    for (final id in runs.where((id) => id != 'I')) {
      e.autoFillWall(id, Band.high);
    }
    final (wash, cook, cool) = e.workZones();
    expect([wash, cook, cool].every((x) => x != null), isTrue);
    expect(e.project.items.where((c) => c.wallId == 'I'), isNotEmpty);
    expect(e.layoutShape(), 'en L avec îlot');
    final errors = e.validate().where((i) => i.severity == Severity.error).toList();
    expect(errors, isEmpty, reason: errors.join('\n'));
    final bom = buildBom(e);
    expect(bom.lines.any((l) => l.ref == 'island_back_panel'), isTrue);

    final d = TechDrawer(e);
    final cs = e.project.cut;
    final plan = nest(cutList(e, cs, d.reperes), cs);
    expect(plan.notPlaced, isEmpty);
    await t.runAsync(() async {
      const size = Size(2400, 1500);
      File('test/out/ilot_plan.png').writeAsBytesSync(await renderPng(size, d.paintPlan));
      File('test/out/ilot_3d.png').writeAsBytesSync(await renderPng(size, (c, s) => d.paint3d(c, s, -0.5)));
      File('test/out/ilot_face.png').writeAsBytesSync(await renderPng(size, (c, s) => d.paintElevation(c, s, 'I')));
      File('test/out/ilot_decoupe.pdf').writeAsBytesSync(await buildCutPdf(e, plan, now: DateTime(2026, 11, 5), pixelRatio: 1.4));
    });
    final buf = StringBuffer('== ${e.layoutShape()} : ${e.project.items.length} éléments, triangle ${e.triangleLegs()}\n');
    for (final i in e.validate().where((i) => i.severity != Severity.info)) {
      buf.writeln('  ! $i');
    }
    buf.writeln('  débit : ${plan.partCount} pièces, ${plan.sheets.length} panneaux');
    // ignore: avoid_print
    print(buf);
  });
}
