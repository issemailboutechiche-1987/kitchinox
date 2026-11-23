// Génération du PDF des étiquettes d'atelier et QR Code (format 50 x 30 mm paysage).
// Reproduit fidèlement le document étiquettes atelier (202 pages pour 201 pièces) :
// Page 1 : Grand QR Code projet (KXD1|1176|Cuisine_MDF||201) + Nom projet + Nombre de pièces + N° Projet.
// Pages 2 à N : Une étiquette par pièce physique (Désignation meuble, cotes L × l mm, Code 128 avec numéro sous les barres).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../engine/engine.dart';
import 'app_settings.dart';
import 'app_state.dart';
import 'i18n.dart';
import 'pdf_fonts.dart';
import 'tech_drawings.dart';

String _clean(String s) => s
    .replaceAll('–', '-')
    .replaceAll('’', "'")
    .replaceAll('²', '2')
    .replaceAll('…', '...')
    .replaceAll(' ', ' ');

/// Numéro de projet des étiquettes (4 chiffres) : la fin du n° du plan d'exécution, sinon tiré du nom.
String labelProjectId(Project p) {
  final digitsOnly = (AppSettings.instance.numberFor(p, DocKind.exec) ?? '').replaceAll(RegExp(r'\D'), '');
  return digitsOnly.length >= 4 ? digitsOnly.substring(digitsOnly.length - 4) : (p.name.hashCode.abs() % 9000 + 1000).toString();
}

/// Étiquettes de quelques pièces du fichier d'atelier (même format et même code que le PDF complet) :
/// l'opérateur imprime celle de la pièce qu'il vient de couper.
Future<Uint8List> buildPieceLabelsPdf(List<WorkshopPiece> pieces) async {
  const labelFormat = PdfPageFormat(50 * PdfPageFormat.mm, 30 * PdfPageFormat.mm, marginAll: 2 * PdfPageFormat.mm);
  final doc = pw.Document(theme: await pdfTheme(), title: 'Étiquettes');
  for (final p in pieces) {
    doc.addPage(pw.Page(
      pageFormat: labelFormat,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: pw.Text(_clean('${p.name} ${p.cabinet}'), style: const pw.TextStyle(fontSize: 7), maxLines: 1)),
            pw.SizedBox(width: 2),
            pw.Text('${p.copy}/${p.copies}', style: const pw.TextStyle(fontSize: 7)),
          ]),
          pw.Text('${p.length} × ${p.width} mm', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.Expanded(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: p.code,
              drawText: true,
              textStyle: const pw.TextStyle(fontSize: 6),
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ],
      ),
    ));
  }
  return doc.save();
}

/// Construit le PDF d'étiquettes d'atelier (50 x 30 mm paysage, marge 2 mm).
Future<Uint8List> buildLabelsPdf(AppState state, {void Function(double, String)? onProgress}) async {
  final p = state.project;
  final e = state.engine;
  final cs = p.cut;
  final reps = repereNumbers(e);
  final parts = cutList(e, cs, reps);
  final totalPartCount = parts.fold(0, (sum, pt) => sum + pt.qty);

  final projId = labelProjectId(p);

  // Format étiquette standard 50 x 30 mm paysage avec marge 2 mm
  const labelFormat = PdfPageFormat(50 * PdfPageFormat.mm, 30 * PdfPageFormat.mm, marginAll: 2 * PdfPageFormat.mm);
  final theme = await pdfTheme();
  final doc = pw.Document(theme: theme, title: 'Étiquettes - ${p.name}');

  // ---- PAGE 1 : QR CODE PROJET
  onProgress?.call(0.05, tr('Génération du QR code projet…'));
  final safeProj = p.name.length > 25 ? p.name.substring(0, 25) : p.name;
  final safeClient = p.client.name.length > 20 ? p.client.name.substring(0, 20) : p.client.name;
  final qrData = projectQr(projId, safeProj, safeClient, totalPartCount);

  doc.addPage(
    pw.Page(
      pageFormat: labelFormat,
      build: (ctx) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: qrData,
            width: 26 * PdfPageFormat.mm,
            height: 26 * PdfPageFormat.mm,
          ),
          pw.SizedBox(width: 2 * PdfPageFormat.mm),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  _clean(p.name),
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                  maxLines: 2,
                ),
                pw.SizedBox(height: 1 * PdfPageFormat.mm),
                pw.Text(
                  _clean('$totalPartCount pièces'),
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 1 * PdfPageFormat.mm),
                pw.Text(
                  _clean('Projet $projId'),
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey800),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  // ---- PAGES 2 à N : UNE ÉTIQUETTE PAR PIÈCE PHYSIQUE
  final labelItems = <({CutPart part, int partNum, int copyIndex, int totalCopies})>[];
  for (var i = 0; i < parts.length; i++) {
    final pt = parts[i];
    final pNum = i + 1;
    for (var c = 0; c < pt.qty; c++) {
      labelItems.add((part: pt, partNum: pNum, copyIndex: c, totalCopies: pt.qty));
    }
  }

  final totalLabels = labelItems.length;
  for (var i = 0; i < totalLabels; i++) {
    if (i % 25 == 0) {
      onProgress?.call(0.1 + 0.8 * (i / math.max(1, totalLabels)), trp('Étiquette {0} sur {1}…', [i + 1, totalLabels]));
    }
    final item = labelItems[i];
    final barcodeValue = labelCode(projId, item.partNum, item.copyIndex + 1);

    doc.addPage(
      pw.Page(
        pageFormat: labelFormat,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            // Ligne 1 : Désignation meuble (gauche) + Exemplaire (droite)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    _clean('${item.part.name} ${item.part.cabinet}'),
                    style: const pw.TextStyle(fontSize: 7),
                    maxLines: 1,
                  ),
                ),
                pw.SizedBox(width: 2),
                pw.Text(
                  '${item.copyIndex + 1}/${item.totalCopies}',
                  style: const pw.TextStyle(fontSize: 7),
                ),
              ],
            ),
            // Ligne 2 : Dimensions en grand et gras
            pw.Text(
              '${item.part.length} × ${item.part.width} mm',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            // Ligne 3 : Code-barres Code 128 avec numéro sous le code
            pw.Expanded(
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: barcodeValue,
                drawText: true,
                textStyle: const pw.TextStyle(fontSize: 6),
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ],
        ),
      ),
    );
  }

  onProgress?.call(0.95, tr('Assemblage du PDF…'));
  final bytes = await doc.save();
  onProgress?.call(1.0, tr('Terminé'));
  return bytes;
}
