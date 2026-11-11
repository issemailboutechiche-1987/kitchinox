/// Marques et prix du marché marocain (panneaux, quincaillerie, accessoires de cuisine, sanitaires, dressing)
/// et dimensions types des pièces avec leurs règles ergonomiques (Neufert, NKBA, NF C 15-100).
/// Sources : assets/data/brands.json et assets/data/sizes.json.
library;

import 'i18n_hook.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'layout_engine.dart';
import 'materials.dart';
import 'project.dart';

class BrandPrice {
  final String key;
  final PriceRange price;
  const BrandPrice(this.key, this.price);

  /// Libellé lisible d'une clé (« charniere_clip_top_blumotion_110 » → « Charnière clip top blumotion 110 »).
  String get label {
    var s = key.replaceAll('_', ' ');
    const fix = {
      'charniere': 'charnière', 'epicier': 'épicier', 'egouttoir': 'égouttoir', 'elevateur': 'élévateur', 'melamine': 'mélaminé',
      'decor': 'décor', 'plaque': 'plaqué', 'contreplaque': 'contreplaqué', 'latte': 'latté', 'bati': 'bâti', 'evier': 'évier',
      'systeme': 'système', 'resine': 'résine', 'thermostatique': 'thermostatique', 'pliante': 'pliante', 'decoratifs': 'décoratifs',
      'sortie': 'sortie', 'amorti': 'amorti', 'cuvette': 'cuvette', 'ceramique': 'céramique', 'mitigeur': 'mitigeur', 'relevable': 'relevable',
    };
    s = s.split(' ').map((w) => fix[w] ?? w).join(' ');
    return s.isEmpty ? key : '${s[0].toUpperCase()}${s.substring(1)}';
  }
}

class Brand {
  final String name, origin, tier;
  final List<String> specialties;
  final List<BrandPrice> prices;
  const Brand(this.name, this.origin, this.tier, this.specialties, this.prices);

  /// Premier prix dont la clé contient l'un des [words] (dans l'ordre de préférence).
  PriceRange? find(List<String> words) {
    for (final w in words) {
      for (final p in prices) {
        if (p.key.contains(w)) return p.price;
      }
    }
    return null;
  }
}

class BrandCategory {
  final String id, label, description;
  final List<String> distributors;
  final List<Brand> brands;
  const BrandCategory(this.id, this.label, this.description, this.distributors, this.brands);
}

class BrandCatalog {
  static final List<BrandCategory> categories = [];

  static const labels = {
    'mdf_and_wood_panels': 'Panneaux',
    'furniture_hardware': 'Quincaillerie',
    'kitchen_internal_accessories': 'Accessoires de cuisine',
    'sanitary_ware_and_faucets': 'Sanitaires et robinetterie',
    'wardrobe_dressing_accessories': 'Accessoires de dressing',
  };

  static void parse(String src) {
    final j = jsonDecode(src) as Map<String, dynamic>;
    categories.clear();
    for (final e in ((j['categories'] as Map?) ?? const {}).entries) {
      final c = (e.value as Map).cast<String, dynamic>();
      categories.add(BrandCategory(
        e.key,
        labels[e.key] ?? e.key,
        '${c['description'] ?? ''}',
        [for (final d in (c['local_distributors_morocco'] as List? ?? const [])) '$d'],
        [
          for (final b in (c['brands'] as List? ?? const []))
            () {
              final m = (b as Map).cast<String, dynamic>();
              return Brand(
                '${m['brand']}',
                '${m['origin'] ?? ''}',
                '${m['tier'] ?? ''}',
                [for (final s in (m['specialties'] as List? ?? const [])) '$s'],
                [
                  for (final p in ((m['pricing_mad'] as Map?) ?? const {}).entries)
                    BrandPrice('${p.key}', PriceRange(((p.value as Map)['min'] as num).toDouble(), ((p.value as Map)['max'] as num).toDouble())),
                ],
              );
            }(),
        ],
      ));
    }
  }

  static BrandCategory? category(String id) => categories.where((c) => c.id == id).firstOrNull;

  /// Marques de quincaillerie du catalogue (pour le choix de la marque du devis).
  static List<String> get hardwareBrands => [for (final b in category('furniture_hardware')?.brands ?? const <Brand>[]) b.name];

  static Brand? hardwareBrand(String name) {
    final n = name.toLowerCase();
    for (final b in category('furniture_hardware')?.brands ?? const <Brand>[]) {
      if (b.name.toLowerCase() == n || b.name.toLowerCase().split(' / ').contains(n)) return b;
    }
    return null;
  }

  /// Prix d'un article de quincaillerie de l'app chez une marque du catalogue (null : pas de prix connu).
  static PriceRange? hardwarePrice(String brand, String hardwareId) {
    final b = hardwareBrand(brand);
    if (b == null) return null;
    switch (hardwareId) {
      case 'hinge_110_soft_close' || 'hinge_corner_bifold_60' || 'hinge_blind_corner_90':
        return b.find(['charniere']);
      case 'double_wall_box_drawer_low':
        return b.find(['tiroir']);
      case 'double_wall_box_casserolier_deep':
        return b.find(['casserolier']) ?? (b.find(['tiroir']) == null ? null : b.find(['tiroir'])! * 1.3);
      case 'lift_stay_single_door_heavy':
        return b.find(['relevable_aventos_hk', 'relevable']) ?? (b.find(['verin']) == null ? null : b.find(['verin'])! * 2);
      case 'wall_cabinet_hangers':
        return b.find(['suspension']);
    }
    return null;
  }

  /// Estimation (min, max) de la quincaillerie du projet chez chaque marque : quantités du devis × prix de la marque.
  static List<(Brand, PriceRange, int)> hardwareEstimate(Map<String, double> qtyById) {
    final out = <(Brand, PriceRange, int)>[];
    for (final b in category('furniture_hardware')?.brands ?? const <Brand>[]) {
      var total = PriceRange.zero;
      var priced = 0;
      for (final e in qtyById.entries) {
        final p = hardwarePrice(b.name, e.key);
        if (p == null) continue;
        total = total + p * e.value;
        priced++;
      }
      if (priced > 0) out.add((b, total, priced));
    }
    out.sort((a, b) => a.$2.min.compareTo(b.$2.min));
    return out;
  }
}

// ---------------------------------------------------------------------------- dimensions types

class RoomPreset {
  final String id, name, layout;
  final double width, depth, area;
  final double? minWidth, minDepth;
  final String note;
  const RoomPreset(this.id, this.name, this.layout, this.width, this.depth, this.area, this.minWidth, this.minDepth, this.note);

  /// Disposition des meubles de cuisine correspondant au type de pièce.
  RoomShape? get kitchenShape => switch (layout) {
        'I_shape' => RoomShape.linear,
        'parallel_galley' => RoomShape.parallel,
        'L_shape' || 'L_or_I_with_island' => RoomShape.lShape,
        'U_shape' => RoomShape.uShape,
        _ => null,
      };
}

class SizeCatalog {
  static final Map<String, List<RoomPreset>> presets = {}; // cuisine, bain, dressing
  static final Map<String, List<int>> ceilings = {};
  static Map<String, dynamic> rules = {}; // règles brutes par pièce (cuisine, bain, dressing)
  static List<String> references = [];

  static const _rooms = {'kitchen': 'cuisine', 'bathroom': 'bain', 'dressing_wardrobe': 'dressing'};

  static void parse(String src) {
    final j = jsonDecode(src) as Map<String, dynamic>;
    references = [for (final r in (j['normative_references'] as List? ?? const [])) '$r'];
    presets.clear();
    ceilings.clear();
    rules = {};
    for (final e in ((j['rooms'] as Map?) ?? const {}).entries) {
      final id = _rooms[e.key];
      if (id == null) continue;
      final r = (e.value as Map).cast<String, dynamic>();
      ceilings[id] = [for (final h in (r['standard_ceiling_heights'] as List? ?? const [])) (h as num).toInt()];
      rules[id] = r['ergonomic_and_normative_rules'] ?? const {};
      presets[id] = [
        for (final p in (r['most_common_room_presets'] as List? ?? const []))
          () {
            final m = (p as Map).cast<String, dynamic>();
            // la clé du JSON contient parfois une espace (« min_viable_ dimensions »)
            final mv = (m.entries.where((x) => x.key.replaceAll(' ', '') == 'min_viable_dimensions').firstOrNull?.value as Map?)?.cast<String, dynamic>();
            return RoomPreset(
              '${m['id']}',
              '${m['name']}',
              '${m['layout_type'] ?? ''}',
              (m['room_width_X'] as num).toDouble(),
              (m['room_depth_Y'] as num).toDouble(),
              (m['area_m2'] as num?)?.toDouble() ?? 0,
              (mv?['width'] as num?)?.toDouble(),
              (mv?['depth'] as num?)?.toDouble(),
              '${m['note'] ?? ''}',
            );
          }(),
      ];
    }
  }

  static double? rule(String room, List<String> path) {
    Object? v = rules[room];
    for (final k in path) {
      if (v is! Map) return null;
      v = v[k];
    }
    return v is num ? v.toDouble() : null;
  }
}

/// Contrôles tirés des normes du catalogue des dimensions : pièce trop petite pour la disposition,
/// hauteur du plan de travail, distance évier / plaque, passage devant un dressing.
List<Issue> sizeChecks(LayoutEngine e) {
  final out = <Issue>[];
  final p = e.project;
  final room = p.room;
  final list = SizeCatalog.presets[p.universe] ?? const <RoomPreset>[];
  if (list.isEmpty) return out;
  // pièce plus petite que le minimum viable de la disposition choisie (cuisine) ou de la plus petite pièce type
  if (p.universe == 'cuisine') {
    final shape = p.shape;
    final pr = list.where((x) => x.kitchenShape == shape && x.minWidth != null).firstOrNull;
    if (pr != null) {
      final w = math.max(room.width, room.depth), d = math.min(room.width, room.depth);
      if (w < pr.minWidth! - 0.5 || d < pr.minDepth! - 0.5) {
        out.add(Issue(Severity.warning, 'room_small',
            L('Pièce de {0} x {1} : une cuisine {2} demande au moins {3} x {4} mm', [room.width.round(), room.depth.round(), shape!.label.toLowerCase(), pr.minWidth!.round(), pr.minDepth!.round()])));
      }
    }
    final wt = p.standards.worktopTop.toDouble();
    final wmin = SizeCatalog.rule('cuisine', ['vertical_heights', 'worktop_standard_height_from_floor', 'min']);
    final wmax = SizeCatalog.rule('cuisine', ['vertical_heights', 'worktop_standard_height_from_floor', 'max']);
    if (wmin != null && wmax != null && (wt < wmin || wt > wmax)) {
      out.add(Issue(Severity.warning, 'worktop_height', L('Plan de travail à {0} mm du sol : {1} à {2} mm conseillés', [wt.round(), wmin.round(), wmax.round()])));
    }
    // évier et plaque trop proches (éclaboussures) : distance entre leurs bords sur le même mur
    final minSinkHob = SizeCatalog.rule('cuisine', ['safety_landing_zones', 'min_distance_sink_to_cooktop']);
    if (minSinkHob != null) {
      for (final s in p.items.where((c) => e.isWashing(e.modelOf(c)))) {
        for (final h in p.items.where((c) => c.wallId == s.wallId && e.isCooking(e.modelOf(c)) && e.modelOf(c).kind.isLow)) {
          final gap = h.s >= s.right ? h.s - s.right : s.s - h.right;
          if (gap >= 0 && gap < minSinkHob) {
            out.add(Issue(Severity.warning, 'sink_hob_close',
                L('Évier et plaque à {0} mm l’un de l’autre : {1} mm au moins (éclaboussures)', [gap.round(), minSinkHob.round()]), [s.uid, h.uid]));
          }
        }
      }
    }
  }
  if (p.universe == 'dressing') {
    // passage devant les rangements : entre deux murs face à face équipés
    final minPass = SizeCatalog.rule('dressing', ['circulation_and_clearances', 'passage_in_front_of_open_or_sliding_wardrobe_min']) ?? 800;
    double depthOn(String w) => p.items.where((c) => c.wallId == w && c.z < 900).fold(0.0, (m, c) => math.max(m, c.depth.toDouble()));
    for (final (a, b, span) in [('A', 'D', room.depth), ('B', 'C', room.width)]) {
      if (room.outline != null) break;
      final da = depthOn(a), db = depthOn(b);
      if (da == 0 && db == 0) continue;
      final free = span - da - db;
      if (free < minPass) {
        out.add(Issue(Severity.warning, 'dressing_passage', L('Passage de {0} mm devant les rangements : {1} mm au moins', [free.round(), minPass.round()])));
      }
    }
  }
  return out;
}
