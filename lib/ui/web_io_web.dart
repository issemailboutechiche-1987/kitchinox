// Ouverture et téléchargement de fichiers dans le navigateur (Flutter web).

import 'dart:async';
import 'dart:js_interop';
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
  final blob = web.Blob([Uint8List.fromList(bytes).toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body!.append(a);
  a.click();
  a.remove();
  Timer(const Duration(seconds: 5), () => web.URL.revokeObjectURL(url));
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
