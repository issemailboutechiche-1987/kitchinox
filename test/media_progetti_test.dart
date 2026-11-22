// Tarif moyenne gamme : prix relevés, tailles estimées, devis hors taxes ; menu Marques et prix.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/brands_ui.dart';

void main() {
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  late MediaProgetti t;
  setUpAll(() {
    t = MediaProgetti.parse(f('mid_range'));
    Market.parse(f('market'));
    BrandCatalog.parse(f('brands'));
    PublicPrices.parse(f('public_prices'));
  });
  tearDownAll(() => MediaProgetti.instance = null);

  test('tous les prix des trois devis sont là : totaux TTC retrouvés', () {
    double sum(Iterable<MpItem> l) => l.fold(0, (a, i) => a + i.price);
    expect(sum(t.carcasses.where((i) => i.line == 'alvic')), closeTo(15805.74, 0.05));
    expect(sum(t.carcasses.where((i) => i.line == 'alvic_hydro')), closeTo(23524.96, 0.05));
    expect(sum(t.doors), closeTo(9633.05, 0.05));
  });

  test('taille au tarif : prix exact et référence', () {
    expect(t.carcass('alvic', 'bas', 600, 700), (price: 372.60, exact: true, ref: 'CBAB600'));
    expect(t.carcass('alvic', 'evier', 800, 700).price, 340.20);
    expect(t.carcass('alvic_hydro', 'haut', 600, 900).price, 488.26);
    expect(t.carcass('alvic', 'colonne', 600, 2200).price, 1611.36);
    expect(t.carcass('alvic', 'colonne', 600, 1300).price, 750.60);
    expect(t.door(700, 400, handle: true), (price: 210.00, exact: true, ref: 'PPISMW70X40'));
    expect(t.door(700, 350, handle: false).price, 152.89);
    expect(t.ht(372.60), 310.5);
  });

  test('taille hors tarif : estimée entre ses voisines, jamais absurde', () {
    final p = t.carcass('alvic', 'bas', 550, 700);
    expect(p.exact, isFalse);
    expect(p.price, inInclusiveRange(345.60, 372.60));
    final h = t.carcass('alvic', 'haut', 600, 800).price; // hauteur 800 : entre 700 (291,60) et le 900 hydrofuge (488,26)
    expect(h, inInclusiveRange(291.60, 488.26));
    expect(t.carcass('alvic', 'colonne', 600, 2100).price, inInclusiveRange(896.40, 1611.36));
    for (final handle in [true, false]) {
      for (final w in [200, 300, 450, 600, 900]) {
        var last = 0.0;
        for (final hh in [140, 175, 300, 350, 400, 560, 700, 750, 900, 1300, 2000, 2200]) {
          final v = t.door(hh, w, handle: handle).price;
          expect(v, greaterThan(20), reason: '$hh x $w');
          expect(v, greaterThan(last * 0.6), reason: '$hh x $w');
          last = v;
        }
      }
    }
    for (final line in t.lines.keys) {
      for (final type in ['bas', 'evier', 'four', 'haut', 'surhotte', 'colonne', 'angle_bas_l', 'angle_haut_l', 'angle_haut_c']) {
        for (final w in [300, 600, 900, 1200]) {
          for (final hh in [350, 700, 750, 900, 2000]) {
            expect(t.carcass(line, type, w, hh).price, inInclusiveRange(60, 6000), reason: '$line $type $w x $hh');
          }
        }
      }
    }
    expect(t.door(700, 600, handle: false).price, lessThan(t.door(700, 600, handle: true).price));
  });

  AppState kitchen() {
    final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'), handles: f('handles'));
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()), db: db, supplier: SupplierTariff.parse(f('supplier_prices')));
    st.engine.applyShape(RoomShape.linear);
    st.engine.add('base_sink', 'A', s: 0, width: 800);
    st.engine.add('base_drawers_multi', 'A', s: 800, width: 600);
    st.engine.add('base_standard_single_door', 'A', s: 1400, width: 600);
    st.engine.add('wall_standard_single_door', 'A', s: 0, width: 600, z: 1500);
    return st;
  }

  test('devis moyenne gamme : caissons et façades à l’article, hors taxes, sans panneaux à la feuille', () {
    final st = kitchen();
    final std = st.estimateLines.map((l) => l.section).toSet();
    st.setGamme('moyen');
    final lines = st.estimateLines;
    expect(lines.any((l) => l.section == 'Panneaux' || l.section == 'Chants'), isFalse);
    final box = lines.where((l) => l.section == 'Caissons').toList();
    expect(box.fold<double>(0, (a, l) => a + l.qty), 4);
    expect(box.every((l) => l.unitPrice.min > 100 && l.detail.startsWith('Moyenne gamme')), isTrue);
    expect(lines.where((l) => l.section == 'Façades'), isNotEmpty);
    for (final s in std.difference({'Panneaux', 'Chants'})) {
      expect(lines.any((l) => l.section == s), isTrue, reason: s);
    }
    // hors taxes : la TVA du devis n'est comptée qu'une fois
    final one = box.firstWhere((l) => l.name.contains('bas évier'));
    final ttc = t.carcass('alvic', 'evier', 800, st.project.items.first.height).price;
    expect(one.unitPrice.min, closeTo(ttc / 1.2, 0.01));
    // hydrofuge : plus cher
    double total() => st.estimateLines.where((l) => l.section == 'Caissons').fold(0, (a, l) => a + l.total.min);
    final a = total();
    st.edit(() => st.project.specs.mpCarcass = 'alvic_hydro');
    expect(total(), greaterThan(a));
    // poignée intégrée : plus de poignées à acheter
    expect(st.estimateLines.any((l) => l.section == 'Quincaillerie' && l.name.toLowerCase().contains('poignée')), isTrue);
    st.edit(() => st.project.specs.mpDoor = 'pi');
    expect(st.estimateLines.any((l) => l.section == 'Quincaillerie' && l.name.toLowerCase().contains('poignée')), isFalse);
    final back = ProjectSpecs.fromJson(st.project.specs.toJson());
    expect((back.gamme, back.mpCarcass, back.mpDoor), ('moyen', 'alvic_hydro', 'pi'));
  });

  test('façade sous un four : sa vraie hauteur ; portes d’angle comptées', () {
    final st = kitchen();
    final c = st.engine.add('base_cooktop_oven', 'A', s: 2000, width: 600);
    st.engine.applyShape(RoomShape.lShape);
    st.engine.add('corner_base_l_shaped', 'A');
    final lines = mediaProgettiLines(st.engine, t, st.project.specs);
    final heights = [for (final l in lines.where((l) => l.name.startsWith('Façade tiroir'))) int.parse(l.name.split(' ')[2])];
    expect(heights, isNotEmpty);
    expect(heights.every((x) => x < c.height * 0.8), isTrue, reason: '$heights');
    expect(lines.where((l) => l.name.startsWith('Porte maître') || l.name.startsWith('Porte esclave')).length, 2);
  });

  testWidgets('menu Marques et prix : tarif, prix indicatifs, panneaux, marques, fabricants', (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final st = kitchen();
    String? msg;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => showBrandsDialog(c, st, (m) => msg = m), child: const Text('go'))))));
    Future<void> open(String tab) async {
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(tab));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }

    await open('Moyenne gamme');
    expect(find.text('CBAB1000'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mp_use')));
    await tester.pumpAndSettle();
    expect(st.project.specs.gamme, 'moyen');
    expect(msg, isNotNull);
    for (final (tab, text) in [('Prix indicatifs', 'Visserie'), ('Marques mondiales', 'Blum · Autriche'), ('Fabricants', 'Julius Blum GmbH')]) {
      await open(tab);
      expect(find.text(text), findsOneWidget, reason: tab);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    }
    await open('Panneaux par gamme');
    await tester.tap(find.byKey(const ValueKey('mk_Standard_2800_2100')));
    await tester.pumpAndSettle();
    expect((st.project.specs.sheetPrice, st.project.cut.sheetLength), (820, 2800));
  });
}
