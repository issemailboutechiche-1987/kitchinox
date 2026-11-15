// Devis (PDF A4 portrait) : en-tête avec numéro, date et client, lignes par poste, sous-totaux,
// remise, TVA et total TTC. « Devis provisoire » tant qu'il n'est pas validé.
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../engine/engine.dart';
import 'i18n.dart';
import 'logo.dart';
import 'pdf_fonts.dart';

const _grey = PdfColor.fromInt(0xFF555555);
const _head = PdfColor.fromInt(0xFFE4E4E4);
const _accent = PdfColor.fromInt(0xFFF26522);

String _t(String s) => s.replaceAll('–', '-').replaceAll('’', "'").replaceAll('²', '2').replaceAll('…', '...').replaceAll(' ', ' ');

/// « 12 345,50 »
String money(double v) {
  final neg = v < 0;
  final s = v.abs().toStringAsFixed(2);
  final i = s.substring(0, s.length - 3);
  final b = StringBuffer();
  for (var k = 0; k < i.length; k++) {
    if (k > 0 && (i.length - k) % 3 == 0) b.write(' ');
    b.write(i[k]);
  }
  return '${neg ? '-' : ''}$b,${s.substring(s.length - 2)}';
}

String quoteQty(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2).replaceAll('.', ',');

String _date(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

/// PDF du devis [q] du projet [p]. [number] et [date] (AAAA-MM-JJ) viennent de la validation ;
/// sans validation le document porte la mention « provisoire ».
Future<Uint8List> buildQuotePdf(Project p, Quote q, {String? number, required String date, bool validated = false}) async {
  final doc = pw.Document(theme: await pdfTheme(), title: 'Devis ${p.name}');
  final logo = await LogoShape.svgText();
  pw.Widget tx(String s, {double fs = 9, bool bold = false, PdfColor? color, pw.TextAlign? align}) => pw.Text(_t(s),
      textAlign: align, style: pw.TextStyle(fontSize: fs, fontWeight: bold ? pw.FontWeight.bold : null, color: color));
  pw.Widget cell(pw.Widget w, {pw.Alignment align = pw.Alignment.centerLeft}) =>
      pw.Container(alignment: align, padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3), child: w);
  const right = pw.Alignment.centerRight;

  final kept = [for (final l in q.lines) if (l.included) l];
  final out = [for (final l in q.lines) if (!l.included) l];
  final sections = {for (final l in kept) l.section}.toList();

  pw.Widget header(pw.Context ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        margin: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1.2, color: _accent))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          if (logo != null) pw.SizedBox(height: 30, child: pw.SvgImage(svg: logo)) else tx('kitchinox', fs: 16, bold: true),
          pw.Spacer(),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            tx(validated ? tr('DEVIS') : tr('DEVIS PROVISOIRE'), fs: 15, bold: true),
            if (number != null) tx(trp('N° {0}', [number]), fs: 10, bold: true),
            tx(trp('Date : {0}', [_date(date)]), color: _grey),
          ]),
        ]),
      );

  pw.TableRow totalRow(String label, String value, {bool strong = false}) => pw.TableRow(
        decoration: strong ? const pw.BoxDecoration(color: _head) : null,
        children: [cell(tx(label, fs: strong ? 11 : 9.5, bold: strong)), cell(tx(value, fs: strong ? 11 : 9.5, bold: strong), align: right)],
      );

  doc.addPage(pw.MultiPage(
    textDirection: pdfDirection,
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    header: header,
    footer: (ctx) => pw.Row(children: [
      pw.Expanded(child: tx(tr('Prix en dirhams (MAD). Devis valable 30 jours.'), fs: 7.5, color: _grey)),
      tx('${ctx.pageNumber} / ${ctx.pagesCount}', fs: 7.5, color: _grey),
    ]),
    build: (_) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            tx(tr('Projet'), fs: 8, color: _grey),
            tx(trName(p.name), fs: 12, bold: true),
          ]),
        ),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6, color: _grey)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              tx(tr('Client'), fs: 8, color: _grey),
              tx(p.client.label.isEmpty ? '-' : p.client.label, fs: 11, bold: true),
              if (p.client.ice.trim().isNotEmpty) tx(trp('ICE {0}', [p.client.ice.trim()])),
            ]),
          ),
        ),
      ]),
      pw.SizedBox(height: 12),
      for (final s in sections) ...[
        pw.Table(
          border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
          columnWidths: const {
            0: pw.FlexColumnWidth(),
            1: pw.FixedColumnWidth(48),
            2: pw.FixedColumnWidth(44),
            3: pw.FixedColumnWidth(70),
            4: pw.FixedColumnWidth(78),
          },
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: _head), children: [
              cell(tx(tr(s), fs: 10, bold: true)),
              cell(tx(tr('Qté'), fs: 8, bold: true), align: right),
              cell(tx(tr('Unité'), fs: 8, bold: true)),
              cell(tx(tr('Prix unitaire'), fs: 8, bold: true), align: right),
              cell(tx(tr('Total HT'), fs: 8, bold: true), align: right),
            ]),
            for (final l in kept.where((l) => l.section == s))
              pw.TableRow(children: [
                cell(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  tx(tr(l.name), bold: true),
                  if (l.detail.isNotEmpty) tx(trParts(l.detail), fs: 7.5, color: _grey),
                ])),
                cell(tx(quoteQty(l.qty)), align: right),
                cell(tx(tr(l.unit))),
                cell(tx(l.unpriced ? tr('à chiffrer') : money(l.unitPrice)), align: right),
                cell(tx(l.unpriced ? '-' : money(l.total)), align: right),
              ]),
            pw.TableRow(children: [
              cell(tx(trp('Sous-total {0}', [tr(s)]), bold: true)),
              cell(pw.SizedBox()),
              cell(pw.SizedBox()),
              cell(pw.SizedBox()),
              cell(tx(money(q.sectionTotal(s)), bold: true), align: right),
            ]),
          ],
        ),
        pw.SizedBox(height: 8),
      ],
      pw.SizedBox(height: 4),
      pw.Row(children: [
        pw.Spacer(),
        pw.SizedBox(
          width: 250,
          child: pw.Table(
            border: pw.TableBorder.all(width: 0.6, color: PdfColors.grey700),
            columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FixedColumnWidth(100)},
            children: [
              totalRow(tr('Total HT'), '${money(q.subtotal)} MAD'),
              if (q.discount > 0) ...[
                totalRow(trp('Remise {0} %', [quoteQty(q.discount)]), '- ${money(q.discountAmount)} MAD'),
                totalRow(tr('Net HT'), '${money(q.net)} MAD'),
              ],
              totalRow(trp('TVA {0} %', [quoteQty(q.vat)]), '${money(q.vatAmount)} MAD'),
              totalRow(tr('Total TTC'), '${money(q.total)} MAD', strong: true),
            ],
          ),
        ),
      ]),
      if (out.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        tx(trp('Non compris dans ce devis : {0}.', [out.map((l) => tr(l.name)).toSet().join(', ')]), fs: 8, color: _grey),
      ],
      if (q.unpriced > 0) ...[
        pw.SizedBox(height: 4),
        tx(trp('{0} ligne(s) restent à chiffrer.', [q.unpriced]), fs: 8, color: _grey),
      ],
      if (!validated) ...[
        pw.SizedBox(height: 4),
        tx(tr('Devis provisoire : les prix peuvent encore changer avant validation.'), fs: 8, color: _grey),
      ],
      pw.SizedBox(height: 28),
      pw.Row(children: [
        pw.Expanded(child: tx(tr('Signature du client (bon pour accord)'), fs: 8.5)),
        pw.Expanded(child: tx(tr('Cachet et signature'), fs: 8.5, align: pw.TextAlign.right)),
      ]),
    ],
  ));
  return doc.save();
}
