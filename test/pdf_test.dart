// Génère le plan d'exécution PDF d'une cuisine d'exemple dans test/out/ pour relecture.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/cut_pdf.dart';
import 'package:kitchen_planner/ui/pdf_export.dart';
import 'package:kitchen_planner/ui/tech_drawings.dart';

Future<void> _loadFonts() async {
  final flutterRoot = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final dir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  final l = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    l.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
  }
  await l.load();
}

LayoutEngine sampleKitchen() {
  final catalog = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  final p = Project(name: 'Cuisine exemple', room: Room(width: 4200, depth: 3400, height: 2500));
  final e = LayoutEngine(catalog, p);
  e.applyShape(RoomShape.lShape);
  e.addOpening('door', 'D', s: 1200);
  e.addOpening('window', 'A', s: 2300, width: 900); // au-dessus de l'évier
  e.add('tall_integrated_fridge', 'A', s: 0, height: 2200);
  e.add('base_drawers_multi', 'A', s: 600, width: 600);
  e.add('base_cooktop_oven', 'A', s: 1200, width: 600);
  e.add('base_sink', 'A', s: 1800, width: 800);
  e.add('base_integrated_dishwasher_door', 'A', s: 2600, width: 600);
  e.add('corner_base_l_shaped', 'A');
  e.add('wall_integrated_hood', 'A', s: 1200, width: 600, z: 1600, height: 600); // 700 au-dessus du plan
  e.add('wall_standard_single_door', 'A', s: 600, width: 600, z: 1500, height: 800);
  e.add('base_standard_double_door', 'B', s: 900, width: 800);
  e.add('base_standard_single_door', 'B', s: 1700, width: 600);
  e.add('tall_oven_microwave', 'B', s: 2800, height: 2200);
  e.add('wall_standard_double_door', 'B', s: 900, width: 800, z: 1500, height: 800);
  return e;
}

void main() {
  testWidgets('plan d\'exécution PDF', (t) async {
    await _loadFonts();
    final e = sampleKitchen();
    expect(repereNumbers(e).length, e.project.items.length);
    expect(wallsToDraw(e), containsAll(['A', 'B', 'D']));
    String f(String n) => File('assets/data/$n.json').readAsStringSync();
    final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'));
    final bytes = await t.runAsync(() => buildExecutionPdf(e, now: DateTime(2026, 11, 4, 18, 30), pixelRatio: 1.6, db: db));
    expect(bytes, isNotNull);
    expect(String.fromCharCodes(bytes!.sublist(0, 5)), '%PDF-');
    final d = TechDrawer(e);
    await t.runAsync(() async {
      const size = Size(2400, 1500);
      File('test/out/plan_dessus.png').writeAsBytesSync(await renderPng(size, d.paintPlan));
      File('test/out/plan_face_A.png').writeAsBytesSync(await renderPng(size, (c, s) => d.paintElevation(c, s, 'A')));
      File('test/out/plan_face_B.png').writeAsBytesSync(await renderPng(size, (c, s) => d.paintElevation(c, s, 'B')));
      File('test/out/vue_3d.png').writeAsBytesSync(await renderPng(size, (c, s) => d.paint3d(c, s, -0.6)));
    });
    final cs = e.project.cut;
    final plan = nest(cutList(e, cs, repereNumbers(e)), cs);
    expect(plan.notPlaced, isEmpty);
    final cut = await t.runAsync(() => buildCutPdf(e, plan, now: DateTime(2026, 11, 5), pixelRatio: 1.6, db: db));
    File('test/out/plan_de_decoupe_exemple.pdf').writeAsBytesSync(cut!);
    await t.runAsync(() async {
      File('test/out/panneau_1.png').writeAsBytesSync(await renderPng(const Size(1400, 1050), (c, s) => paintSheet(c, s, plan.sheets.first)));
    });
    for (final m in plan.materials) {
      File('test/out/exemple_${m.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.sct')
          .writeAsStringSync(toSct(plan, m, order: 'Cuisine exemple', date: DateTime(2026, 11, 5)));
    }
    // ignore: avoid_print
    print('Débit : ${plan.partCount} pièces, ${plan.sheets.length} panneaux, matériaux ${plan.materials}');
    final out = File('test/out/plan_execution_exemple.pdf')..createSync(recursive: true);
    out.writeAsBytesSync(bytes);
    // eslint-disable-next-line
    // ignore: avoid_print
    print('PDF : ${out.path} (${bytes.length ~/ 1024} Ko), avertissements : ${e.validate().map((i) => i.code).toSet()}');
  });
}
