// Aperçu d'un PDF dans l'application avant de l'enregistrer : pages affichées en images, zoom au doigt,
// puis « Enregistrer le PDF » ou « Fermer ».
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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
                  : InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(Tokens.s4),
                        itemCount: _pages.length,
                        itemBuilder: (_, i) {
                          final img = _pages[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: Tokens.s4),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 1100),
                                child: AspectRatio(
                                  aspectRatio: img.width / img.height,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8)]),
                                    child: RawImage(image: img, fit: BoxFit.contain),
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
        ]),
      ),
    );
  }
}
