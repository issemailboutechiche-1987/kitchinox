// Étiquettes des chutes (50 x 30 mm) : numéro, code QR, matière, cotes, sens du fil et projet d'origine.
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../engine/engine.dart';
import 'i18n.dart';
import 'pdf_fonts.dart';

String _t(String s) => s.replaceAll('–', '-').replaceAll('’', "'").replaceAll('…', '...');

Future<Uint8List> buildStockLabelsPdf(List<StockPiece> pieces) async {
  const format = PdfPageFormat(50 * PdfPageFormat.mm, 30 * PdfPageFormat.mm, marginAll: 2 * PdfPageFormat.mm);
  final doc = pw.Document(theme: await pdfTheme(), title: 'Stock');
  for (final p in pieces) {
    doc.addPage(pw.Page(
      pageFormat: format,
      build: (ctx) => pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: p.qr, width: 20 * PdfPageFormat.mm, height: 20 * PdfPageFormat.mm),
        pw.SizedBox(width: 2 * PdfPageFormat.mm),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.center, children: [
            pw.Text(p.id, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text('${p.length} × ${p.width}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text(_t('${tr(p.material)} · ${p.thickness} mm'), style: const pw.TextStyle(fontSize: 6.5), maxLines: 2),
            if (p.offcut) pw.Text(_t(trp('Fil : {0} mm', [p.length])), style: const pw.TextStyle(fontSize: 6)),
            if (p.place.isNotEmpty) pw.Text(_t(p.place), style: const pw.TextStyle(fontSize: 6), maxLines: 1),
            if (p.origin.isNotEmpty) pw.Text(_t(p.origin), style: const pw.TextStyle(fontSize: 5.5), maxLines: 1),
          ]),
        ),
      ]),
    ));
  }
  return doc.save();
}
