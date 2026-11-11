/// Télémétrie de performance embarquée : durée de chaque calcul (débit, nesting, fichiers, contrôles),
/// mémoire, journal exportable en JSON pour le diagnostic.
///
/// ```dart
/// final plan = PerformanceProfiler.instance.measure('nesting', () => nest(parts, cs), info: {'pieces': 355});
/// final pdf = await PerformanceProfiler.instance.measureAsync('pdf_execution', () => buildExecutionPdf(e));
/// downloadBytes('diagnostic.json', utf8.encode(PerformanceProfiler.instance.exportJson()));
/// ```
library;

import 'dart:convert';

/// Statistiques d'une mesure (ms).
class PerfStat {
  int count = 0;
  double totalMs = 0, lastMs = 0, maxMs = 0, minMs = double.infinity;
  double get avgMs => count == 0 ? 0 : totalMs / count;

  void add(double ms) {
    count++;
    totalMs += ms;
    lastMs = ms;
    if (ms > maxMs) maxMs = ms;
    if (ms < minMs) minMs = ms;
  }

  Map<String, Object?> toJson() => {
        'count': count,
        'last_ms': _r(lastMs),
        'avg_ms': _r(avgMs),
        'min_ms': count == 0 ? null : _r(minMs),
        'max_ms': _r(maxMs),
        'total_ms': _r(totalMs),
      };
}

double _r(double v) => (v * 100).roundToDouble() / 100;

class PerformanceProfiler {
  PerformanceProfiler._();
  static final instance = PerformanceProfiler._();

  /// Mesures désactivées : coût nul (un booléen testé).
  bool enabled = true;

  /// Mémoire utilisée (octets) : fournie par la plateforme (navigateur : tas JavaScript ; ailleurs : RSS).
  int? Function()? memoryBytes;

  /// Plateforme (navigateur, système, version) pour le rapport.
  Map<String, Object?> Function()? platformInfo;

  final Map<String, PerfStat> stats = {};
  final List<Map<String, Object?>> events = [];
  static const maxEvents = 300;
  final DateTime started = DateTime.now();
  int? peakMemory;

  /// Chronomètre [f] sous le nom [name].
  T measure<T>(String name, T Function() f, {Map<String, Object?>? info}) {
    if (!enabled) return f();
    final sw = Stopwatch()..start();
    try {
      return f();
    } finally {
      record(name, sw.elapsedMicroseconds / 1000, info: info);
    }
  }

  /// Chronomètre une tâche asynchrone (génération de fichier, calcul en arrière-plan).
  Future<T> measureAsync<T>(String name, Future<T> Function() f, {Map<String, Object?>? info}) async {
    if (!enabled) return f();
    final sw = Stopwatch()..start();
    try {
      return await f();
    } finally {
      record(name, sw.elapsedMicroseconds / 1000, info: info);
    }
  }

  /// Enregistre une durée mesurée ailleurs.
  void record(String name, double ms, {Map<String, Object?>? info}) {
    if (!enabled) return;
    stats.putIfAbsent(name, PerfStat.new).add(ms);
    final mem = memory();
    events.add({
      't': DateTime.now().difference(started).inMilliseconds,
      'name': name,
      'ms': _r(ms),
      if (mem != null) 'mem_mb': _r(mem / (1024 * 1024)),
      ...?info,
    });
    if (events.length > maxEvents) events.removeRange(0, events.length - maxEvents);
  }

  /// Mémoire actuelle (octets), et pic observé.
  int? memory() {
    int? m;
    try {
      m = memoryBytes?.call();
    } catch (_) {
      m = null;
    }
    if (m != null && (peakMemory == null || m > peakMemory!)) peakMemory = m;
    return m;
  }

  void reset() {
    stats.clear();
    events.clear();
    peakMemory = null;
  }

  Map<String, Object?> toJson() {
    final mem = memory();
    return {
      'generated': DateTime.now().toIso8601String(),
      'uptime_s': DateTime.now().difference(started).inSeconds,
      'platform': platformInfo?.call() ?? const {},
      'memory_mb': mem == null ? null : _r(mem / (1024 * 1024)),
      'memory_peak_mb': peakMemory == null ? null : _r(peakMemory! / (1024 * 1024)),
      'stats': {for (final e in stats.entries) e.key: e.value.toJson()},
      'events': events,
    };
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}
