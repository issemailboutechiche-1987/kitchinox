// Version hors navigateur (tests) : pas de sélecteur de fichiers ni de téléchargement.

import 'dart:typed_data';

class PickedFile {
  final String name;
  final Uint8List bytes;
  PickedFile(this.name, this.bytes);
}

Future<PickedFile?> pickFile({String accept = '.sct'}) async => null;

void downloadBytes(String name, List<int> bytes, {String mime = 'application/octet-stream'}) {}

/// Stockage local (tests : en mémoire).
final _store = <String, String>{};
String? storeGet(String key) => _store[key];
/// Vrai si la valeur a été écrite.
bool storeSet(String key, String value) {
  if (storeFull) return false;
  _store[key] = value;
  return true;
}

/// Tests : simule un stockage plein.
bool storeFull = false;
void storeRemove(String key) => _store.remove(key);

/// Rien à préparer ici.
Future<void> initPlatformIo() async {}

/// Fichiers natifs (iPad) : non.
const bool nativeIoEnabled = false;
