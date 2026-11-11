// Vue 3D temps réel (WebGL) : implémentation navigateur, ou rien hors navigateur (tests).
export 'view3d_stub.dart' if (dart.library.js_interop) 'view3d_web.dart' if (dart.library.io) 'view3d_native.dart';
