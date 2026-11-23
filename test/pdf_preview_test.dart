// Aperçu des PDF dans l'application : les pages s'affichent, rien n'est enregistré sans le demander.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/ui/pdf_preview.dart';
import 'package:kitchen_planner/ui/theme.dart';

void main() {
  Future<ui.Image> page() async {
    final r = ui.PictureRecorder();
    Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 60, 85), Paint()..color = const Color(0xFFFFFFFF));
    return r.endRecording().toImage(60, 85);
  }

  testWidgets('aperçu : pages affichées, Fermer n’enregistre pas, Enregistrer enregistre', (t) async {
    final pages = await t.runAsync(() async => [await page(), await page()]);
    pdfPageImages = (bytes, dpi) => Stream.fromIterable([for (final p in pages!) p.clone()]);
    var saves = 0;
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    Future<bool> open() => showPdfPreview(ctx, title: 'Plan de découpe', bytes: Uint8List(2048), onSave: () => saves++);

    var f = open();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf_preview')), findsOneWidget);
    expect(find.byType(RawImage), findsWidgets); // la liste ne construit que les pages visibles
    expect(find.textContaining('2 page(s)'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('pdf_close')));
    await t.pumpAndSettle();
    expect((await f, saves), (false, 0));

    f = open();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('pdf_save')));
    await t.pumpAndSettle();
    expect((await f, saves), (true, 1));
  });

  testWidgets('aperçu impossible : on peut quand même enregistrer', (t) async {
    pdfPageImages = (bytes, dpi) => Stream.error(UnsupportedError('pas de moteur PDF'));
    var saves = 0;
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final f = showPdfPreview(ctx, title: 'Étiquettes', bytes: Uint8List(10), onSave: () => saves++);
    await t.pumpAndSettle();
    expect(find.textContaining('Aperçu impossible'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('pdf_save')));
    await t.pumpAndSettle();
    expect((await f, saves), (true, 1));
  });
}
