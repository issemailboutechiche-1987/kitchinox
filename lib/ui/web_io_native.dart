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

import 'local_server.dart';

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

Directory? _kitchinoxDir;
Directory? _projectsDir;
Directory? _exportDir;
Directory? _importDir;
Directory? _pdfDir;
Directory? _scenesDir;

/// Dossier racine Kitchinox sur l'appareil
Directory? get kitchinoxDir => _kitchinoxDir;
Directory? get projectsDir => _projectsDir;
Directory? get exportDir => _exportDir;
Directory? get importDir => _importDir;

/// Prépare les fichiers, dossiers et la sauvegarde (avant de relire la session).
Future<void> initPlatformIo() async {
  if (!(Platform.isIOS || Platform.isAndroid)) return;
  nativeIoEnabled = true;

  // Création du dossier Kitchinox visible dans l'application "Fichiers" sur iPad
  try {
    final docs = await getApplicationDocumentsDirectory();
    _kitchinoxDir = Directory('${docs.path}/Kitchinox');
    _projectsDir = Directory('${_kitchinoxDir!.path}/projets');
    _exportDir = Directory('${_kitchinoxDir!.path}/export');
    _importDir = Directory('${_kitchinoxDir!.path}/import');
    _pdfDir = Directory('${_kitchinoxDir!.path}/pdf');
    _scenesDir = Directory('${_kitchinoxDir!.path}/scenes');

    // dossiers créés à la première ouverture de l'app : projets, import, export, pdf, scenes
    for (final d in [_projectsDir!, _exportDir!, _importDir!, _pdfDir!, _scenesDir!]) {
      await d.create(recursive: true);
    }
  } catch (e) {
    debugPrint('Erreur création dossiers Kitchinox: $e');
  }

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

bool _isWriting = false;
bool _writePending = false;

void _schedule() {
  if (_file == null) return;
  _flush?.cancel();
  _flush = Timer(const Duration(milliseconds: 300), () => unawaited(_write()));
}

Future<void> _write() async {
  final f = _file;
  if (f == null) return;
  if (_isWriting) {
    _writePending = true;
    return;
  }
  _isWriting = true;
  _writePending = false;

  try {
    final content = jsonEncode(_store);
    try {
      // S'assurer que le dossier parent existe
      if (!await f.parent.exists()) {
        await f.parent.create(recursive: true);
      }
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(content, flush: true);
      // Sur iPadOS / POSIX, supprimer le fichier cible avant renommage si existant
      if (await f.exists()) {
        await f.delete();
      }
      await tmp.rename(f.path);
    } catch (_) {
      // Fallback direct en cas d'erreur de renommage / verrou temporaire de fichier
      await f.writeAsString(content, flush: true);
    }
  } catch (e) {
    debugPrint('sauvegarde session : $e');
    // On ne prévient l'utilisateur que si l'erreur persiste et n'est pas un verrou transitoire
    onStoreFailure?.call(e);
  } finally {
    _isWriting = false;
    if (_writePending) {
      _writePending = false;
      unawaited(_write());
    }
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
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    // Sauvegarder automatiquement une copie dans le dossier Kitchinox approprié
    if (_kitchinoxDir != null) {
      try {
        final targetDir = _folderFor(safe);
        if (targetDir != null) {
          final localCopy = File('${targetDir.path}/$safe');
          await localCopy.writeAsBytes(bytes, flush: true);
        }
      } catch (e) {
        debugPrint('Copie locale dossier Kitchinox: $e');
      }
    }

    final dir = await getTemporaryDirectory();
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

/// Dossier Kitchinox d'un fichier selon son extension : .kin → projets, .pdf → pdf, scènes 3D → scenes,
/// le reste (CSV, Excel, .sct) → export.
Directory? _folderFor(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.kin')) return _projectsDir;
  if (n.endsWith('.pdf')) return _pdfDir;
  if (n.endsWith('.glb') || n.endsWith('.gltf') || n.endsWith('.obj') || n.endsWith('.dae') || n.endsWith('.skp')) return _scenesDir;
  return _exportDir ?? _kitchinoxDir;
}

/// Enregistre le fichier dans son dossier Kitchinox, sans rien demander (bouton Enregistrer).
/// Renvoie le chemin écrit, ou null si l'appareil n'a pas de dossier Kitchinox.
Future<String?> saveToKitchinox(String name, List<int> bytes) async {
  if (!nativeIoEnabled) return null;
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final dir = _folderFor(safe);
  if (dir == null) return null;
  final f = File('${dir.path}/$safe');
  await f.writeAsBytes(bytes, flush: true);
  return 'Kitchinox/${dir.path.split('/').last}/$safe';
}

void saveImportedAsset(String name, Uint8List bytes) {
  LocalServer.instance.put('imported/$name', bytes);
  if (_importDir != null) {
    try {
      File('${_importDir!.path}/$name').writeAsBytesSync(bytes);
    } catch (_) {}
  }
}

/// Document gardé dans le dossier « Documents » de l'app (PDF, fichier d'atelier).
class DocEntry {
  final String name;
  final int size;
  final DateTime date;
  const DocEntry(this.name, this.size, this.date);
}

final _memDocs = <String, (Uint8List, DateTime)>{};

String _safeDoc(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

/// Garde un document dans Kitchinox/pdf (le même nom remplace l'ancien).
Future<void> docPut(String name, List<int> bytes) async {
  final dir = _pdfDir;
  if (!nativeIoEnabled || dir == null) {
    _memDocs[name] = (Uint8List.fromList(bytes), DateTime.now());
    return;
  }
  await File('${dir.path}/${_safeDoc(name)}').writeAsBytes(bytes, flush: true);
}

/// Documents gardés, du plus récent au plus ancien.
Future<List<DocEntry>> docList() async {
  final dir = _pdfDir;
  if (!nativeIoEnabled || dir == null) {
    return [for (final e in _memDocs.entries) DocEntry(e.key, e.value.$1.length, e.value.$2)]..sort((a, b) => b.date.compareTo(a.date));
  }
  final out = <DocEntry>[];
  await for (final f in dir.list()) {
    if (f is! File) continue;
    final st = await f.stat();
    out.add(DocEntry(f.uri.pathSegments.last, st.size, st.modified));
  }
  return out..sort((a, b) => b.date.compareTo(a.date));
}

Future<Uint8List?> docGet(String name) async {
  final dir = _pdfDir;
  if (!nativeIoEnabled || dir == null) return _memDocs[name]?.$1;
  final f = File('${dir.path}/${_safeDoc(name)}');
  return await f.exists() ? f.readAsBytes() : null;
}

Future<void> docDelete(String name) async {
  final dir = _pdfDir;
  if (!nativeIoEnabled || dir == null) {
    _memDocs.remove(name);
    return;
  }
  final f = File('${dir.path}/${_safeDoc(name)}');
  if (await f.exists()) await f.delete();
}
