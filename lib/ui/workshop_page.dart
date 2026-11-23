// Atelier de découpe : les panneaux débités, chaque pièce numérotée comme son étiquette.
// L'opérateur touche la pièce qu'il vient de couper : son étiquette (code-barres) s'imprime et la pièce passe en vert.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../engine/engine.dart';
import 'i18n.dart';
import 'labels_pdf.dart';
import 'theme.dart';
import 'web_io.dart';

/// Imprime des étiquettes (remplaçable dans les tests : pas d'imprimante).
Future<void> Function(Uint8List pdf, String name) printLabels = (pdf, name) => Printing.layoutPdf(onLayout: (_) async => pdf, name: name);

/// Fichier d'atelier (.kin) : nom de fichier et octets.
String workshopFileName(WorkshopJob job) => '${job.project}_atelier.kin';
Uint8List workshopBytes(WorkshopJob job) => KinFormat.encode(jsonEncode(job.toJson()), projectName: job.project);

/// Ouvre l'atelier sur [job] (plein écran).
Future<void> openWorkshop(BuildContext context, WorkshopJob job) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkshopPage(job: job)));

class WorkshopPage extends StatefulWidget {
  final WorkshopJob job;
  const WorkshopPage({super.key, required this.job});
  @override
  State<WorkshopPage> createState() => _WorkshopPageState();
}

class _WorkshopPageState extends State<WorkshopPage> {
  int sheet = 0;
  WorkshopPiece? selected;
  bool printOnTap = true;
  String? message;

  WorkshopJob get job => widget.job;
  WorkshopSheet get current => job.sheets[sheet];

  Future<void> _print(List<WorkshopPiece> pieces) async {
    if (pieces.isEmpty) return;
    final pdf = await buildPieceLabelsPdf(pieces);
    await printLabels(pdf, pieces.length == 1 ? pieces.single.code : '${job.project}_feuille_${current.number}');
  }

  Future<void> _tap(WorkshopPiece p) async {
    setState(() {
      selected = p;
      job.done.add(p.code);
      message = trp('Pièce {0} coupée : {1}', [p.mark, p.code]);
    });
    _keep();
    if (printOnTap) await _print([p]);
  }

  void _undo(WorkshopPiece p) {
    setState(() {
      job.done.remove(p.code);
      selected = p;
      message = trp('Pièce {0} remise à couper', [p.mark]);
    });
    _keep();
  }

  Widget _info(IconData icon, Color color, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      ]);

  /// Le fichier d'atelier garde ce qui est coupé (Documents) : on peut fermer et reprendre.
  void _keep() => docPut(workshopFileName(job), workshopBytes(job));

  Future<void> _save() async {
    final bytes = workshopBytes(job);
    await docPut(workshopFileName(job), bytes);
    downloadBytes(workshopFileName(job), bytes);
    if (mounted) setState(() => message = trp('Fichier d’atelier enregistré : {0}', [workshopFileName(job)]));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final s = current;
    final doneHere = s.pieces.where((p) => job.done.contains(p.code)).length;
    return Scaffold(
      key: const ValueKey('workshop_page'),
      appBar: AppBar(
        title: Text(trp('Atelier de découpe · {0}', [job.project])),
        actions: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Imprimer au toucher'), style: t.labelLarge),
            Switch(key: const ValueKey('ws_print_on_tap'), value: printOnTap, onChanged: (v) => setState(() => printOnTap = v)),
          ]),
          TextButton.icon(
            key: const ValueKey('ws_print_sheet'),
            onPressed: () => _print(s.pieces),
            icon: const Icon(Icons.print_outlined),
            label: Text(tr('Étiquettes de la feuille')),
          ),
          const SizedBox(width: Tokens.s2),
          FilledButton.icon(key: const ValueKey('ws_save'), onPressed: _save, icon: const Icon(Icons.save_outlined), label: Text(tr('Enregistrer le fichier'))),
          const SizedBox(width: Tokens.s3),
        ],
      ),
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // feuilles et avancement
        SizedBox(
          width: 260,
          child: ListView(padding: const EdgeInsets.all(Tokens.s3), children: [
            Row(children: [
              SizedBox(width: 72, height: 72, child: CustomPaint(painter: BarcodePainter(pw.Barcode.qrCode(), job.qr))),
              const SizedBox(width: Tokens.s2),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(trp('Projet {0}', [job.projId]), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text(trp('{0} / {1} pièces coupées', [job.done.length, job.pieceCount]), style: t.bodySmall),
                ]),
              ),
            ]),
            const SizedBox(height: Tokens.s3),
            for (var i = 0; i < job.sheets.length; i++)
              () {
                final sh = job.sheets[i];
                final n = sh.pieces.where((p) => job.done.contains(p.code)).length;
                return Card(
                  margin: const EdgeInsets.only(bottom: Tokens.s2),
                  color: i == sheet ? scheme.primaryContainer : null,
                  child: ListTile(
                    key: ValueKey('ws_sheet_$i'),
                    dense: true,
                    title: Text(trp('Feuille {0}', [sh.number]), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${sh.material} · ${sh.length}×${sh.width}${sh.stockId == null ? '' : ' · ${tr('chute')} ${sh.stockId}'}\n${trp('{0} / {1} pièces', [n, sh.pieces.length])}'),
                    isThreeLine: true,
                    trailing: n == sh.pieces.length ? Icon(Icons.check_circle, color: scheme.primary) : null,
                    onTap: () => setState(() {
                      sheet = i;
                      selected = null;
                    }),
                  ),
                );
              }(),
          ]),
        ),
        const VerticalDivider(width: 1),
        // la feuille : toucher une pièce
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s3, Tokens.s4, 0),
              child: Text(
                message ?? trp('Feuille {0} · {1} · {2} / {3} pièces coupées — touchez la pièce coupée pour imprimer son étiquette', [s.number, s.material, doneHere, s.pieces.length]),
                style: t.bodyMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s2, Tokens.s4, 0),
              child: Wrap(spacing: Tokens.s4, children: [
                _info(Icons.horizontal_rule, const Color(0xFFE8711A), tr('trait orange : chant')),
                _info(Icons.more_horiz, const Color(0xFF2B6CB0), tr('tirets bleus : rainure du fond')),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Tokens.s4),
                child: LayoutBuilder(builder: (context, c) {
                  final k = (c.maxWidth / s.length).clamp(0.0, c.maxHeight / s.width);
                  final size = Size(s.length * k, s.width * k);
                  return InteractiveViewer(
                    maxScale: 6,
                    child: Center(
                      child: GestureDetector(
                        key: const ValueKey('ws_sheet_view'),
                        onTapUp: (d) {
                          final x = d.localPosition.dx / k, y = d.localPosition.dy / k;
                          final hit = s.pieces.where((p) => x >= p.x && x <= p.x + p.dx && y >= p.y && y <= p.y + p.dy).firstOrNull;
                          if (hit != null) _tap(hit);
                        },
                        onLongPressStart: (d) {
                          final x = d.localPosition.dx / k, y = d.localPosition.dy / k;
                          final hit = s.pieces.where((p) => x >= p.x && x <= p.x + p.dx && y >= p.y && y <= p.y + p.dy).firstOrNull;
                          if (hit != null) _undo(hit);
                        },
                        child: CustomPaint(size: size, painter: _SheetPainter(s, k, job.done, selected?.code, scheme)),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ]),
        ),
        // la pièce choisie : son code-barres, réimprimer
        if (selected != null)
          SizedBox(
            width: 280,
            child: Card(
              margin: const EdgeInsets.all(Tokens.s3),
              child: Padding(
                padding: const EdgeInsets.all(Tokens.s4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(trp('Pièce {0}', [selected!.mark]), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text('${selected!.name} ${selected!.cabinet}', style: t.bodyMedium),
                  const SizedBox(height: Tokens.s2),
                  Text('${selected!.length} × ${selected!.width} mm', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(trp('Exemplaire {0} / {1}', [selected!.copy, selected!.copies]), style: t.bodySmall),
                  const SizedBox(height: Tokens.s2),
                  _info(Icons.horizontal_rule, const Color(0xFFE8711A), selected!.edgeText.isEmpty ? tr('Sans chant') : trp('Chant : {0}', [selected!.edgeText])),
                  _info(Icons.more_horiz, const Color(0xFF2B6CB0), selected!.grooveText.isEmpty ? tr('Sans rainure') : trp('Rainure : {0}', [tr(selected!.grooveText)])),
                  const SizedBox(height: Tokens.s3),
                  SizedBox(height: 70, width: double.infinity, child: CustomPaint(painter: BarcodePainter(pw.Barcode.code128(), selected!.code))),
                  const SizedBox(height: 4),
                  Center(child: Text(selected!.code, style: t.labelLarge?.copyWith(letterSpacing: 2))),
                  const SizedBox(height: Tokens.s3),
                  FilledButton.icon(
                    key: const ValueKey('ws_reprint'),
                    onPressed: () => _print([selected!]),
                    icon: const Icon(Icons.print_outlined),
                    label: Text(tr('Imprimer l’étiquette')),
                  ),
                  const SizedBox(height: Tokens.s2),
                  if (job.done.contains(selected!.code))
                    OutlinedButton.icon(
                      key: const ValueKey('ws_undo'),
                      onPressed: () => _undo(selected!),
                      icon: const Icon(Icons.undo),
                      label: Text(tr('Remettre à couper')),
                    ),
                  const SizedBox(height: Tokens.s2),
                  Text(tr('Appui long sur une pièce : la remettre à couper.'), style: t.bodySmall),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _SheetPainter extends CustomPainter {
  final WorkshopSheet s;
  final double k;
  final Set<String> done;
  final String? selected;
  final ColorScheme scheme;
  _SheetPainter(this.s, this.k, this.done, this.selected, this.scheme);

  @override
  void paint(Canvas canvas, Size size) {
    final sheet = Offset.zero & size;
    canvas.drawRect(sheet, Paint()..color = const Color(0xFFE9E2D6));
    canvas.drawRect(sheet, Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF6B6259)
      ..strokeWidth = 1.5);
    for (final p in s.pieces) {
      final r = Rect.fromLTWH(p.x * k, p.y * k, p.dx * k, p.dy * k);
      final isDone = done.contains(p.code), isSel = p.code == selected;
      canvas.drawRect(r, Paint()..color = isDone ? const Color(0xFFBFE3C4) : Colors.white);
      _edgesAndGrooves(canvas, r, p);
      canvas.drawRect(r, Paint()
        ..style = PaintingStyle.stroke
        ..color = isSel ? scheme.primary : const Color(0xFF4A4F55)
        ..strokeWidth = isSel ? 3 : 1);
      final big = (r.shortestSide * 0.32).clamp(9.0, 34.0);
      final tp = TextPainter(
        text: TextSpan(children: [
          TextSpan(text: p.mark, style: TextStyle(fontSize: big, fontWeight: FontWeight.w800, color: const Color(0xFF22262A))),
          if (r.height > big * 2.2 && r.width > 50)
            TextSpan(text: '\n${p.length}×${p.width}', style: TextStyle(fontSize: big * 0.42, color: const Color(0xFF4A4F55))),
        ]),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r.width);
      if (tp.height < r.height) tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
      if (isDone) {
        final tick = TextPainter(
          text: const TextSpan(text: '✓', style: TextStyle(fontSize: 14, color: Color(0xFF2E7D32), fontWeight: FontWeight.w900)),
          textDirection: TextDirection.ltr,
        )..layout();
        tick.paint(canvas, r.topRight + Offset(-tick.width - 3, 2));
      }
    }
  }

  /// Chants : un trait orange le long de chaque chant (le 1er en bas ou à droite) ; rainure : tirets bleus.
  void _edgesAndGrooves(Canvas canvas, Rect r, WorkshopPiece p) {
    final edge = Paint()
      ..color = const Color(0xFFE8711A)
      ..strokeWidth = (r.shortestSide * 0.06).clamp(2.0, 5.0);
    final inset = edge.strokeWidth / 2 + 1;
    final across = p.lengthAcross;
    // côtés « longueur » et « largeur » du rectangle posé
    final longSides = across ? [(r.bottomLeft, r.bottomRight, const Offset(0, -1)), (r.topLeft, r.topRight, const Offset(0, 1))] : [(r.topRight, r.bottomRight, const Offset(-1, 0)), (r.topLeft, r.bottomLeft, const Offset(1, 0))];
    final shortSides = across ? [(r.topRight, r.bottomRight, const Offset(-1, 0)), (r.topLeft, r.bottomLeft, const Offset(1, 0))] : [(r.bottomLeft, r.bottomRight, const Offset(0, -1)), (r.topLeft, r.topRight, const Offset(0, 1))];
    for (final (sides, n) in [(longSides, p.edgeLong), (shortSides, p.edgeShort)]) {
      for (var i = 0; i < n.clamp(0, 2); i++) {
        final (a, b, inward) = sides[i];
        canvas.drawLine(a + inward * inset, b + inward * inset, edge);
      }
    }
    // rainure du fond : parallèle au côté, à 16 mm du bord arrière (en haut ou à gauche)
    final groove = Paint()
      ..color = const Color(0xFF2B6CB0)
      ..strokeWidth = 1.6;
    void dashed(Offset a, Offset b) {
      final len = (b - a).distance, dir = (b - a) / len;
      for (var t = 0.0; t < len; t += 9) {
        canvas.drawLine(a + dir * t, a + dir * math.min(t + 5, len), groove);
      }
    }
    final off = math.max(4.0, 16 * k);
    if (p.grooveLong > 0) {
      across ? dashed(r.topLeft + Offset(0, off), r.topRight + Offset(0, off)) : dashed(r.topLeft + Offset(off, 0), r.bottomLeft + Offset(off, 0));
    }
    if (p.grooveShort > 0) {
      across ? dashed(r.topLeft + Offset(off, 0), r.bottomLeft + Offset(off, 0)) : dashed(r.topLeft + Offset(0, off), r.topRight + Offset(0, off));
    }
  }

  @override
  bool shouldRepaint(_SheetPainter o) => true;
}

/// Code-barres ou QR dessiné à l'écran (mêmes codes que les étiquettes PDF).
class BarcodePainter extends CustomPainter {
  final pw.Barcode barcode;
  final String data;
  BarcodePainter(this.barcode, this.data);
  @override
  void paint(Canvas canvas, Size size) {
    final black = Paint()..color = Colors.black;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    try {
      for (final e in barcode.make(data, width: size.width, height: size.height, drawText: false)) {
        if (e is pw.BarcodeBar && e.black) canvas.drawRect(Rect.fromLTWH(e.left, e.top, e.width, e.height), black);
      }
    } catch (_) {}
  }

  @override
  bool shouldRepaint(BarcodePainter o) => o.data != data;
}
