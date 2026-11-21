/// Catalogue des caissons : lecture du JSON et normalisation.
///
/// Le JSON source décrit les dimensions de plusieurs façons (available_widths, width,
/// width_left/right, footprint "AxB", width_min/max ; height, available_heights, height_variants).
/// Tout est ramené ici à un seul modèle [CabinetModel].
library;

import 'dart:convert';

import 'front_layout.dart';
import 'standards.dart';

/// Rôle d'un caisson dans la cuisine : détermine la hauteur de pose et les règles.
enum CabinetKind {
  base, // caisson bas
  wall, // caisson haut
  tall, // colonne
  cornerBase, // angle bas
  cornerWall, // angle haut
  cornerTall, // colonne d'angle (toute hauteur)
  fillerBase, // fileur bas
  fillerWall, // fileur haut
  coverPanel, // joue de finition
  islandPanel; // habillage d'îlot

  bool get isLow => this == base || this == cornerBase || this == fillerBase;
  bool get isHigh => this == wall || this == cornerWall || this == fillerWall;
  bool get isCorner => this == cornerBase || this == cornerWall || this == cornerTall;
  bool get isFiller => this == fillerBase || this == fillerWall;
}

/// Forme au sol.
enum CabinetShape {
  rect, // rectangle contre un mur
  lShape, // angle en L : un bras sur chaque mur
  diagonal, // angle à pan coupé : emprise en L, façade en diagonale
  blind, // angle droit avec fileur (angle mort) : rectangle calé dans le coin
}

/// Valeurs possibles d'une dimension : une liste fixe ou une plage libre.
class SizeOptions {
  final List<int> values;
  final int? min;
  final int? max;
  const SizeOptions.list(this.values)
      : min = null,
        max = null;
  const SizeOptions.range(int this.min, int this.max) : values = const [];

  bool get isRange => min != null;
  int get first => isRange ? min! : values.first;

  bool allows(int v) => isRange ? v >= min! && v <= max! : values.contains(v);

  /// Valeur autorisée la plus proche de [v].
  int nearest(int v) {
    if (isRange) return v.clamp(min!, max!);
    var best = values.first;
    for (final x in values) {
      if ((x - v).abs() < (best - v).abs()) best = x;
    }
    return best;
  }

  @override
  String toString() => isRange ? '$min–$max' : values.join('/');
}

class CabinetModel {
  final String id;
  final String name;
  final String categoryId;
  final String categoryName;
  final CabinetKind kind;
  final CabinetShape shape;
  final SizeOptions widths;
  final SizeOptions heights;
  final int depth;

  /// Angles en L / pan coupé : longueur du bras sur le mur suivant (sens horaire).
  final int? widthRight;

  /// Angle avec fileur : partie cachée derrière le caisson du mur voisin.
  final int? blindOverlap;
  final int? accessibleDoorWidth;

  final List<String> openingOptions;
  final List<String> internalConfig;

  /// Autres variantes (tiroirs, partage de porte, joue bas/haut/colonne...).
  final List<String> variants;
  final String? doorType;
  final bool isCarcass;
  final bool hasDoors;
  final bool ventilationGapRequired;
  final bool requiresWall;
  final bool floorSupport;
  final String? cornerAnchor;
  final String? requiresAppliance;
  final String? description;

  /// Hauteur écrite dans le JSON avant application des normes (pour mémoire).
  final List<int> catalogHeights;

  /// Composition de façade décrite dans le catalogue (null = dessin standard du modèle).
  final List<FrontRow>? frontLayout;

  /// Électroménager prévu par le catalogue (identifiants de la base électroménager).
  final List<String> appliances;

  /// Rôle dans le triangle d'activité : 'wash' | 'cook' | 'cool' (null = aucun).
  final String? zone;
  final int? mountZ; // hauteur de pose propre au modèle (meubles suspendus hors cuisine)

  const CabinetModel({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.kind,
    required this.shape,
    required this.widths,
    required this.heights,
    required this.depth,
    this.widthRight,
    this.blindOverlap,
    this.accessibleDoorWidth,
    this.openingOptions = const [],
    this.internalConfig = const [],
    this.variants = const [],
    this.doorType,
    this.isCarcass = true,
    this.hasDoors = true,
    this.ventilationGapRequired = false,
    this.requiresWall = true,
    this.floorSupport = false,
    this.cornerAnchor,
    this.requiresAppliance,
    this.description,
    this.catalogHeights = const [],
    this.frontLayout,
    this.appliances = const [],
    this.zone,
    this.mountZ,
  });

  int get defaultWidth {
    if (widths.isRange) return widths.min!;
    if (widths.values.contains(600)) return 600;
    return widths.values.first;
  }

  int get defaultHeight {
    if (heights.isRange) return heights.min!;
    // colonnes : la hauteur du milieu (2200) ; hauts : 800 si dispo
    if (kind == CabinetKind.tall && heights.values.length > 1) return heights.values[1];
    if (kind.isHigh && heights.values.contains(800)) return 800;
    return heights.values.first;
  }

  @override
  String toString() => '$id ($name) L:$widths H:$heights P:$depth';
}

class CabinetCategory {
  final String id;
  final String name;
  final List<CabinetModel> items;
  const CabinetCategory(this.id, this.name, this.items);
}

class Catalog {
  static final Map<String, CabinetModel> _masterRegistry = {};

  final String system;
  final String unit;
  final List<CabinetCategory> categories;
  final Map<String, CabinetModel> _byId;

  Catalog(this.system, this.unit, this.categories)
      : _byId = {for (final c in categories) for (final m in c.items) m.id: m} {
    for (final m in _byId.values) {
      _masterRegistry[m.id] = m;
    }
  }

  CabinetModel operator [](String id) {
    final m = _byId[id] ?? _masterRegistry[id];
    if (m != null) return m;
    // Fallback synthétique si le modèle provient d'un autre univers ou fichier .kin
    final isWall = id.contains('wall') || id.contains('haut') || id.contains('suspendu');
    final isTall = id.contains('tall') || id.contains('colonne') || id.contains('armoire');
    final fallback = CabinetModel(
      id: id,
      name: id,
      categoryId: isTall ? 'tall_cabinets' : (isWall ? 'wall_cabinets' : 'base_cabinets'),
      categoryName: isTall ? 'Colonnes' : (isWall ? 'Meubles hauts' : 'Meubles bas'),
      kind: isTall ? CabinetKind.tall : (isWall ? CabinetKind.wall : CabinetKind.base),
      shape: CabinetShape.rect,
      widths: const SizeOptions.range(100, 2400),
      heights: const SizeOptions.range(200, 2800),
      depth: isWall ? 350 : 600,
    );
    _masterRegistry[id] = fallback;
    return fallback;
  }

  CabinetModel? tryGet(String id) => _byId[id] ?? _masterRegistry[id];
  Iterable<CabinetModel> get models => _byId.values;

  static Catalog parse(String jsonText, {KitchenStandards standards = const KitchenStandards()}) =>
      fromJson(jsonDecode(jsonText) as Map<String, dynamic>, standards: standards);

  static Catalog fromJson(Map<String, dynamic> j, {KitchenStandards standards = const KitchenStandards()}) {
    final unit = (j['unit_metric'] ?? 'mm') as String;
    if (unit != 'mm') throw FormatException('unité non gérée : $unit (mm attendu)');
    final cats = <CabinetCategory>[];
    for (final c in (j['categories'] as List).cast<Map<String, dynamic>>()) {
      final items = <CabinetModel>[];
      for (final it in (c['items'] as List).cast<Map<String, dynamic>>()) {
        items.add(_parseItem(c, it, standards));
      }
      cats.add(CabinetCategory(c['id'] as String, c['name'] as String, items));
    }
    return Catalog(j['system'] as String? ?? '', unit, cats);
  }
}

List<int> _ints(Object? v) => v == null
    ? const []
    : v is List
        ? v.map((e) => (e as num).toInt()).toList()
        : [(v as num).toInt()];

List<String> _strs(Object? v) => v == null ? const [] : (v as List).map((e) => '$e').toList();

CabinetKind _kind(String categoryId, String itemId) {
  switch (categoryId) {
    case 'base_cabinets':
      return CabinetKind.base;
    case 'wall_cabinets':
      return CabinetKind.wall;
    case 'tall_cabinets':
      return CabinetKind.tall;
    case 'corner_base_cabinets':
      return CabinetKind.cornerBase;
    case 'corner_wall_cabinets':
      return CabinetKind.cornerWall;
    case 'corner_tall_cabinets':
      return CabinetKind.cornerTall;
    case 'custom_cabinets':
      // caissons personnalisés : le type se lit dans l'identifiant
      return itemId.contains('wall') ? CabinetKind.wall : itemId.contains('tall') ? CabinetKind.tall : CabinetKind.base;
  }
  if (itemId.startsWith('filler_panel_base')) return CabinetKind.fillerBase;
  if (itemId.startsWith('filler_panel_wall')) return CabinetKind.fillerWall;
  if (itemId.startsWith('island')) return CabinetKind.islandPanel;
  if (itemId.startsWith('cover_panel')) return CabinetKind.coverPanel;
  // catégorie inconnue : on se fie à la hauteur de pose
  return CabinetKind.base;
}

CabinetModel _parseItem(Map<String, dynamic> cat, Map<String, dynamic> it, KitchenStandards std) {
  final id = it['id'] as String;
  final kind = _kind(cat['id'] as String, id);
  final snap = (it['snapping'] as Map?)?.cast<String, dynamic>() ?? const {};

  // ---- largeur et forme
  var shape = CabinetShape.rect;
  int? widthRight;
  SizeOptions widths;
  if (it['width_left'] != null) {
    shape = CabinetShape.lShape;
    widths = SizeOptions.list(_ints(it['width_left']));
    widthRight = (it['width_right'] as num?)?.toInt() ?? widths.first;
  } else if (it['footprint'] != null) {
    shape = CabinetShape.diagonal;
    final p = (it['footprint'] as String).toLowerCase().split('x');
    widths = SizeOptions.list([int.parse(p[0].trim())]);
    widthRight = int.parse(p[1].trim());
  } else if (it['available_widths'] != null) {
    widths = SizeOptions.list(_ints(it['available_widths']));
  } else if (it['width'] != null) {
    widths = SizeOptions.list(_ints(it['width']));
  } else if (it['width_min'] != null) {
    widths = SizeOptions.range((it['width_min'] as num).toInt(), (it['width_max'] as num).toInt());
  } else if (it['thickness'] != null) {
    widths = SizeOptions.list(_ints(it['thickness'])); // joue / panneau : largeur = épaisseur
  } else {
    widths = const SizeOptions.list([600]);
  }
  if (it['blind_overlap'] != null) shape = CabinetShape.blind;

  // ---- profondeur
  int depth = (it['depth'] as num?)?.toInt() ?? (cat['depth_nominal'] as num?)?.toInt() ?? 0;

  // ---- hauteur (normes appliquées aux éléments bas)
  final catalogHeights = [
    ..._ints(it['height']),
    ..._ints(it['available_heights']),
    ..._ints(it['height_variants']),
  ];
  SizeOptions heights;
  final variants = <String>[
    ..._strs(it['drawer_variants']),
    ..._strs(it['door_splits']),
    ..._strs(it['variants']),
  ];

  switch (kind) {
    case CabinetKind.base:
    case CabinetKind.cornerBase:
    case CabinetKind.fillerBase:
      // hors cuisine (vasque, banc TV, buffet...) : les hauteurs du catalogue ; en cuisine : la norme
      heights = SizeOptions.list(it['free_height'] == true && catalogHeights.isNotEmpty ? catalogHeights : [std.baseCarcassHeight]);
      if (depth == 0) depth = 600;
    case CabinetKind.islandPanel:
      // habillage arrière d'îlot : du sol au plan de travail, longueur libre
      heights = SizeOptions.list([std.baseTop]);
      widths = const SizeOptions.range(300, 6000);
      depth = _ints(it['thickness']).isEmpty ? 18 : _ints(it['thickness']).first;
    case CabinetKind.coverPanel:
      // joue : hauteur selon la variante (bas = jusqu'au plan de travail depuis le sol)
      heights = SizeOptions.list([std.baseTop, 600, 800, 1000, 2100, 2300, 2500]);
      depth = 600;
    case CabinetKind.fillerWall:
    case CabinetKind.wall:
    case CabinetKind.cornerWall:
    case CabinetKind.cornerTall:
    case CabinetKind.tall:
      heights = SizeOptions.list(catalogHeights.isEmpty ? [800] : catalogHeights);
      if (depth == 0) depth = kind == CabinetKind.tall || kind == CabinetKind.cornerTall ? 600 : 370;
  }
  // hauteur libre (caisson personnalisé)
  if (it['height_min'] != null) heights = SizeOptions.range((it['height_min'] as num).toInt(), (it['height_max'] as num).toInt());

  final doors = it['doors'];
  return CabinetModel(
    id: id,
    name: it['name'] as String? ?? id,
    categoryId: cat['id'] as String,
    categoryName: cat['name'] as String,
    kind: kind,
    shape: shape,
    widths: widths,
    heights: heights,
    depth: depth,
    widthRight: widthRight,
    blindOverlap: (it['blind_overlap'] as num?)?.toInt(),
    accessibleDoorWidth: (it['accessible_door_width'] as num?)?.toInt(),
    openingOptions: _strs(it['opening_options']),
    internalConfig: _strs(it['internal_config']),
    variants: variants,
    doorType: it['door_type'] as String?,
    isCarcass: it['is_carcass'] as bool? ?? !(kind.isFiller || kind == CabinetKind.coverPanel || kind == CabinetKind.islandPanel),
    hasDoors: doors is bool ? doors : true,
    ventilationGapRequired: it['ventilation_gap_required'] as bool? ?? false,
    requiresWall: snap['requires_wall'] as bool? ?? kind != CabinetKind.islandPanel,
    floorSupport: snap['floor_support'] as bool? ?? (kind.isLow || kind == CabinetKind.tall),
    cornerAnchor: snap['corner_anchor'] as String?,
    requiresAppliance: snap['requires_appliance'] as String?,
    description: it['description'] as String?,
    catalogHeights: catalogHeights,
    frontLayout: it['front_layout'] == null ? null : parseRows(it['front_layout']),
    appliances: _strs(it['appliances']),
    zone: it['zone'] as String?,
    mountZ: (it['mount_z'] as num?)?.toInt(),
  );
}
