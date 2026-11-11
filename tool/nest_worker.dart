// Web Worker du débit : reçoit une demande JSON, calcule le plan de découpe, renvoie le plan JSON.
// Compilation : dart compile js -O2 tool/nest_worker.dart -o web/nest_worker.js
import 'dart:convert';
import 'dart:js_interop';

import 'package:kitchen_planner/engine/cutting.dart';
import 'package:web/web.dart' as web;

@JS('self')
external web.DedicatedWorkerGlobalScope get self;

void main() {
  self.onmessage = ((web.MessageEvent e) {
    final req = (e.data as JSString).toDart;
    String res;
    try {
      res = nestJob(req);
    } catch (err) {
      final id = (jsonDecode(req) as Map<String, dynamic>)['id'];
      res = jsonEncode({'id': id, 'error': '$err'});
    }
    self.postMessage(res.toJS);
  }).toJS;
}
