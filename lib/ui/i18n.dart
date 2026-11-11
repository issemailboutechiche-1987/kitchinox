// Traduction de l'interface : le texte français sert de clé ; anglais et arabe dans i18n_dict.dart.
// Un texte sans traduction reste en français (jamais de clé vide à l'écran).
import 'app_settings.dart';
import 'i18n_dict.dart';

/// Texte [fr] dans la langue choisie.
/// Langue imposée le temps d'un document (PDF en arabe sans police arabe → français).
AppLang? langOverride;

/// Langue des PDF : celle de l'interface.
AppLang get pdfLang => AppSettings.instance.lang; // l'arabe a sa police (pdf_fonts.dart)

/// Exécute [build] (génération d'un PDF) dans la langue des PDF.
Future<T> inPdfLanguage<T>(Future<T> Function() build) async {
  final before = langOverride;
  langOverride = pdfLang;
  try {
    return await build();
  } finally {
    langOverride = before;
  }
}

String tr(String fr) {
  final l = langOverride ?? AppSettings.instance.lang;
  if (l == AppLang.fr) return fr;
  return (l == AppLang.en ? enDict : arDict)[fr] ?? fr;
}

/// Texte avec valeurs : trf('{n} chiffres', {'n': 4}).
String trf(String fr, Map<String, Object?> args) {
  var s = tr(fr);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// Texte avec valeurs numérotées : trp('Évier à {0} m', [d]).
String trp(String fr, List<Object?> args) {
  var s = tr(fr);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
