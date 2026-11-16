// Vue 3D de l'app native (iPad) : le moteur three.js de la version web, dans une WKWebView,
// alimentée par le serveur interne (local_server.dart). Flutter envoie la scène et les images,
// la vue renvoie les gestes (choisir, glisser un meuble, double toucher pour ouvrir).
//
// Hors iPad/iPhone/Android (tests sur PC) : pas de WebView, la vue 3D dessinée par Flutter est utilisée.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_state.dart';
import 'local_server.dart';
import 'scene_export.dart';
import 'textures.dart';
import 'web_io_native.dart' show nativeIoEnabled;

/// Vraie 3D (three.js) disponible : sur appareil seulement.
bool get webgl3dAvailable => nativeIoEnabled;

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
        st.toggleOpen(u);
      case 'dragStart':
        if (_covered || u == null) return;
        st.select(u);
        st.beginDrag();
      case 'drag':
        if (_covered || u == null || a.length < 3) return;
        st.dragTo(u, s: (a[1] as num).toDouble(), z: (a[2] as num).toDouble());
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
