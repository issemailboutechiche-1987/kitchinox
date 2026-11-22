// Stock de l'atelier : chutes servies avant les feuilles neuves, découpe validée, annulation, devis, fichiers.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';

void main() {
  StockPiece chute(String id, int l, int w, {String m = 'MDF', int t = 18}) => StockPiece(id: id, material: m, thickness: t, length: l, width: w);
  tearDown(() => stockSource = null);

  /// Aucune pièce hors de sa feuille, aucun recouvrement, toutes les pièces posées une fois.
  void valid(CutPlan plan, CutSettings cs) {
    final count = <int, int>{};
    for (final s in plan.sheets) {
      for (final p in s.placements) {
        expect(identical(p.part, plan.parts[p.index - 1]), isTrue);
        count[p.index] = (count[p.index] ?? 0) + 1;
        expect(p.x >= cs.trim - 0.01 && p.y >= cs.trim - 0.01 && p.x + p.dx <= s.length - cs.trim + 0.6 && p.y + p.dy <= s.width - cs.trim + 0.6, isTrue);
        for (final q in s.placements) {
          if (identical(p, q)) continue;
          expect(p.x + p.dx <= q.x + 0.6 || q.x + q.dx <= p.x + 0.6 || p.y + p.dy <= q.y + 0.6 || q.y + q.dy <= p.y + 0.6, isTrue);
        }
      }
    }
    for (var i = 0; i < plan.parts.length; i++) {
      expect((count[i + 1] ?? 0) + plan.notPlaced.where((p) => identical(p, plan.parts[i])).length, plan.parts[i].qty);
    }
  }

  List<CutPart> parts() => [
        CutPart('MDF', 'Côté', '1', 720, 560, 6),
        CutPart('MDF', 'Tablette', '1', 500, 300, 9, canRotate: false),
        CutPart('HDF 6 mm', 'Fond', '1', 700, 500, 3),
      ];

  test('matières comparées sans le format, le type ni l’épaisseur', () {
    expect(stockMaterial('MDF (façades)'), 'mdf');
    expect(stockMaterial('MDF 18 (caisson)'), 'mdf');
    expect(stockMaterial('MDF 18 mm'), 'mdf');
    expect(stockMaterial('HDF 6 mm'), 'hdf');
    expect(stockMaterial('Latté 18 · 2440×1220'), 'latté');
    expect(stockMaterial('Latté (Blockboard)'), 'latté (blockboard)');
    expect(chute('a', 1, 1).matches('HDF 18', 18), isFalse);
    expect(chute('a', 1, 1).matches('MDF', 16), isFalse);
  });

  test('sans stock : même plan qu’avant', () {
    final cs = CutSettings();
    final a = nest(parts(), cs);
    stockSource = () => [chute('C-1', 900, 600, m: 'Chêne')]; // autre matière
    final b = nest(parts(), cs);
    expect(b.sheets.length, a.sheets.length);
    expect(b.stockSheets(), isEmpty);
  });

  for (final machine in ['scie', 'cnc']) {
    for (final method in [1, 2, 3]) {
      test('les chutes servent avant les feuilles neuves ($machine, méthode $method)', () {
        final cs = CutSettings(machine: machine, method: method);
        final base = nest(parts(), cs);
        stockSource = () => [chute('C-1', 760, 600), chute('C-2', 1100, 640), chute('C-3', 720, 520, m: 'HDF 6 mm', t: 6), chute('C-4', 200, 200)];
        final plan = nest(parts(), cs);
        valid(plan, cs);
        expect({for (final s in plan.stockSheets()) s.stockId}, containsAll(['C-1', 'C-3']));
        expect({for (final s in plan.stockSheets()) s.stockId}, isNot(contains('C-4')));
        expect(plan.newSheets().length, lessThanOrEqualTo(base.sheets.length));
        for (final s in plan.stockSheets()) {
          expect(s.usage, greaterThanOrEqualTo(0.4));
        }
        // une chute ne sert qu'une fois
        expect(plan.stockSheets().map((s) => s.stockId).toSet().length, plan.stockSheets().length);
      });
    }
  }

  test('une chute évite une feuille ; mode « seulement si elle évite une feuille » ; mode arrêt', () {
    // une seule pièce de trop pour une feuille
    List<CutPart> p() => [CutPart('MDF', 'Grand', '1', 2700, 2000, 1), CutPart('MDF', 'Petit', '1', 500, 400, 1)];
    final cs = CutSettings();
    expect(nest(p(), cs).sheets.length, 2);
    stockSource = () => [chute('C-1', 600, 500)];
    for (final mode in ['always', 'save']) {
      cs.stockMode = mode;
      final plan = nest(p(), cs);
      expect((plan.newSheets().length, plan.stockSheets().length), (1, 1), reason: mode);
    }
    cs.stockMode = 'off';
    expect(nest(p(), cs).stockSheets(), isEmpty);
    // la chute n'évite aucune feuille : laissée au rayon en mode 'save'
    cs.stockMode = 'save';
    expect(nest([CutPart('MDF', 'A', '1', 1000, 1000, 1), CutPart('MDF', 'B', '1', 500, 400, 1)], cs).stockSheets(), isEmpty);
  });

  test('le fil de la chute est respecté', () {
    stockSource = () => [chute('C-1', 400, 700)]; // longueur (fil) 400
    final plan = nest([CutPart('MDF', 'Façade', '1', 600, 350, 1, canRotate: false)], CutSettings());
    expect(plan.stockSheets(), isEmpty);
    final free = nest([CutPart('MDF', 'Tablette', '1', 600, 350, 1)], CutSettings());
    expect(free.stockSheets(), hasLength(1));
  });

  test('fil de calcul : la demande emporte les chutes, la réponse dit lesquelles ont servi', () {
    final cs = CutSettings();
    stockSource = () => [chute('C-1', 760, 600)];
    final ps = parts();
    final req = nestRequest(1, ps, cs);
    final key = nestKey(ps, cs);
    stockSource = null; // le fil de calcul n'a pas accès au stock
    final plan = nestFromResponse(jsonDecode(nestJob(req)) as Map<String, dynamic>, ps, cs);
    expect(plan.stockSheets().single.stockId, 'C-1');
    expect(nestKey(ps, cs), isNot(key), reason: 'le stock a changé : le plan doit être recalculé');
    // le projet enregistré n'emporte pas le stock
    expect(cs.toJson().keys.where((k) => k.contains('stock')), isEmpty);
  });

  test('valider une découpe : chutes sorties, feuilles prises, restes rangés ; annuler remet tout', () {
    final st = Stock();
    final used = st.add(material: 'MDF', thickness: 18, length: 760, width: 600);
    st.add(material: 'MDF', thickness: 18, length: 2800, width: 2100, qty: 1, offcut: false);
    final before = jsonEncode([for (final p in st.pieces) p.toJson()]);
    stockSource = () => st.availableFor('Cuisine A');
    final cs = CutSettings();
    final plan = nest(parts(), cs);
    expect(plan.stockSheets().single.stockId, used.id);
    final need = {for (final n in st.needs(plan)) n.material: n};
    expect(need['MDF']!.inStock, 1);
    expect(need['MDF']!.toBuy, need['MDF']!.needed - 1);
    expect(need['HDF 6 mm']!.toBuy, 1);
    final keep = st.leftovers(plan, project: 'Cuisine A', date: '2026-11-22');
    expect(keep, isNotEmpty);
    for (final k in keep) {
      expect(k.length >= k.width ? k.length : k.width, greaterThanOrEqualTo(st.minLength));
    }
    final move = st.validate(plan, project: 'Cuisine A', date: '2026-11-22', keep: keep);
    expect(st.byId(used.id), isNull);
    expect(st.sheets, isEmpty);
    expect(st.offcuts.length, keep.length);
    expect(st.lastCut('Cuisine A'), same(move));
    // le stock enregistré se relit à l'identique
    final back = Stock()..load(jsonDecode(jsonEncode(st.toJson())) as Map<String, dynamic>);
    expect(jsonEncode(back.toJson()), jsonEncode(st.toJson()));
    expect(st.undo(move), isEmpty);
    expect(jsonEncode([for (final p in st.pieces) p.toJson()]..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'))), before);
    expect(st.lastCut('Cuisine A'), isNull);
    // un numéro de chute ne sert jamais deux fois
    final n = st.add(material: 'MDF', thickness: 18, length: 500, width: 500);
    expect(move.added.any((p) => p.id == n.id), isFalse);
  });

  test('plan figé après validation : le stock peut bouger, le plan non', () {
    final cs = CutSettings();
    stockSource = () => [chute('C-1', 760, 600)];
    final plan = nest(parts(), cs);
    cs.stockFrozen = [for (final p in cs.stock) p.copy()];
    stockSource = () => [chute('C-9', 2000, 2000)];
    final again = nest(parts(), CutSettings.fromJson(jsonDecode(jsonEncode(cs.toJson())) as Map<String, dynamic>));
    expect([for (final s in again.sheets) s.stockId], [for (final s in plan.sheets) s.stockId]);
  });

  test('chute gardée pour un projet : invisible pour les autres', () {
    final st = Stock();
    st.add(material: 'MDF', thickness: 18, length: 800, width: 600).reserved = 'A';
    expect(st.availableFor('A'), hasLength(1));
    expect(st.availableFor('B'), isEmpty);
  });

  test('code QR de l’étiquette', () {
    final p = chute('C-0012', 800, 600);
    expect(StockPiece.idFromScan(p.qr), 'C-0012');
    expect(StockPiece.idFromScan(' c-0012 '), 'c-0012');
  });

  test('gros débit : le calcul reste rapide', () {
    final rnd = [for (var i = 0; i < 30; i++) CutPart('MDF', 'P$i', '1', 300 + (i * 137) % 900, 150 + (i * 71) % 450, 6)];
    stockSource = () => [for (var i = 0; i < 40; i++) chute('C-$i', 400 + (i * 97) % 900, 300 + (i * 53) % 500)];
    final cs = CutSettings();
    final w = Stopwatch()..start();
    final plan = nest(rnd, cs);
    valid(plan, cs);
    // ignore: avoid_print
    print('180 pièces, 40 chutes : ${w.elapsedMilliseconds} ms, ${plan.newSheets().length} feuilles + ${plan.stockSheets().length} chutes');
  });

  test('devis : feuilles neuves et chutes sur des lignes séparées', () {
    String f(String n) => File('assets/data/$n.json').readAsStringSync();
    final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'), handles: f('handles'));
    final e = LayoutEngine(Catalog.parse(File('assets/catalog.json').readAsStringSync()), Project());
    final specs = ProjectSpecs()..sheetPrice = 588;
    final cs = CutSettings();
    stockSource = () => [chute('C-1', 600, 500)];
    final plan = nest([CutPart('MDF', 'Grand', '1', 2700, 2000, 1), CutPart('MDF', 'Petit', '1', 500, 400, 1)], cs);
    SupplyLine? line(bool Function(SupplyLine) t) => estimate(e, db, specs, plan, buildBom(e)).where(t).firstOrNull;
    expect(line((l) => l.unit == 'feuille' && l.section == 'Panneaux' && !l.name.startsWith('Découpe'))!.qty, 1);
    final off = line((l) => l.name == 'Chutes du stock')!;
    expect(off.qty, closeTo(0.3, 0.001));
    expect(off.unitPrice.min, closeTo(588 / (2.8 * 2.1), 0.01));
    cs.offcutPct = 0;
    expect(line((l) => l.name == 'Chutes du stock')!.unitPrice.min, 0);
  });

  debugPrint('');
}
