// Débit calculé hors du fil de l'interface : Web Worker dans le navigateur, Isolate ailleurs.
// L'écran ne gèle jamais pendant l'optimisation des panneaux.
export 'nest_service_io.dart' if (dart.library.js_interop) 'nest_service_web.dart';
