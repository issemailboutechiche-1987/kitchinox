// Navigateur : débit dans un Web Worker (web/nest_worker.js, compilé depuis tool/nest_worker.dart).
// Le fil de l'interface reste libre : animations, glisser-déposer et 3D continuent pendant le calcul.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../engine/engine.dart';

web.Worker? _worker;
var _broken = false;
var _id = 0;
final _waiting = <int, (Completer<CutPlan>, List<CutPart>, CutSettings)>{};

web.Worker? _start() {
  if (_worker != null || _broken) return _worker;
  try {
    final w = web.Worker('nest_worker.js'.toJS);
    w.onmessage = ((web.MessageEvent e) {
      final j = jsonDecode((e.data as JSString).toDart) as Map<String, dynamic>;
      final job = _waiting.remove(j['id'] as int);
      if (job == null) return;
      final (done, parts, cs) = job;
      if (j['error'] != null) {
        done.completeError(StateError('${j['error']}'));
      } else {
        done.complete(nestFromResponse(j, parts, cs));
      }
    }).toJS;
    w.onerror = ((web.Event _) {
      // worker absent ou en échec : on calcule sur place (comme avant), sans bloquer les demandes en cours
      _broken = true;
      _worker = null;
      final pending = [..._waiting.values];
      _waiting.clear();
      for (final (done, parts, cs) in pending) {
        if (!done.isCompleted) done.complete(nest(parts, cs));
      }
    }).toJS;
    _worker = w;
  } catch (_) {
    _broken = true;
  }
  return _worker;
}

/// Débit calculé dans le Web Worker ; même résultat que [nest]. Sans worker : calcul sur place.
Future<CutPlan> nestInBackground(List<CutPart> parts, CutSettings cs) {
  final w = _start();
  if (w == null) return Future(() => nest(parts, cs));
  final id = ++_id;
  final done = Completer<CutPlan>();
  _waiting[id] = (done, parts, cs);
  w.postMessage(nestRequest(id, parts, cs).toJS);
  return done.future;
}

bool get backgroundNestAvailable => !_broken;

/// Tas JavaScript utilisé (octets) : Chrome et Edge seulement (performance.memory) ; null ailleurs.
int? currentMemoryBytes() {
  final mem = web.window.performance.getProperty<JSObject?>('memory'.toJS);
  if (mem == null) return null;
  final used = mem.getProperty<JSNumber?>('usedJSHeapSize'.toJS);
  return used?.toDartInt;
}

Map<String, Object?> platformDescription() => {
      'navigateur': web.window.navigator.userAgent,
      'coeurs': web.window.navigator.hardwareConcurrency,
      'ecran': '${web.window.screen.width}x${web.window.screen.height} @${web.window.devicePixelRatio}',
      'worker_debit': backgroundNestAvailable,
    };
