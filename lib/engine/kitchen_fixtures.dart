/// Équipements posés sur la cuisine et dans les pièces : éviers et mitigeurs (choix du client),
/// appareillage électrique (référence pour les réseaux). Source : assets/data/accessories.json.
library;

import 'dart:convert';

class SinkModel {
  final String id, name;
  final int length, depth, height;
  final List<String> mounting; // 'inset' (à poser) | 'undermount' (sous plan)
  const SinkModel(this.id, this.name, this.length, this.depth, this.height, this.mounting);

  /// Disposition dessinée : bac + égouttoir, deux bacs, ou un bac.
  String get layout => id.contains('2_bowls_drainer')
      ? '2_drainer'
      : (id.contains('drainer')
          ? 'drainer'
          : (id.contains('2_bowls')
              ? '2'
              : 'compact'));
}

class FaucetModel {
  final String id, name;
  final int height, hole;
  const FaucetModel(this.id, this.name, this.height, this.hole);
  bool get pullout => id.contains('pullout');
  bool get spring => id.contains('spring');
  bool get swan => id.contains('swan');
  bool get square => id.contains('square');
}

class KitchenFixtures {
  static final List<SinkModel> sinks = [];
  static final List<FaucetModel> faucets = [];
  static final List<String> brands = []; // appareillage électrique courant au Maroc

  static const defaultSink = SinkModel('sink_1_bowl_drainer', 'Évier 1 Bac avec Égouttoir 86cm', 860, 500, 200, ['inset', 'undermount']);
  static const defaultFaucet = FaucetModel('faucet_mixer_swan', 'Mitigeur Col de Cygne Épuré', 360, 35);

  static void parse(String src) {
    final j = jsonDecode(src) as Map<String, dynamic>;
    final k = (j['kitchen_plumbing_fixtures'] as Map?)?.cast<String, dynamic>() ?? const {};
    sinks
      ..clear()
      ..addAll([
        for (final s in (k['sinks'] as List? ?? const []))
          () {
            final m = (s as Map).cast<String, dynamic>();
            final d = (m['dimensions'] as Map?)?.cast<String, dynamic>() ?? const {};
            return SinkModel('${m['id']}', '${m['name']}', (d['L'] as num?)?.toInt() ?? 860, (d['P'] as num?)?.toInt() ?? 500,
                (d['H'] as num?)?.toInt() ?? 200, [for (final x in (m['mounting'] as List? ?? const [])) '$x']);
          }(),
      ]);
    faucets
      ..clear()
      ..addAll([
        for (final f in (k['faucets'] as List? ?? const []))
          () {
            final m = (f as Map).cast<String, dynamic>();
            return FaucetModel('${m['id']}', '${m['name']}', (m['height'] as num?)?.toInt() ?? 350, (m['hole_diameter'] as num?)?.toInt() ?? 35);
          }(),
      ]);
    final e = (j['electrical_fixtures'] as Map?)?.cast<String, dynamic>() ?? const {};
    brands
      ..clear()
      ..addAll([for (final b in (e['brands_morocco'] as List? ?? const [])) '$b']);
  }

  static SinkModel sink(String? id) => sinks.where((s) => s.id == id).firstOrNull ?? (sinks.isEmpty ? defaultSink : sinks.first);
  static FaucetModel faucet(String? id) => faucets.where((f) => f.id == id).firstOrNull ?? (faucets.isEmpty ? defaultFaucet : faucets.first);
}
