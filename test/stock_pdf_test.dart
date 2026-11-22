// Fichiers tirés du stock : SketchCut par chute, plan de découpe et étiquettes PDF.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/cut_pdf.dart';
import 'package:kitchen_planner/ui/sct_export.dart';
import 'package:kitchen_planner/ui/stock_labels_pdf.dart';
import 'package:kitchen_planner/ui/stock_store.dart';

void main() {
  final store = StockStore.instance;
  tearDown(() => stockSource = null);

  AppState kitchen() {
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    st.engine.applyShape(RoomShape.linear);
    st.engine.add('base_sink', 'A', s: 0, width: 800);
    st.engine.add('base_standard_2doors', 'A', s: 800);
    return st;
  }

  testWidgets('SketchCut et PDF : un fichier par chute, les pièces ne sont pas comptées deux fois', (t) async {
    final st = kitchen();
    store.attach(st);
    store.stock.add(material: 'MDF', thickness: 18, length: 900, width: 600);
    final plan = st.cutPlan;
    final files = sctFiles(plan, name: 'x');
    expect(files.where((f) => f.fileName.contains('_Chute_')).single.sheet, (900, 600));
    expect(files.fold<int>(0, (a, f) => a + f.parts), plan.partCount);
    final pdf = (await t.runAsync(() => buildCutPdf(st.engine, plan)))!;
    expect(pdf.length, greaterThan(1000));
    final labels = (await t.runAsync(() => buildStockLabelsPdf(store.stock.offcuts)))!;
    expect(String.fromCharCodes(labels.sublist(0, 4)), '%PDF');
  });
}
