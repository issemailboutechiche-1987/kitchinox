// Ouverture / téléchargement de fichiers : version navigateur, ou version vide pour les tests.
// navigateur : web_io_web ; iPad / Android (et tests sur PC, où rien n'est activé) : web_io_native
export 'web_io_stub.dart' if (dart.library.js_interop) 'web_io_web.dart' if (dart.library.io) 'web_io_native.dart';
