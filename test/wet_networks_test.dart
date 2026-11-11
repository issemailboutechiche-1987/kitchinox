// Réseaux d'un aménagement automatique de salle de bain : attentes à l'aplomb des sanitaires,
// prises hors volumes, composition tournée vers l'évacuation existante, points orphelins retirés.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

LayoutEngine bath({double w = 3200, double d = 2500}) {
  final u = FurnitureUniverse.parse('bain', File('assets/data/furniture/bain.json').readAsStringSync());
  final p = Project(universe: 'bain', room: Room(width: w, depth: d, height: 2600));
  p.openings.add(Opening(uid: 'door', type: 'door', wallId: 'D', s: 300, width: 800, z: 0, height: 2040));
  return LayoutEngine(universeCatalog(u), p);
}

void main() {
  test('chaque attente d\'un sanitaire est sous son emprise, sur le mur de son dos', () {
    for (final rot in [0, 90, 180, 270]) {
      final e = bath();
      final r = e.project.room;
      final o = RoomObject(uid: 'b', ref: 'fixture:baignoire', x: 0, y: 0, z: 0, rot: rot, w: 1700, h: 580, d: 750);
      snapToWall(r, o);
      e.project.objects.add(o);
      final pts = fixtureWaterPoints(r, e.project.objects);
      final (wall, a, b) = objectOnWall(r, o);
      expect(pts.length, 3);
      for (final (w, s, _, kind, _) in pts) {
        expect(w, wall);
        expect(s >= a && s <= b, isTrue, reason: 'rot $rot $kind $s hors [$a, $b]');
      }
      // mitigeur et bonde du même côté (une extrémité de la baignoire)
      final mix = pts.firstWhere((x) => x.$4 == 'froide').$2, drain = pts.firstWhere((x) => x.$4 == 'evac').$2;
      expect((mix - drain).abs(), lessThan(500), reason: 'rot $rot');
      // même extrémité qu'en 3D : bonde à -0.7 (hw - 110) dans le repère de l'objet
      final (px, py) = objectLocalToPlan(o, -(850 - 110) * 0.7, 0);
      final (sd, _) = r.wall(wall).toWall(px, py);
      expect((sd - drain).abs(), lessThan(1));
    }
  });

  test('douche : alimentations sur la colonne, entraxe 150 ; prise du miroir loin de la douche', () {
    final e = bath();
    final p = e.project;
    final sh = RoomObject(uid: 's', ref: 'fixture:douche', x: 600, y: 0, z: 0, rot: 0, w: 900, h: 2000, d: 900);
    snapToWall(p.room, sh);
    final mi = RoomObject(uid: 'm', ref: 'fixture:miroir', x: 1550, y: 0, z: 1050, rot: 0, w: 800, h: 800, d: 30);
    snapToWall(p.room, mi);
    p.objects.addAll([sh, mi]);
    p.networks = true;
    applyNetworks(e);
    final cold = p.points.firstWhere((x) => x.forUid == 's' && x.kind == NetKind.waterCold);
    final hot = p.points.firstWhere((x) => x.forUid == 's' && x.kind == NetKind.waterHot);
    expect(hot.s - cold.s, closeTo(150, 1));
    expect((cold.s + hot.s) / 2, closeTo(sh.x + 450 * 0.2, 1));
    expect(cold.z, 1100);
    final sock = p.points.where((x) => x.forUid == 'm' && x.kind.isSocket).toList();
    expect(sock, hasLength(1));
    expect(sock.single.s, greaterThan(mi.x + 400), reason: 'du côté opposé à la douche');
    expect(p.points.any((x) => x.forUid == 'm' && x.kind == NetKind.cable), isTrue, reason: 'alimentation du miroir LED');
    expect(networkChecks(e).where((i) => i.code == 'net_volume'), isEmpty);
  });

  test('proposition : la composition se pose sur le mur de l\'évacuation existante', () {
    for (final wall in ['B', 'C']) {
      final e = bath(w: 3200, d: 3000);
      final p = e.project;
      p.points.add(NetPoint(uid: 'ex', kind: NetKind.drain, wallId: wall, s: 1500, z: 400, use: existingUse, auto: false));
      final props = proposeUniverse(e, withStyle: false);
      expect(props, isNotEmpty);
      final best = props.first.$2;
      final q = best.project;
      final pe = LayoutEngine(e.catalog, q);
      final d = wetDrainDistance(pe);
      expect(d, isNotNull);
      // la meilleure proposition ne laisse pas les appareils à eau à l'autre bout de la pièce
      expect(d!, lessThan(2600), reason: '${best.name} : ${d.round()} mm');
      expect(q.points.where((x) => x.use == existingUse), hasLength(1));
    }
  });

  test('nouvel aménagement : les points déplacés à la main des anciens sanitaires disparaissent', () {
    final e = bath();
    final p = e.project;
    final wc = RoomObject(uid: 'w', ref: 'fixture:wc_suspendu', x: 1000, y: 0, z: 0, rot: 0, w: 360, h: 400, d: 540);
    snapToWall(p.room, wc);
    p.objects.add(wc);
    p.networks = true;
    applyNetworks(e);
    final pt = p.points.firstWhere((x) => x.forUid == 'w');
    pt
      ..auto = false
      ..s += 50;
    p.objects.clear();
    applyNetworks(e);
    expect(p.points.where((x) => x.forUid == 'w'), isEmpty);
    // attentes du WC suspendu : dans le bâti (cachées en 3D), évacuation Ø100 à 230 mm
    p.objects.add(wc);
    applyNetworks(e);
    final drain = p.points.firstWhere((x) => x.forUid == 'w' && x.kind == NetKind.drainWc);
    expect(drain.z, 230);
    expect(concealedInFrame(p.room, p.objects, drain.wallId, drain.s, drain.z), isTrue);
  });
}
