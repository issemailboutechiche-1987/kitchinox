// Aperçu d'un PDF dans l'application avant de l'enregistrer : pages affichées en images, zoom au doigt,
// puis « Enregistrer le PDF » ou « Fermer ».
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import 'i18n.dart';
import 'theme.dart';
import 'web_io.dart';

/// Pages d'un PDF en images (remplaçable dans les tests, où il n'y a pas de moteur PDF).
Stream<ui.Image> Function(Uint8List bytes, double dpi) pdfPageImages = (bytes, dpi) async* {
  await for (final page in Printing.raster(bytes, dpi: dpi)) {
    yield await page.toImage();
  }
};

/// Montre [bytes] ; renvoie vrai si l'utilisateur a choisi d'enregistrer ([onSave] est alors appelé).
/// [storeAs] : nom sous lequel le PDF est gardé dans Documents quand on l'enregistre.
Future<bool> showPdfPreview(BuildContext context, {required String title, required Uint8List bytes, required VoidCallback onSave, String? storeAs}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PdfPreviewDialog(title: title, bytes: bytes),
  );
  if (saved == true) {
    if (storeAs != null) await docPut(storeAs, bytes);
    onSave();
  }
  return saved == true;
}

class _PdfPreviewDialog extends StatefulWidget {
  final String title;
  final Uint8List bytes;
  const _PdfPreviewDialog({required this.title, required this.bytes});
  @override
  State<_PdfPreviewDialog> createState() => _PdfPreviewDialogState();
}

class _PdfPreviewDialogState extends State<_PdfPreviewDialog> {
  final _pages = <ui.Image>[];
  StreamSubscription<ui.Image>? _sub;
  bool _done = false;
  double _zoom = 1;
  final _h = ScrollController();
  final _touches = <int, Offset>{};
  double? _pinchStart, _zoomStart;

  void _setZoom(double z) => setState(() => _zoom = z.clamp(0.5, 4.0));

  /// Ctrl / Cmd + molette : zoom ; la molette seule fait défiler la liste.
  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final k = HardwareKeyboard.instance;
    if (!(k.isControlPressed || k.isMetaPressed)) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) => _setZoom(_zoom * ((ev as PointerScrollEvent).scrollDelta.dy < 0 ? 1.12 : 1 / 1.12)));
  }

  /// Deux doigts qui s'écartent ou se rapprochent : zoom.
  void _pinch(PointerMoveEvent e) {
    if (!_touches.containsKey(e.pointer)) return;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length != 2) return;
    final d = (_touches.values.first - _touches.values.last).distance;
    if (_pinchStart == null) {
      _pinchStart = d;
      _zoomStart = _zoom;
    } else if (_pinchStart! > 10) {
      _setZoom(_zoomStart! * d / _pinchStart!);
    }
  }

  void _endTouch(int p) {
    _touches.remove(p);
    if (_touches.length < 2) _pinchStart = null;
  }
  Object? _error;

  @override
  void initState() {
    super.initState();
    _sub = pdfPageImages(widget.bytes, 110).listen(
      (img) => setState(() => _pages.add(img)),
      onError: (Object e) => setState(() => _error = e),
      onDone: () => setState(() => _done = true),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _h.dispose();
    for (final p in _pages) {
      p.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      key: const ValueKey('pdf_preview'),
      insetPadding: const EdgeInsets.all(Tokens.s4),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s3, Tokens.s3, Tokens.s3),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    _error != null
                        ? tr('Aperçu impossible sur cet appareil : le PDF peut quand même être enregistré.')
                        : _done
                            ? trp('{0} page(s) · {1} Ko', [_pages.length, widget.bytes.length ~/ 1024])
                            : trp('Préparation de l’aperçu… {0} page(s)', [_pages.length]),
                    style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ]),
              ),
              IconButton(key: const ValueKey('pdf_zoom_out'), tooltip: tr('Zoom arrière'), onPressed: () => _setZoom(_zoom / 1.25), icon: const Icon(Icons.zoom_out)),
              Text('${(_zoom * 100).round()} %', style: t.labelLarge),
              IconButton(key: const ValueKey('pdf_zoom_in'), tooltip: tr('Zoom avant'), onPressed: () => _setZoom(_zoom * 1.25), icon: const Icon(Icons.zoom_in)),
              const SizedBox(width: Tokens.s3),
              TextButton(key: const ValueKey('pdf_close'), onPressed: () => Navigator.of(context).pop(false), child: Text(tr('Fermer'))),
              const SizedBox(width: Tokens.s2),
              FilledButton.icon(
                key: const ValueKey('pdf_save'),
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.download_outlined),
                label: Text(tr('Enregistrer le PDF')),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              child: _pages.isEmpty
                  ? Center(
                      child: _error != null || _done
                          ? Icon(Icons.picture_as_pdf_outlined, size: 72, color: scheme.outline)
                          : const CircularProgressIndicator(),
                    )
                  : LayoutBuilder(builder: (context, c) {
                      // la molette fait défiler ; Ctrl (ou Cmd) + molette, les boutons ou deux doigts zooment
                      final pageW = 1100.0 * _zoom;
                      final width = math.max(c.maxWidth, pageW + 2 * Tokens.s4);
                      return Listener(
                        onPointerDown: (e) => _touches[e.pointer] = e.localPosition,
                        onPointerMove: _pinch,
                        onPointerUp: (e) => _endTouch(e.pointer),
                        onPointerCancel: (e) => _endTouch(e.pointer),
                        child: Scrollbar(
                          controller: _h,
                          child: SingleChildScrollView(
                            controller: _h,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: width,
                              height: c.maxHeight,
                              child: ListView.builder(
                                key: const ValueKey('pdf_pages'),
                                padding: const EdgeInsets.all(Tokens.s4),
                                itemCount: _pages.length,
                                itemBuilder: (_, i) {
                                  final img = _pages[i];
                                  return Listener(
                                    onPointerSignal: _wheel,
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: Tokens.s4),
                                      child: Center(
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(maxWidth: pageW),
                                          child: AspectRatio(
                                            aspectRatio: img.width / img.height,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8)]),
                                              child: RawImage(image: img, fit: BoxFit.contain),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
            ),
          ),
        ]),
      ),
    );
  }
}
