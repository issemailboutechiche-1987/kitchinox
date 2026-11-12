// Fichiers et sauvegarde de l'app native (iPad) :
// - ouvrir : sélecteur de fichiers d'iPadOS (Fichiers, iCloud Drive, AirDrop reçu...) ;
// - « télécharger » (PDF, SketchCut, projet) : menu Partager (Enregistrer dans Fichiers, AirDrop, Mail...) ;
// - sauvegarde automatique : un fichier dans l'app, gardé d'une ouverture à l'autre.
// Sur PC (tests) : rien n'est activé, le stockage reste en mémoire comme avant.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PickedFile {
  final String name;
  final Uint8List bytes;
  PickedFile(this.name, this.bytes);
}

/// Vrai sur iPad / iPhone / Android, une fois [initPlatformIo] appelé.
bool nativeIoEnabled = false;

/// Tests : simule un stockage plein.
bool storeFull = false;

/// Appelé si l'écriture de la session sur l'appareil échoue (stockage plein...) : l'app prévient l'utilisateur.
void Function(Object error)? onStoreFailure;

final _store = <String, String>{};
File? _file;
Timer? _flush;

/// Prépare les fichiers et la sauvegarde (avant de relire la session).
Future<void> initPlatformIo() async {
  if (!(Platform.isIOS || Platform.isAndroid)) return;
  nativeIoEnabled = true;
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  _file = File('${dir.path}/kitchinox_session.json');
  try {
    if (await _file!.exists()) {
      final m = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      for (final e in m.entries) {
        _store[e.key] = '${e.value}';
      }
    }
  } catch (_) {
    // copie illisible : on repart d'une session vide
  }
  // l'app passe en arrière-plan : on écrit tout de suite (iPadOS peut la fermer sans prévenir)
  WidgetsBinding.instance.addObserver(_Lifecycle());
}

class _Lifecycle with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _flush?.cancel();
      unawaited(_write());
    }
  }
}

String? storeGet(String key) => _store[key];

/// Vrai si la valeur a été écrite.
bool storeSet(String key, String value) {
  if (storeFull) return false;
  _store[key] = value;
  _schedule();
  return true;
}

void storeRemove(String key) {
  _store.remove(key);
  _schedule();
}

void _schedule() {
  if (_file == null) return;
  _flush?.cancel();
  _flush = Timer(const Duration(milliseconds: 400), () => unawaited(_write()));
}

Future<void> _write() async {
  final f = _file;
  if (f == null) return;
  try {
    // écriture dans un fichier temporaire puis renommage : jamais de session à moitié écrite
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(_store), flush: true);
    await tmp.rename(f.path);
  } catch (e) {
    debugPrint('sauvegarde : $e');
    onStoreFailure?.call(e);
  }
}

/// Ouvre le sélecteur de fichiers d'iPadOS. Renvoie null si l'utilisateur annule.
Future<PickedFile?> pickFile({String accept = '.sct'}) async {
  if (!nativeIoEnabled) return null;
  final files = await FilePicker.pickFiles();
  if (files.isEmpty) return null;
  final f = files.first;
  return PickedFile(f.name, await f.readAsBytes());
}

/// Fichier produit par l'app (PDF, .sct, projet) : menu Partager d'iPadOS (Enregistrer dans Fichiers...).
void downloadBytes(String name, List<int> bytes, {String mime = 'application/octet-stream'}) {
  if (!nativeIoEnabled) return;
  unawaited(_share(name, bytes, mime));
}

Future<void> _share(String name, List<int> bytes, String mime) async {
  try {
    final dir = await getTemporaryDirectory();
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final f = File('${dir.path}/$safe');
    await f.writeAsBytes(bytes, flush: true);
    // sur iPad, le menu Partager s'ouvre en bulle : il lui faut un point d'ancrage (en haut à droite, près des exports)
    final v = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = v.physicalSize / v.devicePixelRatio;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: mime, name: safe)],
      sharePositionOrigin: Rect.fromLTWH(size.width - 120, 56, 1, 1),
    ));
  } catch (e) {
    debugPrint('partage : $e');
  }
}
