/// Prix publics des panneaux (tarif fournisseur relevé au Maroc) : MDF, latté, stratifié, panneaux minces,
/// bandes de chant. Sert à chiffrer la feuille du projet et le fond arrière des caissons.
library;

import 'dart:convert';

class PublicPanel {
  final String id, name, family;
  final int length, width, thickness; // mm
  final double price; // MAD par feuille
  final bool thicknessAssumed; // épaisseur non précisée au tarif
  final String note;
  const PublicPanel(this.id, this.name, this.family, this.length, this.width, this.thickness, this.price,
      {this.thicknessAssumed = false, this.note = ''});

  /// « 2800 x 2100 x 18 mm »
  String get format => '$length x $width x $thickness mm';

  /// Prix au m² (comparaison entre formats).
  double get perM2 => price / (length * width / 1e6);
}

class PublicPrices {
  static final List<PublicPanel> panels = [];
  static final List<(String name, double perMeter)> edges = [];
  static String source = '', updated = '';

  static void parse(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    source = '${j['source'] ?? ''}';
    updated = '${j['updated'] ?? ''}';
    panels
      ..clear()
      ..addAll([
        for (final p in (j['panels'] as List? ?? const []).cast<Map<String, dynamic>>())
          PublicPanel('${p['id']}', '${p['name']}', '${p['family']}', (p['length'] as num).toInt(), (p['width'] as num).toInt(),
              (p['thickness'] as num).toInt(), (p['price'] as num).toDouble(),
              thicknessAssumed: p['thickness_assumed'] == true, note: '${p['note'] ?? ''}'),
      ]);
    edges
      ..clear()
      ..addAll([
        for (final e in (j['edge_banding'] as List? ?? const []).cast<Map<String, dynamic>>()) ('${e['name']}', (e['price_per_meter'] as num).toDouble()),
      ]);
  }

  static List<String> get families => {for (final p in panels) p.family}.toList();

  static PublicPanel? byId(String id) {
    for (final p in panels) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Panneaux de structure (caissons, façades) : 16 mm et plus.
  static List<PublicPanel> get structural => [for (final p in panels) if (p.thickness >= 16) p];

  /// Panneau mince blanc pour le fond arrière : l'épaisseur du tarif la plus proche de [thickness].
  static PublicPanel? back(int thickness) {
    PublicPanel? best;
    for (final p in panels.where((p) => p.thickness < 16 && p.id.startsWith('mdf_blanc'))) {
      if (best == null || (p.thickness - thickness).abs() < (best.thickness - thickness).abs()) best = p;
    }
    return best;
  }

  /// Fourchette des bandes de chant (MAD par mètre), ou null si le tarif n'est pas chargé.
  static (double, double)? get edgeRange {
    if (edges.isEmpty) return null;
    final v = edges.map((e) => e.$2).toList()..sort();
    return (v.first, v.last);
  }
}
