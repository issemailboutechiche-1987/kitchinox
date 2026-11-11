// Réseaux : génération d'après l'implantation, règles, circuits, matériel, sauvegarde.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
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

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  LayoutEngine kitchen({String hob = 'gas'}) {
    final p = Project(room: Room(width: 4200, depth: 3400, height: 2600));
    p.specs.hobEnergy = hob;
    final e = LayoutEngine(cat, p);
    e.applyShape(RoomShape.lShape);
    e.addOpening('window', 'A', s: 1500);
    e.addOpening('door', 'D', s: 2400);
    for (final w in ['A', 'B']) {
      e.autoFillWall(w, Band.low);
      e.autoFillWall(w, Band.high);
    }
    return e;
  }

  test('génération : eau et évacuation à l\'évier, appareils alimentés, prises du plan', () {
    final e = kitchen();
    final n = applyNetworks(e);
    final pts = e.project.points;
    expect(n, pts.length);
    final sink = e.project.items.firstWhere((c) => e.isWashing(e.modelOf(c)));
    final water = pts.where((x) => x.forUid == sink.uid).map((x) => x.kind).toSet();
    expect(water, containsAll([NetKind.waterCold, NetKind.waterHot, NetKind.drain]));
    for (final x in pts.where((x) => x.forUid == sink.uid)) {
      expect(x.s, inInclusiveRange(sink.s, sink.right));
    }
    // plaque gaz : robinet gaz, pas de 32 A
    expect(pts.any((x) => x.kind == NetKind.gas), isTrue);
    expect(pts.any((x) => x.kind == NetKind.out32), isFalse);
    expect(pts.where((x) => x.use == NetUse.plan).length, greaterThanOrEqualTo(4));
    expect(pts.any((x) => x.kind == NetKind.switch_ && x.wallId == 'D'), isTrue);
    final issues = networkChecks(e);
    expect(issues.where((i) => i.severity == Severity.error), isEmpty, reason: issues.join('\n'));
    // pas de prise du plan au-dessus de l'évier
    for (final x in pts.where((x) => x.use == NetUse.plan && x.wallId == sink.wallId)) {
      expect(x.s < sink.s - 100 || x.s > sink.right + 100, isTrue, reason: '$x');
    }
  });

  test('lave-vaisselle : prise 20 A et robinet dans le meuble voisin, jamais derrière', () {
    final e = LayoutEngine(cat, Project(room: Room(width: 3600, depth: 3000, height: 2500)));
    final sink = e.add('base_sink', 'A', s: 0, width: 800);
    final lv = e.add('base_integrated_dishwasher_door', 'A', s: 800, width: 600);
    applyNetworks(e);
    final s20 = e.project.points.firstWhere((x) => x.use == NetUse.dishwasher && x.kind == NetKind.socket20);
    expect(s20.s, inInclusiveRange(sink.s, sink.right));
    expect(s20.s < lv.s, isTrue);
    expect(e.project.points.any((x) => x.kind == NetKind.valveMachine), isTrue);
  });

  test('plaque électrique : sortie 32 A, circuit 32 A / 6 mm²', () {
    final e = kitchen(hob: 'electric');
    applyNetworks(e);
    expect(e.project.points.where((x) => x.kind == NetKind.out32).length, 1);
    final c = circuitsOf(e.project);
    expect(c.any((x) => x.breaker == '32 A' && x.cable.contains('6 mm²')), isTrue);
    expect(c.where((x) => x.name.startsWith('Prises cuisine')).every((x) => x.points <= 6), isTrue);
    final mat = networkMaterial(e.project);
    expect(mat.any((m) => m.name.startsWith('Boîte de sortie de câble 32 A')), isTrue);
  });

  test('contrôle : prise déplacée au-dessus de l\'évier → erreur ; points manuels conservés', () {
    final e = kitchen();
    applyNetworks(e);
    final sink = e.project.items.firstWhere((c) => e.isWashing(e.modelOf(c)));
    final x = e.project.points.firstWhere((x) => x.use == NetUse.plan && x.wallId == sink.wallId);
    x
      ..s = sink.s + sink.width / 2
      ..auto = false;
    expect(networkChecks(e).any((i) => i.code == 'net_sink'), isTrue);
    final manual = x.uid;
    applyNetworks(e);
    expect(e.project.pointByUid(manual), isNotNull);
    final back = Project.fromJson(e.project.toJson());
    expect(back.points.length, e.project.points.length);
    expect(back.pointByUid(manual)!.auto, isFalse);
  });

  test('le mur qui bouge déplace les points du mur voisin', () {
    final e = kitchen();
    applyNetworks(e);
    final b = e.project.points.firstWhere((x) => x.wallId == 'B');
    final s0 = b.s;
    e.moveWall('A', 200);
    expect(b.s, s0 + 200);
  });

  testWidgets('PDF : plans des réseaux par mur, circuits et matériel', (t) async {
    await _loadFonts();
    final e = kitchen();
    e.project.networks = true;
    applyNetworks(e);
    await t.runAsync(() async {
      final d = TechDrawer(e);
      File('test/out/reseaux_mur_A.png').writeAsBytesSync(await renderPng(const Size(2000, 1300), (c, s) => d.paintNetworks(c, s, 'A')));
      File('test/out/reseaux_mur_B.png').writeAsBytesSync(await renderPng(const Size(2000, 1300), (c, s) => d.paintNetworks(c, s, 'B')));
      final pdf = await buildExecutionPdf(e, now: DateTime(2026, 11, 5), pixelRatio: 1.4);
      File('test/out/plan_execution_reseaux.pdf').writeAsBytesSync(pdf);
      expect(pdf.length, greaterThan(10000));
    });
  });
}
