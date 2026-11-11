/// Catalogue des portes et fenêtres (menuiseries) : modèle, mécanisme d'ouverture, cotes standard,
/// composition et quincaillerie. Le mécanisme pilote le dessin (plan, élévation, 3D) et la zone libre devant.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'project.dart';

class OpeningModel {
  final String id, name, style, mechanism;
  final bool door;
  final List<int> heights, widths;
  final int thickness;
  final Map<String, String> composition;
  final List<String> hardware;
  const OpeningModel(this.id, this.name, this.style, this.mechanism, this.door, this.heights, this.widths, this.thickness, this.composition,
      this.hardware);

  /// Catalogue chargé (pour nommer et dessiner les ouvertures partout dans l'app).
  static final Map<String, OpeningModel> byId = {};

  static List<OpeningModel> parse(String src) {
    final j = jsonDecode(src) as Map<String, dynamic>;
    OpeningModel one(Map<String, dynamic> m, bool door) {
      final d = (m['standard_dimensions'] as Map?)?.cast<String, dynamic>() ?? const {};
      return OpeningModel(
        '${m['id']}',
        '${m['name']}',
        '${m['style'] ?? ''}',
        '${m['opening_mechanism'] ?? (door ? 'hinged_single' : 'casement_inward')}',
        door,
        [for (final h in (d['heights'] as List? ?? const [])) (h as num).toInt()],
        [for (final w in (d['widths'] as List? ?? const [])) (w as num).toInt()],
        (d['thickness'] as num?)?.toInt() ?? (door ? 40 : 70),
        {for (final e in ((m['composition'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        [for (final h in (m['hardware'] as List? ?? const [])) '$h'],
      );
    }

    final out = [
      for (final m in (j['doors'] as List? ?? const [])) one((m as Map).cast<String, dynamic>(), true),
      for (final m in (j['windows'] as List? ?? const [])) one((m as Map).cast<String, dynamic>(), false),
    ];
    for (final m in out) {
      byId[m.id] = m;
    }
    return out;
  }

  // ---------------------------------------------------------------- mécanismes
  bool get hinged => mechanism.startsWith('hinged') || mechanism.startsWith('casement') || mechanism.startsWith('tilt_and_turn');
  bool get twoLeaves => mechanism == 'hinged_double' || (!door && mechanism.startsWith('casement'));
  bool get sliding => mechanism.startsWith('sliding');
  bool get pocket => mechanism == 'sliding_pocket_wall';
  bool get barn => mechanism == 'sliding_surface_mounted';
  bool get folding => mechanism.startsWith('folding');
  bool get pivot => mechanism.startsWith('pivot');
  bool get fixedPane => mechanism == 'none_fixed';
  bool get glazed => !door || id.contains('french') || id.contains('aluminium');
  bool get flush => mechanism == 'hinged_flush_push_pull';
  bool get arch => mechanism.contains('arch');

  /// Largeur et hauteur proposées par défaut (porte : la plus proche de 830, fenêtre : la plus proche de 1000).
  int get defaultWidth => widths.isEmpty ? (door ? 830 : 1000) : widths.reduce((a, b) => (a - (door ? 830 : 1000)).abs() <= (b - (door ? 830 : 1000)).abs() ? a : b);
  int get defaultHeight => heights.isEmpty ? (door ? 2040 : 1150) : heights.first;

  /// Hauteur d'allège usuelle d'une fenêtre (baie et châssis fixe toute hauteur : au sol ; soufflet : en haut).
  int get defaultSill {
    if (door) return 0;
    if (mechanism == 'sliding_horizontal') return 0;
    if (mechanism == 'tilt_inward_bottom_hinged') return 1600;
    if (mechanism == 'none_fixed') return math.max(0, 2150 - defaultHeight);
    if (mechanism == 'pivot_center_horizontal') return 1600;
    return 1050;
  }

  /// Rayon de débattement devant la porte (mm) : battant = largeur du vantail, coulissant / pliant = rien.
  double swing(double width) {
    if (sliding || folding) return 0;
    if (pivot) return width * 0.8;
    if (twoLeaves) return width / 2;
    return width;
  }

  String get mechanismLabel => switch (mechanism) {
        'hinged_single' => 'Battante, un vantail',
        'hinged_single_heavy' => 'Battante renforcée',
        'hinged_double' => 'Battante, deux vantaux',
        'hinged_single_or_double' => 'Battante (un ou deux vantaux)',
        'hinged_flush_push_pull' => 'Battante affleurante',
        'sliding_pocket_wall' => 'Coulissante dans la cloison',
        'sliding_surface_mounted' => 'Coulissante en applique',
        'folding_bifold' => 'Pliante',
        'pivot_offset' => 'Sur pivot',
        'casement_inward' => 'Ouvrant à la française',
        'sliding_horizontal' => 'Coulissante',
        'tilt_and_turn_inward' => 'Oscillo-battante',
        'tilt_inward_bottom_hinged' => 'À soufflet',
        'none_fixed' => 'Fixe',
        'sliding_vertical' => 'À guillotine',
        'louver_pivoting' => 'À lames orientables',
        'pivot_center_horizontal' => 'Basculante (toit)',
        'mixed_casement_and_fixed' => 'En saillie (bow window)',
        'casement_inward_arch' => 'Cintrée',
        _ => mechanism,
      };
}

/// Modèle d'une ouverture (celui choisi, sinon le modèle par défaut de son type).
OpeningModel? openingModelOf(Opening o) =>
    OpeningModel.byId[o.model ?? (o.isDoor ? 'door_interior_flush' : 'window_casement_french')];

String openingName(Opening o) => openingModelOf(o)?.name ?? (o.isDoor ? 'Porte' : 'Fenêtre');
