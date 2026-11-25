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
  external bool hdStart(int w, int h, int n);
  external String hdState();
  external void hdStop();
  external void input(bool on);
  external bool arSupported();
  external JSPromise<JSString> arPrepare(String json);
  external bool arOpen();
  external int arSize();
  external void arClear();
}

/// Réalité augmentée : l'appareil ouvre les USDZ (AR Quick Look de l'iPad / iPhone).
bool get arQuickLookAvailable {
  try {
    return _k3d?.arSupported() ?? false;
  } catch (_) {
    return false;
  }
}

/// Prépare le paquet AR de la vue 3D affichée ; statistiques en JSON, null si la vue est fermée.
Future<String?> prepareArPackage(String optionsJson) async {
  final k = _k3d;
  if (k == null) return null;
  try {
    return (await k.arPrepare(optionsJson).toDart).toDart;
  } catch (_) {
    return null;
  }
}

/// Scan de la pièce : seulement dans l'app iPad (RoomPlan n'existe pas dans Safari).
Future<bool> arScanAvailable() async => false;
Future<bool> sendArToApp(String name) async => false;

/// Ouvre le paquet préparé : à appeler directement dans le geste (onPressed), jamais après un await.
bool openArPackage() {
  try {
    return _k3d?.arOpen() ?? false;
  } catch (_) {
    return false;
  }
}


/// Capture un instantané de la vue 3D WebGL réelle (Data URL base64 PNG).
Future<String?> getWeb3dSnapshotPng() async {
  try {
    return _k3d?.capturePng();
  } catch (_) {
    return null;
  }
}

/// Rendu HD de la vue affichée : démarre, avancement (JSON), arrêt.
Future<bool> startHdRender(int w, int h, int n) async => _k3d?.hdStart(w, h, n) ?? false;
Future<String?> hdRenderState() async => _k3d?.hdState();
Future<void> stopHdRender() async => _k3d?.hdStop();

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

  /// Gestes acceptés ou non par la 3D (un panneau est sous le pointeur).
  void _input(bool on) => _k3d?.input(on);

  /// Conteneur de CETTE vue (revenir à une étape recrée la vue : l'ancien conteneur n'est plus affiché).
  web.HTMLDivElement? _host;

  @override
  void initState() {
    super.initState();
    _register();
    st.addListener(_schedule);
    TextureBank.instance.addListener(_schedule);
    _installHandlers();
    st.input3d = _input;
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
    // une nouvelle vue a pu prendre le relais (changement d'étape) : on ne débranche que la nôtre
    if (st.input3d == _input) st.input3d = null; // même méthode du même objet : égales
    st.removeListener(_schedule);
    TextureBank.instance.removeListener(_schedule);
    _retry?.cancel();
    super.dispose();
  }

  /// Un menu déroulant ou une fenêtre est ouvert par-dessus : le clic lui appartient, pas à la 3D
  /// (sur le web, il traverse jusqu'au canvas WebGL et changerait la sélection, ce qui ferme le menu).
  bool get _covered => mounted && !(ModalRoute.of(context)?.isCurrent ?? true);

  /// Geste à ignorer : fenêtre par-dessus, ou bouton / panneau posé sur la vue (le clic lui appartient aussi).
  bool get _blocked {
    if (_covered) return true;
    final t = st.overlayDown;
    return t != null && DateTime.now().difference(t) < const Duration(milliseconds: 1200);
  }

  void _installHandlers() {
    final h = JSObject();
    h.setProperty('pick'.toJS, ((JSString? uid) {
      if (_blocked) return;
      final u = uid?.toDart;
      if (u != null && u.startsWith('obj:')) {
        st.selectObject(u.substring(4));
        return;
      }
      st.select(u);
      if (u == null) st.selectObject(null);
    }).toJS);
    h.setProperty('dbl'.toJS, ((JSString uid, JSNumber? part, JSNumber? count) {
      if (_blocked) return;
      if (uid.toDart.startsWith('obj:')) {
        st.selectObject(uid.toDart.substring(4));
        return;
      }
      st.select(uid.toDart);
      st.togglePart(uid.toDart, part?.toDartInt ?? -1, count?.toDartInt ?? 0);
    }).toJS);
    h.setProperty('dragStart'.toJS, ((JSString uid) {
      if (_blocked) return;
      st.select(uid.toDart);
      st.beginDrag();
    }).toJS);
    h.setProperty('drag'.toJS, ((JSString uid, JSNumber s, JSNumber z) {
      if (_blocked) return;
      st.dragTo(uid.toDart, s: s.toDartDouble, z: z.toDartDouble);
    }).toJS);
    h.setProperty('sel'.toJS, ((JSNumber x0, JSNumber y0, JSNumber x1, JSNumber y1) {
      final r = x0.toDartDouble < 0 ? null : Rect.fromLTRB(x0.toDartDouble, y0.toDartDouble, x1.toDartDouble, y1.toDartDouble);
      st.selRect3dNotifier.value = r; // les boutons flottants seuls se redessinent
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
