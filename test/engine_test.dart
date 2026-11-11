import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

void main() {
  late Catalog catalog;
  late Project project;
  late LayoutEngine e;

  setUpAll(() => catalog = Catalog.parse(File('assets/catalog.json').readAsStringSync()));
  setUp(() {
    project = Project(room: Room(width: 3600, depth: 3000, height: 2600));
    e = LayoutEngine(catalog, project);
  });

  group('catalogue', () {
    test('44 modèles, 6 catégories', () {
      expect(catalog.categories.length, 6);
      expect(catalog.models.length, 44);
    });

    test('normes appliquées aux bas : 750 au lieu de 800', () {
      expect(catalog['base_standard_single_door'].heights.values, [750]);
      expect(catalog['base_standard_single_door'].catalogHeights, [800]);
      expect(catalog['corner_base_l_shaped'].heights.values, [750]);
      expect(const KitchenStandards().worktopTop, 900);
      expect(const KitchenStandards().wallBottomMin, 1350);
    });

    test('toutes les formes de dimensions sont normalisées', () {
      expect(catalog['base_sink'].widths.values, [600, 800, 1000]);
      expect(catalog['corner_base_blind'].widths.values, [1200]);
      expect(catalog['corner_base_blind'].shape, CabinetShape.blind);
      expect(catalog['corner_base_l_shaped'].shape, CabinetShape.lShape);
      expect(catalog['corner_base_l_shaped'].widthRight, 900);
      expect(catalog['corner_base_diagonal'].shape, CabinetShape.diagonal);
      expect(catalog['corner_base_diagonal'].widths.values, [1050]);
      expect(catalog['corner_wall_diagonal'].widthRight, 680);
      expect(catalog['filler_panel_base'].widths.isRange, isTrue);
      expect(catalog['filler_panel_base'].widths.nearest(30), 50);
      expect(catalog['wall_standard_single_door'].heights.values, [400, 600, 750, 800, 1000]);
      expect(catalog['corner_wall_l_shaped'].heights.values, [600, 750, 800, 1000]);
      expect(catalog['tall_pantry'].defaultHeight, 2200);
      expect(catalog['wall_open_shelf'].hasDoors, isFalse);
      expect(catalog['base_integrated_dishwasher_door'].isCarcass, isFalse);
      expect(catalog['base_integrated_dishwasher_door'].requiresAppliance, 'integrated_dishwasher');
      expect(catalog['base_drawers_multi'].variants, contains('4_drawers'));
    });

    test('chaque modèle a une largeur, une hauteur et une profondeur', () {
      for (final m in catalog.models) {
        expect(m.defaultWidth, greaterThan(0), reason: m.id);
        expect(m.defaultHeight, greaterThan(0), reason: m.id);
        expect(m.depth, greaterThan(0), reason: m.id);
      }
    });
  });

  group('pose', () {
    test('hauteurs de pose par type', () {
      final b = e.add('base_standard_single_door', 'A');
      final h = e.add('wall_standard_single_door', 'A');
      final t = e.add('tall_pantry', 'A', s: 3000);
      expect(b.z, 100);
      expect(b.top, 850);
      expect(h.z, 1500); // crédence de 60 cm
      expect(t.z, 100);
      expect(t.top, 2300);
    });

    test('un bas et un haut au même endroit ne se gênent pas', () {
      final b = e.add('base_standard_single_door', 'A', s: 500);
      final h = e.add('wall_standard_single_door', 'A', s: 500);
      expect(b.s, 500);
      expect(h.s, 500);
      expect(e.validate().where((i) => i.code == 'overlap'), isEmpty);
    });

    test('aimantation sur le voisin à moins de 50 mm', () {
      e.add('base_standard_single_door', 'A', s: 0, width: 600);
      final b = e.add('base_standard_single_door', 'A', s: 630, width: 600);
      expect(b.s, 600);
    });

    test('pas d\'aimantation au-delà de 50 mm', () {
      e.add('base_standard_single_door', 'A', s: 0, width: 600);
      final b = e.add('base_standard_single_door', 'A', s: 700, width: 600);
      expect(b.s, 700);
    });

    test('collision : le caisson est poussé à la place libre la plus proche', () {
      e.add('base_standard_single_door', 'A', s: 1000, width: 600);
      final b = e.add('base_standard_single_door', 'A', s: 1200, width: 600);
      expect(b.s, 1600);
      final c = e.add('base_standard_single_door', 'A', s: 1050, width: 600);
      expect(c.s, 400);
    });

    test('mur plein : exception', () {
      for (var i = 0; i < 6; i++) {
        e.add('base_standard_single_door', 'A', s: i * 600.0, width: 600);
      }
      expect(() => e.add('base_standard_single_door', 'A', width: 300), throwsA(isA<PlacementException>()));
    });

    test('largeur hors catalogue ramenée à la plus proche', () {
      final b = e.add('base_standard_double_door', 'A', width: 900);
      expect([800, 1000], contains(b.width));
    });

    test('mur désactivé', () {
      project.room.setWallEnabled('D', false);
      expect(() => e.add('base_standard_single_door', 'D'), throwsA(isA<PlacementException>()));
    });
  });

  group('angles', () {
    test('angle en L : collé au coin, un bras sur chaque mur', () {
      final c = e.add('corner_base_l_shaped', 'A');
      expect(c.s, 3600 - 900);
      final boxes = e.boxesOf(c);
      expect(boxes.map((b) => b.wallId), ['A', 'B']);
      // bras sur le mur droit : x de 3000 à 3600, y de 0 à 900
      expect(boxes[1].box.x0, 3000);
      expect(boxes[1].box.x1, 3600);
      expect(boxes[1].box.y1, 900);
    });

    test('après un angle, le mur suivant commence après le bras', () {
      e.add('corner_base_l_shaped', 'A');
      final b = e.add('base_standard_single_door', 'B', s: 0, width: 600);
      expect(b.s, 900);
    });

    test('les caissons d\'un mur bloquent le coin du mur voisin', () {
      // caisson au bout du mur du fond, contre le mur droit
      e.add('base_standard_single_door', 'A', s: 3000, width: 600);
      final b = e.add('base_standard_single_door', 'B', s: 0, width: 600);
      expect(b.s, 600); // la profondeur (600) du caisson du mur A est occupée
    });

    test('angle avec fileur : calé à une extrémité', () {
      final c = e.add('corner_base_blind', 'A', s: 2000);
      expect(c.s, 3600 - 1200);
      final d = e.add('corner_base_blind', 'C', s: 100);
      expect(d.s, 0);
    });

    test('pan coupé : contour à 5 points', () {
      final c = e.add('corner_base_diagonal', 'A');
      expect(e.planShape(c).points.length, 5);
      final l = e.add('corner_wall_l_shaped', 'B');
      expect(e.planShape(l).points.length, 6);
    });
  });

  group('déplacement', () {
    test('glisser le long du mur avec aimantation', () {
      e.add('base_standard_single_door', 'A', s: 0, width: 600);
      final b = e.add('base_standard_single_door', 'A', s: 2000, width: 600);
      final r = e.move(b.uid, s: 640);
      expect(r.moved, isTrue);
      expect(r.snapped, isTrue);
      expect(b.s, 600);
    });

    test('changer de mur', () {
      final b = e.add('base_standard_single_door', 'A', s: 1000);
      e.move(b.uid, wallId: 'C', s: 1000);
      expect(b.wallId, 'C');
      expect(e.planShape(b).points.first.$1, 0); // contre le mur gauche (x = 0)
    });

    test('un bas ne monte pas, un haut s\'aligne sur la colonne', () {
      final t = e.add('tall_pantry', 'A', s: 0, height: 2200); // dessus à 2300
      final b = e.add('base_standard_single_door', 'A', s: 600);
      e.move(b.uid, z: 1200);
      expect(b.z, 100);
      final h = e.add('wall_standard_single_door', 'A', s: 600, height: 800);
      e.move(h.uid, z: 1480);
      expect(h.top, t.top); // 1500 + 800 = 2300
    });

    test('déplacement impossible : rien ne bouge', () {
      e.add('base_standard_single_door', 'A', s: 0, width: 600);
      final b = e.add('base_standard_single_door', 'B', s: 0, width: 600);
      final before = b.s;
      // mur gauche : 3000 mm dont les 600 du coin déjà pris par le caisson du mur du fond
      for (var i = 0; i < 4; i++) {
        e.add('base_standard_single_door', 'C', s: i * 600.0, width: 600);
      }
      final r = e.move(b.uid, wallId: 'C', s: 0);
      expect(r.moved, isFalse);
      expect(b.wallId, 'B');
      expect(b.s, before);
    });
  });

  group('contrôles', () {
    test('vide entre deux caissons : fileur proposé puis posé', () {
      e.add('base_standard_single_door', 'A', s: 0, width: 600);
      e.add('base_standard_single_door', 'A', s: 750, width: 600);
      final g = e.gaps().where((g) => g.fillable).single;
      expect(g.width, 150);
      final f = e.fillGap(g);
      expect(f.s, 600);
      expect(f.width, 150);
      expect(e.gaps().where((g) => g.fillable), isEmpty);
    });

    test('haut trop bas signalé', () {
      final h = e.add('wall_standard_single_door', 'A', z: 1200);
      expect(e.validate().any((i) => i.code == 'wall_too_low' && i.uids.contains(h.uid)), isTrue);
    });

    test('dépassement du plafond signalé', () {
      project.room.height = 2200;
      e.add('tall_pantry', 'A', height: 2400);
      expect(e.validate().any((i) => i.code == 'ceiling'), isTrue);
    });

    test('lave-vaisselle et ventilation signalés en info', () {
      e.add('base_integrated_dishwasher_door', 'A');
      e.add('tall_integrated_fridge', 'A', s: 2000);
      final codes = e.validate().map((i) => i.code).toSet();
      expect(codes, containsAll(['appliance', 'ventilation']));
    });

    test('cuisine en L complète : aucune erreur', () {
      e.add('tall_integrated_fridge', 'C', s: 0, height: 2200);
      e.add('corner_base_l_shaped', 'C');
      e.add('base_drawers_multi', 'A', s: 900, width: 600);
      e.add('base_sink', 'A', s: 1500, width: 1000);
      e.add('base_integrated_dishwasher_door', 'A', s: 2500, width: 600);
      e.add('base_standard_single_door', 'A', s: 3100, width: 500);
      e.add('wall_standard_double_door', 'A', s: 1500, width: 1000);
      final errors = e.validate().where((i) => i.severity == Severity.error && !i.code.startsWith('zone_')).toList();
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  });

  group('vues et sauvegarde', () {
    test('vue de face : caissons du mur + profils des voisins au coin', () {
      e.add('base_standard_single_door', 'A', s: 600, width: 600);
      e.add('base_standard_single_door', 'C', s: 2400, width: 600); // au fond du mur gauche, dans le coin
      final el = e.elevation('A');
      expect(el.where((r) => r.onThisWall).length, 1);
      final side = el.where((r) => !r.onThisWall).single;
      expect(side.s0, 0);
      expect(side.s1, 600); // profondeur du caisson voisin
    });

    test('vue de dessus : un polygone par caisson', () {
      e.add('base_standard_single_door', 'A');
      e.add('wall_standard_single_door', 'A');
      expect(e.planView().length, 2);
    });

    test('projet JSON aller-retour', () {
      e.add('corner_base_l_shaped', 'A');
      e.add('wall_lift_up', 'B', s: 1200);
      final text = jsonEncode(project.toJson());
      final p2 = Project.fromJson(jsonDecode(text) as Map<String, dynamic>);
      expect(jsonEncode(p2.toJson()), text);
      final e2 = LayoutEngine(catalog, p2);
      expect(e2.add('base_standard_single_door', 'C').uid, isNot(anyOf('c1', 'c2')));
    });
  });

  group('ouvertures, formes, remplissage, récapitulatif', () {
    test('une porte bloque les caissons', () {
      e.addOpening('door', 'A', s: 1000); // 585..1415
      final b = e.add('base_standard_single_door', 'A', s: 900, width: 600);
      expect(b.s + b.width <= 585 || b.s >= 1415, isTrue);
      expect(e.validate().where((i) => i.code == 'opening_blocked'), isEmpty);
    });

    test('sous une fenêtre : bas autorisé, haut refusé', () {
      e.addOpening('window', 'A', s: 1800); // 1300..2300, allège 1050
      final b = e.add('base_standard_single_door', 'A', s: 1500, width: 600);
      expect(b.s, 1500);
      final h = e.add('wall_standard_single_door', 'A', s: 1500, width: 600);
      expect(h.s + h.width <= 1300 || h.s >= 2300, isTrue);
    });

    test('forme en U', () {
      e.applyShape(RoomShape.uShape);
      expect(project.shape, RoomShape.uShape);
      expect(project.room.isWallEnabled('D'), isFalse);
    });

    test('meilleure combinaison de modules', () {
      expect(LayoutEngine.bestModules(1500, [300, 400, 500, 600]).fold<int>(0, (a, b) => a + b), 1500);
      expect(LayoutEngine.bestModules(1500, [300, 400, 500, 600]).length, 3);
      expect(LayoutEngine.bestModules(250, [300, 400]), isEmpty);
    });

    test('remplissage automatique d\'un mur autour d\'une porte', () {
      e.addOpening('door', 'A', s: 1800); // 1385..2215
      final n = e.autoFillWall('A', Band.low);
      expect(n, greaterThan(0));
      final errors = e.validate().where((i) => i.severity == Severity.error && !i.code.startsWith('zone_'));
      expect(errors, isEmpty, reason: errors.join('\n'));
      // les deux côtés de la porte sont remplis à moins de 50 mm près
      final free = e.freeIntervals('A', Band.low).where((f) => f.$2 - f.$1 >= 50 && f.$1 != 1385);
      expect(free, isEmpty, reason: '$free');
    });

    test('récapitulatif : plan de travail compté une fois dans l\'angle', () {
      e.applyShape(RoomShape.lShape);
      e.add('corner_base_l_shaped', 'A'); // A 2700..3600, B 0..900
      e.add('base_standard_single_door', 'A', s: 2100, width: 600);
      e.add('base_standard_single_door', 'B', s: 900, width: 600);
      final bom = buildBom(e);
      // A : 2100..3600 = 1500 ; B : 0..1500 - 620 = 880
      expect(bom.worktopLength, 1500 + 880);
      expect(bom.cabinetCount, 3);
      expect(bom.lines.where((l) => l.ref == 'base_standard_single_door').single.qty, 2);
      expect(bom.toCsv(), contains('Plan de travail'));
      // extrémités libres : A à 2100 et B à 1500
      expect(bom.lines.where((l) => l.section == 'Finitions').fold<int>(0, (s, l) => s + l.qty), 2);
    });
  });

  group('règles d\'implantation et mode position', () {
    Set<String> codes() => e.validate().map((i) => i.code).toSet();

    test('hotte trop basse au-dessus de la plaque', () {
      e.add('base_cooktop_oven', 'A', s: 1200, width: 600);
      e.add('wall_integrated_hood', 'A', s: 1200, width: 600, z: 1450, height: 600); // 550 au-dessus du plan
      expect(codes(), contains('hood_low'));
      final h = project.items.last;
      e.move(h.uid, z: 1560); // 660
      expect(codes(), isNot(contains('hood_low')));
    });

    test('plaque sans hotte, sous une fenêtre, trop près d\'une colonne', () {
      e.addOpening('window', 'A', s: 1500, width: 1000); // 1000..2000
      e.add('tall_pantry', 'A', s: 0);
      e.add('base_cooktop_oven', 'A', s: 600, width: 600); // colonne de 400 : 200 mm, sous la fenêtre (1000..1200)
      final c = codes();
      expect(c, containsAll(['hob_no_hood', 'hob_window', 'hob_near_tall']));
    });

    test('passage trop étroit entre deux linéaires', () {
      project.room.depth = 2000;
      e.applyShape(RoomShape.parallel);
      e.add('base_standard_single_door', 'A', s: 1000, width: 600);
      e.add('base_standard_single_door', 'D', s: 2000, width: 600); // face à face : 2000 - 600 - 600 = 800
      expect(codes(), contains('aisle'));
    });

    test('fileur conseillé dans l\'angle', () {
      e.applyShape(RoomShape.lShape);
      e.add('base_standard_single_door', 'A', s: 3000, width: 600); // contre le mur B
      e.add('base_drawers_multi', 'B', s: 600, width: 600); // arrive contre le coin
      expect(codes(), contains('corner_filler'));
    });

    test('écarts aux voisins modifiables', () {
      e.add('base_standard_single_door', 'A', s: 0, width: 600);
      final b = e.add('base_standard_single_door', 'A', s: 1000, width: 600);
      e.add('base_standard_single_door', 'A', s: 2500, width: 600);
      expect(e.neighbourGaps(b.uid), (400.0, 900.0));
      e.setNeighbourGap(b.uid, 150);
      expect(b.s, 750);
      e.setNeighbourGap(b.uid, 0, fromRight: true);
      expect(b.right, 2500);
    });
  });

  group('déplacement des murs', () {
    test('mur droit : la pièce s\'élargit, les éléments restent en place', () {
      final a = e.add('base_standard_single_door', 'A', s: 1000, width: 600);
      final b = e.add('base_standard_single_door', 'B', s: 1000, width: 600);
      final d = e.add('base_standard_single_door', 'D', s: 500, width: 600);
      final ax = e.boxesOf(a).first.box.x0, dx = e.boxesOf(d).first.box.x0;
      e.moveWall('B', 500);
      expect(project.room.width, 4100);
      expect(e.boxesOf(a).first.box.x0, ax); // mur du fond : même position
      expect(e.boxesOf(b).first.box.x1, 4100); // suit le mur droit
      expect(e.boxesOf(d).first.box.x0, dx); // mur avant : même position réelle
    });

    test('mur du fond vers l\'extérieur : les éléments du mur droit gardent leur place', () {
      final b = e.add('base_standard_single_door', 'B', s: 1000, width: 600);
      final yFromFront = project.room.depth - e.boxesOf(b).first.box.y0;
      e.moveWall('A', 400);
      expect(project.room.depth, 3400);
      expect(project.room.depth - e.boxesOf(b).first.box.y0, yFromFront);
    });

    test('refus si un élément sortirait du mur', () {
      e.add('base_standard_single_door', 'A', s: 3000, width: 600); // touche le mur droit
      expect(() => e.moveWall('B', -200), throwsA(isA<PlacementException>()));
      expect(project.room.width, 3600); // rien n'a bougé
    });

    test('refus sous la taille minimale', () {
      expect(() => e.moveWall('D', -2000), throwsA(isA<PlacementException>()));
    });
  });

  group('zones, triangle et débit', () {
    test('largeur par défaut : 600 quand elle existe', () {
      expect(catalog['base_standard_single_door'].defaultWidth, 600);
      expect(catalog['base_standard_double_door'].defaultWidth, 800);
    });

    test('zones manquantes signalées', () {
      e.add('base_standard_single_door', 'A', s: 0);
      e.add('base_standard_single_door', 'A', s: 600);
      e.add('base_standard_single_door', 'A', s: 1200);
      final codes = e.validate().map((i) => i.code).toSet();
      expect(codes, containsAll(['zone_wash', 'zone_cook', 'zone_cool']));
    });

    test('triangle d\'activité calculé et contrôlé', () {
      e.applyShape(RoomShape.lShape);
      e.add('tall_integrated_fridge', 'A', s: 0);
      e.add('base_sink', 'A', s: 1400, width: 800);
      e.add('base_cooktop_oven', 'B', s: 1500, width: 600);
      final legs = e.triangleLegs()!;
      expect(legs.$1, greaterThan(0));
      final codes = e.validate().map((i) => i.code).toSet();
      expect(codes.intersection({'triangle_ok', 'triangle_short', 'triangle_long', 'triangle_perimeter'}), isNotEmpty);
      expect(e.layoutShape(), 'en L');
    });

    test('formes reconnues', () {
      e.add('base_standard_single_door', 'A', s: 0);
      expect(e.layoutShape(), 'linéaire');
      e.add('base_standard_single_door', 'D', s: 1000);
      expect(e.layoutShape(), 'parallèle');
    });

    test('débit d\'un bas 600 : profondeur moins 18 mm de porte', () {
      final c = e.add('base_standard_single_door', 'A', s: 0, width: 600);
      final parts = cutList(e, CutSettings(), {c.uid: 1});
      CutPart part(String n) => parts.firstWhere((p) => p.name == n);
      expect(part('Côté').qty, 2);
      expect((part('Côté').length, part('Côté').width), (750, 582));
      final top = part('Dessus / dessous');
      expect(top.qty, 2);
      expect((top.length, top.width), (582, 564));
      expect(top.edgeText, '1 x 564'); // chant sur la face avant visible
      expect(part('Côté').edgeText, '1 x 750');
      expect(parts.any((p) => p.name == 'Traverse' || p.name == 'Étagère'), isFalse);
      expect((part('Porte').length, part('Porte').width), (746, 596));
      expect(part('Porte').material, 'MDF');
      expect(part('Côté').material, 'MDF');
    });

    test('optimisation : toutes les pièces placées, sans chevauchement, dans le panneau', () {
      for (var i = 0; i < 6; i++) {
        e.add('base_drawers_multi', 'A', s: i * 600.0, width: 600);
      }
      final cs = CutSettings();
      final plan = nest(cutList(e, cs, {}), cs);
      expect(plan.notPlaced, isEmpty);
      expect(plan.sheets.expand((s) => s.placements).length, plan.partCount);
      for (final s in plan.sheets) {
        for (final a in s.placements) {
          expect(a.x >= cs.trim && a.y >= cs.trim, isTrue);
          expect(a.x + a.dx <= s.length - cs.trim + 0.01 && a.y + a.dy <= s.width - cs.trim + 0.01, isTrue);
          for (final b in s.placements) {
            if (identical(a, b)) continue;
            final overlap = a.x < b.x + b.dx && b.x < a.x + a.dx && a.y < b.y + b.dy && b.y < a.y + a.dy;
            expect(overlap, isFalse);
          }
        }
      }
    });

    test('export .sct au format SketchCut', () {
      e.add('base_standard_single_door', 'A', s: 0, width: 600);
      final cs = CutSettings();
      final plan = nest(cutList(e, cs, {}), cs);
      final sct = toSct(plan, cs.carcassMaterial, order: 'test', date: DateTime(2026, 11, 5));
      final lines = sct.split('\r\n');
      expect(lines[0], '<V3.0>');
      expect(lines[2], '2800X2100_0');
      expect(lines[3], '1X4X4_True');
      expect(sct, contains('<Parts>'));
      expect(sct, contains('750X582X2'));
      expect(sct.trimRight().split('\r\n').last, '${cs.backThickness + 1}'); // largeur de rainure : épaisseur du fond + 1 mm
    });
  });
}
