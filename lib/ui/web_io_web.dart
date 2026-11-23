// Ouverture et téléchargement de fichiers dans le navigateur (Flutter web).

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class PickedFile {
  final String name;
  final Uint8List bytes;
  PickedFile(this.name, this.bytes);
}

/// Ouvre le sélecteur de fichiers du navigateur. Renvoie null si l'utilisateur annule.
Future<PickedFile?> pickFile({String accept = '.sct'}) {
  final completer = Completer<PickedFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept;
  input.onchange = (web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      completer.complete(null);
      return;
    }
    final file = files.item(0)!;
    final reader = web.FileReader();
    reader.onload = (web.Event _) {
      final buf = (reader.result as JSArrayBuffer).toDart;
      completer.complete(PickedFile(file.name, buf.asUint8List()));
    }.toJS;
    reader.onerror = (web.Event _) {
      completer.completeError('lecture impossible : ${file.name}');
    }.toJS;
    reader.readAsArrayBuffer(file);
  }.toJS;
  input.oncancel = (web.Event _) {
    if (!completer.isCompleted) completer.complete(null);
  }.toJS;
  input.click();
  return completer.future;
}

/// Propose le fichier au téléchargement.
void downloadBytes(String name, List<int> bytes, {String mime = 'application/octet-stream'}) {
  final cleanName = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  // 'application/octet-stream' garantit que Chrome télécharge directement le fichier (.pdf, .xlsx, etc.)
  // dans le dossier Téléchargements au lieu de bloquer ou d'intercepter avec le visualiseur intégré.
  final effectiveMime = (mime == 'application/pdf') ? 'application/octet-stream' : mime;
  final blob = web.Blob([Uint8List.fromList(bytes).toJS].toJS, web.BlobPropertyBag(type: effectiveMime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = cleanName;
  web.document.body!.append(a);
  a.click();
  a.remove();
  Timer(const Duration(seconds: 60), () => web.URL.revokeObjectURL(url));
}

/// Stockage local du navigateur (survit à la fermeture de l'onglet et au rechargement de la page).
String? storeGet(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

/// Vrai si la valeur a été écrite (faux : stockage plein ou désactivé, navigation privée).
bool storeSet(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
    return true;
  } catch (_) {
    return false;
  }
}

void storeRemove(String key) {
  try {
    web.window.localStorage.removeItem(key);
  } catch (_) {}
}

/// Rien à préparer ici.
Future<void> initPlatformIo() async {}

/// Fichiers natifs (iPad) : non.
const bool nativeIoEnabled = false;

/// Sans objet ici (l'écriture est immédiate : storeSet renvoie faux en cas d'échec).
void Function(Object error)? onStoreFailure;

void saveImportedAsset(String name, Uint8List bytes) {}

/// Navigateur : pas de dossier Kitchinox, le fichier est téléchargé.
Future<String?> saveToKitchinox(String name, List<int> bytes) async {
  downloadBytes(name, bytes);
  return null;
}

/// Document gardé dans le dossier « Documents » de l'app (PDF, fichier d'atelier).
class DocEntry {
  final String name;
  final int size;
  final DateTime date;
  const DocEntry(this.name, this.size, this.date);
}

web.IDBDatabase? _idb;

Future<web.IDBDatabase> _docsDb() {
  if (_idb != null) return Future.value(_idb);
  final c = Completer<web.IDBDatabase>();
  final req = web.window.indexedDB.open('kitchinox-docs', 1);
  req.onupgradeneeded = ((web.Event _) {
    final db = req.result as web.IDBDatabase;
    if (!db.objectStoreNames.contains('meta')) db.createObjectStore('meta');
    if (!db.objectStoreNames.contains('data')) db.createObjectStore('data');
  }).toJS;
  req.onsuccess = ((web.Event _) => c.complete(_idb = req.result as web.IDBDatabase)).toJS;
  req.onerror = ((web.Event _) => c.completeError('stockage des documents indisponible')).toJS;
  return c.future;
}

Future<JSAny?> _await(web.IDBRequest req) {
  final c = Completer<JSAny?>();
  req.onsuccess = ((web.Event _) => c.complete(req.result)).toJS;
  req.onerror = ((web.Event _) => c.completeError('stockage des documents : échec')).toJS;
  return c.future;
}

/// Garde un document (le même nom remplace l'ancien).
Future<void> docPut(String name, List<int> bytes) async {
  final db = await _docsDb();
  final tx = db.transaction(['meta', 'data'].map((s) => s.toJS).toList().toJS, 'readwrite');
  final meta = JSObject()
    ..setProperty('name'.toJS, name.toJS)
    ..setProperty('size'.toJS, bytes.length.toJS)
    ..setProperty('date'.toJS, DateTime.now().millisecondsSinceEpoch.toJS);
  tx.objectStore('data').put(Uint8List.fromList(bytes).toJS, name.toJS);
  await _await(tx.objectStore('meta').put(meta, name.toJS));
}

/// Documents gardés, du plus récent au plus ancien.
Future<List<DocEntry>> docList() async {
  try {
    final db = await _docsDb();
    final all = await _await(db.transaction('meta'.toJS, 'readonly').objectStore('meta').getAll());
    final out = <DocEntry>[];
    for (final m in (all as JSArray<JSObject>).toDart) {
      out.add(DocEntry(
        (m.getProperty('name'.toJS) as JSString).toDart,
        (m.getProperty('size'.toJS) as JSNumber).toDartInt,
        DateTime.fromMillisecondsSinceEpoch((m.getProperty('date'.toJS) as JSNumber).toDartInt),
      ));
    }
    return out..sort((a, b) => b.date.compareTo(a.date));
  } catch (_) {
    return const [];
  }
}

Future<Uint8List?> docGet(String name) async {
  final db = await _docsDb();
  final v = await _await(db.transaction('data'.toJS, 'readonly').objectStore('data').get(name.toJS));
  return v == null ? null : (v as JSUint8Array).toDart;
}

Future<void> docDelete(String name) async {
  final db = await _docsDb();
  final tx = db.transaction(['meta', 'data'].map((s) => s.toJS).toList().toJS, 'readwrite');
  tx.objectStore('data').delete(name.toJS);
  await _await(tx.objectStore('meta').delete(name.toJS));
}

/// Images (rendus, présentation) : sur iPad et téléphone, le menu Partager du navigateur
/// (« Enregistrer l'image » les met dans Photos) ; ailleurs, téléchargement.
/// À appeler juste après le toucher de l'utilisateur (le navigateur l'exige pour partager).
Future<bool> saveImages(List<(String, List<int>)> images) async {
  if (images.isEmpty) return false;
  try {
    final files = [
      for (final (name, bytes) in images)
        web.File([Uint8List.fromList(bytes).toJS].toJS, name, web.FilePropertyBag(type: 'image/png')),
    ];
    final data = web.ShareData(files: files.toJS);
    final nav = web.window.navigator;
    final touch = nav.maxTouchPoints > 0;
    if (touch && nav.canShare(data)) {
      await nav.share(data).toDart;
      return true;
    }
  } catch (_) {
    // partage refusé ou annulé : on télécharge
  }
  for (final (name, bytes) in images) {
    downloadBytes(name, bytes, mime: 'image/png');
  }
  return true;
}
