// Atelier de découpe et Documents : codes des pièces = codes des étiquettes, fichier relu, toucher imprime et coche.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/documents_page.dart';
import 'package:kitchen_planner/ui/labels_pdf.dart';
import 'package:kitchen_planner/ui/pdf_preview.dart';
import 'package:kitchen_planner/ui/theme.dart';
import 'package:kitchen_planner/ui/web_io.dart';
import 'package:kitchen_planner/ui/workshop_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  AppState kitchen() {
    final st = AppState(cat, project: Project(name: 'Essai', room: Room(width: 3600, depth: 3000, height: 2600)));
    st.engine.add('base_standard_single_door', 'A', s: 0, width: 600);
    st.engine.add('base_drawers_multi', 'A', s: 600, width: 600);
    st.engine.add('wall_standard_single_door', 'A', s: 0, width: 600);
    return st;
  }

  test('fichier d’atelier : chaque pièce physique, numérotée comme ses étiquettes ; aller-retour .kin', () {
    final st = kitchen();
    final plan = st.cutPlan;
    final projId = labelProjectId(st.project);
    final job = WorkshopJob.fromPlan(plan, project: st.project.name, projId: projId);
    expect(job.pieceCount, plan.partCount);
    // mêmes codes que le PDF des étiquettes : projet + n° de pièce + exemplaire, un code par pièce physique
    final expected = <String>{
      for (var i = 0; i < plan.parts.length; i++)
        for (var c = 1; c <= plan.parts[i].qty; c++) labelCode(projId, i + 1, c),
    };
    expect({for (final p in job.pieces) p.code}, expected);
    for (final p in job.pieces) {
      expect(plan.parts[p.part - 1].name, p.name);
    }
    job.done.add(job.pieces.first.code);
    final back = WorkshopJob.fromJson(jsonDecode(KinFormat.decode(workshopBytes(job))) as Map<String, dynamic>);
    expect(back.pieceCount, job.pieceCount);
    expect(back.done, job.done);
    expect(back.byCode(job.pieces.last.code)?.name, job.pieces.last.name);
    expect(back.qr, startsWith('KXD1|$projId|'));
  });

  test('atelier : chants et rainures de chaque pièce gardés et lisibles', () {
    final st = kitchen();
    final job = WorkshopJob.fromPlan(st.cutPlan, project: 'Essai', projId: '1234');
    final edged = job.pieces.where((p) => p.edgeLong + p.edgeShort > 0);
    final grooved = job.pieces.where((p) => p.grooveLong + p.grooveShort > 0);
    expect(edged, isNotEmpty);
    expect(grooved, isNotEmpty, reason: 'côtés rainurés pour le fond');
    expect(edged.first.edgeText, contains('×'));
    expect(grooved.first.grooveText, startsWith('sur la'));
    final back = WorkshopJob.fromJson(jsonDecode(KinFormat.decode(workshopBytes(job))) as Map<String, dynamic>);
    expect([for (final p in back.pieces) (p.edgeLong, p.edgeShort, p.grooveLong, p.grooveShort)], [for (final p in job.pieces) (p.edgeLong, p.edgeShort, p.grooveLong, p.grooveShort)]);
  });

  testWidgets('atelier : toucher une pièce imprime son étiquette et la coche ; appui long la remet', (t) async {
    final st = kitchen();
    final job = WorkshopJob.fromPlan(st.cutPlan, project: 'Essai', projId: '1234');
    final printed = <String>[];
    printLabels = (pdf, name) async => printed.add(name);
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: WorkshopPage(job: job)));
    final view = find.byKey(const ValueKey('ws_sheet_view'));
    final rect = t.getRect(view);
    final s = job.sheets.first, p = s.pieces.first;
    final k = rect.width / s.length;
    final at = rect.topLeft + Offset((p.x + p.dx / 2) * k, (p.y + p.dy / 2) * k);
    await t.runAsync(() async {
      await t.tapAt(at);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump();
    expect(job.done, {p.code});
    expect(printed, [p.code]);
    expect(find.text(p.code), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ws_undo')));
    await t.pump();
    expect(job.done, isEmpty);
    // fichier gardé dans Documents
    expect((await docList()).any((d) => d.name == workshopFileName(job)), isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('Documents : PDF enregistré depuis l’aperçu, rouvert, supprimé', (t) async {
    pdfPageImages = (bytes, dpi) => const Stream.empty();
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final f = showPdfPreview(ctx, title: 'Plan', bytes: Uint8List.fromList([1, 2, 3]), storeAs: 'Essai_plan_de_decoupe.pdf', onSave: () {});
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('pdf_save')));
    await t.pumpAndSettle();
    await f;
    expect(await docGet('Essai_plan_de_decoupe.pdf'), [1, 2, 3]);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: const DocumentsPage()));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('doc_Essai_plan_de_decoupe.pdf')), findsOneWidget);
    await t.tap(find.byTooltip('Supprimer').first);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await t.pumpAndSettle();
    expect(await docGet('Essai_plan_de_decoupe.pdf'), isNull);
  });
}
