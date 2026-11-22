// Mode Art : caisson paramétrique universel (enveloppe, colonnes, tablettes, façades par zone, ajouts),
// débit et quincaillerie déduits ; atelier à onglets.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/art_page.dart';
import 'package:kitchen_planner/ui/theme.dart';

int qty(List<CutPart> parts, String name) => parts.where((p) => p.name == name).fold(0, (a, p) => a + p.qty);

void main() {
  test('caisson bas 600 : côtés pleine hauteur, dessous et 2 traverses entre les côtés, fond rainuré', () {
    final b = artPresets.first.build();
    final parts = b.cutParts();
    final side = parts.firstWhere((p) => p.name == 'Côté');
    expect((side.length, side.width, side.qty), (720, 560, 2));
    final bottom = parts.firstWhere((p) => p.name == 'Dessous');
    expect((bottom.length, bottom.width), (564, 560)); // 600 - 2 x 18
    expect(qty(parts, 'Traverse avant') + qty(parts, 'Traverse arrière'), 2);
    // fond rainuré : intérieur + 2 x 9 mm de rainure, en HDF 6
    final back = parts.firstWhere((p) => p.name.startsWith('Fond'));
    expect((back.length, back.width), (702, 582));
    expect(back.material, startsWith('HDF 6'));
    // porte : recouvrement total moins 2 mm de jeu, une seule (600 de large)
    final door = parts.firstWhere((p) => p.name == 'Porte');
    expect((door.length, door.width, door.qty), (719, 598, 1)); // jeu en haut seulement : la porte du bas affleure le dessous
    // tablette mobile : 2 mm de jeu, 20 mm en retrait de l'avant
    final shelf = parts.firstWhere((p) => p.name == 'Étagère mobile');
    expect((shelf.length, shelf.width), (562, 518)); // largeur 564 - 2 ; profondeur utile 560 - 16 - 6, moins 20
    final hw = {for (final (n, _, q) in b.hardware()) n: q};
    expect(hw['Charnière 110° frein intégré Ø35 + embase'], 2);
    expect(hw['Taquets d’étagère Ø5 mm'], 4);
    expect(hw.keys.any((k) => k.startsWith('Pied réglable')), isTrue);
    expect(hw.keys.any((k) => k.startsWith('Fraisage rainure')), isTrue);
  });

  test('colonnes et tablettes fixes : zones de façade ; tablette mobile ne coupe pas la zone', () {
    final b = ArtBox(w: 1000, h: 2000, d: 580, seps: [491], shelves: {
      0: [ArtShelf(1500, fixed: true), ArtShelf(800)],
      1: [ArtShelf(600, fixed: true)],
    });
    final zs = b.zones;
    expect(zs.map((z) => z.id), ['c0z0', 'c0z1', 'c1z0', 'c1z1']);
    final low = zs.first;
    expect(low.fx0, 0);
    expect(low.fx1, 491 + 9); // demi-séparation
    expect(low.fy1, b.innerBottom + 1500 + 9);
    // tiroirs : une façade par tiroir, coulisses à la profondeur utile
    b.covers['c1z0'] = ArtCover(type: CoverType.drawers, count: 3);
    final parts = b.cutParts();
    expect(qty(parts, 'Façade de tiroir'), 3);
    expect(qty(parts, 'Séparation'), 1);
    expect(qty(parts, 'Étagère fixe'), 2);
    expect(b.slideLength, 500); // profondeur utile 558 : 550 ne laisse pas 10 mm
    expect(qty(parts, 'Fond de tiroir'), 3);
  });

  test('structure commune : chaque base est faite des mêmes composants', () {
    for (final pr in artPresets) {
      var k = 0;
      final comps = {for (final p in pr.build().panels(() => 'p${k++}')) p.comp};
      expect(comps, containsAll([Comp.cote, Comp.dessous, Comp.fond]), reason: pr.name);
      expect(comps.contains(Comp.dessus) || comps.contains(Comp.traverse), isTrue, reason: pr.name);
    }
    // caissons de tiroir : visibles en 3D, débités une seule fois
    final b = artPresets[1].build();
    var k = 0;
    expect(b.panels(() => 'p${k++}').where((p) => p.comp == Comp.tiroir).length, 3 * 5);
    expect(b.cutParts().where((p) => p.name == 'Caisson de tiroir'), isEmpty);
  });

  test('porte large : deux portes ; avertissements utiles', () {
    final b = ArtBox(w: 1200, h: 800, covers: {'c0z0': ArtCover(type: CoverType.door, hinge: 'double')});
    expect(qty(b.cutParts(), 'Porte'), 2);
    b.covers['c0z0']!.hinge = 'left';
    expect(b.warnings().any((w) => w.contains('deux portes')), isTrue);
    expect(b.warnings().any((w) => w.contains('fléchissent')), isTrue);
  });

  test('JSON « universal_parametric_box » : enveloppe, grille, zones, ajouts et quincaillerie lus', () {
    final j = jsonDecode(File('test/data/universal_box.json').readAsStringSync()) as Map<String, dynamic>;
    final b = ArtBox.fromUniversal(j);
    expect(b.back, BackType.groove);
    expect((b.backRecess, b.groove), (16, 9));
    expect(b.seps, [600]);
    expect(b.columns, 2);
    expect(b.shelvesOf(0).map((s) => (s.y, s.fixed)), [(400, true), (800, false)]);
    final zs = b.zones;
    expect(b.coverOf(zs[0]).type, CoverType.door);
    expect(b.coverOf(zs[1]).type, CoverType.drawers);
    expect(b.coverOf(zs[1]).count, 3);
    expect(b.coverOf(zs[2]).type, CoverType.open);
    expect(b.coverOf(zs[0]).accessories, contains('rod'));
    expect(b.coverOf(zs[1]).accessories, contains('spice'));
    expect(b.cheekRight, isTrue);
    expect(b.cheekLeft, isFalse);
    expect(b.fillerRight, 50);
    expect(b.handle, 'gola');
    expect(b.drawerBox, DrawerBox.metal);
    expect(b.base, BaseType.legs);
    final hw = [for (final (n, _, _) in b.hardware()) n];
    expect(hw.any((n) => n.startsWith('Profil Gola')), isTrue);
    expect(hw.any((n) => n.startsWith('Tringle')), isTrue);
    expect(hw.any((n) => n.startsWith('Tiroir double paroi')), isTrue);
    final parts = b.cutParts();
    expect(qty(parts, 'Joue de finition'), 1);
    expect(qty(parts, 'Fileur'), 1);
  });

  test('chaque base se construit, se débite, et s’enregistre avec le projet', () {
    final p = Project();
    for (final pr in artPresets) {
      final b = pr.build();
      expect(b.cutParts(), isNotEmpty, reason: pr.name);
      expect(b.hardware(), isNotEmpty, reason: pr.name);
      p.art.boxes.add(b);
    }
    final back = Project.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
    expect(back.art.boxes.length, artPresets.length);
    expect(back.art.panels.length, p.art.panels.length);
    expect(jsonEncode(back.art.toJson()), jsonEncode(p.art.toJson()));
    // caissons côte à côte, sans chevauchement
    final xs = p.art.boxOrigins;
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], greaterThanOrEqualTo(xs[i - 1] + p.art.boxes[i - 1].w));
    }
    expect(p.art.plan(p.cut).sheets, isNotEmpty);
  });

  testWidgets('atelier : choisir une base, régler les colonnes, habiller une zone, débit', (t) async {
    t.view.physicalSize = const Size(1180, 820);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: ArtPage(state: st)));
    await t.pumpAndSettle();
    await closeArtWelcome(t);
    // les caissons à composer sont dans « Ma bibliothèque »
    await t.tap(find.byKey(const ValueKey('art_tab_biblio')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Colonne de dressing'), 200, scrollable: find.ancestor(of: find.text('Meubles depuis une feuille'), matching: find.byType(Scrollable)).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Colonne de dressing'));
    await t.pumpAndSettle();
    final art = st.project.art;
    expect(art.boxes, hasLength(1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/art_box.png'));
    // trois colonnes
    await t.tap(find.text('Intérieur'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithIcon(IconButton, Icons.add).first);
    await t.pumpAndSettle();
    expect(art.boxes.single.columns, 3);
    // toucher la zone basse de la 1re colonne dans la 3D : onglet Façades
    await t.ensureVisible(find.text('Face'));
    await t.pumpAndSettle();
    await t.tap(find.text('Face'));
    await t.pumpAndSettle();
    final vp = t.getRect(find.byKey(const Key('art-viewport')));
    final b = art.boxes.single;
    final z = b.zones.first;
    // en vue de face cadrée, la zone basse gauche est en bas à gauche du meuble
    await t.tapAt(vp.center + Offset(-vp.width * 0.18 * (b.w - z.fx1) / b.w, vp.height * 0.2));
    await t.pumpAndSettle();
    await t.tap(find.text('Façades').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Tiroirs').first);
    await t.pumpAndSettle();
    expect(b.covers.values.any((c) => c.type == CoverType.drawers), isTrue);
    // structure commune : vue éclatée, couleurs par composant
    await t.ensureVisible(find.text('3D'));
    await t.pumpAndSettle();
    await t.tap(find.text('3D'));
    await t.ensureVisible(find.text('Éclaté'));
    await t.pumpAndSettle();
    await t.tap(find.text('Éclaté'));
    await t.ensureVisible(find.text('Composants'));
    await t.pumpAndSettle();
    await t.tap(find.text('Composants'));
    await t.pumpAndSettle();
    expect(find.text('Calques'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/art_box_eclate.png'));
    await t.ensureVisible(find.text('Éclaté'));
    await t.pumpAndSettle();
    await t.tap(find.text('Éclaté'));
    await t.ensureVisible(find.text('Composants'));
    await t.pumpAndSettle();
    await t.tap(find.text('Composants'));
    await t.tap(find.text('Débit'));
    await t.pumpAndSettle();
    // la liste du débit défile : les façades de tiroir sont plus bas
    final debitList = find.ancestor(of: find.textContaining('Porte ·').first, matching: find.byType(Scrollable)).first;
    for (var i = 0; i < 8 && find.textContaining('Façade de tiroir').evaluate().isEmpty; i++) {
      await t.drag(debitList, const Offset(0, -200));
      await t.pumpAndSettle();
    }
    expect(find.textContaining('Façade de tiroir'), findsWidgets);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/art_box_debit.png'));
    expect(t.takeException(), isNull);
  });
}

/// Ferme l'accueil du mode Art (Nouveau / Ouvrir / Bibliothèque) quand la scène est vide.
Future<void> closeArtWelcome(WidgetTester t) async {
  final f = find.byKey(const ValueKey('welcome_close'));
  if (f.evaluate().isNotEmpty) {
    await t.tap(f);
    await t.pumpAndSettle();
  }
}
