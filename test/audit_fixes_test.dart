// Corrections de l'audit : réseaux des sanitaires, objets dans le dossier (PDF, dessins, devis),
// objets ramenés dans une pièce réduite, étagères hors hauteur (Art), alerte de sauvegarde.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/pdf_export.dart';
import 'package:kitchen_planner/ui/session.dart';
import 'package:kitchen_planner/ui/tech_drawings.dart';
import 'package:kitchen_planner/ui/web_io.dart';

AppState bath() {
  final u = FurnitureUniverse.parse('bain', File('assets/data/furniture/bain.json').readAsStringSync());
  final p = Project(universe: 'bain', name: 'Salle de bain', room: Room(width: 3600, depth: 3000, height: 2600));
  p.openings.add(Opening(uid: 'door', type: 'door', wallId: 'D', s: 300, width: 800, z: 0, height: 2040));
  final st = AppState(universeCatalog(u), project: p)..objectCatalog = CatalogObject.parse(File('assets/data/objects.json').readAsStringSync());
  st.applyLayoutProposal(proposeUniverse(st.engine).firstWhere((x) => x.$2.name == 'Fès').$2, withStyle: true);
  return st;
}

void main() {
  test('1. réseaux : chaque sanitaire a ses arrivées, son évacuation (WC en Ø100), ses câbles ; pas de prise de cuisine', () {
    final st = bath();
    st.setNetworks(true);
    final pts = st.project.points;
    for (final o in st.project.objects) {
      final f = o.fixture!;
      final mine = pts.where((x) => x.forUid == o.uid).toList();
      if (f.water.isNotEmpty) expect(mine.any((x) => x.kind.network == 'drain'), isTrue, reason: f.name);
      if (f.id.startsWith('wc')) expect(mine.any((x) => x.kind == NetKind.drainWc), isTrue);
      if (f.id == 'chauffe_eau') expect(mine.any((x) => x.kind == NetKind.cable), isTrue);
      // le point est sur le mur du sanitaire, dans sa largeur
      final (wid, a, b) = objectOnWall(st.project.room, o);
      for (final x in mine.where((x) => x.kind.network != 'elec')) {
        expect(x.wallId, wid, reason: f.name);
        expect(x.s, inInclusiveRange(a - 1, b + 1), reason: f.name);
      }
    }
    // vasque du meuble : eau et évacuation ; aucune « prise du plan de travail » de cuisine
    expect(pts.any((x) => x.use == NetUse.vanity && x.kind == NetKind.drain), isTrue);
    expect(pts.where((x) => x.use == NetUse.plan), isEmpty);
    final issues = networkChecks(st.engine);
    expect(issues.where((i) => i.code == 'net_fixture' || i.code == 'net_plan' || i.code == 'net_count'), isEmpty);
    // une prise posée contre la baignoire : volume 2 interdit
    final tub = st.project.objects.firstWhere((o) => o.ref == 'fixture:baignoire');
    final (wid, a, _) = objectOnWall(st.project.room, tub);
    st.project.points.add(NetPoint(uid: 'px', kind: NetKind.socket, wallId: wid, s: a + 100, z: 1100, auto: false));
    expect(networkChecks(st.engine).any((i) => i.code == 'net_volume'), isTrue);
  });

  testWidgets('2. dossier : sanitaires dans le récapitulatif, le devis, les dessins et le PDF', (t) async {
    final st = bath();
    expect(st.bom.lines.where((l) => l.section == 'Sanitaires' || l.section == heaterCategory).length, 4);
    String f(String n) => File('assets/data/$n.json').readAsStringSync();
    final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'));
    final lines = estimate(st.engine, db, st.project.specs, st.cutPlan, st.bom).where((l) => l.section == 'Sanitaires' || l.section == heaterCategory).toList();
    expect(lines.length, 4);
    expect(lines.every((l) => !l.unitPrice.isZero), isTrue);
    final d = TechDrawer(st.engine);
    await t.runAsync(() async {
      const size = Size(2400, 1500);
      File('test/out/bain_plan.png').writeAsBytesSync(await renderPng(size, d.paintPlan));
      final wc = st.project.objects.firstWhere((o) => o.ref.startsWith('fixture:wc'));
      File('test/out/bain_face.png').writeAsBytesSync(await renderPng(size, (c, s) => d.paintElevation(c, s, fixtureWall(wc))));
      final bytes = await buildExecutionPdf(st.engine, now: DateTime(2026, 11, 7), pixelRatio: 1.2, db: db);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });
  });

  test('3. pièce réduite : les objets restent dedans et plaqués à leur mur', () {
    final st = bath();
    final onB = st.project.objects.firstWhere((o) => o.rot == 90);
    st.updateRoom(width: 3000, depth: 2600);
    final r = st.project.room;
    for (final o in st.project.objects) {
      final (x0, y0, x1, y1) = o.footprint;
      expect(x0 >= -0.5 && y0 >= -0.5 && x1 <= r.width + 0.5 && y1 <= r.depth + 0.5, isTrue, reason: objectName(o));
    }
    expect(onB.footprint.$3, closeTo(3000, 0.5));
    expect(st.issues.any((i) => i.code == 'object_outside'), isFalse);
  });

  test('4. Art : étagères au-dessus de la nouvelle hauteur retirées, zones valides', () {
    final b = ArtBox(w: 800, h: 2000, shelves: {
      0: [ArtShelf(600, fixed: true), ArtShelf(1500, fixed: true), ArtShelf(1800)],
    });
    b.h = 1000;
    expect(b.warnings().any((w) => w.contains('hors de la hauteur')), isTrue);
    for (final z in b.zones) {
      expect(z.height, greaterThan(0));
    }
    expect(b.pruneShelves(), 2);
    expect(b.shelvesOf(0).length, 1);
    expect(b.cutParts().where((p) => p.name.startsWith('Étagère')).fold<int>(0, (a, p) => a + p.qty), 1);
  });

  test('5. sauvegarde automatique impossible : une alerte, une seule fois', () {
    final got = <String>[];
    Session.onFailure = got.add;
    Session.saveNow('cuisine', 'x' * 4000001);
    Session.saveNow('cuisine', 'x' * 4000001);
    expect(got, hasLength(1));
    expect(got.single, contains('trop lourd'));
    Session.saveNow('cuisine', '{}');
    storeFull = true;
    Session.saveNow('cuisine', '{"a":1}');
    storeFull = false;
    expect(got, hasLength(2));
    expect(got.last, contains('stockage'));
  });

  test('autres pièces : aucune règle de cuisine (hauteur des hauts, vides, accès à 800 mm)', () {
    for (final id in ['bain', 'dressing', 'tv', 'interieur']) {
      final u = FurnitureUniverse.parse(id, File('assets/data/furniture/$id.json').readAsStringSync());
      final p = Project(universe: id, room: Room(width: 3600, depth: 3000, height: 2600));
      p.openings.add(Opening(uid: 'door', type: 'door', wallId: 'D', s: 300, width: 800, z: 0, height: 2040));
      final st = AppState(universeCatalog(u), project: p);
      for (final (_, pr) in proposeUniverse(st.engine).take(3)) {
        st.applyLayoutProposal(pr, withStyle: true);
        expect(st.issues, isEmpty, reason: '$id ${pr.name}: ${st.issues.map((i) => i.message)}');
      }
    }
  });

  test("porte de 800 mm dégagée : pas d'alerte d'accès, même en cuisine", () {
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    st.engine.addOpening('door', 'D', s: 1500, width: 800);
    st.engine.add('base_drawers_multi', 'A', s: 0, width: 600);
    expect(accessChecks(st.engine), isEmpty);
  });

  test('SketchCut : fonds rainurés par défaut, rainure sur côtés et dessus / dessous, réglages en fin de fichier', () {
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    st.engine.add('base_drawers_multi', 'A', s: 0, width: 600);
    st.engine.add('base_sink', 'A', s: 1200, width: 800);
    st.engine.add('tall_integrated_fridge', 'A', s: 600, height: 2200);
    final cs = st.project.cut;
    expect(cs.backPanel, isTrue);
    // anciens réglages enregistrés sans version : fond rainuré quand même
    expect(CutSettings.fromJson({'back_panel': false}).backPanel, isTrue);
    final parts = cutList(st.engine, cs, repereNumbers(st.engine));
    final sides = parts.where((p) => p.name == 'Côté').toList();
    expect(sides, isNotEmpty);
    expect(sides.every((p) => p.grooveLong == 1 && p.grooveShort == 0), isTrue); // le long de la hauteur
    expect(parts.where((p) => p.name.startsWith('Dessus') || p.name == 'Dessous').every((p) => p.grooveLong + p.grooveShort == 1), isTrue);
    expect(parts.where((p) => p.name.startsWith('Porte') || p.name.startsWith('Fond')).every((p) => p.grooveLength == 0), isTrue);
    final plan = nest(parts, cs);
    final sct = toSct(plan, cs.carcassMaterial);
    expect(sct, contains('1X0_1X0'));
    final lines = sct.trim().split(RegExp(r'\r?\n'));
    expect(lines.sublist(lines.length - 3), ['${cs.grooveDepth}', '${CutSettings.grooveOffset}', '${cs.backThickness + 1}']);
    // étagère en retrait du fond
    final shelf = parts.firstWhere((p) => p.name == 'Tablette fixe médiane');
    expect(shelf.width, lessThanOrEqualTo(sides.first.width - CutSettings.grooveOffset - cs.backThickness)); // en retrait du fond
  });
}
