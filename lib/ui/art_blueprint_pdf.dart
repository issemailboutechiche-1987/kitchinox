// Plan de fabrication du meuble de l'atelier (PDF A4 paysage), pour fabriquer sans autre document :
// 1. vue d'ensemble en perspective cavalière (pièces numérotées), vues de face, de dessus et de côté cotées,
//    résumé (matières, accessoires, feuilles, chant) ;
// 2. nomenclature des pièces (cotes finies, matière, chants, rainures, nombre d'usinages) ;
// 3. une fiche par pièce : dessin coté, chants plaqués, rainures, perçages avec leurs coordonnées ;
// 4. assemblage : qui se fixe sur qui et comment, ordre de montage, quincaillerie à commander.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../engine/art_machining.dart';
import '../engine/engine.dart';
import 'art_camera.dart' show V3;
import 'art_page.dart' show artColor;
import 'i18n.dart';
import 'logo.dart';
import 'pdf_fonts.dart';

const _grey = PdfColor.fromInt(0xFF555555);
const _head = PdfColor.fromInt(0xFFE6E6E6);
const _orange = PdfColor.fromInt(0xFFF26522);

String _t(String s) => s.replaceAll('–', '-').replaceAll('’', "'").replaceAll('…', '...').replaceAll(' ', ' ');
String _mm(double v) => v.round().toString();

double _lo(ArtPanel p, int a) => a == 0 ? p.x : a == 1 ? p.y : p.z;
double _hi(ArtPanel p, int a) => a == 0 ? p.right : a == 1 ? p.top : p.back;
double _sz(ArtPanel p, int a) => _hi(p, a) - _lo(p, a);

/// Repère d'une pièce dans sa fiche : u = sa longueur, v = sa largeur, t = son épaisseur.
(int, int, int) _frame(ArtPanel p) {
  final t = thicknessAxis(p);
  final ins = [for (var k = 0; k < 3; k++) if (k != t) k];
  final u = _sz(p, ins[0]) >= _sz(p, ins[1]) ? ins[0] : ins[1];
  return (u, ins.firstWhere((k) => k != u), t);
}

PdfColor _pc(Color c) => PdfColor.fromInt(c.toARGB32());

/// Figure vectorielle qui prend toute la place disponible.
pw.Widget _fill(void Function(PdfGraphics, PdfPoint) painter) =>
    pw.LayoutBuilder(builder: (ctx, c) => pw.CustomPaint(size: PdfPoint(c!.maxWidth, c.maxHeight), painter: painter));

Future<Uint8List> buildArtBlueprint(ArtProject art, CutSettings cs, {required String projectName, ClientInfo? client, String? number, DateTime? now}) async {
  final date = now ?? DateTime.now();
  final doc = pw.Document(theme: await pdfTheme(), title: _t('Plan de fabrication - ${art.name}'), author: 'kitchinox');
  final font = PdfFont.helvetica(doc.document), bold = PdfFont.helveticaBold(doc.document);
  final logo = await LogoShape.svgText();
  final panels = art.panels;
  final ids = {for (var i = 0; i < panels.length; i++) panels[i].id: 'P${i + 1}'};
  final m = computeMachiningElements(panels, fittings: art.fittings, jointCuts: art.jointCuts, jointFits: art.jointFits);
  final plan = nest(art.cutParts(), cs);
  final hardware = art.hardware();
  final b = art.bounds;
  final x0 = panels.isEmpty ? 0.0 : panels.map((p) => p.x).reduce(math.min), x1 = panels.isEmpty ? 0.0 : panels.map((p) => p.right).reduce(math.max);
  final y0 = panels.isEmpty ? 0.0 : panels.map((p) => p.y).reduce(math.min), y1 = panels.isEmpty ? 0.0 : panels.map((p) => p.top).reduce(math.max);
  final z0 = panels.isEmpty ? 0.0 : panels.map((p) => p.z).reduce(math.min), z1 = panels.isEmpty ? 0.0 : panels.map((p) => p.back).reduce(math.max);
  assert(b != null || panels.isEmpty);
  final dateStr = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  pw.Widget tx(String s, {double fs = 9, bool strong = false, PdfColor? color, pw.TextAlign? align}) =>
      pw.Text(_t(s), textAlign: align, style: pw.TextStyle(fontSize: fs, fontWeight: strong ? pw.FontWeight.bold : null, color: color));
  pw.Widget cell(String s, {bool strong = false, double fs = 8, pw.Alignment align = pw.Alignment.centerLeft}) =>
      pw.Container(alignment: align, padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2), child: tx(s, fs: fs, strong: strong));
  pw.Widget header(pw.Context ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.only(bottom: 4),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1, color: _orange))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          if (logo != null) pw.SizedBox(height: 22, child: pw.SvgImage(svg: logo)),
          pw.SizedBox(width: 10),
          pw.Expanded(
              child: tx('${tr('PLAN DE FABRICATION')} · ${art.name == 'Création libre' ? projectName : art.name}', fs: 12, strong: true)),
          tx([
            if (number != null) trp('N° {0}', [number]),
            if (client != null && client.label.isNotEmpty) trp('Client : {0}', [client.label]),
            dateStr,
            '${ctx.pageNumber} / ${ctx.pagesCount}',
          ].join('   '), fs: 8, color: _grey),
        ]),
      );

  // ------------------------------------------------------------------ dessins
  void str(PdfGraphics g, String s, double x, double y, double fs, {bool strong = false, PdfColor color = PdfColors.black, bool center = true}) {
    final f = strong ? bold : font;
    final w = f.stringMetrics(_t(s)).advanceWidth * fs;
    g
      ..setFillColor(color)
      ..drawString(f, fs, _t(s), center ? x - w / 2 : x, y - fs * 0.35);
  }

  /// Ligne de cote entre a et b (repère PDF), texte au milieu, décalée de [off].
  void dim(PdfGraphics g, double ax, double ay, double bx, double by, String label, {double off = 10}) {
    final dx = bx - ax, dy = by - ay, l = math.sqrt(dx * dx + dy * dy);
    if (l < 1) return;
    final nx = -dy / l * off, ny = dx / l * off;
    g
      ..setStrokeColor(_grey)
      ..setLineWidth(0.5)
      ..moveTo(ax, ay)
      ..lineTo(ax + nx, ay + ny)
      ..moveTo(bx, by)
      ..lineTo(bx + nx, by + ny)
      ..moveTo(ax + nx, ay + ny)
      ..lineTo(bx + nx, by + ny)
      ..strokePath();
    for (final (px, py, sx, sy) in [(ax + nx, ay + ny, 1.0, 1.0), (bx + nx, by + ny, -1.0, -1.0)]) {
      g
        ..moveTo(px, py)
        ..lineTo(px + (dx / l * 4 + dy / l * 1.6) * sx, py + (dy / l * 4 - dx / l * 1.6) * sy)
        ..lineTo(px + (dx / l * 4 - dy / l * 1.6) * sx, py + (dy / l * 4 + dx / l * 1.6) * sy)
        ..closePath()
        ..setFillColor(_grey)
        ..fillPath();
    }
    str(g, label, (ax + bx) / 2 + nx * 1.7, (ay + by) / 2 + ny * 1.7, 7, color: _grey);
  }

  /// Perspective cavalière : face avant vraie grandeur, profondeur fuyant en haut à droite (× 0,5 à 45°).
  void cavalier(PdfGraphics g, PdfPoint size) {
    if (panels.isEmpty) return;
    const k = 0.5 * 0.7071;
    final wMax = (x1 - x0) + (z1 - z0) * k, hMax = (y1 - y0) + (z1 - z0) * k;
    final s = math.min((size.x - 40) / wMax, (size.y - 40) / hMax);
    final ox = (size.x - wMax * s) / 2, oy = (size.y - hMax * s) / 2;
    (double, double) pr(double x, double y, double z) => (ox + ((x - x0) + (z - z0) * k) * s, oy + ((y - y0) + (z - z0) * k) * s);
    // du fond vers l'avant, de bas en haut : les pièces de devant recouvrent celles de derrière
    final order = [...panels]..sort((a, c) {
        final d = (c.z + c.d / 2).compareTo(a.z + a.d / 2);
        if (d != 0) return d;
        return (a.y + a.h / 2).compareTo(c.y + c.h / 2);
      });
    void poly(List<(double, double)> pts, PdfColor fill) {
      g.moveTo(pts.first.$1, pts.first.$2);
      for (final q in pts.skip(1)) {
        g.lineTo(q.$1, q.$2);
      }
      g
        ..closePath()
        ..setFillColor(fill)
        ..fillPath();
      g.moveTo(pts.first.$1, pts.first.$2);
      for (final q in pts.skip(1)) {
        g.lineTo(q.$1, q.$2);
      }
      g
        ..closePath()
        ..setStrokeColor(const PdfColor.fromInt(0xFF333333))
        ..setLineWidth(0.4)
        ..strokePath();
    }

    for (final p in order) {
      final base = _pc(artColor(p.finish));
      PdfColor shade(double f) => PdfColor(base.red * f, base.green * f, base.blue * f);
      // dessus, côté droit, face avant
      poly([pr(p.x, p.top, p.z), pr(p.right, p.top, p.z), pr(p.right, p.top, p.back), pr(p.x, p.top, p.back)], shade(0.98));
      poly([pr(p.right, p.y, p.z), pr(p.right, p.y, p.back), pr(p.right, p.top, p.back), pr(p.right, p.top, p.z)], shade(0.78));
      poly([pr(p.x, p.y, p.z), pr(p.right, p.y, p.z), pr(p.right, p.top, p.z), pr(p.x, p.top, p.z)], shade(0.9));
    }
    for (final p in order) {
      final (cx, cy) = pr(p.x + p.w / 2, p.y + p.h / 2, p.z);
      final label = ids[p.id]!;
      final w = bold.stringMetrics(label).advanceWidth * 7 + 4;
      g
        ..setFillColor(PdfColors.white)
        ..drawRect(cx - w / 2, cy - 5, w, 10)
        ..fillPath();
      str(g, label, cx, cy, 7, strong: true, color: _orange);
    }
    // cotes hors tout
    final (ax, ay) = pr(x0, y0, z0);
    final (bx, by) = pr(x1, y0, z0);
    final (cx2, cy2) = pr(x0, y1, z0);
    final (dx2, dy2) = pr(x1, y0, z1);
    dim(g, ax, ay, bx, by, _mm(x1 - x0), off: -12);
    dim(g, ax, ay, cx2, cy2, _mm(y1 - y0), off: 12);
    dim(g, bx, by, dx2, dy2, _mm(z1 - z0), off: -10);
  }

  /// Vue orthogonale : axes (h, v) de l'espace ; [flipH] pour la vue de côté (profondeur vers la gauche).
  void ortho(PdfGraphics g, PdfPoint size, int h, int v, {bool flipH = false}) {
    if (panels.isEmpty) return;
    double lo(int a) => a == 0 ? x0 : a == 1 ? y0 : z0;
    double hi(int a) => a == 0 ? x1 : a == 1 ? y1 : z1;
    final sw = hi(h) - lo(h), sh = hi(v) - lo(v);
    final s = math.min((size.x - 30) / sw, (size.y - 30) / sh);
    final ox = (size.x - sw * s) / 2, oy = (size.y - sh * s) / 2 + 4;
    double X(double val) => flipH ? ox + (hi(h) - val) * s : ox + (val - lo(h)) * s;
    double Y(double val) => v == 2 ? oy + (hi(v) - val) * s : oy + (val - lo(v)) * s; // dessus : l'avant en bas
    for (final p in panels) {
      final xa = X(_lo(p, h)), xb = X(_hi(p, h)), ya = Y(_lo(p, v)), yb = Y(_hi(p, v));
      g
        ..setFillColor(_pc(artColor(p.finish)))
        ..drawRect(math.min(xa, xb), math.min(ya, yb), (xb - xa).abs(), (yb - ya).abs())
        ..fillPath()
        ..setStrokeColor(const PdfColor.fromInt(0xFF333333))
        ..setLineWidth(0.35)
        ..drawRect(math.min(xa, xb), math.min(ya, yb), (xb - xa).abs(), (yb - ya).abs())
        ..strokePath();
    }
    dim(g, X(lo(h)), Y(lo(v)) - 0, X(hi(h)), Y(lo(v)), _mm(sw), off: -8);
    dim(g, X(hi(h)), Y(lo(v)), X(hi(h)), Y(hi(v)), _mm(sh), off: -8);
  }

  // ------------------------------------------------------------------ page 1 : ensemble
  final mats = <String, int>{};
  for (final sh in plan.sheets) {
    mats[sh.material] = (mats[sh.material] ?? 0) + 1;
  }
  final edgeM = m.edgeByThickness;
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(22),
    textDirection: pdfDirection,
    build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      header(ctx),
      pw.Expanded(
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            flex: 3,
            child: pw.Column(children: [
              pw.Expanded(child: _fill(cavalier)),
              pw.SizedBox(
                height: 150,
                child: pw.Row(children: [
                  for (final (title, h, v, flip) in [
                    ('Face', 0, 1, false),
                    ('Dessus', 0, 2, false),
                    ('Côté droit', 2, 1, true),
                  ])
                    pw.Expanded(
                      child: pw.Column(children: [
                        tx(tr(title), fs: 8, strong: true),
                        pw.Expanded(child: _fill((g, s) => ortho(g, s, h, v, flipH: flip))),
                      ]),
                    ),
                ]),
              ),
            ]),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            flex: 2,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              tx(tr('Résumé'), fs: 11, strong: true),
              pw.SizedBox(height: 4),
              tx(trp('Encombrement : {0} × {1} × {2} mm (L × H × P)', [_mm(x1 - x0), _mm(y1 - y0), _mm(z1 - z0)])),
              tx(trp('{0} pièces · {1} feuille(s) à débiter', [panels.length, plan.sheets.length])),
              pw.SizedBox(height: 6),
              tx(tr('Matières'), strong: true),
              for (final e in mats.entries) tx('· ${e.key} : ${e.value} ${tr('feuille(s)')}', fs: 8),
              pw.SizedBox(height: 6),
              tx(tr('Chants'), strong: true),
              for (final e in edgeM.entries) tx(trp('· chant {0} mm : {1} m', [e.key == e.key.roundToDouble() ? e.key.round() : e.key, e.value.toStringAsFixed(2)]), fs: 8),
              if (m.totalGrooveMeters > 0) tx(trp('· rainures : {0} m', [m.totalGrooveMeters.toStringAsFixed(2)]), fs: 8),
              pw.SizedBox(height: 6),
              tx(tr('Accessoires'), strong: true),
              tx('· ${tr('Assemblage')} : ${tr(art.fittings.joint.label)}', fs: 8),
              tx('· ${tr('Charnières')} : ${tr(art.fittings.hinge.label)}', fs: 8),
              tx('· ${tr('Meubles hauts')} : ${tr(art.fittings.hang.label)}', fs: 8),
              tx('· ${tr('Pieds')} : ${tr(art.fittings.foot.label)}', fs: 8),
              tx('· ${tr('Entre caissons')} : ${tr(art.fittings.link.label)}', fs: 8),
              pw.SizedBox(height: 6),
              tx(tr('Repères'), strong: true),
              tx(tr('Cotes en mm, finies (chants compris). P1, P2… : numéros des pièces, repris dans la nomenclature et les fiches.'), fs: 7.5, color: _grey),
              tx(tr('Origine de chaque fiche : coin bas gauche de la pièce vue de sa face A (face vers l’avant, le haut ou la droite du meuble).'),
                  fs: 7.5, color: _grey),
            ]),
          ),
        ]),
      ),
    ]),
  ));

  // ------------------------------------------------------------------ page 2 : nomenclature
  int holesOf(String id) => m.elements
      .where((e) =>
          (e.panelId == id || e.partnerPanelId == id) &&
          const {MachiningKind.dowel, MachiningKind.screw, MachiningKind.hingeCup, MachiningKind.hingePlate, MachiningKind.shelfHole, MachiningKind.connector, MachiningKind.hanger}
              .contains(e.kind))
      .length;
  String edgesOf(ArtPanel p) {
    final w = m.work[p.id];
    if (p.edgeLong > 0 || p.edgeShort > 0) return '${p.edgeLong}L ${p.edgeShort}C · ${p.edgeThickness} mm';
    if (w == null || w.edgeLong + w.edgeShort == 0) return '-';
    return '${w.edgeLong}L ${w.edgeShort}C · ${w.edgeThickness == w.edgeThickness.roundToDouble() ? w.edgeThickness.round() : w.edgeThickness} mm';
  }

  String grooveOf(ArtPanel p) {
    final w = m.work[p.id];
    if (w == null || w.grooveLong + w.grooveShort == 0) return p.hasGroove ? tr('oui') : '-';
    return [if (w.grooveLong > 0) tr('long'), if (w.grooveShort > 0) tr('court')].join(' + ');
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(22),
    textDirection: pdfDirection,
    header: header,
    build: (_) => [
      tx(tr('Nomenclature des pièces'), fs: 12, strong: true),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        headerDecoration: const pw.BoxDecoration(color: _head),
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 8),
        cellAlignments: {0: pw.Alignment.center, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
        headers: [for (final h in ['N°', 'Désignation', 'Longueur', 'Largeur', 'Ép.', 'Matière', 'Chants (L / C)', 'Rainure', 'Usinages', 'Coupe d’angle']) _t(tr(h))],
        data: [
          for (final p in panels)
            () {
              final (u, v, t) = _frame(p);
              final cuts = [
                for (final e in art.jointCuts.entries)
                  if (e.key.split('|').contains(p.id))
                    '${e.value == 'onglet' ? tr('onglet 45°') : tr('chanfrein')} / ${ids[e.key.split('|').firstWhere((x) => x != p.id)] ?? ''}',
              ];
              return [
                ids[p.id]!,
                _t(tr(p.role.label)),
                _mm(_sz(p, u)),
                _mm(_sz(p, v)),
                _mm(_sz(p, t)),
                _t(ArtProject.materialOf(p)),
                edgesOf(p),
                grooveOf(p),
                '${holesOf(p.id)}',
                _t(cuts.join(', ')),
              ];
            }(),
        ],
      ),
      pw.SizedBox(height: 6),
      tx(tr('L / C : nombre de chants plaqués sur les longueurs et sur les largeurs. Usinages : perçages et pièces de quincaillerie de la fiche.'), fs: 7.5, color: _grey),
    ],
  ));

  // ------------------------------------------------------------------ fiches pièces
  /// Usinages d'une pièce dans son repère : (désignation, x, y, Ø, profondeur, face).
  List<(String, double, double, double, double, String)> holes(ArtPanel p) {
    final (u, v, t) = _frame(p);
    final out = <(String, double, double, double, double, String)>[];
    String face(V3 at) {
      final pt = at[t];
      if ((pt - _hi(p, t)).abs() < 1) return tr('face A');
      if ((pt - _lo(p, t)).abs() < 1) return tr('face B');
      return tr('chant');
    }

    for (final e in m.elements) {
      final mine = e.panelId == p.id, edge = e.partnerPanelId == p.id;
      if (!mine && !edge) continue;
      final at = e.position;
      final x = at[u] - _lo(p, u), y = at[v] - _lo(p, v);
      switch (e.kind) {
        case MachiningKind.dowel when mine:
          out.add((tr(e.item == 'Lamelle bois n° 20' ? 'Rainure de lamelle' : 'Tourillon (face)'), x, y, e.diameter, e.item == 'Lamelle bois n° 20' ? 10 : 13, face(at)));
        case MachiningKind.dowel:
          out.add((tr(e.item == 'Lamelle bois n° 20' ? 'Rainure de lamelle' : 'Tourillon (chant)'), x, y, e.diameter, e.item == 'Lamelle bois n° 20' ? 10 : 22, tr('chant')));
        case MachiningKind.screw when mine:
          out.add((tr('Vis : passage'), x, y, e.diameter, _sz(p, t), face(at)));
        case MachiningKind.screw:
          out.add((tr('Vis : avant-trou'), x, y, e.diameter == 7 ? 5 : math.max(3, e.diameter - 2), e.length - _sz(p, t) + 2, tr('chant')));
        case MachiningKind.hingeCup when mine && e.diameter > 0:
          out.add((tr('Boîtier de charnière'), x, y, e.diameter, e.length, tr('face intérieure')));
        case MachiningKind.hingePlate when mine:
          out.add((tr('Embase de charnière'), x, y, 5, 12, face(at)));
        case MachiningKind.shelfHole when mine:
          out.add((tr('Trou de taquet'), x, y, 5, 12, face(at)));
        case MachiningKind.connector:
          out.add((tr('Vis de jonction'), x, y, 5, _sz(p, t), face(at)));
        case MachiningKind.handle when mine:
          out.add((tr('Poignée : 2 trous Ø4 traversants'), x, y, 4, _sz(p, t), tr('face avant')));
        case MachiningKind.drill when mine:
          out.add((tr('Perçage'), x, y, e.diameter, e.length, face(at)));
        case MachiningKind.hanger when mine:
          out.add((tr('Suspension'), x, y, 0, 0, face(at)));
        default:
          break;
      }
    }
    out.sort((a, c) => a.$1 != c.$1 ? a.$1.compareTo(c.$1) : (a.$2 != c.$2 ? a.$2.compareTo(c.$2) : a.$3.compareTo(c.$3)));
    return out;
  }

  void partDrawing(PdfGraphics g, PdfPoint size, ArtPanel p) {
    final (u, v, _) = _frame(p);
    final L = _sz(p, u), W = _sz(p, v);
    final s = math.min((size.x - 50) / L, (size.y - 40) / W);
    final ox = 28.0, oy = 22.0;
    double X(double val) => ox + val * s;
    double Y(double val) => oy + val * s;
    g
      ..setFillColor(_pc(artColor(p.finish)))
      ..drawRect(X(0), Y(0), L * s, W * s)
      ..fillPath()
      ..setStrokeColor(PdfColors.black)
      ..setLineWidth(0.8)
      ..drawRect(X(0), Y(0), L * s, W * s)
      ..strokePath();
    // chants (orange épais) et rainures (gris)
    for (final e in m.elements.where((e) => e.panelId == p.id && (e.kind == MachiningKind.edge || e.kind == MachiningKind.groove))) {
      final a = e.position, z = e.end;
      final ax = a[u] - _lo(p, u), ay = a[v] - _lo(p, v), bx = z[u] - _lo(p, u), by = z[v] - _lo(p, v);
      g
        ..setStrokeColor(e.kind == MachiningKind.edge ? _orange : const PdfColor.fromInt(0xFF475569))
        ..setLineWidth(e.kind == MachiningKind.edge ? 2.6 : 1.6)
        ..moveTo(X(ax), Y(ay))
        ..lineTo(X(bx), Y(by))
        ..strokePath();
    }
    // perçages
    for (final h in holes(p)) {
      final r = math.max(1.4, h.$4 * s / 2);
      g
        ..setStrokeColor(h.$6 == tr('chant') ? const PdfColor.fromInt(0xFF2563EB) : PdfColors.black)
        ..setLineWidth(0.6)
        ..drawEllipse(X(h.$2), Y(h.$3), r, r)
        ..strokePath();
    }
    dim(g, X(0), Y(0), X(L), Y(0), _mm(L), off: -9);
    dim(g, X(0), Y(0), X(0), Y(W), _mm(W), off: 9);
    str(g, ids[p.id]!, X(L / 2), Y(W / 2), 10, strong: true, color: _orange);
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(22),
    textDirection: pdfDirection,
    header: header,
    build: (_) => [
      tx(tr('Fiches des pièces'), fs: 12, strong: true),
      tx(tr('Orange : chant plaqué. Gris : rainure. Cercle noir : perçage de face ; bleu : perçage dans le chant (au bord). X le long de la longueur, Y le long de la largeur, depuis le coin bas gauche.'),
          fs: 7.5, color: _grey),
      pw.SizedBox(height: 6),
      for (final p in panels)
        () {
          final (u, v, t) = _frame(p);
          final hs = holes(p);
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6, color: _grey)),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(width: 330, height: 170, child: pw.CustomPaint(painter: (g, s) => partDrawing(g, s, p))),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  tx('${ids[p.id]} · ${tr(p.role.label)} · ${_mm(_sz(p, u))} × ${_mm(_sz(p, v))} × ${_mm(_sz(p, t))} mm', fs: 10, strong: true),
                  tx('${ArtProject.materialOf(p)} · ${tr('chants')} ${edgesOf(p)} · ${tr('rainure')} ${grooveOf(p)}${ArtProject.hasGrain(p) ? ' · ${tr('sens du fil : longueur')}' : ''}',
                      fs: 8, color: _grey),
                  pw.SizedBox(height: 4),
                  if (hs.isEmpty) tx(tr('Aucun perçage.'), fs: 8),
                  if (hs.isNotEmpty)
                    pw.Table(
                      border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey500),
                      columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1), 4: pw.FlexColumnWidth(1), 5: pw.FlexColumnWidth(1.4)},
                      children: [
                        pw.TableRow(decoration: const pw.BoxDecoration(color: _head), children: [
                          for (final h in ['Usinage', 'X', 'Y', 'Ø', 'Prof.', 'Face']) cell(tr(h), strong: true, fs: 7),
                        ]),
                        for (final h in hs.take(28))
                          pw.TableRow(children: [
                            cell(h.$1, fs: 7),
                            cell(_mm(h.$2), fs: 7, align: pw.Alignment.centerRight),
                            cell(_mm(h.$3), fs: 7, align: pw.Alignment.centerRight),
                            cell(h.$4 == 0 ? '-' : (h.$4 == h.$4.roundToDouble() ? '${h.$4.round()}' : '${h.$4}'), fs: 7, align: pw.Alignment.centerRight),
                            cell(h.$5 == 0 ? '-' : _mm(h.$5), fs: 7, align: pw.Alignment.centerRight),
                            cell(h.$6, fs: 7),
                          ]),
                      ],
                    ),
                  if (hs.length > 28) tx(trp('… et {0} autres perçages (même répartition).', [hs.length - 28]), fs: 7, color: _grey),
                ]),
              ),
            ]),
          );
        }(),
    ],
  ));

  // ------------------------------------------------------------------ assemblage
  final links = <String, (String, String, Map<String, int>)>{};
  for (final e in m.elements) {
    if (e.panelId == null || e.partnerPanelId == null) continue;
    if (!const {MachiningKind.dowel, MachiningKind.screw, MachiningKind.connector, MachiningKind.groove, MachiningKind.nail}.contains(e.kind)) continue;
    final key = '${e.panelId}|${e.partnerPanelId}';
    final cur = links[key] ?? (e.panelId!, e.partnerPanelId!, <String, int>{});
    final name = e.kind == MachiningKind.groove ? tr('fond dans rainure') : tr(e.item ?? e.kind.label);
    cur.$3[name] = (cur.$3[name] ?? 0) + 1;
    links[key] = cur;
  }
  String nm(String id) {
    final p = panels.where((q) => q.id == id).firstOrNull;
    return p == null ? id : '${ids[id]} ${tr(p.role.label)}';
  }

  final steps = [
    tr('Débiter les pièces (plan de coupe), repérer chaque pièce avec son numéro au crayon.'),
    tr('Plaquer les chants indiqués en orange sur les fiches, puis affleurer.'),
    tr('Percer selon les fiches : perçages de face, puis perçages dans les chants (gabarit de perçage conseillé). Usiner les rainures.'),
    tr('Monter le dessous sur les côtés (tourillons collés, puis vis), glisser le fond dans ses rainures, poser le dessus.'),
    tr('Poser séparations et tablettes fixes ; taquets des tablettes mobiles.'),
    tr('Vérifier l’équerrage (diagonales égales) avant que la colle prenne.'),
    tr('Pieds ou suspension, puis jonction des caissons voisins.'),
    tr('Façades : charnières et réglage du jeu (2 à 3 mm), coulisses et tiroirs, poignées.'),
  ];
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(22),
    textDirection: pdfDirection,
    header: header,
    build: (_) => [
      tx(tr('Assemblage'), fs: 12, strong: true),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        headerDecoration: const pw.BoxDecoration(color: _head),
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 8),
        headers: [_t(tr('Pièce qui porte')), _t(tr('Pièce fixée')), _t(tr('Fixation'))],
        data: [
          for (final l in links.values) [_t(nm(l.$1)), _t(nm(l.$2)), _t(l.$3.entries.map((e) => '${e.value} × ${e.key}').join(', '))],
          for (final e in art.jointCuts.entries)
            [_t(nm(e.key.split('|')[0])), _t(nm(e.key.split('|')[1])), _t(e.value == 'onglet' ? tr('onglet 45° collé + lamelles') : tr('angle chanfreiné'))],
        ],
      ),
      pw.SizedBox(height: 10),
      tx(tr('Ordre de montage'), fs: 11, strong: true),
      for (var i = 0; i < steps.length; i++) tx('${i + 1}. ${steps[i]}', fs: 9),
      pw.SizedBox(height: 10),
      tx(tr('Quincaillerie et visserie'), fs: 11, strong: true),
      pw.TableHelper.fromTextArray(
        headerDecoration: const pw.BoxDecoration(color: _head),
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 8),
        cellAlignments: {0: pw.Alignment.centerRight},
        headers: [_t(tr('Qté')), _t(tr('Désignation')), _t(tr('Usage'))],
        data: [for (final (name, usage, q) in hardware) ['$q', _t(tr(name)), _t(tr(usage))]],
      ),
    ],
  ));
  return doc.save();
}
