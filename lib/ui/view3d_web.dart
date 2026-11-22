// Vue 3D temps réel dans le navigateur : un élément HTML hébergé par Flutter, dans lequel
// web/three_view.js (three.js) dessine la scène. Flutter envoie la scène (JSON) et les images ;
// la vue renvoie les gestes : choisir, glisser un meuble, double clic pour ouvrir / fermer.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'app_state.dart';
import 'scene_export.dart';
import 'textures.dart';

@JS('kitchen3d')
external _K3d? get _k3d;

extension type _K3d._(JSObject _) implements JSObject {
  external void mount(web.HTMLElement el);
  external void addImage(String key, int w, int h, JSUint8Array rgba);
  external void setScene(String json);
  external bool supported();
  external String? capturePng();
}

/// Capture un instantané de la vue 3D WebGL réelle (Data URL base64 PNG).
String? getWeb3dSnapshotPng() {
  try {
    return _k3d?.capturePng();
  } catch (_) {
    return null;
  }
}

bool? _supported;

/// WebGL disponible (et la vue three.js chargée ou en cours de chargement).
bool get webgl3dAvailable {
  if (_supported != null) return _supported!;
  try {
    final c = web.document.createElement('canvas') as web.HTMLCanvasElement;
    _supported = c.getContext('webgl2') != null || c.getContext('webgl') != null;
  } catch (_) {
    _supported = false;
  }
  return _supported!;
}

const _viewType = 'kitchinox-3d';
final _hosts = <int, web.HTMLDivElement>{}; // conteneur HTML de chaque vue créée (par identifiant)
bool _registered = false;

void _register() {
  if (_registered) return;
  _registered = true;
  ui_web.platformViewRegistry.registerViewFactory(_viewType, (int id) {
    final existing = _hosts[id];
    if (existing != null) return existing;
    final div = web.document.createElement('div') as web.HTMLDivElement;
    div.style
      ..width = '100%'
      ..height = '100%'
      ..position = 'relative';
    _hosts[id] = div;
    return div;
  });
}

class Kitchen3dView extends StatefulWidget {
  final AppState state;
  const Kitchen3dView({super.key, required this.state});
  @override
  State<Kitchen3dView> createState() => _Kitchen3dViewState();
}

class _Kitchen3dViewState extends State<Kitchen3dView> {
  final _exporter = SceneExporter();
  bool _busy = false, _dirty = false, _mounted = false;
  Timer? _retry;

  AppState get st => widget.state;

  /// Conteneur de CETTE vue (revenir à une étape recrée la vue : l'ancien conteneur n'est plus affiché).
  web.HTMLDivElement? _host;

  @override
  void initState() {
    super.initState();
    _register();
    st.addListener(_schedule);
    TextureBank.instance.addListener(_schedule);
    _installHandlers();
    if (_hosts.isNotEmpty) {
      _host = _hosts.values.last;
      _tryMount();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // menu ou fenêtre par-dessus : la vue 3D laisse passer la souris vers Flutter (sinon le clic
    // sur un choix du menu tombe dans la 3D et le menu se ferme)
    _host?.style.pointerEvents = _covered ? 'none' : 'auto';
  }

  @override
  void dispose() {
    _host?.style.pointerEvents = 'auto';
    st.removeListener(_schedule);
    TextureBank.instance.removeListener(_schedule);
    _retry?.cancel();
    super.dispose();
  }

  /// Un menu déroulant ou une fenêtre est ouvert par-dessus : le clic lui appartient, pas à la 3D
  /// (sur le web, il traverse jusqu'au canvas WebGL et changerait la sélection, ce qui ferme le menu).
  bool get _covered => mounted && !(ModalRoute.of(context)?.isCurrent ?? true);

  void _installHandlers() {
    final h = JSObject();
    h.setProperty('pick'.toJS, ((JSString? uid) {
      if (_covered) return;
      final u = uid?.toDart;
      if (u != null && u.startsWith('obj:')) {
        st.selectObject(u.substring(4));
        return;
      }
      st.select(u);
      if (u == null) st.selectObject(null);
    }).toJS);
    h.setProperty('dbl'.toJS, ((JSString uid) {
      if (_covered) return;
      if (uid.toDart.startsWith('obj:')) {
        st.selectObject(uid.toDart.substring(4));
        return;
      }
      st.select(uid.toDart);
      st.toggleOpen(uid.toDart);
    }).toJS);
    h.setProperty('dragStart'.toJS, ((JSString uid) {
      if (_covered) return;
      st.select(uid.toDart);
      st.beginDrag();
    }).toJS);
    h.setProperty('drag'.toJS, ((JSString uid, JSNumber s, JSNumber z) {
      if (_covered) return;
      st.dragTo(uid.toDart, s: s.toDartDouble, z: z.toDartDouble);
    }).toJS);
    h.setProperty('dragEnd'.toJS, ((JSString uid) {
      st.endDrag();
    }).toJS);
    globalContext.setProperty('kitchen3dHandlers'.toJS, h);
  }

  /// La vue three.js est un module chargé en parallèle : on attend qu'elle soit prête.
  void _tryMount() {
    if (!mounted) return;
    _host ??= _hosts.values.lastOrNull;
    final k = _k3d;
    final host = _host;
    if (k == null || host == null) {
      _retry = Timer(const Duration(milliseconds: 100), _tryMount);
      return;
    }
    k.mount(host);
    _mounted = true;
    _schedule();
  }

  void _schedule() {
    if (!_mounted) return;
    if (_busy) {
      _dirty = true;
      return;
    }
    _update();
  }

  Future<void> _update() async {
    _busy = true;
    try {
      do {
        _dirty = false;
        final json = await _exporter.build(st);
        final k = _k3d;
        if (k == null) break;
        for (final img in _exporter.takeNewImages()) {
          k.addImage(img.key, img.width, img.height, img.rgba.toJS);
        }
        k.setScene(jsonEncode(json));
      } while (_dirty && mounted);
    } catch (e) {
      debugPrint('3D : $e');
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(
        viewType: _viewType,
        onPlatformViewCreated: (id) {
          _host = _hosts[id];
          _host?.style.pointerEvents = _covered ? 'none' : 'auto';
          _tryMount();
        },
      );
}
