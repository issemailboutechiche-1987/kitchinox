// Plan de découpe pour scie à panneaux (PDF A4 portrait), sur le modèle de SketchCut PRO :
// 1. résultats (feuilles, surfaces, chutes, déchet, longueur de coupe, chants, rainures),
// 2. liste des pièces (cotes soulignées selon les chants, rotation, désignation, case AP),
// 3. une page par feuille : bandes verticales, pièces cotées et colorées, chutes hachurées cotées,
//    tableau des pièces de la feuille et synthèse (quantité, surface, taux d'utilisation).

import 'i18n.dart';
import 'pdf_fonts.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../engine/engine.dart';
import 'logo.dart';

const _grey = PdfColor.fromInt(0xFF555555);
const _head = PdfColor.fromInt(0xFFD9D9D9);

String _t(String s) => s.replaceAll('–', '-').replaceAll('’', "'").replaceAll('²', '2').replaceAll('…', '...');
String _n(double v, [int d = 2]) => v.toStringAsFixed(d).replaceAll('.', ',');
String _m2(double v) => '${_n(v, 3)} m2';
String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Pièce de façade (chant épais, trait plein) ou de caisson (chant fin, pointillés).
bool isFrontPart(CutPart p) =>
    p.name.startsWith('Porte') ||
    p.name.startsWith('Façade') ||
    p.name.startsWith('Fileur') ||
    p.name.startsWith('Joue') ||
    p.name.startsWith('Panneau') ||
    p.name.startsWith('Habillage');

/// Couleurs pastel des pièces (une par n° de pièce), comme sur SketchCut.
const _pastels = [
  Color(0xFFE8F59A),
  Color(0xFFD3F7CF),
  Color(0xFFCDEFF7),
  Color(0xFFF9D9C6),
  Color(0xFFE3D5F5),
  Color(0xFFFFF0B3),
  Color(0xFFCFE3F9),
  Color(0xFFF6CFE0),
  Color(0xFFD9F0E3),
  Color(0xFFF2E3CC),
];

/// Ancien dessin (paysage) gardé pour les aperçus.
void paintSheet(Canvas c, Size size, CutSheet sheet) => paintSawSheet(c, size, sheet, portrait: false);

/// Dessin d'une feuille pour la scie : en portrait, la longueur de la feuille est verticale et les
/// bandes (refentes) apparaissent en colonnes. Pièces colorées et cotées (soulignement = chant),
/// chutes hachurées avec leurs dimensions.
void paintSawSheet(Canvas c, Size size, CutSheet sheet, {bool portrait = true}) {
  final u = size.shortestSide / 1000;
  final margin = 46 * u;
  // repère : (x le long de la longueur, y en travers) → écran
  final sw = portrait ? sheet.width.toDouble() : sheet.length.toDouble();
  final sh = portrait ? sheet.length.toDouble() : sheet.width.toDouble();
  final k = math.min((size.width - 2 * margin) / sw, (size.height - 2 * margin) / sh);
  final ox = (size.width - sw * k) / 2, oy = (size.height - sh * k) / 2;
  Rect r(double x, double y, double dx, double dy) => portrait
      // longueur vers le haut (x = 0 en bas), travers vers la droite
      ? Rect.fromLTWH(ox + y * k, oy + (sheet.length - x - dx) * k, dy * k, dx * k)
      : Rect.fromLTWH(ox + x * k, oy + y * k, dx * k, dy * k);
  Paint line(double w, [Color col = const Color(0xFF1A1A1A)]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w * u
    ..color = col;

  /// Texte centré en [at] ; [lines] traits sous le texte (chants), pleins ou pointillés.
  void text(String s, Offset at, double fs, {double angle = 0, int lines = 0, bool dashed = false, Color color = const Color(0xFF1A1A1A), bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(fontSize: fs * u, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontFamily: 'Roboto')),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    c.save();
    c.translate(at.dx, at.dy);
    c.rotate(angle);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    for (var i = 0; i < lines; i++) {
      final y = tp.height / 2 + (2 + i * 3.2) * u;
      final p = line(1.3);
      if (dashed) {
        for (var x = -tp.width / 2; x < tp.width / 2; x += 6 * u) {
          c.drawLine(Offset(x, y), Offset(math.min(tp.width / 2, x + 3.5 * u), y), p);
        }
      } else {
        c.drawLine(Offset(-tp.width / 2, y), Offset(tp.width / 2, y), p);
      }
    }
    c.restore();
  }

  final sheetRect = r(0, 0, sheet.length.toDouble(), sheet.width.toDouble());
  c.drawRect(sheetRect, Paint()..color = Colors.white);
  // chutes : hachures et dimensions (longueur x largeur)
  for (final (x, y, w, h) in sheet.remnants) {
    final rr = r(x, y, w, h);
    c.save();
    c.clipRect(rr);
    for (var d = -rr.height; d < rr.width; d += 14 * u) {
      c.drawLine(Offset(rr.left + d, rr.bottom), Offset(rr.left + d + rr.height, rr.top), line(0.6, const Color(0xFF9A9A9A)));
    }
    c.restore();
    c.drawRect(rr, line(0.6, const Color(0xFF9A9A9A)));
    final fs = math.max(9.0, math.min(16.0, math.min(rr.width, rr.height) / u / 4));
    if (rr.shortestSide > 22 * u) {
      // la longueur le long du côté long, la largeur le long du côté court
      final vertical = rr.height >= rr.width;
      text('${w.round()}', vertical ? Offset(rr.left + fs * 0.9 * u, rr.center.dy) : Offset(rr.center.dx, rr.bottom - fs * 0.9 * u), fs,
          angle: vertical ? -math.pi / 2 : 0, color: const Color(0xFF555555));
      text('${h.round()}', vertical ? Offset(rr.center.dx, rr.bottom - fs * 0.9 * u) : Offset(rr.left + fs * 0.9 * u, rr.center.dy), fs,
          angle: vertical ? 0 : -math.pi / 2, color: const Color(0xFF555555));
    }
  }

  // pièces
  for (final p in sheet.placements) {
    final rr = r(p.x, p.y, p.dx.toDouble(), p.dy.toDouble());
    c.drawRect(rr, Paint()..color = _pastels[(p.index - 1) % _pastels.length]);
    c.drawRect(rr, line(1.4));
    final front = isFrontPart(p.part);
    // côté « longueur de la pièce » le long du plus grand côté dessiné
    final lenAlongX = p.dx == math.max(p.dx, p.dy);
    final lenVertical = portrait ? lenAlongX : !lenAlongX;
    final fs = math.max(10.0, math.min(30.0, rr.shortestSide / u / 4.2));
    final eLong = p.part.edgeLong, eShort = p.part.edgeShort;
    final lenTxt = '${math.max(p.dx, p.dy)}', widTxt = '${math.min(p.dx, p.dy)}';
    if (lenVertical) {
      text(lenTxt, Offset(rr.left + fs * 1.0 * u, rr.center.dy), fs, angle: -math.pi / 2, lines: eLong, dashed: !front, bold: true);
      text(widTxt, Offset(rr.center.dx, rr.bottom - fs * 1.0 * u), fs, lines: eShort, dashed: !front, bold: true);
    } else {
      text(lenTxt, Offset(rr.center.dx, rr.bottom - fs * 1.0 * u), fs, lines: eLong, dashed: !front, bold: true);
      text(widTxt, Offset(rr.left + fs * 1.0 * u, rr.center.dy), fs, angle: -math.pi / 2, lines: eShort, dashed: !front, bold: true);
    }
    final label = '#${p.index}. ${p.part.name.toUpperCase()}';
    final lf = math.max(8.0, math.min(14.0, fs * 0.55));
    // étiquette dans le coin opposé aux cotes
    if (lenVertical) {
      text(label, Offset(rr.right - lf * 1.1 * u, rr.top + rr.height * 0.28), lf, angle: -math.pi / 2, color: const Color(0xFF333333));
    } else {
      text(label, Offset(rr.center.dx, rr.top + lf * 1.1 * u), lf, color: const Color(0xFF333333));
    }
  }
  c.drawRect(sheetRect, line(2.2));
}


/// Même figure que [paintSawSheet], tracée en vectoriel dans le PDF : nette à tous les zooms,
/// sans image à calculer, encoder puis décoder (fichier léger, génération rapide, peu de mémoire).
void paintSawSheetPdf(PdfGraphics g, PdfPoint size, CutSheet sheet, PdfFont font, PdfFont bold) {
  final W = size.x, H = size.y;
  final u = math.min(W, H) / 1000;
  final margin = 46 * u;
  final sw = sheet.width.toDouble(), sh = sheet.length.toDouble();
  final k = math.min((W - 2 * margin) / sw, (H - 2 * margin) / sh);
  final ox = (W - sw * k) / 2, oy = (H - sh * k) / 2;
  // rectangle « écran » (origine en haut à gauche) → repère PDF (origine en bas à gauche)
  ({double l, double t, double w, double h}) r(double x, double y, double dx, double dy) =>
      (l: ox + y * k, t: oy + (sheet.length - x - dx) * k, w: dy * k, h: dx * k);
  double py(double y) => H - y;
  PdfColor col(Color c) => PdfColor.fromInt(c.toARGB32());
  void rect(({double l, double t, double w, double h}) q) => g.drawRect(q.l, py(q.t + q.h), q.w, q.h);

  void text(String str, double cx, double cy, double fs, {double angle = 0, int lines = 0, bool dashed = false, Color color = const Color(0xFF1A1A1A), bool isBold = false}) {
    final f = isBold ? bold : font;
    final size = fs * u;
    final tw = f.stringMetrics(str).advanceWidth * size;
    g
      ..saveContext()
      ..setTransform(Matrix4.identity()
        ..translateByDouble(cx, py(cy), 0, 1)
        ..rotateZ(-angle));
    g
      ..setFillColor(col(color))
      ..drawString(f, size, str, -tw / 2, -size * 0.35);
    if (lines > 0) {
      g
        ..setStrokeColor(col(const Color(0xFF1A1A1A)))
        ..setLineWidth(1.3 * u);
      if (dashed) g.setLineDashPattern([3.5 * u, 2.5 * u]);
      for (var i = 0; i < lines; i++) {
        final y = -size * 0.5 - (2 + i * 3.2) * u;
        g
          ..moveTo(-tw / 2, y)
          ..lineTo(tw / 2, y)
          ..strokePath();
      }
    }
    g.restoreContext();
  }

  final sheetR = r(0, 0, sheet.length.toDouble(), sheet.width.toDouble());
  g
    ..setFillColor(PdfColors.white)
    ..drawRect(sheetR.l, py(sheetR.t + sheetR.h), sheetR.w, sheetR.h)
    ..fillPath();
  // chutes : hachures et dimensions
  for (final (x, y, w, h) in sheet.remnants) {
    final q = r(x, y, w, h);
    g.saveContext();
    rect(q);
    g.clipPath();
    g
      ..setStrokeColor(col(const Color(0xFF9A9A9A)))
      ..setLineWidth(0.6 * u);
    for (var d = -q.h; d < q.w; d += 14 * u) {
      g
        ..moveTo(q.l + d, py(q.t + q.h))
        ..lineTo(q.l + d + q.h, py(q.t));
    }
    g
      ..strokePath()
      ..restoreContext();
    g
      ..setStrokeColor(col(const Color(0xFF9A9A9A)))
      ..setLineWidth(0.6 * u);
    rect(q);
    g.strokePath();
    final fs = math.max(9.0, math.min(16.0, math.min(q.w, q.h) / u / 4));
    if (math.min(q.w, q.h) > 22 * u) {
      final vertical = q.h >= q.w;
      final cx = q.l + q.w / 2, cy = q.t + q.h / 2, bottom = q.t + q.h;
      text('${w.round()}', vertical ? q.l + fs * 0.9 * u : cx, vertical ? cy : bottom - fs * 0.9 * u, fs,
          angle: vertical ? -math.pi / 2 : 0, color: const Color(0xFF555555));
      text('${h.round()}', vertical ? cx : q.l + fs * 0.9 * u, vertical ? bottom - fs * 0.9 * u : cy, fs,
          angle: vertical ? 0 : -math.pi / 2, color: const Color(0xFF555555));
    }
  }
  // pièces
  for (final p in sheet.placements) {
    final q = r(p.x, p.y, p.dx.toDouble(), p.dy.toDouble());
    g.setFillColor(col(_pastels[(p.index - 1) % _pastels.length]));
    rect(q);
    g.fillPath();
    g
      ..setStrokeColor(col(const Color(0xFF1A1A1A)))
      ..setLineWidth(1.4 * u);
    rect(q);
    g.strokePath();
    final front = isFrontPart(p.part);
    final lenVertical = p.dx == math.max(p.dx, p.dy);
    final fs = math.max(10.0, math.min(30.0, math.min(q.w, q.h) / u / 4.2));
    final eLong = p.part.edgeLong, eShort = p.part.edgeShort;
    final lenTxt = '${math.max(p.dx, p.dy)}', widTxt = '${math.min(p.dx, p.dy)}';
    final cx = q.l + q.w / 2, cy = q.t + q.h / 2, bottom = q.t + q.h;
    if (lenVertical) {
      text(lenTxt, q.l + fs * u, cy, fs, angle: -math.pi / 2, lines: eLong, dashed: !front, isBold: true);
      text(widTxt, cx, bottom - fs * u, fs, lines: eShort, dashed: !front, isBold: true);
    } else {
      text(lenTxt, cx, bottom - fs * u, fs, lines: eLong, dashed: !front, isBold: true);
      text(widTxt, q.l + fs * u, cy, fs, angle: -math.pi / 2, lines: eShort, dashed: !front, isBold: true);
    }
    final label = _t('#${p.index}. ${p.part.name.toUpperCase()}');
    final lf = math.max(8.0, math.min(14.0, fs * 0.55));
    if (lenVertical) {
      text(label, q.l + q.w - lf * 1.1 * u, q.t + q.h * 0.28, lf, angle: -math.pi / 2, color: const Color(0xFF333333));
    } else {
      text(label, cx, q.t + lf * 1.1 * u, lf, color: const Color(0xFF333333));
    }
  }
  g
    ..setStrokeColor(col(const Color(0xFF1A1A1A)))
    ..setLineWidth(2.2 * u);
  rect(sheetR);
  g.strokePath();
}

Future<Uint8List> buildCutPdf(LayoutEngine e, CutPlan plan,
    {DateTime? now, double pixelRatio = 2.2, MaterialsDb? db, String? number, void Function(double, String)? onProgress}) async {
  final prof = PerformanceProfiler.instance;
  // par étapes : l'écran se redessine entre deux feuilles (barre de progression, pas de gel)
  Future<void> step(double f, String what) async {
    onProgress?.call(f, what);
    if (onProgress != null) await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  final logo = await LogoShape.svgText();
  final p = e.project;
  final cs = plan.settings;
  final date = _date(now ?? DateTime.now());
  final format = PdfPageFormat.a4;
  const margin = 26.0;
  final doc = pw.Document(theme: await pdfTheme(), title: _t(trp('Plan de découpe - {0}', [trName(p.name)])), author: 'kitchinox');
  final figFont = PdfFont.helvetica(doc.document), figBold = PdfFont.helveticaBold(doc.document);
  int thick(String mat) => cs.thicknessFor(mat);
  final method = switch (cs.method) { 2 => 'par largeur', 3 => 'optimale', _ => 'par longueur' };

  pw.Widget header(String material, int page) => pw.Column(children: [
        pw.Row(children: [
          pw.Spacer(),
          if (logo != null)
            pw.SizedBox(height: 26, child: pw.SvgImage(svg: logo))
          else
            pw.Text(tr('kitchinox'), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFF26522))),
          pw.Text(tr('  scie à panneaux').replaceAll('à', 'a'), style: const pw.TextStyle(fontSize: 9, color: _grey)),
        ]),
        pw.Container(
          decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.8), bottom: pw.BorderSide(width: 0.8))),
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [
            pw.Expanded(
                child: pw.Text(
                    _t([
                      trp('Commande : {0}', [trName(p.name)]),
                      if (number != null) trp('N° {0}', [number]),
                      if (p.client.label.isNotEmpty) trp('Client : {0}', [p.client.label]),
                      if (p.client.ice.trim().isNotEmpty) trp('ICE {0}', [p.client.ice.trim()]),
                    ].join('   ')),
                    style: const pw.TextStyle(fontSize: 8.5))),
            pw.Text(trp('Date : {0}', [date]), style: const pw.TextStyle(fontSize: 8.5)),
            pw.SizedBox(width: 20),
            pw.Text(_t(tr('Date de réalisation : ')), style: const pw.TextStyle(fontSize: 8.5)),
            pw.SizedBox(width: 50),
          ]),
        ),
        pw.Container(
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.8))),
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Text(_t(trp('Matériau : {0}', [material])), style: const pw.TextStyle(fontSize: 8.5))),
            pw.Text(_t(trp('Épaisseur : {0} mm', [thick(material)])), style: const pw.TextStyle(fontSize: 8.5)),
            pw.SizedBox(width: 70),
          ]),
        ),
        pw.SizedBox(height: 8),
      ]);

  pw.Widget pageNo(pw.Context ctx) => pw.Align(alignment: pw.Alignment.bottomRight, child: pw.Text('${ctx.pageNumber}', style: const pw.TextStyle(fontSize: 9)));

  // nombre souligné : [lines] traits pleins (chant façade) ou pointillés (chant caisson)
  pw.Widget dim(int v, int lines, bool dashed, {double fs = 11}) => pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
        pw.Text('$v', style: pw.TextStyle(fontSize: fs)),
        for (var i = 0; i < lines; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 1.2),
            child: pw.Container(
              width: fs * 2.6,
              height: 0.9,
              decoration: dashed
                  ? const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.9, style: pw.BorderStyle.dashed)))
                  : const pw.BoxDecoration(color: PdfColors.black),
            ),
          ),
      ]);

  pw.Widget cell(pw.Widget child, {PdfColor? bg, pw.Alignment align = pw.Alignment.center}) =>
      pw.Container(color: bg, alignment: align, padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3), child: child);
  pw.Widget tx(String s, {double fs = 9, bool bold = false}) => pw.Text(_t(s), style: pw.TextStyle(fontSize: fs, fontWeight: bold ? pw.FontWeight.bold : null));
  pw.Widget apBox() => pw.Container(width: 11, height: 11, decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)));

  pw.Widget box(String title, pw.Widget child) => pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6, color: PdfColors.grey600)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Container(color: _head, alignment: pw.Alignment.center, padding: const pw.EdgeInsets.all(3), child: tx(title, fs: 11)),
          child,
        ]),
      );

  for (final mat in plan.materials) {
    final sheets = plan.sheets.where((s) => s.material == mat).toList();
    final parts = plan.parts.where((x) => x.material == mat).toList();
    final count = parts.fold<int>(0, (a, x) => a + x.qty);
    final partsArea = parts.fold<double>(0, (a, x) => a + x.area * x.qty) / 1e6;
    final fresh = sheets.where((s) => !s.fromStock).toList(), reused = sheets.where((s) => s.fromStock).toList();
    // dimensions réelles de la première feuille neuve de ce matériau (pas les dimensions globales)
    final (fL, fW) = fresh.isNotEmpty ? (fresh.first.length, fresh.first.width) : cs.sheetDimensionsFor(mat);
    final sheetL = fL.toDouble(), sheetW = fW.toDouble();
    final reusedArea = reused.fold<double>(0, (a, s) => a + s.length * s.width) / 1e6;
    final sheetArea = sheetL * sheetW / 1e6;
    final allArea = sheetArea * fresh.length + reusedArea;
    final remn = sheets.expand((s) => s.remnants).fold<double>(0, (a, r) => a + r.$3 * r.$4) / 1e6;
    final waste = math.max(0.0, allArea - partsArea - remn);
    final frontEdge = parts.where(isFrontPart).fold<double>(0, (a, x) => a + x.edgeLength * x.qty) / 1000;
    final carcassEdge = parts.where((x) => !isFrontPart(x)).fold<double>(0, (a, x) => a + x.edgeLength * x.qty) / 1000;
    final grooves = parts.fold<double>(0, (a, x) => a + x.grooveLength * x.qty) / 1000;
    final sp = p.specs;

    // ---- 1. résultats
    pw.TableRow row(String a, String b, String c2, String d) => pw.TableRow(children: [
          cell(tx(a), align: pw.Alignment.centerLeft),
          cell(tx(b), align: pw.Alignment.centerRight),
          cell(tx(c2), align: pw.Alignment.centerLeft),
          cell(tx(d), align: pw.Alignment.centerRight),
        ]);
    doc.addPage(pw.Page(
      textDirection: pdfDirection,
      pageFormat: format,
      margin: const pw.EdgeInsets.all(margin),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        header(mat, ctx.pageNumber),
        box(
          'Résultats',
          pw.Table(
            border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
            columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(3), 3: pw.FlexColumnWidth(2)},
            children: [
              row('Format de feuille', '${sheetL.toInt()} X ${sheetW.toInt()}', 'Nombre de pièces', '$count'),
              row('Nombre de feuilles', '${fresh.length}', 'Surface des pièces', _m2(partsArea)),
              row('Surface d\'une feuille', _m2(sheetArea), 'Surface des chutes', _m2(remn)),
              row('Surface de toutes les feuilles', _m2(allArea), 'Surface de déchet', _m2(waste)),
              row('Chutes réutilisées', reused.isEmpty ? '0' : '${reused.length} (${reused.map((s) => s.stockId).join(', ')})', 'Chant ${_n(sp.frontEdge, 1)} mm (façades)', '${_n(frontEdge)} m'),
              row('Surface des chutes réutilisées', reused.isEmpty ? '0 m2' : _m2(reusedArea), 'Chant ${_n(sp.carcassEdge, 1)} mm (caissons)', '${_n(carcassEdge)} m'),
              row('Longueur de coupe', '${_n(plan.cutLengthOf(mat))} m', 'Longueur de rainures', '${_n(grooves)} m'),
              row('Taux d\'utilisation', allArea == 0 ? '-' : '${_n(100 * partsArea / allArea)} %', 'Méthode', 'scie, $method'),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(children: [
              box(
                'Chants',
                pw.Table(border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600), children: [
                  pw.TableRow(children: [
                    cell(tx(trp('Type 1 : {0} mm (façades)', [_n(sp.frontEdge, 1)])), align: pw.Alignment.centerLeft),
                    cell(pw.Container(width: 40, height: 1.4, color: PdfColors.black)),
                  ]),
                  pw.TableRow(children: [
                    cell(tx(trp('Type 2 : {0} mm (caissons)', [_n(sp.carcassEdge, 1)])), align: pw.Alignment.centerLeft),
                    cell(pw.Container(
                        width: 40,
                        height: 1.4,
                        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1.4, style: pw.BorderStyle.dashed))))),
                  ]),
                ]),
              ),
              pw.SizedBox(height: 10),
              box(
                'Rainures',
                pw.Table(border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600), children: [
                  for (final (k, v) in [
                    ('Décalage', cs.backPanel ? '${CutSettings.grooveOffset}' : '-'),
                    ('Profondeur', cs.backPanel ? '${cs.grooveDepth}' : '-'),
                    ('Largeur', cs.backPanel ? '${cs.backThickness + 1}' : '-'),
                  ])
                    pw.TableRow(children: [cell(tx(k), align: pw.Alignment.centerLeft), cell(tx(v))]),
                ]),
              ),
            ]),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: box(
              'Informations',
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  tx(trp('Trait de scie : {0} mm · recoupe des bords : {1} mm', [cs.kerf, cs.trim])),
                  tx(tr('Coupes : refentes sur toute la longueur (bandes), puis tronçonnage, puis recoupes.')),
                  tx(trp('Profondeur des caissons : profondeur du meuble - {0} mm (porte).', [cs.doorThickness])),
                  if (db != null) ...() {
                    final lines = estimate(e, db, sp, plan, buildBom(e)).where((l) => l.section == 'Panneaux' || l.section == 'Chants').toList();
                    final t = totalOf(lines);
                    return [
                      pw.SizedBox(height: 6),
                      tx(tr('Coût du débit'), bold: true),
                      for (final l in lines)
                        tx(trp('{0} : {1} {2} x {3} MAD', [tr(l.name), l.qty == l.qty.roundToDouble() ? l.qty.round() : _n(l.qty), l.unit, l.unitPrice.min == l.unitPrice.max ? l.unitPrice.min.round() : '${l.unitPrice.min.round()}-${l.unitPrice.max.round()}'])),
                      tx(trp('Total feuilles + découpe + chant : {0} MAD', [t.min == t.max ? '${t.min.round()}' : '${t.min.round()} - ${t.max.round()}']), bold: true),
                    ];
                  }(),
                  if (plan.notPlaced.any((x) => x.material == mat))
                    pw.Text(_t(trp('Attention : {0} pièce(s) plus grande(s) que la feuille', [plan.notPlaced.where((x) => x.material == mat).length])),
                        style: pw.TextStyle(color: PdfColors.red800, fontWeight: pw.FontWeight.bold, fontSize: 9)),
                ]),
              ),
            ),
          ),
        ]),
        pw.Spacer(),
        pageNo(ctx),
      ]),
    ));

    // ---- 2. pièces
    final idx = {for (var i = 0; i < plan.parts.length; i++) plan.parts[i]: i + 1};
    doc.addPage(pw.MultiPage(
      textDirection: pdfDirection,
      pageFormat: format,
      margin: const pw.EdgeInsets.all(margin),
      header: (ctx) => header(mat, ctx.pageNumber),
      footer: pageNo,
      build: (_) => [
        pw.Center(child: tx(tr('Pièces'), fs: 12)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(width: 0.6),
          columnWidths: const {
            0: pw.FixedColumnWidth(30),
            1: pw.FixedColumnWidth(58),
            2: pw.FixedColumnWidth(58),
            3: pw.FixedColumnWidth(48),
            4: pw.FixedColumnWidth(44),
            5: pw.FlexColumnWidth(),
            6: pw.FixedColumnWidth(26),
          },
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: _head), children: [
              for (final h in ['#', 'Longueur', 'Largeur', 'Quantité', 'Rotation', 'Désignation', 'AP']) cell(tx(h, fs: 8.5)),
            ]),
            for (final x in parts)
              pw.TableRow(children: [
                cell(tx('${idx[x]}.', fs: 11)),
                cell(dim(x.length, x.edgeLong, !isFrontPart(x))),
                cell(dim(x.width, x.edgeShort, !isFrontPart(x))),
                cell(tx('${x.qty}', fs: 11)),
                cell(tx(x.canRotate ? tr('Oui') : tr('Non')), bg: _head),
                cell(pw.Column(children: [tx(x.name.toUpperCase(), fs: 10), tx(x.cabinet, fs: 7)])),
                cell(apBox(), bg: _head),
              ]),
          ],
        ),
        pw.SizedBox(height: 6),
        tx(trp('Soulignement des cotes : un trait par chant à plaquer sur ce côté (plein : chant {0} mm, pointillé : chant {1} mm). AP : case à cocher à l\'atelier.', [_n(sp.frontEdge, 1), _n(sp.carcassEdge, 1)]),
            fs: 7.5),
      ],
    ));

    // ---- 3. chaque feuille sur deux pages : page des mesures (tableau), puis page de la figure de découpe
    //         (la figure occupe environ 80 % de la page)
    for (var i = 0; i < sheets.length; i++) {
      final s = sheets[i];
      await step(0.05 + 0.75 * i / sheets.length, trp('Feuille {0} sur {1}', [i + 1, sheets.length]));
      // figure vectorielle (plus d'image de 1672 x 2222 px par feuille)
      final groups = <int, (CutPart, int)>{};
      for (final pl in s.placements) {
        final g = groups[pl.index];
        groups[pl.index] = (pl.part, (g?.$2 ?? 0) + 1);
      }
      final rows = groups.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      final area = s.partsArea / 1e6;
      pw.Widget summary() => pw.Container(
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.8))),
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              tx(trp('{0} X {1}  -  {2} ({3})   |   Quantité - 1   |   {4} bande(s)', [s.length, s.width, s.fromStock ? i + 1 : i + 1 - reused.length, s.fromStock ? reused.length : fresh.length, s.strips]), fs: 10),
              tx(trp('Nombre de pièces : {0}   |   Surface des pièces : {1}   |   {2} %', [s.placements.length, _m2(area), _n(100 * s.usage)]), fs: 10),
            ]),
          );
      pw.Widget title(String what) => pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, bottom: 6),
            child: pw.Text(_t(s.fromStock ? trp('Chute {0} ({1} x {2})  -  {3}', [s.stockId, s.length, s.width, what]) : trp('Feuille {0} / {1}  -  {2}', [i + 1 - reused.length, fresh.length, what])), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          );
      String grooveText(CutPart x) => x.grooveLength == 0 ? '' : (x.grooveLong > 0 ? 'long.' : 'larg.');

      // page A : mesures
      doc.addPage(pw.Page(
      textDirection: pdfDirection,
        pageFormat: format,
        margin: const pw.EdgeInsets.all(margin),
        build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          header(mat, ctx.pageNumber),
          title(tr('Mesures des pièces')),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(26),
              1: pw.FixedColumnWidth(54),
              2: pw.FixedColumnWidth(54),
              3: pw.FixedColumnWidth(30),
              4: pw.FlexColumnWidth(2),
              5: pw.FlexColumnWidth(3),
              6: pw.FixedColumnWidth(42),
              7: pw.FixedColumnWidth(24),
            },
            children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: _head), children: [
                for (final h in ['#', 'Long.', 'Larg.', 'Qté', 'Désignation', 'Meuble', 'Rainure', 'AP']) cell(tx(h, fs: 8.5, bold: true)),
              ]),
              for (final r in rows)
                pw.TableRow(children: [
                  cell(tx('${r.key}', fs: 9.5)),
                  cell(dim(r.value.$1.length, r.value.$1.edgeLong, !isFrontPart(r.value.$1), fs: 10)),
                  cell(dim(r.value.$1.width, r.value.$1.edgeShort, !isFrontPart(r.value.$1), fs: 10)),
                  cell(tx('${r.value.$2}', fs: 9.5)),
                  cell(tx(r.value.$1.name, fs: 8.5), align: pw.Alignment.centerLeft),
                  cell(tx(r.value.$1.cabinet, fs: 7.5), align: pw.Alignment.centerLeft),
                  cell(tx(grooveText(r.value.$1), fs: 8)),
                  cell(apBox()),
                ]),
            ],
          ),
          pw.SizedBox(height: 6),
          tx(tr('Chants : soulignés (trait plein : façade, pointillés : caisson), un trait par chant. Rainure : fond arrière rainuré, le long du côté indiqué.'), fs: 7.5),
          pw.Spacer(),
          summary(),
          pageNo(ctx),
        ]),
      ));

      // page B : figure de découpe, en grand
      doc.addPage(pw.Page(
      textDirection: pdfDirection,
        pageFormat: format,
        margin: const pw.EdgeInsets.all(margin),
        build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          header(mat, ctx.pageNumber),
          title(tr('Figure de découpe')),
          pw.Expanded(
              child: pw.CustomPaint(
                  size: const PdfPoint(double.infinity, double.infinity),
                  painter: (g, sz) => prof.measure('pdf_debit_figure', () => paintSawSheetPdf(g, sz, s, figFont, figBold)))),
          pw.SizedBox(height: 4),
          summary(),
          pageNo(ctx),
        ]),
      ));
    }
  }

  await step(0.85, tr('Assemblage du PDF'));
  final bytes = await prof.measureAsync('pdf_debit_assemblage', () => doc.save(), info: {'feuilles': plan.sheets.length});
  await step(1, tr('Terminé'));
  return bytes;
}
