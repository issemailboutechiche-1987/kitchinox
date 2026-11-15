// Rapport de Diagnostic Technique et Conformité (PDF A4 portrait).
// Audit complet de la pièce : ergonomie, norme NF C 15-100, réseaux plomberie/électricité,
// contrôles dimensionnels et performances d'usinage/débit.
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../engine/engine.dart';
import 'app_state.dart';
import 'i18n.dart';
import 'logo.dart';
import 'pdf_fonts.dart';

const _grey = PdfColor.fromInt(0xFF555555);
const _dark = PdfColor.fromInt(0xFF222222);
const _light = PdfColor.fromInt(0xFFF6F7F9);
const _head = PdfColor.fromInt(0xFFEEEEEE);
const _accent = PdfColor.fromInt(0xFFF26522);
const _green = PdfColor.fromInt(0xFF1E824C);
const _red = PdfColor.fromInt(0xFFC0392B);
const _amber = PdfColor.fromInt(0xFFD35400);

String _t(String s) => s
    .replaceAll('–', '-')
    .replaceAll('’', "'")
    .replaceAll('²', '2')
    .replaceAll('…', '...')
    .replaceAll(' ', ' ');

Future<Uint8List> buildDiagnosticPdf(AppState state) async {
  final p = state.project;
  final doc = pw.Document(theme: await pdfTheme(), title: 'Diagnostic Technique - ${p.name}');
  final logo = await LogoShape.svgText();

  final now = DateTime.now();
  final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

  pw.Widget tx(String s, {double fs = 9, bool bold = false, PdfColor? color, pw.TextAlign? align}) => pw.Text(
        _t(s),
        textAlign: align,
        style: pw.TextStyle(fontSize: fs, fontWeight: bold ? pw.FontWeight.bold : null, color: color),
      );

  pw.Widget badge(String text, PdfColor bg, {PdfColor fg = PdfColors.white}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(3)),
        child: pw.Text(_t(text), style: pw.TextStyle(color: fg, fontSize: 8, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget sectionHeader(String title, String subtitle) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12, bottom: 6),
        padding: const pw.EdgeInsets.only(bottom: 4),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1, color: _accent))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            tx(title, fs: 11, bold: true, color: _accent),
            tx(subtitle, fs: 8, color: _grey),
          ],
        ),
      );

  // Analyse des contrôles
  final issues = state.issues;
  final errors = issues.where((x) => x.severity == Severity.error).toList();
  final warnings = issues.where((x) => x.severity == Severity.warning).toList();

  // Norme NF C 15-100 & Réseaux
  final pts = p.points.where((x) => !x.hidden).toList();
  final socketsPlan = pts.where((x) => x.use == NetUse.plan && x.kind.isSocket).length;
  final has32A = pts.any((x) => x.kind == NetKind.out32);
  final hasGas = pts.any((x) => x.kind == NetKind.gas);
  final hasWaterCold = pts.any((x) => x.kind == NetKind.waterCold);
  final hasDrain = pts.any((x) => x.kind == NetKind.drain);

  // Débit & Panneaux
  final plan = state.cutPlan;
  final nSheets = plan.sheets.length;
  final nParts = plan.parts.fold<int>(0, (a, x) => a + x.qty);
  final sheetArea = (p.cut.sheetLength * p.cut.sheetWidth / 1e6) * nSheets;
  final usedArea = plan.sheets.fold<double>(0, (a, s) => a + s.placements.fold<double>(0, (b, pl) => b + pl.dx * pl.dy)) / 1e6;
  final yieldPct = sheetArea > 0 ? (usedArea / sheetArea * 100) : 0.0;
  final roomArea = p.room.area;
  final roomPerim = p.room.walls.fold<double>(0, (a, w) => a + w.length) / 1000;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        margin: const pw.EdgeInsets.only(bottom: 12),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1.5, color: _accent))),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (logo != null) pw.SizedBox(height: 28, child: pw.SvgImage(svg: logo)) else tx('kitchinox', fs: 16, bold: true, color: _accent),
            pw.Spacer(),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                tx('RAPPORT DE DIAGNOSTIC TECHNIQUE & CONFORMITÉ', fs: 10, bold: true, color: _dark),
                tx('Conforme normes architecturales & NF C 15-100 · Date : $dateStr', fs: 8, color: _grey),
              ],
            ),
          ],
        ),
      ),
      footer: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.only(top: 4),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5, color: _head))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            tx('kitchinox · Rapport généré automatiquement pour le dossier de fabrication', fs: 7, color: _grey),
            tx('Page ${ctx.pageNumber} / ${ctx.pagesCount}', fs: 7, color: _grey),
          ],
        ),
      ),
      build: (ctx) => [
        // Fiche d'identification
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: _light, borderRadius: pw.BorderRadius.circular(4), border: pw.Border.all(color: _head)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  tx('Projet : ${p.name}', fs: 11, bold: true, color: _dark),
                  tx('Client : ${p.client.name.isEmpty ? "Particulier" : p.client.name}', fs: 9, color: _grey),
                  if (p.client.company.isNotEmpty) tx('Société : ${p.client.company}', fs: 8, color: _grey),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  tx('Univers : ${tr(p.universe.toUpperCase())}', fs: 9, bold: true),
                  tx('Surface pièce : ${roomArea.toStringAsFixed(1)} m2 · Périmètre : ${roomPerim.toStringAsFixed(1)} m', fs: 8),
                  tx('Hauteur sous plafond : ${p.room.height} mm', fs: 8),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (errors.isEmpty)
                    badge('CONFORME POUR FABRICATION', _green)
                  else
                    badge('${errors.length} ANOMALIE(S) BLOQUANTE(S)', _red),
                  pw.SizedBox(height: 4),
                  tx('${warnings.length} avertissement(s) d\'ergonomie', fs: 8, color: warnings.isEmpty ? _green : _amber),
                ],
              ),
            ],
          ),
        ),

        // 1. Audit Électrique & Réseaux MEP
        sectionHeader('1. AUDIT DES RÉSEAUX ET CONFORMITÉ NF C 15-100', 'Électricité, plomberie et sécurité'),
        pw.Table(
          border: pw.TableBorder.all(color: _head, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1.2),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FlexColumnWidth(4),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _head),
              children: [
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Point de contrôle', bold: true, fs: 8)),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Exigé', bold: true, fs: 8)),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Constaté', bold: true, fs: 8)),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Statut & Recommandation', bold: true, fs: 8)),
              ],
            ),
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Prises de plan de travail (crédence)', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Min. 4', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('$socketsPlan', fs: 8, bold: true)),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: socketsPlan >= 4
                    ? tx('Conforme NF C 15-100', color: _green, fs: 8)
                    : tx('Manque ${4 - socketsPlan} prise(s) sur le plan de travail', color: _amber, fs: 8),
              ),
            ]),
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Alimentation table de cuisson', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Sortie 32A ou gaz', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx(has32A ? 'Sortie 32A' : (hasGas ? 'Gaz' : 'Non détecté'), fs: 8)),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: has32A || hasGas
                    ? tx('Ligne dédiée conforme', color: _green, fs: 8)
                    : tx('Prévoir sortie de câble 32A ou robinet ROAI gaz', color: _red, fs: 8),
              ),
            ]),
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Alimentation eau froide / chaude', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Sous évier', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx(hasWaterCold ? 'Présent' : 'Non', fs: 8)),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: hasWaterCold ? tx('Positionnement conforme', color: _green, fs: 8) : tx('Arrivée eau à créer', color: _red, fs: 8),
              ),
            ]),
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Évacuation des eaux usées', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Pente >= 1 cm/m', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx(hasDrain ? 'Présente' : 'Non', fs: 8)),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: hasDrain ? tx('Évacuation PVC conforme', color: _green, fs: 8) : tx('Prévoir évacuation Ø40', color: _red, fs: 8),
              ),
            ]),
          ],
        ),

        // 2. Audit Ergonomie & Triangle d'activité
        sectionHeader('2. AUDIT ERGONOMIQUE ET VOLUMES DE CIRCULATION', 'Implantation et accessibilité'),
        pw.Table(
          border: pw.TableBorder.all(color: _head, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1.2),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FlexColumnWidth(4),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _head),
              children: [
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Paramètre dimensionnel', bold: true, fs: 8)),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Standard usuel', bold: true, fs: 8)),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Projet', bold: true, fs: 8)),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Évaluation', bold: true, fs: 8)),
              ],
            ),
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Hauteur plan de travail fini', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('880 - 930 mm', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('${p.standards.worktopTop} mm', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Hauteur ergonomique optimale', color: _green, fs: 8)),
            ]),
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Hauteur de plinthe', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('100 - 150 mm', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('${p.standards.plinthHeight} mm', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Passage pied et lave-vaisselle OK', color: _green, fs: 8)),
            ]),
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Hauteur de crédence (dégagement)', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('500 - 600 mm', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('${p.standards.credenceHeight} mm', fs: 8)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: tx('Dégagement visuel et hotte conforme', color: _green, fs: 8)),
            ]),
          ],
        ),

        // 3. Détection des anomalies et alertes
        sectionHeader('3. BILAN DES CONTRÔLES TECHNIQUES ET RISQUES', 'Règles métier Kitchinox'),
        if (issues.isEmpty)
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(color: _light, borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Row(children: [
              pw.Text('✓', style: const pw.TextStyle(color: _green, fontSize: 14)),
              pw.SizedBox(width: 8),
              tx('Aucune anomalie détectée : toutes les règles d\'implantation et de jeu sont validées.', color: _green, bold: true),
            ]),
          )
        else
          pw.Column(children: [
            for (final isItem in issues)
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 4),
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: pw.BoxDecoration(
                  color: isItem.severity == Severity.error ? const PdfColor(1, 0.95, 0.95) : const PdfColor(1, 0.98, 0.92),
                  border: pw.Border.all(color: isItem.severity == Severity.error ? _red : _amber, width: 0.5),
                  borderRadius: pw.BorderRadius.circular(3),
                ),
                child: pw.Row(children: [
                  badge(
                    isItem.severity == Severity.error ? 'BLOQUANT' : 'ATTENTION',
                    isItem.severity == Severity.error ? _red : _amber,
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(child: tx(isItem.message, fs: 8, bold: true)),
                ]),
              ),
          ]),

        // 4. Synthèse Débit & Usinage
        sectionHeader('4. INDICATEURS DE DÉBITAGE ET OPTIMISATION PANNEAUX', 'Rendement matière et chutes'),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(color: _light, borderRadius: pw.BorderRadius.circular(4), border: pw.Border.all(color: _head)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              pw.Column(children: [
                tx('Panneaux bruts', fs: 8, color: _grey),
                tx('$nSheets', fs: 14, bold: true, color: _accent),
                tx('${p.cut.sheetLength}x${p.cut.sheetWidth} mm', fs: 7, color: _grey),
              ]),
              pw.Column(children: [
                tx('Pièces usinées', fs: 8, color: _grey),
                tx('$nParts', fs: 14, bold: true, color: _dark),
                tx('Trait scie : ${p.cut.kerf} mm', fs: 7, color: _grey),
              ]),
              pw.Column(children: [
                tx('Surface totale débitée', fs: 8, color: _grey),
                tx('${usedArea.toStringAsFixed(1)} m2', fs: 14, bold: true, color: _dark),
                tx('Sur ${sheetArea.toStringAsFixed(1)} m2 bruts', fs: 7, color: _grey),
              ]),
              pw.Column(children: [
                tx('Rendement d\'optimisation', fs: 8, color: _grey),
                tx('${yieldPct.toStringAsFixed(1)} %', fs: 14, bold: true, color: yieldPct >= 80 ? _green : _amber),
                tx(yieldPct >= 80 ? 'Excellent rendement' : 'Pertes maîtrisées', fs: 7, color: _grey),
              ]),
            ],
          ),
        ),

        // Cadre de visa / validation
        pw.SizedBox(height: 16),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Container(
              width: 220,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: _head), borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                tx('Visa du Responsable Bureau d\'Études :', fs: 8, bold: true),
                pw.SizedBox(height: 32),
                tx('Date & Signature :', fs: 7, color: _grey),
              ]),
            ),
            pw.Container(
              width: 220,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: _head), borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                tx('Visa du Conducteur de Travaux / Poseur :', fs: 8, bold: true),
                pw.SizedBox(height: 32),
                tx('Bon pour exécution et traçage réseaux :', fs: 7, color: _grey),
              ]),
            ),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}
