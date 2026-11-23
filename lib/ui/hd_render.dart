// Rendu HD : choix de la qualité, avancement, image avant de l'enregistrer.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'i18n.dart';
import 'kx_choices.dart';
import 'theme.dart';
import 'view3d.dart';
import 'web_io.dart';

/// Qualités : largeur, hauteur, passes.
const hdQualities = <String, (String, int, int, int)>{
  'rapide': ('Rapide', 1600, 1000, 48),
  'belle': ('Belle', 2400, 1500, 120),
  'max': ('Très fine', 3200, 2000, 256),
};

Uint8List? pngOf(String? dataUrl) => dataUrl == null || !dataUrl.contains(',') ? null : base64Decode(dataUrl.split(',').last);

/// Lance un rendu HD de la vue affichée et attend l'image (null : impossible ou arrêté).
Future<Uint8List?> renderHd(String quality, {void Function(double k)? onProgress}) async {
  final (_, w, h, n) = hdQualities[quality]!;
  if (!await startHdRender(w, h, n)) return null;
  for (;;) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final raw = await hdRenderState();
    if (raw == null) return null;
    final s = jsonDecode(raw) as Map<String, dynamic>;
    onProgress?.call(((s['k'] as num?) ?? 0) / (((s['n'] as num?) ?? 1) == 0 ? 1 : (s['n'] as num)));
    if (s['running'] != true) return pngOf(s['url'] as String?);
  }
}

/// Fiche de présentation : la vue complète en grand, les deux autres dessous, sur fond blanc.
Future<Uint8List> composeSheet(List<Uint8List> shots, {int width = 2400, int height = 1800, String title = ''}) async {
  final images = <ui.Image>[];
  for (final b in shots) {
    final c = await ui.instantiateImageCodec(b);
    images.add((await c.getNextFrame()).image);
  }
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final W = width.toDouble(), H = height.toDouble();
  c.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()..color = Colors.white);
  final pad = W * 0.03, head = title.isEmpty ? 0.0 : H * 0.05;
  if (title.isNotEmpty) {
    final tp = TextPainter(text: TextSpan(text: title, style: TextStyle(color: const Color(0xFF111827), fontSize: H * 0.028, fontWeight: FontWeight.w700)), textDirection: TextDirection.ltr)..layout(maxWidth: W - 2 * pad);
    tp.paint(c, Offset(pad, pad * 0.6));
  }
  void contain(ui.Image im, Rect r) {
    final k = [r.width / im.width, r.height / im.height].reduce((a, b) => a < b ? a : b);
    final dst = Rect.fromCenter(center: r.center, width: im.width * k, height: im.height * k);
    c.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.high);
  }

  final heroH = (H - head) * 0.6, subY = head + heroH + pad;
  contain(images.first, Rect.fromLTWH(pad, head + pad * 0.4, W - 2 * pad, heroH));
  final subW = (W - 3 * pad) / 2;
  for (var i = 1; i < images.length && i < 3; i++) {
    contain(images[i], Rect.fromLTWH(pad + (i - 1) * (subW + pad), subY, subW, H - subY - pad));
  }
  final out = await rec.endRecording().toImage(width, height);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Fenêtre du rendu HD.
Future<void> showHdRender(BuildContext context, AppState state, void Function(String) onMessage) async {
  var quality = 'belle';
  double? k;
  Uint8List? png;
  var failed = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      final t = Theme.of(ctx).textTheme;
      final busy = k != null && png == null && !failed;
      Future<void> go() async {
        setD(() {
          k = 0;
          png = null;
          failed = false;
        });
        final img = await renderHd(quality, onProgress: (v) {
          if (ctx.mounted) setD(() => k = v);
        });
        if (ctx.mounted) {
          setD(() {
            png = img;
            failed = img == null;
            k = img == null ? null : 1;
          });
        }
      }

      return AlertDialog(
        key: const ValueKey('hd_dialog'),
        title: Text(tr('Rendu HD')),
        content: SizedBox(
          width: 760,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('La vue 3D affichée, avec une vraie lumière : ombres douces, coins sombres naturels, contours nets.'), style: t.bodySmall),
            const SizedBox(height: Tokens.s3),
            KxChoices<String>(
              key: const ValueKey('hd_quality'),
              segments: [for (final e in hdQualities.entries) ButtonSegment(value: e.key, label: Text('${tr(e.value.$1)} · ${e.value.$2} × ${e.value.$3}'))],
              selected: {quality},
              onSelectionChanged: busy ? null : (v) => setD(() => quality = v.first),
            ),
            const SizedBox(height: Tokens.s3),
            if (busy) ...[LinearProgressIndicator(value: k), const SizedBox(height: 6), Text(trp('{0} %', [((k ?? 0) * 100).round()]), style: t.labelMedium)],
            if (failed) Text(tr('Image impossible : ouvrez la vue 3D.'), style: t.bodyMedium?.copyWith(color: Theme.of(ctx).colorScheme.error)),
            if (png != null) ClipRRect(borderRadius: BorderRadius.circular(10), child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 420), child: Image.memory(png!, fit: BoxFit.contain))),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () {
                stopHdRender();
                Navigator.pop(ctx);
              },
              child: Text(tr(png == null ? 'Annuler' : 'Fermer'))),
          if (png != null)
            FilledButton.icon(
              key: const ValueKey('hd_save'),
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(tr('Enregistrer l’image')),
              onPressed: () async {
                await saveImages([('${state.project.name}_rendu_HD.png', png!)]);
                onMessage(tr('Image enregistrée'));
                if (ctx.mounted) Navigator.pop(ctx);
              },
            )
          else
            FilledButton.icon(key: const ValueKey('hd_go'), icon: const Icon(Icons.auto_awesome, size: 18), label: Text(tr('Lancer le rendu')), onPressed: busy ? null : go),
        ],
      );
    }),
  );
}
