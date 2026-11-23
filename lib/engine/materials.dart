/// Bases de données « matériaux » (Maroc, prix en MAD) : électroménager, plans de travail,
/// panneaux et chants, quincaillerie. Lecture des 4 fichiers JSON et calculs dérivés :
/// électroménager de chaque caisson (niches, découpes), quincaillerie automatique, estimation.
library;

import 'i18n_hook.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'bom.dart';
import 'furniture_accessories.dart';
import 'public_prices.dart';
import 'brands_sizes.dart';
import 'assembly.dart';
import 'catalog.dart';
import 'cutting.dart';
import 'handles.dart';
import 'layout_engine.dart';
import 'project.dart';
import 'room_objects.dart';
import 'worktop_looks.dart';
import 'backsplash.dart';

class PriceRange {
  final double min, max;
  const PriceRange(this.min, this.max);
  static const zero = PriceRange(0, 0);
  PriceRange operator +(PriceRange o) => PriceRange(min + o.min, max + o.max);
  PriceRange operator *(num k) => PriceRange(min * k, max * k);
  bool get isZero => min == 0 && max == 0;
  @override
  String toString() => '${min.round()} - ${max.round()} MAD';

  static PriceRange? fromJson(Object? j) {
    if (j is Map && j['min'] is num && j['max'] is num) return PriceRange((j['min'] as num).toDouble(), (j['max'] as num).toDouble());
    return null;
  }
}

/// Une offre de prix : marque / gamme / variante.
class Offer {
  final String label; // marque ou gamme
  final String detail; // modèle ou marques
  final PriceRange price;
  const Offer(this.label, this.detail, this.price);
}

/// Toutes les offres d'un élément, quelle que soit la forme du JSON
/// (brands_pricing_..., market_segments_morocco, pricing_mad..., price_per_...).
List<Offer> _offers(Map<String, dynamic> it) {
  final out = <Offer>[];
  for (final e in it.entries) {
    final k = e.key, v = e.value;
    if (k == 'market_segments_morocco' && v is List) {
      for (final s in v.cast<Map>()) {
        final p = PriceRange.fromJson(s['price_mad']);
        if (p != null) out.add(Offer('${s['tier']}', (s['brands'] as List? ?? const []).join(', '), p));
      }
    } else if (k.startsWith('brands_pricing') && v is List) {
      for (final s in v.cast<Map>()) {
        final p = PriceRange.fromJson(s['price_mad']);
        if (p != null) out.add(Offer('${s['brand']}', '${s['model'] ?? ''}', p));
      }
    } else if (k.startsWith('pricing') || k.startsWith('price_per')) {
      final p = PriceRange.fromJson(v);
      if (p != null) {
        out.add(Offer('Standard', k, p));
      } else if (v is Map) {
        for (final sub in v.entries) {
          final q = PriceRange.fromJson(sub.value);
          if (q != null) out.add(Offer(sub.key.replaceAll('_', ' '), k, q));
        }
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Électroménager
// ---------------------------------------------------------------------------

class Appliance {
  final String id, name, category, categoryName;
  final int? width, height, depth; // encombrement
  final (int, int, int)? niche; // largeur, hauteur, profondeur mini de la niche
  final (int, int)? cutout; // découpe du plan de travail (largeur x profondeur)
  final String? cutoutNote;
  final int? cabinetWidth; // largeur de caisson compatible
  final int? minCabinetWidth;
  final List<int> widths;
  final int? ventilationGap;
  final List<Offer> offers;
  const Appliance({
    required this.id,
    required this.name,
    required this.category,
    required this.categoryName,
    this.width,
    this.height,
    this.depth,
    this.niche,
    this.cutout,
    this.cutoutNote,
    this.cabinetWidth,
    this.minCabinetWidth,
    this.widths = const [],
    this.ventilationGap,
    this.offers = const [],
  });

  String get dimsText {
    final parts = <String>[
      if (width != null) ['L$width', if (height != null) 'H$height', if (depth != null) 'P$depth'].join('×'),
      if (niche != null) 'niche ${niche!.$1}×${niche!.$2}×${niche!.$3}',
      if (cutout != null) 'découpe plan ${cutout!.$1}×${cutout!.$2}',
    ];
    return parts.join(' · ');
  }

  PriceRange get priceRange {
    if (offers.isEmpty) return PriceRange.zero;
    return PriceRange(offers.map((o) => o.price.min).reduce(math.min), offers.map((o) => o.price.max).reduce(math.max));
  }
}

// ---------------------------------------------------------------------------
// Plans de travail, panneaux, chants, quincaillerie
// ---------------------------------------------------------------------------

class WorktopMaterial {
  final String id, name;
  final List<int> thicknesses;
  final List<String> edgeProfiles;
  final List<Offer> variants; // une variante = une couleur et son prix au mètre linéaire
  final List<String> notes;
  const WorktopMaterial(this.id, this.name, this.thicknesses, this.edgeProfiles, this.variants, this.notes);
}

class PanelType {
  final String id, name;
  final List<String> usage;
  final List<(int, int)> sheets;
  final List<int> thicknesses;
  final bool moistureResistant, grainMandatory;
  final List<Offer> offers;
  final bool pricedFor2440; // prix donnés pour une feuille 2440 x 1220
  const PanelType(this.id, this.name, this.usage, this.sheets, this.thicknesses, this.moistureResistant, this.grainMandatory, this.offers,
      this.pricedFor2440);

  /// Prix d'une feuille [l] x [w] (proportionnel à la surface quand le prix est donné en 2440 x 1220).
  PriceRange sheetPrice(int l, int w) {
    if (offers.isEmpty) return PriceRange.zero;
    final o = offers.first.price;
    return pricedFor2440 ? o * (l * w / (2440 * 1220)) : o;
  }
}

class EdgeBand {
  final String type, usage;
  final double thickness, pricePerM;
  const EdgeBand(this.type, this.thickness, this.usage, this.pricePerM);
}

class HardwareItem {
  final String id, name, category;
  final List<Offer> offers;
  const HardwareItem(this.id, this.name, this.category, this.offers);

  /// Offre de la marque choisie, sinon la moins chère.
  Offer offer(String brand) {
    if (offers.isEmpty) return const Offer('-', '', PriceRange.zero);
    for (final o in offers) {
      if (o.label.toLowerCase().contains(brand.toLowerCase())) return o;
    }
    return offers.reduce((a, b) => a.price.min <= b.price.min ? a : b);
  }
}

class MaterialsDb {
  final Map<String, Appliance> appliances;
  final List<WorktopMaterial> worktops;
  final List<PanelType> panels;
  final List<EdgeBand> edgeBands;
  final double kerf, trim;
  final List<(int, int)> hingeRules; // (hauteur max, nombre de charnières)
  final Map<String, int> legRules;
  final Map<String, HardwareItem> hardware;
  final List<String> hardwareBrands;
  HandleCatalog handles = const HandleCatalog([]); // poignées (fichier séparé)

  MaterialsDb._(this.appliances, this.worktops, this.panels, this.edgeBands, this.kerf, this.trim, this.hingeRules, this.legRules,
      this.hardware, this.hardwareBrands);

  static MaterialsDb parse(
      {required String appliances, required String worktops, required String panels, required String hardware, String? handles}) {
    final db = _parse(appliances: appliances, worktops: worktops, panels: panels, hardware: hardware);
    if (handles != null) db.handles = HandleCatalog.parse(handles);
    return db;
  }

  static MaterialsDb _parse({required String appliances, required String worktops, required String panels, required String hardware}) {
    // --- électroménager
    final ap = <String, Appliance>{};
    final aj = jsonDecode(appliances) as Map<String, dynamic>;
    (int, int, int)? triple(Object? m, String w, String h, String d) {
      if (m is! Map) return null;
      final a = m[w], b = m[h], c = m[d];
      return a is num && b is num && c is num ? (a.toInt(), b.toInt(), c.toInt()) : null;
    }

    for (final c in (aj['categories'] as List).cast<Map<String, dynamic>>()) {
      for (final it in (c['items'] as List).cast<Map<String, dynamic>>()) {
        final od = it['overall_dimensions_mm'] as Map?;
        final niche = triple(it['cutout_niche_mm'], 'width', 'height', 'depth_min') ??
            triple(it['niche_dimensions_mm'], 'width', 'height', 'depth_min') ??
            triple(it['niche_dimensions_builtin_mm'], 'width', 'height_min', 'depth');
        final cut = it['worktop_cutout_mm'] as Map?;
        ap[it['id']] = Appliance(
          id: it['id'],
          name: it['name'],
          category: c['category_id'],
          categoryName: c['name'],
          width: (od?['width'] as num?)?.toInt() ?? ((it['available_widths_mm'] as List?)?.first as num?)?.toInt(),
          height: (od?['height'] as num?)?.toInt() ?? ((it['height_range_mm'] as List?)?.last as num?)?.toInt(),
          depth: (od?['depth'] as num?)?.toInt() ?? (it['depth_mm'] as num?)?.toInt(),
          niche: niche,
          cutout: cut == null ? null : ((cut['width'] as num).toInt(), (cut['depth'] as num).toInt()),
          cutoutNote: cut?['note'] as String?,
          cabinetWidth: ((it['compatible_cabinet_width'] ?? it['compatible_tall_cabinet_width']) as num?)?.toInt(),
          minCabinetWidth: (it['minimum_base_cabinet_width'] as num?)?.toInt(),
          widths: [for (final w in (it['available_widths_mm'] ?? it['compatible_wall_cabinet_width'] ?? const []) as List) (w as num).toInt()],
          ventilationGap: (it['ventilation_back_gap_mm'] as num?)?.toInt(),
          offers: _offers(it),
        );
      }
    }

    // --- plans de travail
    final wj = jsonDecode(worktops) as Map<String, dynamic>;
    final wts = <WorktopMaterial>[
      for (final m in (wj['worktop_materials'] as List).cast<Map<String, dynamic>>())
        WorktopMaterial(
          m['id'],
          m['name'],
          [for (final t in (m['thickness_options_mm'] ?? const []) as List) (t as num).toInt()],
          [for (final p in (m['edge_profiles'] ?? const []) as List) '$p'],
          m['popular_variants_morocco'] is List
              ? [
                  for (final v in (m['popular_variants_morocco'] as List).cast<Map>())
                    Offer('${v['name']}', 'par mètre linéaire', PriceRange.fromJson(v['price_per_ml_mad']) ?? PriceRange.zero)
                ]
              : [if (PriceRange.fromJson(m['price_per_ml_mad']) != null) Offer(m['name'], 'par mètre linéaire', PriceRange.fromJson(m['price_per_ml_mad'])!)],
          [
            for (final k in ['heat_resistance', 'scratch_resistance', 'stain_resistance', 'water_sensitivity', 'maintenance', 'particularity'])
              if (m[k] != null) '${_label(k)} : ${m[k]}'
          ],
        )
    ];

    // --- panneaux et chants
    final pj = jsonDecode(panels) as Map<String, dynamic>;
    final nd = pj['nesting_defaults'] as Map<String, dynamic>;
    final pts = <PanelType>[
      for (final m in (pj['panel_types'] as List).cast<Map<String, dynamic>>())
        PanelType(
          m['id'],
          m['name'],
          [for (final u in (m['usage'] ?? const []) as List) '$u'],
          [for (final s in (m['standard_sheets'] as List).cast<Map>()) ((s['length'] as num).toInt(), (s['width'] as num).toInt())],
          [for (final t in (m['available_thicknesses_mm'] ?? const []) as List) (t as num).toInt()],
          m['moisture_resistant'] == true,
          m['grain_direction_mandatory'] == true,
          _offers(m),
          m.keys.any((k) => k.contains('2440x1220')),
        )
    ];
    final ebs = <EdgeBand>[
      for (final e in (nd['edge_banding_Options'] ?? nd['edge_banding_options'] as List? ?? const []) as List)
        EdgeBand('${(e as Map)['type']}', (e['thickness_mm'] as num).toDouble(), '${e['usage']}', (e['price_per_meter_mad'] as num).toDouble())
    ];

    // --- quincaillerie
    final hj = jsonDecode(hardware) as Map<String, dynamic>;
    final rules = hj['auto_calculation_rules'] as Map<String, dynamic>;
    final hinges = [
      for (final r in (rules['hinges_per_door_by_height'] as List).cast<Map>()) ((r['max_height_mm'] as num).toInt(), (r['hinges_qty'] as num).toInt())
    ];
    final legs = (rules['plinth_legs_per_cabinet'] as Map).map((k, v) => MapEntry('$k', (v as num).toInt()));
    final hw = <String, HardwareItem>{};
    final brands = <String>{};
    for (final c in (hj['categories'] as List).cast<Map<String, dynamic>>()) {
      for (final it in (c['items'] as List).cast<Map<String, dynamic>>()) {
        final offers = _offers(it);
        hw[it['id']] = HardwareItem(it['id'], it['name'], c['name'], offers);
        for (final o in offers) {
          if (it.keys.any((k) => k.startsWith('brands_pricing'))) brands.add(o.label.split(' ').first);
        }
      }
    }
    return MaterialsDb._(ap, wts, pts, ebs, (nd['saw_kerf_mm'] as num).toDouble(), (nd['panel_trim_margin_mm'] as num).toDouble(), hinges,
        legs, hw, brands.toList());
  }

  static String _label(String k) => switch (k) {
        'heat_resistance' => 'Chaleur',
        'scratch_resistance' => 'Rayures',
        'stain_resistance' => 'Taches',
        'water_sensitivity' => 'Eau',
        'maintenance' => 'Entretien',
        _ => 'Particularité',
      };

  int hingesFor(int doorHeight) {
    for (final (h, q) in hingeRules) {
      if (doorHeight <= h) return q;
    }
    return hingeRules.isEmpty ? 2 : hingeRules.last.$2 + 1;
  }

  PanelType? panel(String id) => panels.where((p) => p.id == id).firstOrNull;
  WorktopMaterial? worktop(String id) => worktops.where((w) => w.id == id).firstOrNull;
  EdgeBand? edge(double thickness) => edgeBands.where((e) => (e.thickness - thickness).abs() < 0.01).firstOrNull;

  /// Électroménager de cette catégorie (pour proposer un remplacement).
  List<Appliance> ofCategory(String category) => appliances.values.where((a) => a.category == category).toList();
}

// ---------------------------------------------------------------------------
// Choix du projet (panneaux, plan de travail, gamme)
// ---------------------------------------------------------------------------

class ProjectSpecs {
  String carcassPanel;
  String frontPanel;
  String worktopMaterial;
  int worktopVariant;
  int worktopThickness;
  String hardwareBrand;
  int applianceTier; // 0 entrée, 1 milieu, 2 haut de gamme (index de segment quand il existe)
  double carcassEdge; // chant visible des caissons (mm)
  double frontEdge; // chant des façades (mm)
  // tarifs réels de l'atelier (MAD) ; null = fourchette du catalogue
  double? sheetPrice; // prix d'une feuille (caissons)
  double? frontSheetPrice, backSheetPrice; // prix d'une feuille de façades, de fonds (null : caissons / prix public)
  double? edgePriceMin, edgePriceMax; // chant au mètre, pose comprise
  double cuttingPerSheet; // découpe (service) par feuille
  String hobEnergy; // 'gas' | 'electric' : alimentation de la plaque
  String gamme; // 'standard' : MDF, chiffré à la feuille ; 'moyen' : caissons Alvic, à l'article ; 'luxe' : contreplaqué latté, à l'article
  String mpCarcass; // moyenne gamme : caissons 'alvic' ou 'alvic_hydro'
  String mpDoor; // moyenne gamme : portes 'auto', 'pi' (poignée intégrée) ou 'plain' (sans)

  ProjectSpecs({
    this.carcassPanel = 'mdf_melamine_hydrofuge',
    this.frontPanel = 'mdf_melamine_hydrofuge',
    this.worktopMaterial = 'quartz_synthese',
    this.worktopVariant = 0,
    this.worktopThickness = 20,
    this.hardwareBrand = 'Samet',
    this.applianceTier = 1,
    this.carcassEdge = 1.0,
    this.frontEdge = 2.0,
    this.sheetPrice = 850,
    this.frontSheetPrice,
    this.backSheetPrice,
    this.edgePriceMin = 9,
    this.edgePriceMax = 10,
    this.cuttingPerSheet = 53,
    this.hobEnergy = 'gas',
    this.gamme = 'standard',
    this.mpCarcass = 'alvic',
    this.mpDoor = 'auto',
  });

  Map<String, dynamic> toJson() => {
        'carcass_panel': carcassPanel,
        'front_panel': frontPanel,
        'worktop_material': worktopMaterial,
        'worktop_variant': worktopVariant,
        'worktop_thickness': worktopThickness,
        'hardware_brand': hardwareBrand,
        'appliance_tier': applianceTier,
        'carcass_edge': carcassEdge,
        'front_edge': frontEdge,
        'sheet_price': sheetPrice,
        if (frontSheetPrice != null) 'front_sheet_price': frontSheetPrice,
        if (backSheetPrice != null) 'back_sheet_price': backSheetPrice,
        'edge_price_min': edgePriceMin,
        'edge_price_max': edgePriceMax,
        'cutting_per_sheet': cuttingPerSheet,
        'hob_energy': hobEnergy,
        'gamme': gamme,
        if (mpCarcass != 'alvic') 'mp_carcass': mpCarcass,
        if (mpDoor != 'auto') 'mp_door': mpDoor,
      };

  factory ProjectSpecs.fromJson(Map<String, dynamic> j) {
    final d = ProjectSpecs();
    return ProjectSpecs(
      carcassPanel: j['carcass_panel'] ?? d.carcassPanel,
      frontPanel: j['front_panel'] ?? d.frontPanel,
      worktopMaterial: j['worktop_material'] ?? d.worktopMaterial,
      worktopVariant: j['worktop_variant'] ?? d.worktopVariant,
      worktopThickness: j['worktop_thickness'] ?? d.worktopThickness,
      hardwareBrand: j['hardware_brand'] ?? d.hardwareBrand,
      applianceTier: j['appliance_tier'] ?? d.applianceTier,
      carcassEdge: (j['carcass_edge'] as num?)?.toDouble() ?? d.carcassEdge,
      frontEdge: (j['front_edge'] as num?)?.toDouble() ?? d.frontEdge,
      sheetPrice: j.containsKey('sheet_price') ? (j['sheet_price'] as num?)?.toDouble() : d.sheetPrice,
      frontSheetPrice: (j['front_sheet_price'] as num?)?.toDouble(),
      backSheetPrice: (j['back_sheet_price'] as num?)?.toDouble(),
      edgePriceMin: j.containsKey('edge_price_min') ? (j['edge_price_min'] as num?)?.toDouble() : d.edgePriceMin,
      edgePriceMax: j.containsKey('edge_price_max') ? (j['edge_price_max'] as num?)?.toDouble() : d.edgePriceMax,
      cuttingPerSheet: (j['cutting_per_sheet'] as num?)?.toDouble() ?? d.cuttingPerSheet,
      hobEnergy: j['hob_energy'] as String? ?? d.hobEnergy,
      gamme: j['gamme'] as String? ?? d.gamme,
      mpCarcass: j['mp_carcass'] as String? ?? d.mpCarcass,
      mpDoor: j['mp_door'] as String? ?? d.mpDoor,
    );
  }
}

// ---------------------------------------------------------------------------
// Électroménager des caissons
// ---------------------------------------------------------------------------

/// Électroménager prévu par défaut pour un caisson (vide si aucun).
List<String> defaultAppliances(CabinetModel m, PlacedCabinet c) => m.appliances.isNotEmpty ? m.appliances : switch (m.id) {
      'base_cooktop_oven' => [c.width >= 900 ? 'oven_large_90' : 'oven_standard_60', c.width >= 750 ? 'cooktop_5_burners_75_90' : 'cooktop_4_burners_60'],
      'tall_oven_microwave' => ['oven_standard_60', 'microwave_builtin_60'],
      'tall_integrated_fridge' => ['fridge_builtin_60'],
      'base_integrated_dishwasher_door' => [c.width <= 450 ? 'dishwasher_45_compact' : 'dishwasher_60_standard'],
      'base_sink' || 'base_sink_1door' || 'base_sink_2doors' || 'base_sink_drawers' =>
        [c.width >= 800 ? 'sink_2_bowls' : 'sink_1_bowl_undermount_or_topmount'],
      'wall_integrated_hood' => ['hood_telescopic_or_builtin'],
      _ => const [],
    };

List<String> appliancesOf(CabinetModel m, PlacedCabinet c) => c.appliances ?? defaultAppliances(m, c);

/// Contrôles de compatibilité caisson / appareil (niches, largeurs, découpes).
List<Issue> applianceChecks(LayoutEngine e, MaterialsDb db) {
  final out = <Issue>[];
  final T = e.project.cut.carcassThickness;
  for (final c in e.project.items) {
    final m = e.modelOf(c);
    for (final id in appliancesOf(m, c)) {
      final a = db.appliances[id];
      if (a == null) continue;
      final inner = c.width - 2 * T;
      if (a.minCabinetWidth != null && c.width < a.minCabinetWidth!) {
        out.add(Issue(Severity.error, 'appliance_width', L('{0} : caisson de {1} mm minimum (actuel {2})', [L(a.name), a.minCabinetWidth, c.width]), [c.uid]));
      }
      if (a.cabinetWidth != null && c.width != a.cabinetWidth && a.category != 'cooktops') {
        out.add(Issue(Severity.warning, 'appliance_cabinet', L('{0} : prévu pour un caisson de {1} mm (actuel {2})', [L(a.name), a.cabinetWidth, c.width]), [c.uid]));
      }
      if (a.niche != null && m.isCarcass && inner < a.niche!.$1) {
        out.add(Issue(Severity.error, 'appliance_niche', L('{0} : niche de {1} mm, intérieur du caisson {2} mm', [L(a.name), a.niche!.$1, inner]), [c.uid]));
      }
      if (a.category == 'dishwashers' && a.niche != null && (c.width - a.niche!.$1).abs() > 5) {
        out.add(Issue(Severity.error, 'dishwasher_width', L('{0} : façade de {1} mm attendue (actuelle {2})', [L(a.name), a.niche!.$1, c.width]), [c.uid]));
      }
      if (a.category == 'refrigerators' && a.niche != null && c.height - 2 * T < a.niche!.$2) {
        out.add(Issue(Severity.error, 'fridge_niche', L('{0} : niche de {1} mm de haut, colonne trop basse', [L(a.name), a.niche!.$2]), [c.uid]));
      }
    }
    // hotte au moins aussi large que la plaque
    if (m.id == 'base_cooktop_oven') {
      final hob = appliancesOf(m, c).map((id) => db.appliances[id]).whereType<Appliance>().where((a) => a.category == 'cooktops').firstOrNull;
      final hood = e.project.items.where((h) => (e.modelOf(h).isHoodUnit || e.modelOf(h).isFreeHood) && h.wallId == c.wallId && h.s < c.right && c.s < h.right).firstOrNull;
      if (hob != null && hood != null && hob.width != null && hood.width + 5 < hob.width!) {
        out.add(Issue(Severity.warning, 'hood_narrow', L('Hotte de {0} mm plus étroite que la plaque ({1} mm)', [hood.width, hob.width]), [hood.uid, c.uid]));
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Quincaillerie calculée et estimation
// ---------------------------------------------------------------------------

class SupplyLine {
  final String section; // Quincaillerie, Électroménager, Panneaux, Chants, Plan de travail
  final String name;
  final String detail;
  final double qty;
  final String unit;
  final PriceRange unitPrice;
  const SupplyLine(this.section, this.name, this.detail, this.qty, this.unit, this.unitPrice);
  PriceRange get total => unitPrice * qty;
}

/// Quincaillerie de toute la cuisine, d'après les règles du catalogue.
List<SupplyLine> hardwareList(LayoutEngine e, MaterialsDb db, ProjectSpecs specs, List<CutPart> parts, double plinthLength) {
  final lines = <String, (HardwareItem, double, String, String)>{};
  void add(String id, double qty, {String unit = 'pce', String detail = ''}) {
    final it = db.hardware[id];
    if (it == null || qty <= 0) return;
    final k = '$id|$detail';
    final prev = lines[k];
    lines[k] = (it, (prev?.$2 ?? 0) + qty, unit, detail);
  }

  // charnières : d'après la hauteur de chaque porte
  for (final p in parts) {
    if (!p.name.startsWith('Porte') || p.name.contains('relevable')) continue;
    final perDoor = db.hingesFor(p.length);
    if (p.name.startsWith('Porte d\'angle')) {
      add('hinge_corner_bifold_60', perDoor * p.qty.toDouble(), detail: 'portes pliantes d\'angle');
    } else {
      add('hinge_110_soft_close', perDoor * p.qty.toDouble(), detail: '${p.length} mm : $perDoor par porte');
    }
  }
  // abattants : un compas par porte relevable
  for (final p in parts.where((p) => p.name == 'Porte relevable')) {
    add('lift_stay_single_door_heavy', p.qty.toDouble(), unit: 'jeu');
  }
  // tiroirs : casserolier si la façade fait 250 mm ou plus
  for (final p in parts.where((p) => p.name == 'Façade tiroir')) {
    add(p.width >= 250 ? 'double_wall_box_casserolier_deep' : 'double_wall_box_drawer_low', p.qty.toDouble(), unit: 'kit');
  }
  final gola = e.project.style.handle == 'gola';
  var lowRun = 0.0, drawerRun = 0.0;
  for (final c in e.project.items) {
    final m = e.modelOf(c);
    // pieds réglables
    if (m.floorSupport && m.isCarcass && !m.kind.isFiller) {
      final n = m.shape == CabinetShape.lShape ? (db.legRules['corner_cabinet_L'] ?? 6) : c.width <= 800 ? (db.legRules['width_up_to_800mm'] ?? 4) : (db.legRules['width_900mm_to_1200mm'] ?? 6);
      add('adjustable_cabinet_legs', n.toDouble(), detail: 'H${e.project.standards.plinthHeight}');
    }
    if (m.kind.isHigh && m.isCarcass) add('wall_cabinet_hangers', 1, unit: 'paire');
    if (m.id == 'base_pullout_spice') add('pullout_bottle_spice_rack', 1);
    if (m.shape == CabinetShape.blind) add('corner_magic_or_lemans', 1, detail: 'angle mort');
    if (m.shape == CabinetShape.lShape && m.kind == CabinetKind.cornerBase) add('corner_magic_or_lemans', 1, detail: 'tourniquet 360');
    if (m.shape == CabinetShape.blind) add('hinge_blind_corner_90', 2);
    if (m.id == 'base_sink') {
      add('under_sink_aluminium_mat', 1);
      final above = e.project.items.any((h) => e.modelOf(h).kind == CabinetKind.wall && h.wallId == c.wallId && h.s < c.right && c.s < h.right);
      if (above) add('dish_drainer_wall_cabinet', 1, detail: 'au-dessus de l\'évier');
    }
    // le profil passe aussi sur le lave-vaisselle et tourne dans les meubles d'angle (moins l'angle caché)
    if (m.kind.isLow && (m.isCarcass || m.id == 'base_integrated_dishwasher_door')) {
      lowRun += m.kind.isCorner && c.widthRight != null ? math.max(0, c.width + c.widthRight! - 2 * c.depth) : c.width;
    }
    if (m.id == 'base_drawers_multi') drawerRun += c.width;
  }
  // poignées ou profils Gola
  if (gola) {
    final gf = e.project.style.handleFinish ?? HandleCatalog.golaFinishes.first;
    add('gola_profile_horizontal_L', (lowRun / 3000).ceilToDouble(), unit: 'barre 3 m', detail: gf);
    if (drawerRun > 0) add('gola_profile_horizontal_C', (drawerRun / 3000).ceilToDouble(), unit: 'barre 3 m', detail: gf);
    final talls = e.project.items.where((c) => e.modelOf(c).kind == CabinetKind.tall).length;
    if (talls > 0) add('gola_profile_vertical_tall', talls.toDouble(), unit: 'barre', detail: gf);
    if (e.project.style.handleAt('haut').kind == 'gola') {
      final wallDoors = parts.where((p) => p.name.startsWith('Porte') && p.length < 1000).fold<int>(0, (a, p) => a + p.qty);
      add('push_to_open_latch', wallDoors.toDouble());
    }
  } else {
    // endroits sans modèle du catalogue : poignée standard
    var plain = 0;
    for (final z in frontsByZone(e, parts).entries) {
      final ch = e.project.style.handleAt(z.key);
      if (ch.kind != 'push' && db.handles.byId(ch.id) == null) plain += z.value.fold<int>(0, (a, p) => a + p.qty);
    }
    if (plain > 0) add('handle_standard_screw_on', plain.toDouble());
  }
  // plinthe en barres de 4 m
  if (plinthLength > 0) add('kitchen_plinth_pvc_aluminium', (plinthLength / 4000).ceilToDouble(), unit: 'barre 4 m');

  return [
    for (final (it, qty, unit, detail) in lines.values)
      () {
        // prix de la marque choisie dans le catalogue des marques (marché marocain), sinon offre de la base
        final bp = BrandCatalog.hardwarePrice(specs.hardwareBrand, it.id);
        final label = bp != null ? specs.hardwareBrand : it.offer(specs.hardwareBrand).label;
        return SupplyLine('Quincaillerie', it.name, [label, if (detail.isNotEmpty) detail].join(' · '), qty, unit, bp ?? it.offer(specs.hardwareBrand).price);
      }(),
    ...handleLines(e, db, parts),
  ];
}

/// Façades à poignée, par endroit : (hauteur, largeur, nombre) et poignée choisie.
Map<String, List<CutPart>> frontsByZone(LayoutEngine e, List<CutPart> parts) {
  final kinds = <String, CabinetKind>{};
  for (final c in e.project.items) {
    final m = e.modelOf(c);
    kinds[m.name] = m.kind;
  }
  final out = <String, List<CutPart>>{};
  for (final p in parts) {
    final drawer = p.name == 'Façade tiroir';
    if (!drawer && !p.name.startsWith('Porte')) continue;
    final name = p.cabinet.replaceFirst(RegExp(r'^Rep\. \d+ - '), '');
    out.putIfAbsent(LayoutEngine.handleZone(kinds[name] ?? CabinetKind.base, drawer: drawer), () => []).add(p);
  }
  return out;
}

/// Poignées du catalogue : à l'unité, en barres de 3 m (profil continu) ou usinage par façade, selon l'endroit.
List<SupplyLine> handleLines(LayoutEngine e, MaterialsDb db, List<CutPart> parts) {
  final st = e.project.style;
  final xxl = st.tallXxl && st.handle != 'gola' ? db.handles.items.where((x) => x.render == HandleRender.xxl).firstOrNull : null;
  var tallDoors = 0, push = 0;
  // mêmes modèle, taille et finition : une seule ligne
  final groups = <String, (HandleModel, HandleChoice, List<CutPart>)>{};
  for (final MapEntry(key: zone, value: list) in frontsByZone(e, parts).entries) {
    final ch = st.handleAt(zone);
    final mine = <CutPart>[];
    for (final p in list) {
      if (xxl != null && p.name.startsWith('Porte') && p.length >= 1200) {
        tallDoors += p.qty;
      } else {
        mine.add(p);
      }
    }
    if (ch.kind == 'push') push += mine.fold<int>(0, (a, p) => a + p.qty);
    final h = db.handles.byId(ch.id);
    if (h == null || h.render == HandleRender.gola || h.render == HandleRender.push || mine.isEmpty) continue;
    final k = '${h.id}|${ch.size}|${ch.finish}|${zone == 'tiroir' && ch.pair}';
    groups.putIfAbsent(k, () => (h, ch, <CutPart>[])).$3.addAll(mine);
  }
  final out = <SupplyLine>[];
  for (final (h, ch, fronts) in groups.values) {
    final size = ch.size ?? h.defaultSize;
    final finish = ch.finish ?? (h.finishes.isEmpty ? '' : h.finishes.first);
    final detail = [
      if (size > 0) '${h.sizeLabel.toLowerCase()} $size mm',
      if (finish.isNotEmpty) finish,
      if (h.drillingText(size).isNotEmpty) h.drillingText(size),
    ].join(' · ');
    final count = fronts.fold<int>(0, (a, p) => a + p.qty * (ch.pair && p.name == 'Façade tiroir' && p.length >= 780 && h.holes > 0 ? 2 : 1));
    if (h.perBar) {
      final len = fronts.fold<double>(0, (a, p) => a + p.width * p.qty);
      out.add(SupplyLine('Quincaillerie', h.name, '$detail · ${(len / 1000).toStringAsFixed(1)} m de façades', (len / 3000).ceilToDouble(), 'barre 3 m', h.price));
    } else {
      out.add(SupplyLine('Quincaillerie', h.name, detail, count.toDouble(), h.perDoorMilling ? 'façade' : 'pce', h.price));
    }
  }
  if (xxl != null && tallDoors > 0) {
    out.add(SupplyLine('Quincaillerie', xxl.name, 'portes de colonne · ${xxl.drillingText(xxl.defaultSize)}', tallDoors.toDouble(), 'pce', xxl.price));
  }
  // ouverture par pression : un loqueteau par façade
  final latch = push == 0 ? null : db.hardware['push_to_open_latch'];
  if (latch != null) out.add(SupplyLine('Quincaillerie', latch.name, 'façades sans poignée', push.toDouble(), 'pce', latch.offer('').price));
  return out;
}

/// Électroménager de la cuisine (gamme choisie quand elle existe).
List<SupplyLine> applianceList(LayoutEngine e, MaterialsDb db, ProjectSpecs specs) {
  final counts = <String, int>{};
  for (final c in e.project.items) {
    for (final id in appliancesOf(e.modelOf(c), c)) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }
  return [
    for (final en in counts.entries)
      if (db.appliances[en.key] != null)
        () {
          final a = db.appliances[en.key]!;
          final o = a.offers.isEmpty ? null : a.offers[math.min(specs.applianceTier, a.offers.length - 1)];
          return SupplyLine('Électroménager', a.name, [if (o != null) o.label, a.dimsText].where((s) => s.isNotEmpty).join(' · '),
              en.value.toDouble(), 'pce', o?.price ?? PriceRange.zero);
        }()
  ];
}

/// Estimation complète : panneaux, chants, plan de travail, quincaillerie, électroménager.
List<SupplyLine> estimate(LayoutEngine e, MaterialsDb db, ProjectSpecs specs, CutPlan plan, Bom bom) {
  final out = <SupplyLine>[];
  final cs = plan.settings;
  // panneaux : une ligne par matériau débité
  for (final mat in plan.materials) {
    final n = plan.newSheets(mat).length;
    final offcuts = plan.stockSheets(mat).toList();
    final kind = cs.panelKind(mat);
    final main = mat == cs.carcassMaterial || mat == cs.frontKey;
    final decor = mat.startsWith('MDF plaqué') || mat.startsWith('Panneau décor');
    final pt = decor
        ? db.panel('mdf_plaque_essence_fine')
        : main
            ? db.panel(panelIdOf(mat == cs.frontKey ? cs.frontMaterial : mat) ?? (mat == cs.frontKey && cs.frontMaterial != cs.carcassMaterial ? specs.frontPanel : specs.carcassPanel))
            : null;
    final (sL, sW) = cs.sheetDimensionsFor(mat);
    // prix d'une feuille fixé par l'atelier, propre à chaque type de panneau (caissons, façades, fonds)
    final own = switch (kind) {
      PanelKind.front => specs.frontSheetPrice ?? (main ? specs.sheetPrice : null),
      PanelKind.back => specs.backSheetPrice,
      _ => main ? specs.sheetPrice : null,
    };
    final atelier = own != null;
    // fond arrière : prix public du panneau mince blanc le plus proche en épaisseur, au prorata du format réglé
    final back = !atelier && kind == PanelKind.back && pt == null ? PublicPrices.back(cs.backThickness) : null;
    final backPrice = back == null
        ? 0.0
        : cs.backSheetLength == null || cs.backSheetWidth == null
            ? back.price.toDouble()
            : (back.price * sL * sW / (back.length * back.width)).roundToDouble();
    final price = own != null
        ? PriceRange(own, own)
        : back != null
            ? PriceRange(backPrice, backPrice)
            : pt?.sheetPrice(sL, sW) ?? PriceRange.zero;
    final thick = cs.thicknessFor(mat);
    final how = atelier
        ? ' · tarif atelier'
        : back != null
            ? ' · prix public ${back.name}'
            : pt == null
                ? ' · prix à demander'
                : '';
    final label = decor ? '$mat (${pt?.name ?? 'décor'})' : (main ? pt?.name ?? mat : mat);
    if (n > 0 || offcuts.isEmpty) {
      out.add(SupplyLine('Panneaux', label, '$sL x $sW x $thick mm$how', n.toDouble(), 'feuille', price));
    }
    if (offcuts.isNotEmpty) {
      // chutes du stock : au prorata du prix de la feuille, selon le réglage du projet
      final k = cs.offcutPct / 100 / (sL * sW / 1e6);
      final m2 = offcuts.fold<double>(0, (a, s) => a + s.length * s.width) / 1e6;
      out.add(SupplyLine('Panneaux', 'Chutes du stock', '$label · $thick mm · ${offcuts.length} chute(s)', double.parse(m2.toStringAsFixed(2)), 'm²',
          PriceRange(price.min * k, price.max * k)));
    }
    if (specs.cuttingPerSheet > 0 && n > 0) {
      out.add(SupplyLine('Panneaux', 'Découpe à la scie à panneaux', 'service par feuille', n.toDouble(), 'feuille',
          PriceRange(specs.cuttingPerSheet, specs.cuttingPerSheet)));
    }
  }
  // chants : caissons (face visible) et façades
  double carcassEdge = 0, frontEdge = 0;
  for (final p in plan.parts) {
    final isFront = p.name.startsWith('Porte') || p.name.startsWith('Façade') || p.name.startsWith('Fileur') || p.name.startsWith('Joue') ||
        p.name.startsWith('Panneau') || p.name.startsWith('Habillage');
    if (isFront) {
      frontEdge += p.edgeLength * p.qty / 1000;
    } else {
      carcassEdge += p.edgeLength * p.qty / 1000;
    }
  }
  for (final (len, th) in [(carcassEdge, specs.carcassEdge), (frontEdge, specs.frontEdge)]) {
    final eb = db.edge(th);
    if (len > 0 && eb != null) {
      final atelier = specs.edgePriceMin != null && specs.edgePriceMax != null;
      out.add(SupplyLine('Chants', '${eb.type} (${eb.thickness} mm)', atelier ? '${eb.usage} · fourni et collé' : eb.usage,
          double.parse(len.toStringAsFixed(2)), 'm',
          atelier ? PriceRange(specs.edgePriceMin!, specs.edgePriceMax!) : PriceRange(eb.pricePerM, eb.pricePerM)));
    }
  }
  // plan de travail
  final (wtId, wtVariant) = worktopOf(e.project);
  final wt = db.worktop(wtId);
  if (wt != null && bom.worktopLength > 0 && wt.variants.isNotEmpty) {
    final v = wt.variants[math.min(wtVariant, wt.variants.length - 1)];
    // épaisseur : celle choisie si la matière l'a, sinon la plus courante de la matière
    final th = wt.thicknesses.isEmpty || wt.thicknesses.contains(specs.worktopThickness) ? specs.worktopThickness : wt.thicknesses.last;
    // îlot : son propre plan, jambages compris s'il est en cascade
    final islLen = e.room.island == null ? 0.0 : e.runs('I', (m) => e.hasWorktop && m.kind.isLow).fold<double>(0, (a, r) => a + r.$2 - r.$1);
    final islLook = islLen > 0 ? e.project.style.islandTop : null;
    final falls = islLen > 0 && e.project.style.islandWaterfall ? 2 * e.std.worktopTop.toDouble() : 0.0;
    final own = islLook == null ? null : worktopLooks[islLook];
    final main = bom.worktopLength - (own != null ? islLen : 0) + (own == null ? falls : 0);
    out.add(SupplyLine('Plan de travail', wt.name, '${v.label} · $th mm', double.parse((main / 1000).toStringAsFixed(2)),
        'm.l.', v.price));
    if (own != null) {
      final iw = db.worktop(own.$1);
      if (iw != null && iw.variants.isNotEmpty) {
        final iv = iw.variants[math.min(own.$2, iw.variants.length - 1)];
        out.add(SupplyLine('Plan de travail', 'Îlot : ${iw.name}', '${iv.label}${falls > 0 ? ' · jambages compris' : ''}', double.parse(((islLen + falls) / 1000).toStringAsFixed(2)), 'm.l.', iv.price));
      }
    }
    // crédence ou relevé dans la même matière : prix au mètre (600 mm de profondeur) ramené au m²
    if (splashMatchesTop(e.project.style)) {
      final m2 = double.parse(splashArea(e).toStringAsFixed(2));
      if (m2 > 0) {
        out.add(SupplyLine('Plan de travail', e.project.style.splash == splashUpstand ? 'Relevé assorti 10 cm' : 'Crédence assortie', '${v.label} · $th mm', m2, 'm²', v.price * (1 / 0.6)));
      }
    }
  }
  out.addAll(hardwareList(e, db, specs, plan.parts, bom.plinthLength));
  out.addAll(assemblySupplyLines(e, plan.parts)); // visserie, fixations et pose
  if (e.project.items.isNotEmpty) {
    out.add(const SupplyLine(
      'Pose',
      'Pose des caissons de cuisine',
      'Menuiserie, mise à niveau et fixations murales (1 000 MAD éco à 6 000 MAD luxe)',
      1,
      'forfait',
      PriceRange(1000, 6000),
    ));
    if (bom.worktopLength > 0) {
      out.add(const SupplyLine(
        'Pose',
        'Pose et façonnage du plan de travail',
        'Marbrerie, découpes encastrement évier/plaque, joints et retombées (800 MAD kitchenette à 4 000 MAD luxe)',
        1,
        'forfait',
        PriceRange(800, 4000),
      ));
    }
  }
  out.addAll(applianceList(e, db, specs));
  out.addAll(fixtureSupplyLines(e));
  out.addAll(furnitureAccessoryLines(e.project.accessories));
  return out;
}

/// Fourchettes indicatives des sanitaires (fourniture seule, marché marocain, gamme courante à confort).
const fixturePrices = <String, PriceRange>{
  'wc_suspendu': PriceRange(2500, 6000),
  'wc_sol': PriceRange(1200, 3500),
  'bidet': PriceRange(900, 2500),
  'lavabo': PriceRange(600, 2000),
  'vasque_double': PriceRange(2500, 7000),
  'baignoire': PriceRange(2500, 8000),
  'douche': PriceRange(3000, 8000),
  'douche_italienne': PriceRange(4000, 10000),
  'seche_serviettes': PriceRange(900, 2500),
  'chauffe_eau': PriceRange(1800, 3500),
  'miroir': PriceRange(600, 2500),
};

/// Sanitaires, chauffe-eau et machines à laver (posés ou logés dans un meuble) : fourniture indicative, à confirmer avec le client.
List<SupplyLine> fixtureSupplyLines(LayoutEngine e) {
  final n = <(String, String?), int>{};
  for (final o in e.project.objects) {
    final f = o.fixture;
    if (f == null) continue;
    final k = (f.id, o.capacity?.label);
    n[k] = (n[k] ?? 0) + 1;
  }
  for (final c in e.project.items) {
    for (final mc in e.machinesIn(c)) {
      final k = (mc.ref.substring(8), mc.cap);
      n[k] = (n[k] ?? 0) + 1;
    }
  }
  return [
    for (final MapEntry(key: (id, cap), value: q) in n.entries)
      () {
        final f = fixtureById(id)!;
        final v = cap == null ? null : f.variants.where((x) => x.label == cap).firstOrNull;
        return SupplyLine(f.category, v == null ? f.name : '${f.name} ${v.label}', 'fourniture seule, prix indicatif à confirmer', q.toDouble(), 'pce',
            v?.price ?? fixturePrices[id] ?? PriceRange.zero);
      }(),
  ];
}

PriceRange totalOf(Iterable<SupplyLine> lines) => lines.fold(PriceRange.zero, (a, l) => a + l.total);
