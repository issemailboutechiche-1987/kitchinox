// Polices des PDF : Helvetica (intégrée) pour le latin ; en arabe, Noto Sans Arabic (licence OFL,
// assets/fonts/noto_arabic) prend le relais pour chaque caractère arabe, et la page se lit de droite à gauche.
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_settings.dart';
import 'i18n.dart';

/// Le document en cours est en arabe.
bool get pdfArabic => (langOverride ?? AppSettings.instance.lang) == AppLang.ar;

/// Sens de lecture des pages (null : gauche à droite, valeur par défaut).
pw.TextDirection? get pdfDirection => pdfArabic ? pw.TextDirection.rtl : null;

pw.Font? _arabic, _arabicBold;

/// Thème du document : police arabe en relais si besoin (null : thème par défaut).
Future<pw.ThemeData?> pdfTheme() async {
  if (!pdfArabic) return null;
  _arabic ??= pw.Font.ttf(await rootBundle.load('assets/fonts/noto_arabic/NotoSansArabic-Regular.ttf'));
  _arabicBold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/noto_arabic/NotoSansArabic-Bold.ttf'));
  return pw.ThemeData.withFont(
    base: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    fontFallback: [_arabic!, _arabicBold!],
  );
}
