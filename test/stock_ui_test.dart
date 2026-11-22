// Écran du stock : ajouter une chute, la voir servir dans la cuisine, valider la découpe, annuler ; fichiers.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/stock_page.dart';
import 'package:kitchen_planner/ui/stock_store.dart';

void main() {
  final store = StockStore.instance;
  setUpAll(() => PublicPrices.parse(File('assets/data/public_prices.json').readAsStringSync()));
  tearDown(() {
    stockSource = null;
    store.stock.load(const {});
  });

  AppState kitchen() {
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    st.engine.applyShape(RoomShape.linear);
    st.engine.add('base_sink', 'A', s: 0, width: 800);
    st.engine.add('base_standard_2doors', 'A', s: 800);
    return st;
  }

  testWidgets('ajouter une chute à la main ; la retrouver par son étiquette', (t) async {
    t.view.physicalSize = const Size(1180, 820);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = kitchen();
    store.attach(st);
    await t.pumpWidget(MaterialApp(home: StockPage(state: st)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('stock_add_offcut')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('piece_ok')));
    await t.pumpAndSettle();
    expect(find.textContaining('Vérifiez'), findsOneWidget, reason: 'cotes vides refusées');
    await t.enterText(find.byKey(const ValueKey('piece_l')), '900');
    await t.enterText(find.byKey(const ValueKey('piece_w')), '600');
    await t.tap(find.byKey(const ValueKey('piece_ok')));
    await t.pumpAndSettle();
    final c = store.stock.offcuts.single;
    expect((c.length, c.width, c.material, c.thickness), (900, 600, 'MDF', 18));
    expect(st.cutPlan.stockSheets().map((s) => s.stockId), contains(c.id), reason: 'le débit de la cuisine s’en sert aussitôt');
    await t.enterText(find.byKey(const ValueKey('stock_search')), c.qr);
    await t.pumpAndSettle();
    expect(find.byKey(ValueKey('stock_${c.id}')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('stock_search')), 'C-9999');
    await t.pumpAndSettle();
    expect(find.byKey(ValueKey('stock_${c.id}')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('valider la découpe, plan figé, puis annuler', (t) async {
    t.view.physicalSize = const Size(1180, 820);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = kitchen();
    store.attach(st);
    store.update((s) => s.add(material: 'MDF', thickness: 18, length: 900, width: 600));
    final id = store.stock.offcuts.single.id;
    final plan = st.cutPlan;
    expect(plan.stockSheets().single.stockId, id);
    final shape = [for (final s in plan.sheets) '${s.stockId}:${s.placements.length}'];
    String? msg;
    Future<void> done(BuildContext c) async => msg = await showCutDone(c, st, st.cutPlan,
        project: stockLabelFor(st), settings: st.project.cut, freeze: (f) => st.project.cut.stockFrozen = f);
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) => TextButton(onPressed: () => done(c), child: const Text('go')))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.textContaining('à acheter'), findsWidgets);
    final label = find.byType(SwitchListTile); // sans étiquettes ici
    await t.ensureVisible(label);
    await t.tap(label);
    await t.tap(find.byKey(const ValueKey('cut_ok')));
    await t.pumpAndSettle();
    expect(msg, contains('Découpe validée'));
    expect(store.stock.byId(id), isNull);
    expect(store.stock.offcuts, isNotEmpty);
    expect([for (final s in st.cutPlan.sheets) '${s.stockId}:${s.placements.length}'], shape, reason: 'le plan ne change plus');
    // deuxième validation : proposée en annulation seulement
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('cut_undo')));
    await t.pumpAndSettle();
    expect(store.stock.offcuts.single.id, id);
    expect(st.project.cut.stockFrozen, isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('export puis import du stock ; fichier étranger refusé', (t) async {
    store.update((s) => s.add(material: 'MDF', thickness: 18, length: 900, width: 600));
    expect(store.importXlsx(store.exportXlsx()), isTrue);
    expect(store.importXlsx([0]), isFalse);
    final text = store.export();
    store.update((s) => s.pieces.clear());
    expect(store.import('{"kind":"autre"}'), isFalse);
    expect(store.import('{"kind":"kitchinox_stock","pieces":[{"id":1}]}'), isFalse);
    expect(store.import(text), isTrue);
    expect(store.stock.offcuts.single.length, 900);
  });
}
