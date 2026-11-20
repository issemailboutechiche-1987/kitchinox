// Usinage automatique de l'atelier : assemblages, fond, charnières, coulisses, poignées, taquets, pieds, chants.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/cutting.dart';
import 'package:kitchen_planner/engine/public_prices.dart';
import 'dart:convert';

import 'package:kitchen_planner/engine/art.dart';
import 'package:kitchen_planner/engine/art_fittings.dart';
import 'package:kitchen_planner/engine/art_machining.dart';

int n(MachiningSummary m, MachiningKind k) => m.count(k);

void main() {
  setUpAll(() => PublicPrices.parse(File('assets/data/public_prices.json').readAsStringSync()));

  test('caisson 2 portes de 600 x 720 x 560 sur pieds : tourillons, vis, charnières, poignées, pieds, chants', () {
    final art = ArtProject();
    // caisson posé à 100 mm du sol (pieds), fond de 6 mm encastré de 8 mm dans les côtés, le dessus et le dessous
    const x = 0.0, y = 100.0, w = 600.0, h = 720.0, d = 560.0, t = 18.0;
    art.free.addAll([
      ArtPanel(id: 'g', role: ArtRole.montant, x: x, y: y, w: t, h: h, d: d),
      ArtPanel(id: 'dr', role: ArtRole.montant, x: x + w - t, y: y, w: t, h: h, d: d),
      ArtPanel(id: 'bas', role: ArtRole.tablette, x: x + t, y: y, w: w - 2 * t, h: t, d: d),
      ArtPanel(id: 'haut', role: ArtRole.tablette, x: x + t, y: y + h - t, w: w - 2 * t, h: t, d: d),
      ArtPanel(id: 'fond', role: ArtRole.fond, x: x + t - 8, y: y + t - 8, z: d - 20, w: w - 2 * t + 16, h: h - 2 * t + 16, d: 6),
      ArtPanel(id: 'p1', role: ArtRole.porte, x: x + 2, y: y + 2, z: -t, w: w / 2 - 3.5, h: h - 4, d: t, hinge: 'left'),
      ArtPanel(id: 'p2', role: ArtRole.porte, x: x + w / 2 + 1.5, y: y + 2, z: -t, w: w / 2 - 3.5, h: h - 4, d: t, hinge: 'right'),
    ]);
    final m = computeMachiningElements(art.panels);
    // 4 jonctions (dessus et dessous contre chaque côté), 560 de long : 2 tourillons et 2 vis chacune
    expect(n(m, MachiningKind.dowel), 8);
    expect(n(m, MachiningKind.screw), 8);
    expect(m.elements.where((e) => e.kind == MachiningKind.screw).every((e) => e.panelId == 'g' || e.panelId == 'dr'), isTrue,
        reason: 'les vis traversent les côtés et entrent dans le chant du dessus et du dessous');
    // fond encastré : rainure dans les 4 panneaux, pas de pointes
    expect(n(m, MachiningKind.groove), 4);
    expect(n(m, MachiningKind.nail), 0);
    expect(m.work['g']!.grooveLong, 1);
    // portes de 716 de haut : 2 charnières chacune, embases sur le côté correspondant
    expect(n(m, MachiningKind.hingeCup), 4);
    final plates = m.elements.where((e) => e.kind == MachiningKind.hingePlate).toList();
    expect(plates, hasLength(4));
    expect(plates.where((e) => e.panelId == 'g'), hasLength(2));
    expect(plates.where((e) => e.panelId == 'dr'), hasLength(2));
    // poignées : une par porte, côté opposé aux charnières, en haut (meuble bas)
    final handles = m.elements.where((e) => e.kind == MachiningKind.handle).toList();
    expect(handles, hasLength(2));
    final h1 = handles.firstWhere((e) => e.panelId == 'p1');
    expect(h1.position.x, greaterThan(250), reason: 'porte gauche, charnières à gauche : poignée à droite');
    expect(h1.end.y, greaterThan(y + h - 120));
    // pieds : dessous à 100 mm du sol, 600 de large → 4 pieds
    expect(n(m, MachiningKind.foot), 4);
    // chants : portes sur 4 côtés en 2 mm ; caisson en 1 mm sur l'avant seulement (pas au dos, pas contre un autre panneau)
    expect(m.work['p1']!.edgeLong + m.work['p1']!.edgeShort, 4);
    expect(m.work['p1']!.edgeThickness, 2);
    final bas = m.work['bas']!;
    expect(bas.edgeLong + bas.edgeShort, 1, reason: 'dessous : chant avant seulement, ses bouts sont contre les côtés');
    final g = m.work['g']!;
    expect(g.edgeLong + g.edgeShort, 3, reason: 'côté : avant, dessus et dessous visibles (pieds), dos sans chant');
    // quincaillerie à commander
    final hw = {for (final (name, _, q) in m.hardware) name: q};
    expect(hw['Charnière 110° en applique'], 4);
    expect(hw['Pied vérin réglable 100 à 150 mm'], 4);
    expect(hw['Clip de plinthe'], 2);
    expect(hw['Tourillons bois Ø8 x 35 mm'], 8);
    // le débit reprend les chants et les rainures
    final parts = art.cutParts();
    final side = parts.firstWhere((p) => p.length == 720 && p.width == 560);
    expect(side.qty, 2);
    expect(side.edgeLong + side.edgeShort, 3);
    expect(side.grooveLong, 1);
  });

  test('banc à coffre : coulisses pour chaque façade de tiroir, longueur selon la profondeur', () {
    final art = ArtProject();
    artStarters.firstWhere((s) => s.name == 'Banc à coffre').build(art);
    final m = computeMachiningElements(art.panels);
    final slides = m.elements.where((e) => e.kind == MachiningKind.slide).toList();
    expect(slides, hasLength(4), reason: '2 tiroirs, une paire de coulisses chacun');
    expect(slides.every((e) => e.length == 400), isTrue, reason: 'caisson de 450 de profondeur → coulisses de 400');
    final hw = {for (final (name, _, q) in m.hardware) name: q};
    expect(hw['Paire de coulisses à billes 400 mm'], 2);
    expect(n(m, MachiningKind.handle), 2);
  });

  test('tablette mobile entre deux montants : taquets et 7 perçages par rangée ; tablette fixe : tourillons', () {
    final art = ArtProject();
    art.free.addAll([
      ArtPanel(id: 'l', role: ArtRole.montant, x: 0, y: 0, w: 18, h: 1000, d: 350),
      ArtPanel(id: 'r', role: ArtRole.montant, x: 618, y: 0, w: 18, h: 1000, d: 350),
      ArtPanel(id: 'mobile', role: ArtRole.tablette, x: 19, y: 500, w: 598, h: 18, d: 330),
    ]);
    var m = computeMachiningElements(art.panels);
    expect(n(m, MachiningKind.shelfPin), 4);
    expect(n(m, MachiningKind.shelfHole), 4 * 7);
    expect(n(m, MachiningKind.dowel), 0);
    art.free.last
      ..x = 18
      ..w = 600;
    m = computeMachiningElements(art.panels);
    expect(n(m, MachiningKind.shelfPin), 0);
    expect(n(m, MachiningKind.dowel), 4);
  });

  test('fond appliqué au dos (non encastré) : cloué tous les 150 mm', () {
    final art = ArtProject();
    art.free.addAll([
      ArtPanel(id: 'l', role: ArtRole.montant, x: 0, y: 0, w: 18, h: 600, d: 300),
      ArtPanel(id: 'r', role: ArtRole.montant, x: 482, y: 0, w: 18, h: 600, d: 300),
      ArtPanel(id: 'f', role: ArtRole.fond, x: 0, y: 0, z: 300, w: 500, h: 600, d: 3),
    ]);
    final m = computeMachiningElements(art.panels);
    expect(n(m, MachiningKind.groove), 0);
    expect(n(m, MachiningKind.nail), 8, reason: '600 mm de haut sur chaque côté : 4 pointes par côté');
  });

  test('matière du tarif : latté débité sur feuilles 2440 x 1220, sans rotation ; contrôles avant débit', () {
    final art = ArtProject();
    art.free.addAll([
      ArtPanel(id: 'a', role: ArtRole.montant, x: 0, y: 0, w: 18, h: 2000, d: 560, material: 'latte_chene_bois_rouge'),
      ArtPanel(id: 'b', role: ArtRole.montant, x: 782, y: 0, w: 18, h: 2000, d: 560, material: 'latte_chene_bois_rouge'),
      ArtPanel(id: 'c', role: ArtRole.tablette, x: 18, y: 0, w: 764, h: 18, d: 560, material: 'mdf_blanc_18'),
    ]);
    final cs = CutSettings();
    final parts = art.cutParts();
    final latte = parts.firstWhere((p) => p.material.startsWith('Latté'));
    expect(latte.material, 'Latté chêne bois rouge 18 · 2440×1220');
    expect(latte.canRotate, isFalse, reason: 'latté : la pièce garde son sens');
    expect(cs.sheetDimensionsFor(latte.material), (2440, 1220));
    final plan = art.plan(cs);
    final sheet = plan.sheets.firstWhere((sh) => sh.material == latte.material);
    expect((sheet.length, sheet.width), (2440, 1220));
    for (final method in [1, 2, 3]) {
      cs.method = method;
      final pl = nest(art.cutParts(), cs);
      expect(pl.sheets.where((sh) => sh.material == latte.material).every((sh) => sh.length == 2440 && sh.width == 1220), isTrue,
          reason: 'méthode $method : format du latté');
    }
    expect(artChecks(art.panels, cs), isEmpty);

    // chevauchement, épaisseur différente de la matière, pièce plus grande que la feuille
    art.free.add(ArtPanel(id: 'd', role: ArtRole.tablette, x: 10, y: 500, w: 764, h: 19, d: 560, material: 'mdf_blanc_18'));
    art.free.add(ArtPanel(id: 'e', role: ArtRole.decor, x: 2000, y: 300, w: 2600, h: 1300, d: 18, material: 'latte_blanc_bois_rouge_cp'));
    final ck = artChecks(art.panels, cs);
    expect(ck.where((c) => c.error && c.panelIds.contains('d') && c.panelIds.contains('a')), isNotEmpty, reason: 'd chevauche le montant a');
    expect(ck.where((c) => c.error && c.message.contains('19 mm')), isNotEmpty, reason: '19 mm dans du MDF 18');
    expect(ck.where((c) => c.error && c.panelIds.contains('e') && c.message.contains('plus grand')), isNotEmpty);
    expect(ck.where((c) => !c.error && c.panelIds.contains('e')), isNotEmpty, reason: 'e ne touche rien');
  });

  test('accessoires : meuble haut suspendu, caissons joints, Minifix, porte à poussoir ; enregistrés', () {
    final art = ArtProject();
    // deux meubles hauts côte à côte, à 1400 mm du sol
    art.addBox(0, 1400, 600, 700, depth: 350, doors: 1);
    art.addBox(600, 1400, 600, 700, depth: 350, doors: 1);
    art.fittings
      ..joint = JointType.minifix
      ..hinge = HingeType.pushOpen;
    final m = computeMachiningElements(art.panels, fittings: art.fittings);
    final hangers = m.elements.where((e) => e.kind == MachiningKind.hanger).toList();
    expect(hangers, hasLength(4), reason: 'un boîtier par côté, 2 meubles hauts');
    final links = m.elements.where((e) => e.kind == MachiningKind.connector).toList();
    expect(links, hasLength(4), reason: 'côtés voisins face contre face : 4 vis de jonction aux coins');
    expect(m.elements.where((e) => e.kind == MachiningKind.screw).every((e) => e.item!.startsWith('Excentrique Minifix')), isTrue);
    expect(m.count(MachiningKind.handle), 0, reason: 'portes à poussoir : pas de poignée');
    expect(m.count(MachiningKind.latch), 2);
    final hw = {for (final (n, _, q) in m.hardware) n: q};
    expect(hw['Boîtier de suspension réglable (gauche / droite)'], 4);
    expect(hw['Rail de suspension (1 par meuble haut)'], 2);
    expect(hw['Vis de jonction avec manchon Ø5 x 30'], 4);
    expect(hw['Charnière sans ressort + poussoir'], 4);
    // une porte avec sa propre charnière
    final door = art.free.firstWhere((p) => p.role == ArtRole.porte);
    door.hingeType = HingeType.grandAngle.name;
    final m2 = computeMachiningElements(art.panels, fittings: art.fittings);
    expect(m2.elements.where((e) => e.kind == MachiningKind.hingeCup && e.item == HingeType.grandAngle.label), hasLength(2));
    expect(m2.count(MachiningKind.handle), 1, reason: 'cette porte a de nouveau une poignée');
    // enregistrement
    final back = ArtProject.fromJson(jsonDecode(jsonEncode(art.toJson())) as Map<String, dynamic>);
    expect(back.fittings.joint, JointType.minifix);
    expect(back.fittings.hinge, HingeType.pushOpen);
    expect(back.free.firstWhere((p) => p.id == door.id).hingeType, 'grandAngle');
  });

  test('assemblage de deux pièces : qui passe dessus, onglet 45°, orientation', () {
    final art = ArtProject();
    final side = ArtPanel(id: 's', role: ArtRole.montant, x: 0, y: 0, w: 18, h: 720, d: 560);
    final top = ArtPanel(id: 't', role: ArtRole.tablette, x: 18, y: 702, w: 582, h: 18, d: 560);
    art.free.addAll([side, top]);
    // au départ le dessus est entre les côtés (le côté présente sa face)
    expect(ArtProject.corner(side, top)!.$2, same(side));
    // le dessus passe par-dessus le côté : le côté perd 18 mm, le dessus en gagne 18 vers la gauche
    expect(art.putOver(top, side), isTrue);
    expect((side.h, top.x, top.w), (702, 0, 600));
    expect(computeMachiningElements(art.panels).elements.where((e) => e.kind == MachiningKind.screw).every((e) => e.panelId == 't'), isTrue,
        reason: 'les vis traversent maintenant le dessus');
    // et inversement
    expect(art.putOver(side, top), isTrue);
    expect((side.h, top.x, top.w), (720, 18, 582));
    // onglet : le dessus va jusqu'à l'angle extérieur ; pas de chevauchement signalé ; lamelles ; noté au débit
    expect(art.setJointCut(top, side, 'onglet'), isTrue);
    expect((top.x, top.w), (0, 600));
    expect(artChecks(art.panels, CutSettings(), jointCuts: art.jointCuts).where((c) => c.error), isEmpty);
    final m = computeMachiningElements(art.panels, jointCuts: art.jointCuts);
    expect(m.elements.where((e) => e.item == 'Lamelle bois n° 20'), isNotEmpty);
    expect(art.cutParts().where((p) => p.name.contains('onglet 45°')), hasLength(2));
    // retour au bout à bout
    art.setJointCut(top, side, null);
    expect((top.x, top.w), (18, 582));
    expect(art.jointCuts, isEmpty);
    // orientation d'une pièce coupée à plat
    final piece = ArtPanel(id: 'p', role: ArtRole.decor, x: 0, y: 0, w: 2092, h: 18, d: 600);
    ArtProject.orient(piece, 'montant');
    expect((piece.w, piece.h, piece.d), (18, 2092, 600));
    ArtProject.orient(piece, 'facade');
    expect((piece.w, piece.h, piece.d), (600, 2092, 18));
  });

  test('lier deux chants : la 1re pièce se place sous la 2e, perpendiculaire, à fleur du chant', () {
    final b = ArtPanel(id: 'b', role: ArtRole.decor, x: 0, y: 500, z: 0, w: 600, h: 18, d: 400);
    final a = ArtPanel(id: 'a', role: ArtRole.decor, x: 1000, y: 0, z: 0, w: 400, h: 18, d: 300);
    // chant 1 de a (le long de ses 400 mm) sous le chant 2 de b (bout droit)
    expect(ArtProject.linkEdges(a, 1, b, 2), isTrue);
    expect((a.x, a.y, a.z), (582, 200, 0));
    expect((a.w, a.h, a.d), (18, 300, 400));
    // b couvre le chant de a : b est l'hôte de l'assemblage (vis dans b, chant de a)
    final m = computeMachiningElements([a, b]);
    final screws = m.elements.where((e) => e.kind == MachiningKind.screw).toList();
    expect(screws, isNotEmpty);
    expect(screws.every((e) => e.panelId == 'b' && e.partnerPanelId == 'a'), isTrue);
    expect(ArtProject.linkEdges(a, 5, b, 1), isFalse);
  });
}
