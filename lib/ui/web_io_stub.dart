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

/// Sans objet ici (l'écriture est immédiate : storeSet renvoie faux en cas d'échec).
void Function(Object error)? onStoreFailure;

void saveImportedAsset(String name, Uint8List bytes) {}

/// Tests : rien n'est écrit.
Future<String?> saveToKitchinox(String name, List<int> bytes) async => null;

/// Document gardé dans le dossier « Documents » de l'app (PDF, fichier d'atelier).
class DocEntry {
  final String name;
  final int size;
  final DateTime date;
  const DocEntry(this.name, this.size, this.date);
}

final _docs = <String, (Uint8List, DateTime)>{};

/// Garde un document (le même nom remplace l'ancien).
Future<void> docPut(String name, List<int> bytes) async => _docs[name] = (Uint8List.fromList(bytes), DateTime.now());

/// Documents gardés, du plus récent au plus ancien.
Future<List<DocEntry>> docList() async =>
    [for (final e in _docs.entries) DocEntry(e.key, e.value.$1.length, e.value.$2)]..sort((a, b) => b.date.compareTo(a.date));

Future<Uint8List?> docGet(String name) async => _docs[name]?.$1;

Future<void> docDelete(String name) async => _docs.remove(name);

/// Images (rendus, présentation) : enregistrées dans les Photos de l'appareil (tests : rien).
Future<bool> saveImages(List<(String, List<int>)> images) async => true;
