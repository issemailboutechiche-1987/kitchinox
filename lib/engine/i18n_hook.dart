/// Traduction des messages du moteur (contrôles, erreurs de pose, propositions) sans dépendre de l'interface :
/// l'application branche [translateHook] sur son dictionnaire ; sans branchement, le français reste.
library;

/// Traduction d'un texte français (modèle compris) ; identité par défaut.
String Function(String fr) translateHook = _same;

String _same(String s) => s;

/// Message [fr] traduit, valeurs insérées à la place de {0}, {1}…
/// ex. L('Évier à {0} m de l\'évacuation', [d]) → « Sink 2.1 m from the drain ».
String L(String fr, [List<Object?> args = const []]) {
  var s = translateHook(fr);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
