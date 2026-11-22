// Moteur du mode Art : recettes paramétriques posées sur une feuille, montage par le solveur (ordre libre),
// support (pieds + plinthe), usinage et contrôles — sur plusieurs meubles et plusieurs tailles.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/art.dart';
import 'package:kitchen_planner/engine/art_machining.dart';
import 'package:kitchen_planner/engine/art_recipes.dart';
import 'package:kitchen_planner/engine/art_relations.dart';
import 'package:kitchen_planner/engine/cutting.dart';

ArtProject sheetProject({double t = 18}) {
  final art = ArtProject();
  art.free.add(ArtPanel(id: art.newId(), role: ArtRole.decor, x: 0, y: 0, z: 0, w: 2792, h: t, d: 2062, finish: 'blanc'));
  return art;
}

/// Encombrement (x, y, z) de la structure (sans façades ni plinthe) et des façades.
(double, double, double) size(Iterable<ArtPanel> ps) => (
      ps.map((p) => p.right).reduce(math.max) - ps.map((p) => p.x).reduce(math.min),
      ps.map((p) => p.top).reduce(math.max) - ps.map((p) => p.y).reduce(math.min),
      ps.map((p) => p.back).reduce(math.max) - ps.map((p) => p.z).reduce(math.min),
    );

void main() {
  setUpAll(() => ArtRecipes.parse(File('assets/data/art_recipes.json').readAsStringSync()));

  test('formules : opérations, parenthèses, comparaisons, fonctions, erreurs claires', () {
    final v = {'L': 600.0, 'T': 18.0, 'pieds': 100.0};
    expect(evalFormula('L-2*T', v), 564);
    expect(evalFormula('(L-6)/2', v), 297);
    expect(evalFormula('pieds>20', v), 1);
    expect(evalFormula('min(L, 500) + max(1, 2)', v), 502);
    expect(evalFormula('arrondi(L/7, 5)', v), 85);
    expect(evalFormula('-T+1.5', v), -16.5);
    expect(() => evalFormula('L+X', v), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('« X »'))));
    expect(() => evalFormula('(L', v), throwsFormatException);
  });

  // chaque recette, à trois tailles : coupée sur la feuille, montée, contrôlée, usinée
  final sizes = <String, List<Map<String, double>>>{
    'bas_1p': [{'L': 600, 'H': 750, 'P': 600, 'pieds': 100}, {'L': 400, 'H': 720, 'P': 580, 'pieds': 150}, {'L': 900, 'H': 800, 'P': 650, 'pieds': 0}],
    'haut_2p': [{'L': 800, 'H': 720, 'P': 350}, {'L': 600, 'H': 400, 'P': 320}, {'L': 1000, 'H': 900, 'P': 400}],
    'colonne_2p': [{'L': 600, 'H': 2100, 'P': 580, 'Hb': 1300, 'pieds': 100}, {'L': 450, 'H': 1800, 'P': 560, 'Hb': 900, 'pieds': 120}],
    'etagere': [{'L': 800, 'H': 1000, 'P': 300}, {'L': 500, 'H': 2000, 'P': 250}],
    'simple_1p': [{'L': 600, 'H': 720, 'P': 560}, {'L': 450, 'H': 500, 'P': 400}],
  };
  for (final e in sizes.entries) {
    for (final params in e.value) {
      test('recette ${e.key} $params : coupe, montage, contrôles, usinage', () {
        final r = ArtRecipes.byId(e.key)!;
        final art = sheetProject();
        final sheet = art.free.single;
        final b = buildRecipe(r, params, 18);
        expect(recipeProblems(b, sheet), isEmpty);
        final cut = cutRecipe(art, sheet, b)!;
        expect(cut, hasLength(b.pieces.length));
        // sur la feuille : rien ne se chevauche, cotes exactes
        for (var i = 0; i < art.free.length; i++) {
          for (var j = i + 1; j < art.free.length; j++) {
            final p = art.free[i], q = art.free[j];
            expect(p.right <= q.x + 0.01 || q.right <= p.x + 0.01 || p.back <= q.z + 0.01 || q.back <= p.z + 0.01, isTrue, reason: '${p.note} / ${q.note}');
          }
        }
        for (var i = 0; i < cut.length; i++) {
          expect(cut[i].w, closeTo(b.pieces[i].lo, 0.01), reason: b.pieces[i].name);
          expect(cut[i].d, closeTo(b.pieces[i].la, 0.01), reason: b.pieces[i].name);
        }
        // montage : sans conflit, toutes les liaisons appliquées
        final solved = solveAssembly(art.free, art.edgeLinks, support: art.support);
        expect(solved.conflicts, isEmpty);
        expect(solved.unresolved, isEmpty);
        expect(art.applyEdgeLinks(), b.links.length);
        final parts = {for (final p in b.pieces) p.id: cut[b.pieces.indexOf(p)]};
        final structure = [for (final p in b.pieces) if (!p.role.isFront && p.role != ArtRole.plinthe) parts[p.id]!];
        final fronts = [for (final p in b.pieces) if (p.role.isFront) parts[p.id]!];
        final L = b.vars['L']!, H = b.vars['H']!;
        final (sx, sy, _) = size(structure);
        expect(sx, closeTo(L, 0.01), reason: 'largeur hors tout');
        expect(sy, closeTo(H, 0.01), reason: 'hauteur du caisson');
        // façades : devant la structure, dans sa largeur, jeux respectés
        final front = structure.map((p) => p.z).reduce(math.min);
        for (final f in fronts) {
          expect(f.role, ArtRole.porte);
          expect(f.back, closeTo(front, 0.01), reason: 'porte en applique devant');
          expect(f.x, greaterThanOrEqualTo(structure.map((p) => p.x).reduce(math.min) - 0.01));
          expect(f.right, lessThanOrEqualTo(structure.map((p) => p.right).reduce(math.max) + 0.01));
        }
        // pieds et plinthe
        final pieds = b.vars['pieds'] ?? 0;
        final bottom = parts['dessous']!;
        if (r.raw['support'] != null) expect(bottom.y, closeTo(pieds, 0.01), reason: 'dessous à la hauteur des pieds');
        final plinth = parts['plinthe'];
        if (plinth != null) {
          expect(plinth.role, ArtRole.plinthe);
          expect(plinth.y, 0);
          expect(plinth.top, closeTo(pieds - 3, 0.01));
          expect(plinth.z, closeTo(fronts.map((f) => f.z).reduce(math.min) + 50, 0.01), reason: 'retrait de 50 depuis la face des portes');
          expect(plinth.w, closeTo(L, 0.01));
        }
        // contrôles : aucun chevauchement ni pièce en l'air
        final checks = artChecks(art.panels, CutSettings(), jointCuts: art.jointCuts);
        expect(checks.where((c) => c.error), isEmpty, reason: checks.map((c) => c.message).join('\n'));
        // usinage : assemblages, charnières pour chaque porte, pieds si surélevé, rien de vissé dans les portes
        final m = computeMachiningElements(art.panels, fittings: art.fittings, jointCuts: art.jointCuts, jointFits: art.jointFits);
        expect(m.screwsCount, greaterThan(0));
        expect(m.dowelsCount, greaterThan(0));
        expect(m.hingeCupsCount, fronts.fold<int>(0, (a, f) => a + hingeCount(f.h)), reason: 'charnières selon la hauteur des portes');
        expect(m.count(MachiningKind.foot), pieds >= 50 ? 4 : 0);
        for (final f in fronts) {
          expect(m.elements.where((x) => x.panelId == f.id && (x.kind == MachiningKind.dowel || x.kind == MachiningKind.screw)), isEmpty);
        }
      });
    }
  }

  test('caisson bas 600 × 750 × 600 : pièces, découpe sur une feuille, quincaillerie', () {
    final art = sheetProject();
    final b = buildRecipe(ArtRecipes.byId('bas_1p')!, {'L': 600, 'H': 750, 'P': 600, 'pieds': 100}, 18);
    final dims = {for (final p in b.pieces) p.id: '${p.lo.round()}x${p.la.round()}'};
    expect(dims, {
      'dessous': '564x580', 'coteG': '750x580', 'coteD': '750x580', 'traverseAv': '564x100', 'traverseAr': '564x100',
      'fond': '714x564', 'porte': '747x597', 'plinthe': '600x97',
    });
    cutRecipe(art, art.free.single, b)!;
    expect(art.free.where((p) => p.note != 'Chute'), hasLength(8), reason: 'une seule feuille suffit');
    art.applyEdgeLinks();
    final m = computeMachiningElements(art.panels, fittings: art.fittings, jointCuts: art.jointCuts, jointFits: art.jointFits);
    expect(m.hingeCupsCount, 2);
    expect(m.count(MachiningKind.foot), 4);
    final hw = machiningHardware(m.elements, fittings: art.fittings).map((h) => h.$1).toList();
    expect(hw.any((n) => n.toLowerCase().contains('clip')), isTrue, reason: 'clips de plinthe');
  });

  test('colonne de 2100 : une deuxième feuille est posée et coupée', () {
    final art = sheetProject();
    final b = buildRecipe(ArtRecipes.byId('colonne_2p')!, {}, 18);
    cutRecipe(art, art.free.first, b)!;
    final sheets = art.free.map((p) => p.x > 2792 ? 2 : 1).toSet();
    expect(sheets, {1, 2});
  });

  test('solveur : ordre des liaisons sans importance', () {
    final r = ArtRecipes.byId('bas_1p')!;
    final a1 = sheetProject(), a2 = sheetProject();
    cutRecipe(a1, a1.free.single, buildRecipe(r, {}, 18))!;
    cutRecipe(a2, a2.free.single, buildRecipe(r, {}, 18))!;
    a2.edgeLinks.setAll(0, a2.edgeLinks.reversed.toList());
    final s1 = solveAssembly(a1.free, a1.edgeLinks, support: a1.support).panels;
    final s2 = solveAssembly(a2.free, a2.edgeLinks, support: a2.support).panels;
    for (var i = 0; i < s1.length; i++) {
      expect((s2[i].x, s2[i].y, s2[i].z, s2[i].w, s2[i].h, s2[i].d), (s1[i].x, s1[i].y, s1[i].z, s1[i].w, s1[i].h, s1[i].d), reason: s1[i].note);
    }
  });

  test('solveur : deux liaisons qui ne concordent pas → conflit ; référence jamais placée → non résolue', () {
    final art = sheetProject();
    final b = buildRecipe(ArtRecipes.byId('haut_2p')!, {}, 18);
    final cut = cutRecipe(art, art.free.single, b)!;
    final dessus = cut[b.pieces.indexWhere((p) => p.id == 'dessus')], coteD = cut[b.pieces.indexWhere((p) => p.id == 'coteD')];
    // le dessus, déjà posé entre les côtés en haut, est aussi « posé » en bas du côté droit
    art.edgeLinks.add(EdgeLink(dessus.id, ArtProject.edgeWithNormal(dessus, 0, -1), coteD.id, 0, bSide: 'bas', over: false));
    final s = solveAssembly(art.free, art.edgeLinks);
    expect(s.conflicts, hasLength(1));
    expect(s.conflicts.single, contains('ne concordent pas'));
    // boucle sans pièce de référence
    final p = art.free.where((x) => x.note == 'Chute').take(2).toList();
    final loop = [EdgeLink(p[0].id, 1, p[1].id, 2), EdgeLink(p[1].id, 1, p[0].id, 2)];
    expect(solveAssembly(art.free, loop).unresolved, hasLength(2));
  });

  test('sauvegarde : liaisons typées et support relus à l’identique ; anciens fichiers (outside) compris', () {
    final art = sheetProject();
    cutRecipe(art, art.free.single, buildRecipe(ArtRecipes.byId('bas_1p')!, {}, 18))!;
    final back = ArtProject.fromJson(art.toJson());
    expect(back.edgeLinks.map((l) => (l.kind, l.bSide, l.align, l.over)).toList(), art.edgeLinks.map((l) => (l.kind, l.bSide, l.align, l.over)).toList());
    expect((back.support!.anchor, back.support!.height, back.support!.plinth), (art.support!.anchor, 100, art.support!.plinth));
    expect(EdgeLink.fromJson({'a': 'x', 'ea': 1, 'b': 'y', 'eb': 2, 'outside': true}).kind, 'articule');
  });
}
