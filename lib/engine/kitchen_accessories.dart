// Catalogue exhaustif des accessoires d'équipement de cuisine & quincaillerie
// (INOXA collection Hyper, Blum, Kesseböhmer, Hettich, Grass, Vauth-Sagel, DTC, Atelier).
// Gère la compatibilité par zone de caisson (base, colonne, angle, haut, sous-évier)
// et par largeur de meuble, ainsi que les illustrations produits, lifestyle et plans techniques.

import 'dart:convert';
import 'materials.dart';
import 'project.dart';

class KitchenAccessory {
  final String id;
  final String code;
  final String brand;
  final String collection;
  final String category;
  final String type;
  final String nameFr;
  final String? nameEn;
  final String? nameIt;
  final List<String> tiers;
  final List<String> cabinetZones;
  final Map<String, dynamic> dimensions;
  final int? shelvesCount;
  final String? slides;
  final bool softClose;
  final bool antiSlipMat;
  final List<String> finishes;
  final Map<String, String> illustrations;
  final double? loadCapacityKg;
  final int? sourcePdfPage;
  final String? notes;
  final PriceRange price;

  const KitchenAccessory({
    required this.id,
    required this.code,
    required this.brand,
    required this.collection,
    required this.category,
    required this.type,
    required this.nameFr,
    this.nameEn,
    this.nameIt,
    this.tiers = const [],
    this.cabinetZones = const [],
    this.dimensions = const {},
    this.shelvesCount,
    this.slides,
    this.softClose = false,
    this.antiSlipMat = false,
    this.finishes = const [],
    this.illustrations = const {},
    this.loadCapacityKg,
    this.sourcePdfPage,
    this.notes,
    required this.price,
  });

  /// Chemin Flutter asset de la photo produit (détourée sur fond blanc).
  String? get productAsset {
    final path = illustrations['product'];
    if (path == null || path.isEmpty) return null;
    return 'assets/$path';
  }

  /// Chemin Flutter asset de la photo d'ambiance / lifestyle.
  String? get lifestyleAsset {
    final path = illustrations['lifestyle'];
    if (path == null || path.isEmpty) return null;
    return 'assets/$path';
  }

  /// Chemin Flutter asset du schéma technique / blueprint avec cotes.
  String? get blueprintAsset {
    final path = illustrations['blueprint'];
    if (path == null || path.isEmpty) return null;
    return 'assets/$path';
  }

  /// Largeurs de caisson compatibles (mm).
  List<int> get supportedWidths {
    final out = <int>{};
    final vl = dimensions['variants_L_W'];
    if (vl is List) {
      for (final v in vl) {
        if (v is Map && v['cabinet_width_L_mm'] is num) {
          out.add((v['cabinet_width_L_mm'] as num).toInt());
        }
      }
    }
    final cw = dimensions['cabinet_widths_L'];
    if (cw is List) {
      for (final w in cw) {
        if (w is num) out.add(w.toInt());
      }
    }
    final dw = dimensions['door_widths_L'];
    if (dw is List) {
      for (final w in dw) {
        if (w is num) out.add(w.toInt());
      }
    }
    final sorted = out.toList()..sort();
    return sorted;
  }

  /// Largeur minimale de caisson requise (mm).
  int? get minCabinetWidth {
    final wMin = dimensions['cabinet_width_L_min'] ?? dimensions['cabinet_width_min'];
    if (wMin is num) return wMin.toInt();
    final sw = supportedWidths;
    if (sw.isNotEmpty) return sw.first;
    return null;
  }

  /// Vérifie si l'accessoire convient pour un caisson donné (zone et largeur).
  bool isCompatibleWith({required String zone, int? width}) {
    // 1. Vérification de la zone
    if (cabinetZones.isNotEmpty) {
      final matchesZone = switch (zone) {
        'base' => cabinetZones.contains('base') || cabinetZones.contains('base_and_overhead') || cabinetZones.contains('under_sink') || cabinetZones.contains('drawer'),
        'column' || 'tall' => cabinetZones.contains('column') || cabinetZones.contains('tall'),
        'corner' => cabinetZones.contains('corner'),
        'overhead' || 'wall' => cabinetZones.contains('overhead') || cabinetZones.contains('base_and_overhead'),
        'under_sink' => cabinetZones.contains('under_sink') || cabinetZones.contains('base'),
        _ => cabinetZones.contains(zone),
      };
      if (!matchesZone) return false;
    }

    // 2. Vérification de la largeur
    if (width == null) return true;
    final sw = supportedWidths;
    if (sw.isNotEmpty) {
      return sw.contains(width);
    }
    final minW = minCabinetWidth;
    if (minW != null && width < minW) return false;
    final maxW = dimensions['cabinet_width_max'];
    if (maxW is num && width > maxW.toInt()) return false;
    return true;
  }

  factory KitchenAccessory.fromJson(String id, Map<String, dynamic> j) {
    final code = j['code'] as String? ?? id;
    final brand = j['brand'] as String? ?? 'Atelier';
    final collection = j['collection'] as String? ?? '';
    final category = j['category'] as String? ?? 'base';
    final type = j['type'] as String? ?? '';
    final nameFr = j['name_fr'] as String? ?? code;
    final nameEn = j['name_en'] as String?;
    final nameIt = j['name_it'] as String?;
    final tiers = (j['tiers'] as List?)?.map((e) => '$e').toList() ?? const [];
    final cabinetZones = (j['cabinet_zones'] as List?)?.map((e) => '$e').toList() ?? const [];
    final dimensions = (j['dimensions_mm'] as Map?)?.cast<String, dynamic>() ?? const {};
    final shelvesCount = (j['shelves_count'] as num?)?.toInt();
    final slides = j['slides'] as String?;
    final softClose = j['soft_close'] == true;
    final antiSlipMat = j['anti_slip_mat'] == true;
    final finishes = (j['finishes'] as List?)?.map((e) => '$e').toList() ?? const [];
    final illustrations = (j['illustrations'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {};
    double? loadCap;
    final rawCap = j['load_capacity_kg'];
    if (rawCap is num) {
      loadCap = rawCap.toDouble();
    } else if (rawCap is List && rawCap.isNotEmpty && rawCap.first is num) {
      loadCap = (rawCap.first as num).toDouble();
    }
    final pdfPage = (j['source_pdf_page'] as num?)?.toInt();
    final notes = j['notes'] as String?;

    // Estimation de la fourchette de prix public indicatif (Maroc - MAD)
    final price = _estimatePrice(brand, category, type, cabinetZones, shelvesCount);

    return KitchenAccessory(
      id: id,
      code: code,
      brand: brand,
      collection: collection,
      category: category,
      type: type,
      nameFr: nameFr,
      nameEn: nameEn,
      nameIt: nameIt,
      tiers: tiers,
      cabinetZones: cabinetZones,
      dimensions: dimensions,
      shelvesCount: shelvesCount,
      slides: slides,
      softClose: softClose,
      antiSlipMat: antiSlipMat,
      finishes: finishes,
      illustrations: illustrations,
      loadCapacityKg: loadCap,
      sourcePdfPage: pdfPage,
      notes: notes,
      price: price,
    );
  }

  static PriceRange _estimatePrice(String brand, String cat, String type, List<String> zones, int? shelves) {
    if (zones.contains('column')) {
      if (brand == 'INOXA' || brand == 'Kesseböhmer' || brand == 'Blum') {
        return const PriceRange(3800, 6800);
      }
      return const PriceRange(2400, 4500);
    }
    if (zones.contains('corner')) {
      if (brand == 'INOXA' || brand == 'Kesseböhmer' || brand == 'Blum') {
        return const PriceRange(3400, 5600);
      }
      return const PriceRange(2200, 3900);
    }
    if (cat == 'under_sink') {
      return const PriceRange(650, 1500);
    }
    if (cat == 'drawer') {
      if (brand == 'Blum' || brand == 'Grass' || brand == 'Hettich') {
        return const PriceRange(850, 1600);
      }
      return const PriceRange(500, 950);
    }
    if (cat == 'overhead') {
      if (brand == 'Blum' || brand == 'Kesseböhmer') {
        return const PriceRange(950, 2200);
      }
      return const PriceRange(450, 950);
    }
    if (cat == 'base_and_overhead' || cat == 'base') {
      if (brand == 'INOXA') {
        return (shelves != null && shelves > 2) ? const PriceRange(750, 1400) : const PriceRange(480, 980);
      }
      return const PriceRange(350, 750);
    }
    return const PriceRange(300, 850);
  }
}

class KitchenAccessoriesCatalog {
  static final Map<String, KitchenAccessory> byId = {};
  static final List<KitchenAccessory> all = [];
  static final Map<String, List<String>> byBrand = {};
  static final Map<String, List<String>> byCategory = {};

  static bool _loaded = false;
  static bool get isLoaded => _loaded;

  static void parse(String jsonString, {bool clear = true}) {
    if (clear) {
      byId.clear();
      all.clear();
      byBrand.clear();
      byCategory.clear();
    }

    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final accs = data['accessories'];
    if (accs is List) {
      for (final a in accs) {
        if (a is Map) {
          final id = a['id'] as String? ?? a['code'] as String? ?? '';
          if (id.isEmpty) continue;
          final item = KitchenAccessory.fromJson(id, a.cast<String, dynamic>());
          byId[id] = item;
          all.add(item);
          byBrand.putIfAbsent(item.brand, () => []).add(item.id);
          byCategory.putIfAbsent(item.category, () => []).add(item.id);
        }
      }
    } else if (accs is Map) {
      for (final entry in accs.entries) {
        final item = KitchenAccessory.fromJson(entry.key, (entry.value as Map).cast<String, dynamic>());
        byId[entry.key] = item;
        all.add(item);
        byBrand.putIfAbsent(item.brand, () => []).add(item.id);
        byCategory.putIfAbsent(item.category, () => []).add(item.id);
      }
    }

    // Format Klaus Systems Maroc (klaus_ma_catalog.json)
    final prods = data['products'];
    if (prods is List) {
      final supplierName = (data['supplier'] is Map)
          ? ((data['supplier'] as Map)['name'] as String? ?? 'Klaus Systems')
          : 'Klaus Systems';
      for (final p in prods) {
        if (p is Map) {
          final id = p['id'] as String? ?? '';
          if (id.isEmpty) continue;
          final item = _parseKlausProduct(id, p.cast<String, dynamic>(), supplierName);
          byId[id] = item;
          all.add(item);
          byBrand.putIfAbsent(item.brand, () => []).add(item.id);
          byCategory.putIfAbsent(item.category, () => []).add(item.id);
        }
      }
    }

    _loaded = true;
  }

  static KitchenAccessory _parseKlausProduct(
    String id,
    Map<String, dynamic> p,
    String supplierName,
  ) {
    final code = id;
    final universe = p['universe'] as String? ?? 'cuisine';
    final rawCat = p['category'] as String? ?? 'accessoires_meuble_bas';
    final type = p['type'] as String? ?? '';
    final nameFr = p['name'] as String? ?? id;

    // Normalisation de la catégorie et des zones de caisson
    String category;
    List<String> cabinetZones;
    List<int> supportedWidths = [];

    switch (universe) {
      case 'dressing':
        category = 'dressing';
        cabinetZones = const ['column', 'dressing'];
        supportedWidths = const [600, 800, 900, 1000, 1200];
        break;
      case 'poignees':
        if (rawCat == 'gola') {
          category = 'gola';
          cabinetZones = const ['base', 'column', 'overhead'];
        } else {
          category = 'poignee';
          cabinetZones = const ['base', 'column', 'overhead'];
        }
        break;
      case 'cuisine':
      default:
        switch (rawCat) {
          case 'accessoires_meuble_bas':
            if (type.contains('under_sink')) {
              category = 'under_sink';
              cabinetZones = const ['under_sink', 'base'];
              supportedWidths = const [600, 800, 900, 1000, 1200];
            } else {
              category = 'base';
              cabinetZones = const ['base'];
              if (type.contains('spice')) {
                supportedWidths = const [150, 200, 300];
              } else if (type.contains('pot_drawer')) {
                supportedWidths = const [600, 800, 900];
              } else if (type.contains('cleaning')) {
                supportedWidths = const [300, 400, 450];
              } else if (type.contains('gas_bottle')) {
                supportedWidths = const [400, 450, 600];
              } else {
                supportedWidths = const [300, 400, 450, 600];
              }
            }
            break;
          case 'accessoires_meuble_colonne':
            category = 'column';
            cabinetZones = const ['column', 'tall'];
            if (type.contains('slim')) {
              supportedWidths = const [150, 200, 300];
            } else {
              supportedWidths = const [400, 450, 600];
            }
            break;
          case 'accessoires_meuble_dangle':
            category = 'corner';
            cabinetZones = const ['corner'];
            supportedWidths = const [900, 1000, 1050, 1200];
            break;
          case 'accessoires_meuble_haut':
            category = 'overhead';
            cabinetZones = const ['overhead', 'wall'];
            supportedWidths = const [400, 450, 500, 600, 800, 900];
            break;
          case 'poubelle_cuisine':
            category = 'under_sink';
            cabinetZones = const ['under_sink', 'base'];
            final specs = p['specs'];
            final capL = (specs is Map) ? (specs['capacity_L'] as num?)?.toInt() : null;
            if ((capL != null && capL >= 58) || id.contains('80l') || id.contains('64l') || id.contains('58l')) {
              supportedWidths = const [600, 800, 900];
            } else {
              supportedWidths = const [400, 450, 500, 600];
            }
            break;
          case 'accessoires_tiroirs':
            category = 'drawer';
            cabinetZones = const ['drawer', 'base'];
            if (type.contains('table')) {
              supportedWidths = const [600, 800, 900];
            } else {
              supportedWidths = const [400, 450, 500, 600, 800, 900];
            }
            break;
          default:
            category = 'base';
            cabinetZones = const ['base'];
            supportedWidths = const [300, 400, 450, 600];
        }
        break;
    }

    // Prix MAD
    PriceRange price;
    if (p['price_mad'] is num) {
      final v = (p['price_mad'] as num).toDouble();
      price = PriceRange(v, v);
    } else if (p['price_min_mad'] is num && p['price_max_mad'] is num) {
      final min = (p['price_min_mad'] as num).toDouble();
      final max = (p['price_max_mad'] as num).toDouble();
      price = PriceRange(min, max);
    } else {
      price = const PriceRange(350, 850);
    }

    final specs = (p['specs'] as Map?)?.cast<String, dynamic>() ?? {};
    final dimensions = <String, dynamic>{
      if (supportedWidths.isNotEmpty) 'cabinet_widths_L': supportedWidths,
      ...specs,
    };

    final notesParts = <String>[];
    if (p['discount_pct'] != null) notesParts.add('Remise : ${p['discount_pct']}');
    if (p['in_stock'] == false) notesParts.add('Sur commande');
    if (p['source_category_url'] != null) notesParts.add('${p['source_category_url']}');

    final collection = switch (universe) {
      'dressing' => 'Dressing',
      'poignees' => 'Poignées & Profils',
      _ => 'Cuisine',
    };

    return KitchenAccessory(
      id: id,
      code: code,
      brand: 'Klaus Systems',
      collection: collection,
      category: category,
      type: type,
      nameFr: nameFr,
      tiers: [if (p['specs']?['shelves'] != null) '${p['specs']['shelves']} niveaux'],
      cabinetZones: cabinetZones,
      dimensions: dimensions,
      shelvesCount: (p['specs']?['shelves'] as num?)?.toInt(),
      finishes: specs['finish'] != null ? ['${specs['finish']}'] : const [],
      illustrations: const {},
      notes: notesParts.isNotEmpty ? notesParts.join(' • ') : null,
      price: price,
    );
  }

  /// Retourne les accessoires compatibles avec une zone et une largeur donnée.
  static List<KitchenAccessory> compatibleWith({required String zone, int? width}) {
    return all.where((a) => a.isCompatibleWith(zone: zone, width: width)).toList();
  }

  /// Recherche filtrée (marque, catégorie, texte, zone, largeur).
  static List<KitchenAccessory> filter({
    String? brand,
    String? category,
    String? zone,
    int? width,
    String? query,
  }) {
    return all.where((a) {
      if (brand != null && brand.isNotEmpty && a.brand != brand) return false;
      if (category != null && category.isNotEmpty && a.category != category) return false;
      if (zone != null && zone.isNotEmpty && !a.isCompatibleWith(zone: zone, width: width)) return false;
      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        final match = a.nameFr.toLowerCase().contains(q) ||
            a.code.toLowerCase().contains(q) ||
            a.brand.toLowerCase().contains(q) ||
            a.type.toLowerCase().contains(q);
        if (!match) return false;
      }
      return true;
    }).toList();
  }
}

/// Lignes de chiffrage pour le devis et la nomenclature industrielle.
List<SupplyLine> kitchenCabinetAccessoryLines(Project p) {
  final out = <SupplyLine>[];
  for (final c in p.items) {
    final accId = c.accessory;
    if (accId != null && accId.isNotEmpty) {
      final acc = KitchenAccessoriesCatalog.byId[accId];
      if (acc != null) {
        out.add(SupplyLine(
          'Accessoires',
          '${acc.brand} ${acc.code} : ${acc.nameFr}',
          'Caisson ${c.width} mm',
          1.0,
          'pce',
          acc.price,
        ));
      }
    }
  }
  return out;
}
