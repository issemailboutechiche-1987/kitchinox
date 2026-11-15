// Traduction de l'interface : le texte français sert de clé ; anglais et arabe dans i18n_dict.dart.
// Un texte sans traduction reste en français (jamais de clé vide à l'écran).
import 'app_settings.dart';
import 'i18n_dict.dart';

/// Texte [fr] dans la langue choisie.
/// Langue imposée le temps d'un document (PDF en arabe sans police arabe → français).
AppLang? langOverride;

/// Langue des PDF : celle choisie pour les documents, sinon celle de l'interface (l'arabe a sa police, pdf_fonts.dart).
AppLang get pdfLang => AppSettings.instance.docLang ?? AppSettings.instance.lang;

/// Noms de projet créés par l'application : seuls ceux-là se traduisent, jamais un nom saisi par l'utilisateur.
const _defaultNames = {'Cuisine', 'Dressing', 'Salle de bain', 'Meuble TV', 'Intérieur', 'Projet'};
String trName(String name) => _defaultNames.contains(name) ? tr(name) : name;

/// Texte composé de fragments séparés par « · » (détail d'une ligne de devis) : chaque fragment est traduit.
String trParts(String s) => s.isEmpty ? s : s.split(' · ').map((x) => tr(x)).join(' · ');

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

/// Texte au pluriel selon la valeur [count] :
/// ex. trpPlural(count, 'élément', 'éléments', zero: 'aucun élément')
String trPlural(int count, String one, String many, {String? zero}) {
  final l = langOverride ?? AppSettings.instance.lang;
  if (count == 0 && zero != null) return tr(zero);
  if (l == AppLang.ar) {
    // Pluriel arabe : 0 (zéro), 1 (singulier), 2 (duel), 3-10 (pluriel), 11-99 (singulier accusatif)
    if (count == 1) return tr(one);
    if (count == 2) return '${tr(one)}ان';
    return tr(many);
  }
  return count == 1 ? tr(one) : tr(many);
}

/// Texte avec détection de clé manquante en mode debug
String tr(String fr) {
  final l = langOverride ?? AppSettings.instance.lang;
  if (l == AppLang.fr) return fr;
  final dict = l == AppLang.en ? enDict : arDict;
  final translated = dict[fr];
  return translated ?? fr;
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
