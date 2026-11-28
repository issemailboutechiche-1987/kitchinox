// Calcul de l'éclairage selon les normes (docs/lighting/lighting_engineering_standards.json).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';

void main() {
  late Catalog cat;
  setUpAll(() => cat = Catalog.parse(File('assets/catalog.json').readAsStringSync()));

  test('méthode des lumens : exemples chiffrés du fichier de normes', () {
    // cuisine 12 m², 200 lux, UF 0,70, MF 0,80 → 4286 lm
    expect(lumensFor(200, 12, 0.70, 0.80), 4286);
    // chambre 16 m², 100 lux, UF 0,65, MF 0,85 → 2896 lm
    expect(lumensFor(100, 16, 0.65, 0.85), 2896);
    expect(heightFactor(2600), 1.0);
    expect(heightFactor(2800), 1.15);
    expect(heightFactor(3200), 1.30);
    expect(heightFactor(3800), 1.50);
    // ruban 24 V 14 W/m sur 3,5 m : 49 W → transformateur 60 W (marge 20 %)
    const s = LightStrip('kitchen_worktop', 'A', 3500, 1300, 14);
    expect(s.watts, closeTo(49, 0.01));
    expect(s.lumens, 4550);
    expect(s.driverW, 60);
    expect(s.feed, contains('un bout'));
  });

  test('cuisine : assez de lumière, spots au bord avant du plan, ruban sous les hauts', () {
    final p = Project(room: Room(width: 4000, depth: 3000, height: 2600));
    final e = LayoutEngine(cat, p);
    e.autoFillWall('A', Band.low);
    e.autoFillWall('A', Band.high);
    final plan = planLighting(e);
    final general = plan.zones.first;
    expect(general.zone.id, 'kitchen_general');
    expect(general.lumensNeeded, lumensFor(200, 12, 0.75, 0.80));
    expect(general.ok, isTrue, reason: '${general.lumensPlanned} lm prévus pour ${general.lumensNeeded}');
    final spots = plan.spots.where((s) => s.kind == 'spot').toList();
    expect(spots.length, greaterThanOrEqualTo(3));
    for (final s in spots) {
      expect(p.room.contains(s.x, s.y), isTrue);
    }
    // une ligne au bord avant du plan de travail du mur A (à 600 mm du mur)
    final wallA = p.room.wall('A');
    final dist = [for (final s in spots) ((s.x - wallA.x0) * wallA.nx + (s.y - wallA.y0) * wallA.ny)];
    expect(dist.where((d) => (d - 600).abs() < 1).length, greaterThanOrEqualTo(2));
    // ruban LED sous les meubles hauts, et l'éclairement du plan atteint
    final strip = plan.strips.where((s) => s.zone == 'kitchen_worktop').toList();
    expect(strip, isNotEmpty);
    expect(plan.zones.firstWhere((z) => z.zone.id == 'kitchen_worktop').ok, isTrue);
  });

  test('murs foncés et plafond haut : plus de lumière', () {
    final p = Project(room: Room(width: 4000, depth: 3000, height: 3200));
    final e = LayoutEngine(cat, p);
    final clair = planLighting(e, tone: 'clair').zones.first.lumensNeeded;
    final fonce = planLighting(e, tone: 'fonce').zones.first.lumensNeeded;
    expect(fonce, greaterThan(clair * 1.4));
    expect(clair, lumensFor(200, 12, 0.75, 0.80, hk: 1.30));
  });

  test('les réseaux posent les points lumineux calculés au plafond', () {
    final p = Project(room: Room(width: 4000, depth: 3000, height: 2600));
    final e = LayoutEngine(cat, p);
    e.autoFillWall('A', Band.low);
    // rien tant que les lumières ne sont pas posées (menu Lumière)
    expect(generateNetworks(e).where((x) => x.kind == NetKind.light && x.onCeiling), isEmpty);
    p.specs.lighting.placed = true;
    final pts = generateNetworks(e).where((x) => x.kind == NetKind.light && x.onCeiling).toList();
    expect(pts.length, planLighting(e).spots.length);
  });

  test('bouton Auto : luminaires adaptés à la pièce, jamais d’halogène, norme tenue', () {
    final p = Project(room: Room(width: 4000, depth: 3000, height: 2600));
    final e = LayoutEngine(cat, p);
    e.autoFillWall('A', Band.low);
    e.autoFillWall('A', Band.high);
    final ch = autoLighting(e);
    expect(ch.general, isNot(contains('halogene')));
    expect(ch.generalSource.cri, greaterThanOrEqualTo(90));
    expect(ch.generalSource.ugr ?? 0, lessThanOrEqualTo(19), reason: 'pas d’éblouissement au plan de travail');
    final plan = planLighting(e, choice: ch);
    expect(plan.zones.first.ok, isTrue);
    // à peu près un luminaire par 1,2 m² (spots espacés de 1000 à 1200 mm)
    expect(plan.spots.fold<int>(0, (t, s) => t + s.heads), inInclusiveRange(5, 16));
    // les textes du calcul se remplissent
    expect(plan.zones.first.setup.fill(), contains('×'));
  });

  test('projecteurs : un rail continu par linéaire meublé, au moins deux têtes', () {
    final p = Project(room: Room(width: 4000, depth: 3000, height: 2600));
    final e = LayoutEngine(cat, p);
    e.autoFillWall('A', Band.low);
    final plan = planLighting(e, choice: LightingChoice(general: 'rail_magnetique_48v'));
    final rails = plan.spots.where((s) => s.kind == 'magnetic').toList();
    // un rail par linéaire meublé (la cuisine de test est en L sur plusieurs murs), jamais le long d'un mur vide
    expect(rails.length, inInclusiveRange(1, 4));
    final run = e.runs('A', (m) => m.kind.isLow).first;
    final onA = rails.where((r) => (r.y - 700).abs() < 1).single; // à 700 mm du mur A
    expect(onA.length, closeTo(run.$2 - run.$1 - 600, 1));
    for (final r in rails) {
      expect(r.heads, greaterThanOrEqualTo(2));
    }
    expect(plan.zones.first.ok, isTrue);
  });

  test('pièce vide : pas de lumières posées tant que la cuisine n’est pas meublée', () {
    final st = AppState(cat, project: Project(room: Room(width: 4000, depth: 3000, height: 2600)));
    expect(st.placeLighting(), -1);
    expect(st.autoLightingForRoom(), -1);
    expect(st.project.points.where((x) => x.kind == NetKind.light), isEmpty);
    st.engine.autoFillWall('A', Band.low);
    expect(st.placeLighting(), greaterThan(0));
  });
}
