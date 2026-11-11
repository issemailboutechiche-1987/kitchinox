// Bureau et mobile (Windows, macOS, iOS, Android) : débit dans un Isolate (autre cœur du processeur).
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../engine/engine.dart';

var _id = 0;

/// Débit calculé dans un Isolate ; même résultat que [nest].
Future<CutPlan> nestInBackground(List<CutPart> parts, CutSettings cs) async {
  final req = nestRequest(++_id, parts, cs);
  final res = await Isolate.run(() => nestJob(req));
  return nestFromResponse(jsonDecode(res) as Map<String, dynamic>, parts, cs);
}

/// Toujours disponible hors navigateur.
bool get backgroundNestAvailable => true;

/// Mémoire du processus (octets).
int? currentMemoryBytes() => ProcessInfo.currentRss;

Map<String, Object?> platformDescription() => {
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'cpus': Platform.numberOfProcessors,
      'dart': Platform.version.split(' ').first,
    };
