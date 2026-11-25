// Vue 3D de l'app native (iPad) : le moteur three.js de la version web, dans une WKWebView,
// alimentée par le serveur interne (local_server.dart). Flutter envoie la scène et les images,
// la vue renvoie les gestes (choisir, glisser un meuble, double toucher pour ouvrir).
//
// Hors iPad/iPhone/Android (tests sur PC) : pas de WebView, la vue 3D dessinée par Flutter est utilisée.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_state.dart';
import 'local_server.dart';
import 'scene_export.dart';
import 'textures.dart';
import 'package:path_provider/path_provider.dart';

import 'web_io_native.dart' show nativeIoEnabled, downloadBytes;

/// Vraie 3D (three.js) disponible : sur appareil seulement.
bool get webgl3dAvailable => nativeIoEnabled;
WebViewController? _live; // vue 3D affichée

/// Rendu HD de la vue affichée : démarre, avancement (JSON), arrêt.
Future<bool> startHdRender(int w, int h, int n) async {
  if (_live == null) return false;
  await _live!.runJavaScript('window.kitchen3d.hdStart($w, $h, $n)');
  return true;
}

Future<String?> hdRenderState() async {
  final r = await _live?.runJavaScriptReturningResult('window.kitchen3d.hdState()');
  if (r == null) return null;
  final s = '$r';
  return s.startsWith('"') ? jsonDecode(s) as String : s; // Android renvoie la chaîne entre guillemets
}

Future<void> stopHdRender() async => _live?.runJavaScript('window.kitchen3d.hdStop()');

String _jsString(Object? r) {
  final s = '$r';
  return s.startsWith('"') ? jsonDecode(s) as String : s; // Android renvoie la chaîne entre guillemets
}

// Réalité augmentée dans l'app native : la vue 3D (WebView) prépare le paquet USDZ comme dans Safari,
// puis le menu Partager d'iPadOS l'envoie à Kitchinox AR (ou l'enregistre dans Fichiers).
bool get arQuickLookAvailable => false;

Future<String?> prepareArPackage(String optionsJson) async {
  final c = _live;
  if (c == null) return null;
  try {
    await c.runJavaScript('window.__arStats = ""; window.kitchen3d.arPrepare(${jsonEncode(optionsJson)})'
        '.then((s) => { window.__arStats = s; }).catch((e) => { window.__arStats = "ERR " + e; });');
    for (var i = 0; i < 600; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final s = _jsString(await c.runJavaScriptReturningResult('window.__arStats || ""'));
      if (s.startsWith('ERR')) return null;
      if (s.isNotEmpty) return s;
    }
  } catch (_) {}
  return null;
}

const _arChannel = MethodChannel('kitchinox/ar');

/// Paquet préparé par la vue 3D, récupéré par le serveur interne ; avec les cotes de la pièce (« 3600x3000 »).
Future<(Uint8List, String)?> _arBytes() async {
  final c = _live;
  if (c == null) return null;
  try {
    final size = _jsString(await c.runJavaScriptReturningResult('window.kitchen3d.arRoomSize()'));
    final waiting = LocalServer.instance.nextArUpload();
    await c.runJavaScript('window.kitchen3d.arUpload()');
    return (await waiting.timeout(const Duration(seconds: 90)), size);
  } catch (_) {
    return null;
  }
}

/// Menu Partager : enregistrer le .usdz dans Fichiers ou l'ouvrir ailleurs.
Future<bool> _shareAr(String name) async {
  final p = await _arBytes();
  if (p == null) return false;
  final (bytes, size) = p;
  final base = name.trim().isEmpty ? 'Cuisine' : name.trim();
  downloadBytes('$base${size.isEmpty ? '' : '_${size}mm'}.usdz', bytes, mime: 'model/vnd.usdz+zip');
  return true;
}

bool openArPackage() {
  if (_live == null) return false;
  unawaited(_shareAr('Kitchinox'));
  return true;
}

/// Le scan de la pièce est-il possible ici (app iPad avec LiDAR, iOS 18) ?
Future<bool> arScanAvailable() async {
  if (!nativeIoEnabled) return false;
  try {
    return await _arChannel.invokeMethod<bool>('supported') ?? false;
  } catch (_) {
    return false;
  }
}

/// Ouvre le scan de la pièce dans kitchinox (plein écran natif) avec le paquet préparé.
Future<bool> sendArToApp(String name) async {
  final p = await _arBytes();
  if (p == null) return false;
  final (bytes, size) = p;
  try {
    final f = File('${(await getTemporaryDirectory()).path}/kitchinox_ar.usdz');
    await f.writeAsBytes(bytes, flush: true);
    final dims = size.split('x').map(double.tryParse).toList();
    return await _arChannel.invokeMethod<bool>('open', {
          'path': f.path,
          'name': name.trim().isEmpty ? 'Cuisine' : name.trim(),
          if (dims.length == 2 && dims[0] != null && dims[1] != null) 'w': dims[0],
          if (dims.length == 2 && dims[0] != null && dims[1] != null) 'd': dims[1],
        }) ??
        false;
  } catch (_) {
    return false;
  }
}

/// Image de la vue 3D affichée (Data URL PNG), ou null si elle n'est pas ouverte.
Future<String?> getWeb3dSnapshotPng() async {
  try {
    final r = await _live?.runJavaScriptReturningResult('window.kitchen3d.capturePng() || ""').timeout(const Duration(seconds: 5));
    final s = r == null ? '' : '$r'.replaceAll('"', ''); // Android renvoie la chaîne entre guillemets
    return s.isEmpty ? null : s;
  } catch (_) {
    return null;
  }
}

class Kitchen3dView extends StatefulWidget {
  final AppState state;
  const Kitchen3dView({super.key, required this.state});
  @override
  State<Kitchen3dView> createState() => _Kitchen3dViewState();
}

class _Kitchen3dViewState extends State<Kitchen3dView> {
  final _exporter = SceneExporter();
  WebViewController? _c;
  bool _ready = false, _busy = false, _dirty = false;
  int _n = 0;
  final _pending = <int, List<String>>{}; // mise à jour → fichiers à libérer quand la vue les a lus

  AppState get st => widget.state;

  @override
  void initState() {
    super.initState();
    st.addListener(_schedule);
    TextureBank.instance.addListener(_schedule);
    unawaited(_init());
  }

  @override
  void dispose() {
    if (identical(_live, _c)) _live = null;
    st.removeListener(_schedule);
    TextureBank.instance.removeListener(_schedule);
    for (final files in _pending.values) {
      files.forEach(LocalServer.instance.remove);
    }
    super.dispose();
  }

  Future<void> _init() async {
    final base = await LocalServer.instance.start();
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFEEF1F3))
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (err) {
          debugPrint('3D web resource error: ${err.description}');
        },
        onPageFinished: (_) {
          if (mounted && _ready) _schedule();
        },
      ))
      ..setOnConsoleMessage((cm) {
        debugPrint('3D console [${cm.level.name}]: ${cm.message}');
      })
      ..addJavaScriptChannel('Bridge', onMessageReceived: (m) => _onMessage(m.message));
    if (mounted) setState(() => _c = c);
    _live = c;
    await c.loadRequest(Uri.parse('$base/index.html'));
    if (mounted && _ready) _schedule();
  }

  /// Un menu ou une fenêtre est ouvert par-dessus : le geste ne concerne pas la 3D.
  bool get _covered => mounted && !(ModalRoute.of(context)?.isCurrent ?? true);

  void _onMessage(String raw) {
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final a = (m['a'] as List?) ?? const [];
    final u = a.isEmpty || a[0] == null ? null : '${a[0]}';
    switch (m['h']) {
      case 'ready':
        _ready = true;
        _schedule();
      case 'done':
        final files = _pending.remove(a.isEmpty ? -1 : (a[0] as num).toInt());
        files?.forEach(LocalServer.instance.remove);
      case 'error':
        // la mise à jour a échoué : ses images et sa scène ne seront jamais lues, on les libère
        final failed = _pending.remove(a.isEmpty || a[0] is! num ? -1 : (a[0] as num).toInt());
        failed?.forEach(LocalServer.instance.remove);
        debugPrint('3D : ${a.length > 1 ? a[1] : u}');
        if (mounted && _ready) {
          _dirty = true;
          _schedule();
        }
      case 'pick':
        if (_covered) return;
        if (u != null && u.startsWith('obj:')) {
          st.selectObject(u.substring(4));
          return;
        }
        st.select(u);
        if (u == null) st.selectObject(null);
      case 'dbl':
        if (_covered || u == null) return;
        if (u.startsWith('obj:')) {
          st.selectObject(u.substring(4));
          return;
        }
        st.select(u);
        st.togglePart(u, a.length > 1 ? (a[1] as num).toInt() : -1, a.length > 2 ? (a[2] as num).toInt() : 0);
      case 'dragStart':
        if (_covered || u == null) return;
        st.select(u);
        st.beginDrag();
      case 'drag':
        if (_covered || u == null || a.length < 3) return;
        st.dragTo(u, s: (a[1] as num).toDouble(), z: (a[2] as num).toDouble());
      case 'sel':
        final r = a.length < 4 || (a[0] as num) < 0 ? null : Rect.fromLTRB((a[0] as num).toDouble(), (a[1] as num).toDouble(), (a[2] as num).toDouble(), (a[3] as num).toDouble());
        st.selRect3dNotifier.value = r; // les boutons flottants seuls se redessinent
      case 'dragEnd':
        st.endDrag();
    }
  }

  void _schedule() {
    if (!_ready) return;
    if (_busy) {
      _dirty = true;
      return;
    }
    unawaited(_update());
  }

  Future<void> _update() async {
    _busy = true;
    try {
      do {
        _dirty = false;
        final json = await _exporter.build(st);
        final c = _c;
        if (c == null || !mounted) break;
        final id = ++_n;
        final files = <String>[];
        final imgs = <Map<String, Object>>[];
        for (final img in _exporter.takeNewImages()) {
          final path = 'mem/img/$id/${imgs.length}';
          LocalServer.instance.put(path, img.rgba);
          files.add(path);
          imgs.add({'key': img.key, 'w': img.width, 'h': img.height, 'url': '/$path'});
        }
        final scenePath = 'mem/scene/$id.json';
        LocalServer.instance.put(scenePath, Uint8List.fromList(utf8.encode(jsonEncode(json))));
        files.add(scenePath);
        _pending[id] = files;
        await c.runJavaScript('window.kitchen3dNative.update($id, ${jsonEncode(imgs)}, "/$scenePath")');
      } while (_dirty && mounted);
    } catch (e) {
      debugPrint('3D : $e');
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return const ColoredBox(color: Color(0xFFEEF1F3));
    return WebViewWidget(
      controller: c,
      // la 3D garde ses gestes (tourner, zoomer, glisser un meuble)
      gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
    );
  }
}
