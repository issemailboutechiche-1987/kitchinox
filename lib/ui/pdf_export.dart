// Plan d'exécution en PDF (A3 paysage).
// Pages : couverture (vue 3D, fiche projet, plan en vignette), plan du dessus coté, un plan de face
// par mur, puis nomenclature par mur et contrôles d'implantation. Chaque planche a sa légende des
// repères et un cartouche.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Size, Color, Canvas;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../engine/engine.dart';
import 'finishes.dart';
import 'i18n.dart';
import 'logo.dart';
import 'net_symbols.dart';
import 'pdf_fonts.dart';
import 'tech_drawings.dart';
import 'view3d_stub.dart'
    if (dart.library.js_interop) 'view3d_web.dart'
    if (dart.library.io) 'view3d_native.dart';

const _orange = PdfColor.fromInt(0xFFB45309); // avertissements (ambre, distinct de la marque)
const _brand = PdfColor.fromInt(0xFFF26522);
const _greyText = PdfColor.fromInt(0xFF555555);
const _line = PdfColor.fromInt(0xFF1A1A1A);
const _zebra = PdfColor.fromInt(0xFFF3F5F5);

/// Caractères hors de la police PDF standard (Latin-1) remplacés.
String _t(String s) => s
    .replaceAll('≥', '>=')
    .replaceAll('≤', '<=')
    .replaceAll('–', '-')
    .replaceAll('—', '-')
    .replaceAll('’', "'")
    .replaceAll('«', '"')
    .replaceAll('»', '"')
    .replaceAll('…', '...')
    .replaceAll('²', '2')
    .replaceAll('→', '->');

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _date(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// Construit le PDF. [pixelRatio] règle la finesse des dessins (2,5 ≈ 220 dpi en A3).
/// [onProgress] : avancement (0 à 1) et étape ; entre deux dessins la main est rendue à l'interface
/// (la barre de progression avance et le navigateur ne se fige pas).
Future<Uint8List> buildExecutionPdf(LayoutEngine e,
    {DateTime? now,
    double pixelRatio = 2.5,
    MaterialsDb? db,
    SupplierTariff? supplier,
    CutPlan? plan,
    String? number,
    void Function(double, String)? onProgress}) async {
  Future<void> step(double f, String what) async {
    onProgress?.call(f, what);
    if (onProgress != null) await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  await step(0.02, tr('Contrôles et nomenclature'));
  final logo = await LogoShape.svgText();
  final p = e.project;
  final std = p.standards;
  final date = _date(now ?? DateTime.now());
  final drawer = TechDrawer(e);
  final reps = drawer.reperes;
  final walls = wallsToDraw(e);
  final issues = [...e.validate(), if (p.networks) ...networkChecks(e)]..sort((a, b) => a.severity.index.compareTo(b.severity.index));
  final bom = buildBom(e);

  final format = PdfPageFormat.a3.landscape;
  const margin = 22.0, cartoucheH = 56.0, legendW = 215.0, gap = 10.0;
  final bodyH = format.height - 2 * margin - cartoucheH - gap;
  final drawW = format.width - 2 * margin - legendW - gap;
  final px = Size(drawW * pixelRatio, bodyH * pixelRatio);

  // ---- dessins (un par un, avec l'avancement : 85 % du temps environ)
  final netWalls = p.networks ? [for (final w in [...p.room.order, 'I']) if (visiblePoints(p).any((x) => x.wallId == w)) w] : const <String>[];
  final drawings = 3 + walls.length + netWalls.length;
  var done = 0;
  Future<Uint8List> draw(String what, Size size, void Function(Canvas, Size) paint) async {
    await step(0.05 + 0.8 * done / drawings, what);
    final png = await renderPng(size, paint);
    done++;
    return png;
  }

  final planPng = await draw('Plan du dessus', px, drawer.paintPlan);
  final elevPngs = <String, Uint8List>{
    for (final w in walls) w: await draw('Plan de face, mur $w', px, (c, s) => drawer.paintElevation(c, s, w)),
  };
  final netPngs = <String, Uint8List>{
    for (final w in netWalls) w: await draw('Réseaux, ${w == 'I' ? 'îlot' : 'mur $w'}', px, (c, s) => drawer.paintNetworks(c, s, w)),
  };
  final coverW = format.width - 2 * margin - 330 - gap;
  Uint8List? view3d;
  final web3dData = getWeb3dSnapshotPng();
  if (web3dData != null && web3dData.startsWith('data:image/png;base64,')) {
    try {
      final b64 = web3dData.substring('data:image/png;base64,'.length);
      view3d = base64Decode(b64);
    } catch (_) {}
  }
  view3d ??= await draw('Vue 3D de couverture', Size(coverW * pixelRatio, bodyH * pixelRatio), (c, s) => drawer.paint3d(c, s, -0.6));
  final planThumb = await draw('Miniature du plan', Size(330 * pixelRatio, 250 * pixelRatio), drawer.paintPlan);
  await step(0.86, tr('Mise en pages')); 

  final titles = <String>[
    'Couverture',
    'Plan du dessus',
    for (final w in walls) 'Plan de face - mur $w',
    for (final w in netWalls) 'Réseaux - ${w == 'I' ? 'îlot' : 'mur $w'}',
    if (netWalls.isNotEmpty) 'Réseaux - circuits et matériel',
    'Nomenclature et contrôles',
    if (db != null) 'Fournitures et estimation',
  ];
  final total = titles.length;
  final total0 = total;

  // ---- éléments communs
  pw.Widget cartouche(int index) => pw.Container(
        height: cartoucheH,
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.8)),
        child: pw.Column(children: [
          pw.Expanded(
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              pw.Container(
                width: 120,
                padding: const pw.EdgeInsets.all(4),
                decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(color: _brand, width: 2))),
                alignment: pw.Alignment.center,
                child: logo != null
                    ? pw.SvgImage(svg: logo)
                    : pw.Text(tr('kitchinox'), style: pw.TextStyle(color: _brand, fontSize: 16, fontWeight: pw.FontWeight.bold)),
              ),
              _cell(tr('Projet'), _t(p.name), flex: 3),
              if (!p.client.isEmpty) _cell(tr('Client'), _t(p.client.label), flex: 3),
              _cell(tr('Planche'), _t(titles[index]), flex: 3, bold: true),
              if (number != null) _cell(tr('N°'), number, flex: 2, bold: true),
              _cell(tr('Date'), date, flex: 2),
              _cell(tr('Échelle'), tr('cotes en mm'), flex: 2),
              _cell(tr('Page'), '${index + 1} / $total', flex: 1),
            ]),
          ),
          pw.Container(
            height: 14,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line, width: 0.6))),
            child: pw.Text(
              _t(trp('Plinthe {0} + caisson {1} + plan de travail {2} : dessus du plan à {3} mm. Toutes les cotes sont à vérifier sur place avant fabrication et pose.', [std.plinthHeight, std.baseCarcassHeight, std.worktopThickness, std.worktopTop])),
              style: const pw.TextStyle(fontSize: 7.5, color: _greyText),
            ),
          ),
        ]),
      );

  pw.Page page(int index, pw.Widget body) => pw.Page(
      textDirection: pdfDirection,
        pageFormat: format,
        margin: const pw.EdgeInsets.all(margin),
        build: (_) => pw.Column(children: [
          pw.Expanded(child: body),
          pw.SizedBox(height: gap),
          cartouche(index),
        ]),
      );

  pw.Widget frame(pw.Widget child) =>
      pw.Container(decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.8)), child: child);

  pw.Widget image(Uint8List png) => frame(pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain));

  pw.Widget badge(int n) => pw.Container(
        width: 17,
        height: 17,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, border: pw.Border.all(color: _orange, width: 1.1)),
        child: pw.Text('$n', style: pw.TextStyle(color: _orange, fontSize: 8, fontWeight: pw.FontWeight.bold)),
      );

  String dims(PlacedCabinet c) =>
      c.widthRight != null ? '${c.width}+${c.widthRight} x ${c.height}' : '${c.width} x ${c.height}';

  /// Légende : repères visibles sur la planche + informations utiles à la pose.
  pw.Widget legend(String title, List<PlacedCabinet> items, List<pw.Widget> extra) => frame(pw.Padding(
        padding: const pw.EdgeInsets.all(10),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(_t(title), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          for (final c in items)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                badge(reps[c.uid] ?? 0),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text(_t(e.modelOf(c).name), style: const pw.TextStyle(fontSize: 8.5)),
                    pw.Text(_t(trp('{0} mm  -  x {1}{2}', [dims(c), c.s.round(), e.modelOf(c).kind.isHigh ? ', bas à ${c.z.round()}' : ''])),
                        style: const pw.TextStyle(fontSize: 7.5, color: _greyText)),
                  ]),
                ),
              ]),
            ),
          if (extra.isNotEmpty) ...[pw.Divider(color: PdfColors.grey400, thickness: 0.5), ...extra],
        ]),
      ));

  pw.Widget note(String s, {bool strong = false}) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Text(_t(s), style: pw.TextStyle(fontSize: 8, fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  List<PlacedCabinet> sortedItems(Iterable<PlacedCabinet> it) =>
      [...it]..sort((a, b) => (reps[a.uid] ?? 0).compareTo(reps[b.uid] ?? 0));

  final doc = pw.Document(theme: await pdfTheme(), title: _t(trp('Plan d\'exécution - {0}', [trName(p.name)])), author: 'kitchinox', creator: 'kitchinox planner');
  var i = 0;

  // ---- 1. couverture
  final errors = issues.where((x) => x.severity == Severity.error).length;
  final warnings = issues.where((x) => x.severity == Severity.warning).length;
  doc.addPage(page(
    i++,
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Expanded(child: image(view3d)),
      pw.SizedBox(width: gap),
      pw.SizedBox(
        width: 330,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(tr('PLAN D\'EXECUTION'), style: pw.TextStyle(fontSize: 11, color: _orange, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
          pw.SizedBox(height: 4),
          pw.Text(_t(p.name), style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          if (number != null) _kv(tr('N°'), number),
          if (p.client.label.isNotEmpty) _kv(tr('Client'), _t(p.client.label)),
          if (p.client.ice.trim().isNotEmpty) _kv(tr('ICE'), p.client.ice.trim()),
          _kv(tr('Pièce'), trp('{0} x {1} mm, hauteur {2} mm', [p.room.width.round(), p.room.depth.round(), p.room.height.round()])),
          _kv(tr('Forme'), _t(trp('cuisine {0}', [e.layoutShape()]))),
          _kv(tr('Triangle'), () {
            final l = e.triangleLegs();
            if (l == null) return _t(tr('incomplet (évier, plaque, froid)'));
            return trp('{0} + {1} + {2} = {3} mm', [l.$1.round(), l.$2.round(), l.$3.round(), (l.$1 + l.$2 + l.$3).round()]);
          }()),
          _kv(tr('Murs équipés'), _t(p.room.order.where(p.room.isWallEnabled).map((w) => trp('mur {0}', [w])).join(', '))),
          _kv(tr('Ouvertures'), trp('{0} porte(s), {1} fenêtre(s)', [p.openings.where((o) => o.isDoor).length, p.openings.where((o) => !o.isDoor).length])),
          _kv(tr('Éléments'), trp('{0} repères, dont {1} caissons', [p.items.length, bom.cabinetCount])),
          _kv(tr('Plan de travail'), trp('{0} m, épaisseur {1} mm', [(bom.worktopLength / 1000).toStringAsFixed(2).replaceAll('.', ','), std.worktopThickness])),
          _kv(tr('Plinthes'), trp('{0} m, hauteur {1} mm', [(bom.plinthLength / 1000).toStringAsFixed(2).replaceAll('.', ','), std.plinthHeight])),
          _kv(tr('Finitions'), _t(finishSummary(p))),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            color: errors > 0 ? PdfColors.red50 : (warnings > 0 ? PdfColors.orange50 : PdfColor.fromInt(0xFFFFF1E7)),
            child: pw.Text(
              errors == 0 && warnings == 0
                  ? tr('Implantation conforme aux règles contrôlées.')
                  : _t(trp('{0} erreur(s) et {1} point(s) à vérifier : voir la dernière page.', [errors, warnings])),
              style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: errors > 0 ? PdfColors.red800 : _line),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(tr('Sommaire'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          for (var k = 1; k < total; k++) pw.Text('${k + 1}.  ${_t(titles[k])}', style: const pw.TextStyle(fontSize: 9.5)),
          pw.Spacer(),
          pw.SizedBox(height: 250, child: image(planThumb)),
        ]),
      ),
    ]),
  ));

  // ---- 2. plan du dessus
  doc.addPage(page(
    i++,
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Expanded(child: image(planPng)),
      pw.SizedBox(width: gap),
      pw.SizedBox(
        width: legendW,
        child: legend('Repères', sortedItems(p.items).where((c) => !e.modelOf(c).kind.isHigh).toList(), [
          note(tr('Ouvertures'), strong: true),
          for (final o in p.openings)
            note(trp('{0} mur {1} : {2} mm à {3} mm du coin gauche{4}', [o.isDoor ? 'Porte' : 'Fenêtre', o.wallId, o.width.round(), o.s.round(), o.isDoor ? '' : ', allège ${o.z.round()}'])),
          if (p.openings.isEmpty) note(tr('aucune')),
          pw.SizedBox(height: 4),
          note(tr('Éléments hauts en pointillés : repères sur les plans de face.')),
        ]),
      ),
    ]),
  ));

  // ---- 3. plans de face
  for (final w in walls) {
    final onWall = sortedItems(p.items.where((c) => e.boxesOf(c).any((b) => b.wallId == w)));
    final high = onWall.where((c) => e.modelOf(c).kind.isHigh).toList();
    final gaps = e.gaps().where((g) => g.wallId == w).toList();
    doc.addPage(page(
      i++,
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Expanded(child: image(elevPngs[w]!)),
        pw.SizedBox(width: gap),
        pw.SizedBox(
          width: legendW,
          child: legend('Mur $w - ${p.room.wall(w).length.round()} mm', onWall, [
            note(tr('Hauteurs'), strong: true),
            note(trp('Plinthe {0} - dessus caisson {1} - dessus plan {2}', [std.plinthHeight, std.baseTop, std.worktopTop])),
            if (high.isNotEmpty) note(trp('Bas des éléments hauts : {0} mm', [high.map((c) => c.z.round()).toSet().join(' / ')])),
            if (gaps.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              note(tr('Vides (hachurés en orange)'), strong: true),
              for (final g in gaps) note(trp('{0} mm entre {1} et {2}{3}', [g.width.round(), g.s0.round(), g.s1.round(), g.fillable ? ' : fileur' : ''])),
            ],
          ]),
        ),
      ]),
    ));
  }

  // ---- 3 bis. réseaux : un plan coté par mur, puis circuits et matériel
  PdfColor pdfColor(Color c) => PdfColor.fromInt(c.toARGB32());
  pw.Widget dot(NetKind k) => pw.Container(
        width: 22,
        height: 14,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: k.network == 'elec' ? PdfColors.white : pdfColor(netColor(k)),
          border: pw.Border.all(color: pdfColor(netColor(k)), width: 1),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
        ),
        child: pw.Text(k.tag,
            style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: k.network == 'elec' ? pdfColor(netColor(k)) : PdfColors.white)),
      );
  final circuits = circuitsOf(p);
  for (final w in netWalls) {
    final pts = visiblePoints(p).where((x) => x.wallId == w).toList()..sort((a, b) => a.s.compareTo(b.s));
    doc.addPage(page(
      i++,
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Expanded(child: image(netPngs[w]!)),
        pw.SizedBox(width: gap),
        pw.SizedBox(
          width: legendW,
          child: frame(pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(_t(trp('Réseaux - {0}', [w == 'I' ? 'îlot' : 'mur $w'])), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              note(tr('Position depuis la gauche du mur (vu de face) / hauteur depuis le sol fini, en mm.')),
              pw.SizedBox(height: 4),
              for (final x in pts)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Row(children: [
                    dot(x.kind),
                    pw.SizedBox(width: 5),
                    pw.Expanded(child: pw.Text(_t(x.kind.label), style: const pw.TextStyle(fontSize: 7.5))),
                    pw.Text(trp('{0} / h {1}', [x.s.round(), x.z.round()]), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                  ]),
                ),
            ]),
          )),
        ),
      ]),
    ));
  }
  if (netWalls.isNotEmpty) {
    final mat = networkMaterial(p);
    final checks = networkChecks(e);
    final th = pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9);
    doc.addPage(page(
      i++,
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          flex: 5,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(tr('Circuits au tableau'), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(
                _t(tr('Règles usuelles de la NF C 15-100 : chaque gros appareil sur son circuit, prises de la cuisine sur des circuits 20 A, protection par interrupteur différentiel 30 mA (type A pour la plaque et le lave-vaisselle). À faire valider par un électricien.')),
                style: const pw.TextStyle(fontSize: 8.5, color: _greyText)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Circuit', 'Disjoncteur', 'Câble', 'Points', 'Remarque'].map(_t).toList(),
              data: [for (final c in circuits) [_t(c.name), c.breaker, _t(c.cable), '${c.points}', _t(c.note)]],
              headerStyle: th,
              headerDecoration: const pw.BoxDecoration(color: _brand),
              cellStyle: const pw.TextStyle(fontSize: 9),
              oddRowDecoration: const pw.BoxDecoration(color: _zebra),
              border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FixedColumnWidth(70),
                2: const pw.FixedColumnWidth(80),
                3: const pw.FixedColumnWidth(45),
                4: const pw.FlexColumnWidth(4),
              },
            ),
            pw.SizedBox(height: 14),
            pw.Text(_t(tr('Légende')), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Wrap(spacing: 14, runSpacing: 5, children: [
              for (final k in NetKind.values)
                pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [dot(k), pw.SizedBox(width: 4), pw.Text(_t(k.label), style: const pw.TextStyle(fontSize: 8))]),
            ]),
            pw.SizedBox(height: 14),
            pw.Text(_t(tr('Contrôles des réseaux')), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            if (checks.isEmpty) note(tr('Aucune remarque.')),
            for (final x in checks) note('${x.severity == Severity.error ? 'ERREUR' : 'A VERIFIER'} - ${x.message}'),
          ]),
        ),
        pw.SizedBox(width: 18),
        pw.Expanded(
          flex: 4,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(_t(tr('Matériel')), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Réseau', 'Désignation', 'Qté'].map(_t).toList(),
              data: [for (final m in mat) [_t(m.network), _t(m.name), '${m.qty}']],
              headerStyle: th,
              headerDecoration: const pw.BoxDecoration(color: _brand),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {2: pw.Alignment.centerRight},
              oddRowDecoration: const pw.BoxDecoration(color: _zebra),
              border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
              columnWidths: {0: const pw.FixedColumnWidth(80), 1: const pw.FlexColumnWidth(5), 2: const pw.FixedColumnWidth(40)},
            ),
            pw.SizedBox(height: 6),
            note(tr('Câbles, gaines et tubes à métrer sur place selon le cheminement depuis le tableau et les arrivées.')),
          ]),
        ),
      ]),
    ));
  }

  // ---- 4. nomenclature et contrôles
  String sev(Severity s) => switch (s) { Severity.error => 'ERREUR', Severity.warning => 'A VERIFIER', Severity.info => 'INFO' };
  PdfColor sevColor(Severity s) => switch (s) { Severity.error => PdfColors.red800, Severity.warning => _orange, Severity.info => _brand };
  String repOf(Issue x) => x.uids.map((u) => reps[u]).whereType<int>().map((n) => '$n').join(', ');

  pw.Widget table(List<PlacedCabinet> rows) => pw.TableHelper.fromTextArray(
        headers: ['Rep.', 'Désignation', 'L x H x P (mm)', 'Depuis la gauche', 'Bas à', 'Options'].map(_t).toList(),
        data: [
          for (final c in rows)
            [
              '${reps[c.uid]}',
              _t(e.modelOf(c).name),
              c.widthRight != null ? '${c.width}+${c.widthRight} x ${c.height} x ${c.depth}' : '${c.width} x ${c.height} x ${c.depth}',
              '${c.s.round()}',
              '${c.z.round()}',
              _t([optionLabel(c.opening), optionLabel(c.variant)].where((s) => s.isNotEmpty).join(', ')),
            ]
        ],
        columnWidths: {
          0: const pw.FixedColumnWidth(32),
          1: const pw.FlexColumnWidth(4),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FixedColumnWidth(80),
          4: const pw.FixedColumnWidth(48),
          5: const pw.FlexColumnWidth(3),
        },
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: _brand),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignments: {0: pw.Alignment.center, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
        oddRowDecoration: const pw.BoxDecoration(color: _zebra),
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
      );

  doc.addPage(pw.MultiPage(
      textDirection: pdfDirection,
    pageFormat: format,
    margin: const pw.EdgeInsets.all(margin),
    footer: (ctx) => pw.Padding(padding: const pw.EdgeInsets.only(top: gap), child: cartouche(titles.indexOf('Nomenclature et contrôles'))),
    // blocs les uns sous les autres : les tableaux longs passent d'une page à l'autre (grandes cuisines)
    build: (_) => [
      pw.Text(tr('Nomenclature'), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      for (final w in p.room.order)
        if (p.items.any((c) => c.wallId == w)) ...[
          pw.SizedBox(height: 8),
          pw.Text(_t(trp('Mur {0} - {1} ({2} mm)', [w, (Room.wallNames[w] ?? 'mur $w').toLowerCase(), p.room.wall(w).length.round()])),
              style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _brand)),
          pw.SizedBox(height: 3),
          table(sortedItems(p.items.where((c) => c.wallId == w))),
        ],
      if (p.room.island != null && p.items.any((c) => c.wallId == 'I')) ...[
        pw.SizedBox(height: 8),
        pw.Text(_t(trp('Îlot ({0} mm)', [p.room.island!.length.round()])), style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _brand)),
        pw.SizedBox(height: 3),
        table(sortedItems(p.items.where((c) => c.wallId == 'I'))),
      ],
      if (p.objects.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.Text(tr('Sanitaires et objets posés'), style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _brand)),
        pw.SizedBox(height: 3),
        for (final o in p.objects)
          () {
            final (wid, a, b) = objectOnWall(p.room, o);
            final f = o.fixture;
            return pw.Bullet(
                text: _t(trp('{0} : {1} x {2} x {3} mm, mur {4}, axe à {5} mm{6}{7}', [objectName(o), o.w, o.d, o.h, wid, ((a + b) / 2).round(), o.z > 0 ? ', pose à ${o.z.round()} mm du sol' : '', f == null ? ' (mobilier du client)' : ''])),
                style: const pw.TextStyle(fontSize: 9));
          }(),
      ],
      pw.SizedBox(height: 10),
      pw.Text(tr('Linéaires et finitions'), style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _brand)),
      pw.SizedBox(height: 3),
      for (final l in bom.lines.where((l) => l.unit != 'pce' || l.section == 'À prévoir'))
        pw.Bullet(
            text: _t('${l.name} : ${l.dims}${l.details.isEmpty ? '' : ' (${l.details})'}${l.unit == 'pce' ? ' - quantité ${l.qty}' : ''}'),
            style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 16),
      pw.Text(_t(tr('Contrôles d\'implantation')), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      if (issues.isEmpty) pw.Text(tr('Aucun problème détecté.'), style: const pw.TextStyle(fontSize: 10)),
      for (final x in issues)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(
              width: 62,
              padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
              alignment: pw.Alignment.center,
              color: sevColor(x.severity),
              child: pw.Text(sev(x.severity), style: pw.TextStyle(color: PdfColors.white, fontSize: 7, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: pw.Text(_t(_cap(x.message)) + (repOf(x).isEmpty ? '' : trp('  (rep. {0})', [repOf(x)])), style: const pw.TextStyle(fontSize: 9)),
            ),
          ]),
        ),
      pw.SizedBox(height: 12),
      pw.Text(_t(tr('Règles appliquées')), style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _brand)),
      pw.SizedBox(height: 3),
      for (final n in [
        'Éléments hauts : bas à ${std.wallBottomMin} mm minimum (${std.wallClearanceMin} mm au-dessus du plan de travail).',
        'Hotte : ${LayoutEngine.hoodAboveHobMin} mm minimum au-dessus de la plaque de cuisson.',
        'Plan de travail : ${LayoutEngine.worktopThicknessMin} mm minimum au-dessus d\'une plaque.',
        'Plaque : ${LayoutEngine.hobSideClearance} mm conseillés de chaque côté (colonne, mur), jamais sous une fenêtre.',
        'Passage entre deux linéaires : ${LayoutEngine.aisleMin} mm minimum, ${LayoutEngine.aisleAdvised} mm conseillés.',
        'Angle : fileur de ${LayoutEngine.cornerFillerMin} mm minimum pour les poignées et tiroirs.',
        'Porte : 900 mm dégagés devant. Fenêtre : ni élément haut ni colonne devant.',
        'Vides de 50 à ${std.fillerMax} mm : fileur. Lave-vaisselle à 600 mm maximum de l\'évier.',
      ])
        pw.Bullet(text: _t(n), style: const pw.TextStyle(fontSize: 8.5)),
    ],
  ));

  // ---- 5. fournitures : électroménager, quincaillerie, panneaux, chants, plan de travail
  if (db != null) {
    final cut = plan ?? nestCached(cutList(e, p.cut, reps), p.cut);
    final lines = quoteLines(e, db, p.specs, cut, bom, supplier,
        gloss: frontFinish(p.style, p.style.frontLower ?? p.style.front).gloss);
    final bySection = <String, List<SupplyLine>>{};
    for (final l in lines) {
      bySection.putIfAbsent(l.section, () => []).add(l);
    }
    String mad(PriceRange r) => r.min == r.max ? '${r.min.round()}' : '${r.min.round()} - ${r.max.round()}';
    String q(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2).replaceAll('.', ',');
    final total = totalOf(lines);
    doc.addPage(pw.MultiPage(
      textDirection: pdfDirection,
      pageFormat: format,
      margin: const pw.EdgeInsets.all(margin),
      footer: (ctx) => pw.Padding(padding: const pw.EdgeInsets.only(top: gap), child: cartouche(total0 - 1)),
      build: (_) => [
        pw.Text(tr('Fournitures et estimation'), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(_t(trp('Panneaux, découpe et chant au tarif de l\'atelier ; quincaillerie {0} ; électroménager et plan de travail selon les fourchettes du marché (MAD).', [p.specs.hardwareBrand])),
            style: const pw.TextStyle(fontSize: 9, color: _greyText)),
        for (final en in bySection.entries) ...[
          pw.SizedBox(height: 8),
          pw.Text(_t(totalOf(en.value).isZero ? en.key : trp('{0}  -  {1} MAD', [en.key, mad(totalOf(en.value))])), style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _brand)),
          pw.SizedBox(height: 3),
          pw.TableHelper.fromTextArray(
            headers: ['Qté', 'Désignation', 'Détail', 'Prix unitaire', 'Total (MAD)'].map(_t).toList(),
            data: [
              for (final l in en.value) ['${q(l.qty)} ${l.unit}', _t(l.name), _t(l.detail), l.unitPrice.isZero ? '-' : mad(l.unitPrice), l.unitPrice.isZero ? _t(tr('à chiffrer')) : mad(l.total)]
            ],
            columnWidths: {
              0: const pw.FixedColumnWidth(70),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FlexColumnWidth(4),
              3: const pw.FixedColumnWidth(80),
              4: const pw.FixedColumnWidth(90),
            },
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8.5),
            headerDecoration: const pw.BoxDecoration(color: _brand),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignments: {3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
            oddRowDecoration: const pw.BoxDecoration(color: _zebra),
            border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
          ),
        ],
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          color: PdfColor.fromInt(0xFFFFF1E7),
          child: pw.Text(_t(trp('Estimation totale : {0} MAD', [mad(total)])), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ),
      ],
    ));
  }

  await step(0.92, tr('Compression du PDF'));
  final bytes = await PerformanceProfiler.instance.measureAsync('pdf_execution_assemblage', () => doc.save());
  await step(1, tr('Terminé'));
  return bytes;
}

pw.Widget _cell(String label, String value, {int flex = 1, bool bold = false}) => pw.Expanded(
      flex: flex,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6),
        decoration: const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(color: _line, width: 0.6))),
        child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(_t(label).toUpperCase(), style: const pw.TextStyle(fontSize: 6.5, color: _greyText, letterSpacing: 0.6)),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ]),
      ),
    );

pw.Widget _kv(String k, String v) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(width: 95, child: pw.Text(_t(k), style: const pw.TextStyle(fontSize: 10, color: _greyText))),
        pw.Expanded(child: pw.Text(v, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold))),
      ]),
    );
