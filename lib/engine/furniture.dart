/// Mobilier hors cuisine (dressing, salle de bain / WC, meuble TV, intérieur) : catalogues
/// assets/data/furniture/*.json, composition de modules le long d'un mur, débit paramétrique
/// (caisson 18 mm, fond 6 mm, étagères, penderies, portes, tiroirs, abattants), quincaillerie.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'cutting.dart';

/// Un univers : dressing, bain, tv, interieur.
class FurnitureUniverse {
  final String id, name;
  final List<FurnitureModel> models;
  final List<FurnitureAccessory> accessories;
  const FurnitureUniverse(this.id, this.name, this.models, this.accessories);

  FurnitureModel? model(String id) => models.where((m) => m.id == id).firstOrNull;

  static const names = {
    'dressing': 'Dressing',
    'bain': 'Salle de bain et WC',
    'buanderie': 'Buanderie',
    'tv': 'Meuble TV',
    'interieur': 'Mobilier intérieur',
  };

  /// Lit un des catalogues : modules (« modules » au premier niveau ou dans des catégories) et accessoires.
  factory FurnitureUniverse.parse(String id, String src) {
    final j = jsonDecode(src) as Map<String, dynamic>;
    final models = <FurnitureModel>[];
    final acc = <FurnitureAccessory>[];
    void take(Map<String, dynamic> group, String category) {
      for (final m in (group['modules'] as List? ?? const [])) {
        models.add(FurnitureModel.fromJson((m as Map).cast<String, dynamic>(), category, j));
      }
      for (final a in (group['accessories'] as List? ?? const [])) {
        acc.add(FurnitureAccessory.fromJson((a as Map).cast<String, dynamic>(), category));
      }
    }

    take(j, '');
    for (final c in (j['categories'] as List? ?? const [])) {
      final cm = (c as Map).cast<String, dynamic>();
      take(cm, '${cm['category_name'] ?? ''}');
    }
    return FurnitureUniverse(id, names[id] ?? id, models, acc);
  }
}

/// Accessoire du catalogue et sa fourchette de prix (MAD), quelle que soit l'unité indiquée.
class FurnitureAccessory {
  final String id, name, category, unit;
  final double? min, max;
  const FurnitureAccessory(this.id, this.name, this.category, this.unit, this.min, this.max);

  factory FurnitureAccessory.fromJson(Map<String, dynamic> j, String category) {
    double? lo, hi;
    var unit = 'pce';
    for (final e in j.entries.where((e) => e.key.startsWith('price_mad'))) {
      unit = switch (e.key) {
        'price_mad_per_pair' => 'paire',
        'price_mad_per_linear_meter' => 'm',
        'price_mad_set_of_4' || 'price_mad_per_set_of_4' => 'lot de 4',
        'price_mad_per_panel' => 'panneau',
        'price_mad_per_2_doors_kit' => 'kit 2 portes',
        'price_mad_per_door_assembled' => 'porte',
        'price_mad_per_blade_set' => 'lame',
        _ => 'pce',
      };
      final v = e.value;
      if (v is Map) {
        final nums = [for (final x in v.values) if (x is num) x.toDouble()];
        if (v['min'] is num) {
          lo = (v['min'] as num).toDouble();
          hi = (v['max'] as num?)?.toDouble() ?? lo;
        } else if (nums.isNotEmpty) {
          lo = nums.reduce(math.min);
          hi = nums.reduce(math.max);
        }
      } else if (v is num) {
        lo = hi = v.toDouble();
      }
    }
    return FurnitureAccessory('${j['id']}', '${j['name']}', category, unit, lo, hi);
  }
}

/// Module du catalogue : tailles proposées et composition par défaut.
class FurnitureModel {
  final String id, name, category;
  final List<int> widths, heights, depths;
  final List<String> variants; // formats d'angle W1/W2/H/D, tailles de matelas...
  final FurnitureSetup setup;
  const FurnitureModel(this.id, this.name, this.category, this.widths, this.heights, this.depths, this.variants, this.setup);

  factory FurnitureModel.fromJson(Map<String, dynamic> j, String category, Map<String, dynamic> db) {
    List<int> ints(List<String> keys) {
      for (final k in keys) {
        final v = j[k];
        if (v is List && v.isNotEmpty && v.first is num) return [for (final x in v) (x as num).toInt()];
        if (v is num) return [v.toInt()];
      }
      return const [];
    }

    final id = '${j['id']}';
    final variants = [for (final x in (j['code_4_params_variants'] as List? ?? j['mattress_sizes'] as List? ?? const [])) '$x'];
    var widths = ints(['available_widths', 'widths', 'total_widths']);
    var heights = ints(['available_heights', 'heights', 'height', 'carcass_height', 'headboard_height', 'box_height']);
    var depths = ints(['available_depths', 'depths', 'depth', 'thickness_or_depth', 'folded_depth']);
    // formats d'angle « 900/900/2400/580 » : W1, H, D tirés du code
    if (widths.isEmpty && variants.isNotEmpty && variants.first.contains('/')) {
      final p = [for (final v in variants) v.split('/').map(int.parse).toList()];
      widths = [for (final x in p) x[0]];
      heights = [p.first[2]];
      depths = [p.first[3] + 20];
    }
    // lit coffre « 1600x2000 » : largeur et longueur du cadre (matelas + 2 x 20 mm)
    if (widths.isEmpty && variants.isNotEmpty && variants.first.contains('x')) {
      final p = [for (final v in variants) v.split('x').map(int.parse).toList()];
      widths = [for (final x in p) x[0] + 40];
      depths = [for (final x in p) x[1] + 40];
    }
    final std = (db['standard_parameters'] as Map?)?.cast<String, dynamic>();
    if (heights.isEmpty) heights = [for (final x in (std?['standard_heights'] as List? ?? const [2200])) (x as num).toInt()];
    if (depths.isEmpty) depths = [for (final x in (db['standard_depths'] as List? ?? const [600])) (x as num).toInt()];
    if (widths.isEmpty) widths = const [600];
    return FurnitureModel(id, '${j['name']}', category, widths, heights, depths, variants, FurnitureSetup.defaultsFor(id, j));
  }
}

/// Composition d'un module : ce que le débit et le dessin en tirent.
class FurnitureSetup {
  int doors, drawers, flaps, shelves, rods;
  int drawerFront; // hauteur d'une façade de tiroir (mm)
  bool open; // sans façade (niches)
  bool glass, mirror; // portes vitrées / miroir
  bool panel; // panneau seul (habillage, tête de lit, claustra)
  bool wallHung; // suspendu (sinon posé au sol / sur socle)
  int z; // hauteur du bas du module (suspendu)
  bool liftUp; // abattant relevable (au lieu d'un abattant qui s'ouvre vers le bas)
  String shape; // 'box' | 'L' | 'diagonal' | 'desk' | 'slats'
  int returnWidth; // angle : largeur sur le mur de retour

  FurnitureSetup({
    this.doors = 0,
    this.drawers = 0,
    this.flaps = 0,
    this.shelves = 0,
    this.rods = 0,
    this.drawerFront = 200,
    this.open = false,
    this.glass = false,
    this.mirror = false,
    this.panel = false,
    this.wallHung = false,
    this.z = 0,
    this.liftUp = false,
    this.shape = 'box',
    this.returnWidth = 0,
  });

  FurnitureSetup copy() => FurnitureSetup.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'doors': doors,
        'drawers': drawers,
        'flaps': flaps,
        'shelves': shelves,
        'rods': rods,
        'drawer_front': drawerFront,
        'open': open,
        'glass': glass,
        'mirror': mirror,
        'panel': panel,
        'wall_hung': wallHung,
        'z': z,
        'lift_up': liftUp,
        'shape': shape,
        'return_width': returnWidth,
      };

  factory FurnitureSetup.fromJson(Map<String, dynamic> j) => FurnitureSetup(
        doors: (j['doors'] as num?)?.toInt() ?? 0,
        drawers: (j['drawers'] as num?)?.toInt() ?? 0,
        flaps: (j['flaps'] as num?)?.toInt() ?? 0,
        shelves: (j['shelves'] as num?)?.toInt() ?? 0,
        rods: (j['rods'] as num?)?.toInt() ?? 0,
        drawerFront: (j['drawer_front'] as num?)?.toInt() ?? 200,
        open: j['open'] as bool? ?? false,
        glass: j['glass'] as bool? ?? false,
        mirror: j['mirror'] as bool? ?? false,
        panel: j['panel'] as bool? ?? false,
        wallHung: j['wall_hung'] as bool? ?? false,
        z: (j['z'] as num?)?.toInt() ?? 0,
        liftUp: j['lift_up'] as bool? ?? false,
        shape: j['shape'] as String? ?? 'box',
        returnWidth: (j['return_width'] as num?)?.toInt() ?? 0,
      );

  /// Composition par défaut d'après le type de module.
  static FurnitureSetup defaultsFor(String id, Map<String, dynamic> j) {
    // composition décrite dans le catalogue : elle prime sur les valeurs par défaut
    final comp = (j['composition'] as Map?)?.cast<String, dynamic>();
    if (comp != null) return FurnitureSetup.fromJson(comp);
    final s = FurnitureSetup();
    switch (id) {
      case 'wardrobe_long_hanging':
        s
          ..shelves = 2
          ..rods = 1;
      case 'wardrobe_double_hanging':
        s
          ..shelves = 2
          ..rods = 2;
      case 'wardrobe_linen_drawers_tower':
        s
          ..drawers = 4
          ..shelves = 4;
      case 'wardrobe_corner_L_90':
        s
          ..shape = 'L'
          ..shelves = 3
          ..rods = 2
          ..doors = 2;
      case 'wardrobe_corner_diagonal_45':
        s
          ..shape = 'diagonal'
          ..shelves = 3
          ..rods = 1
          ..doors = 1;
      case 'wardrobe_island_central':
        s.drawers = 3;
      case 'bath_vanity_single_basin_wall_hung':
        s
          ..drawers = 2
          ..drawerFront = 250
          ..wallHung = true
          ..z = 300;
      case 'bath_vanity_double_basin_wall_hung':
        s
          ..drawers = 2
          ..drawerFront = 250
          ..wallHung = true
          ..z = 300;
      case 'bath_vanity_floor_standing':
        s
          ..drawers = 3
          ..drawerFront = 240;
      case 'bath_tall_linen_column':
        s
          ..doors = 1
          ..shelves = 4
          ..wallHung = true
          ..z = 300;
      case 'bath_mirror_medicine_cabinet':
        s
          ..doors = 2
          ..mirror = true
          ..shelves = 2
          ..wallHung = true
          ..z = 1150;
      case 'bath_wc_over_cabinet':
        s
          ..doors = 2
          ..shelves = 1
          ..wallHung = true
          ..z = 1200;
      case 'tv_low_bench_floating':
        s
          ..flaps = 3
          ..wallHung = true
          ..z = 250;
      case 'tv_low_bench_floor_standing':
        s.drawers = 2;
      case 'tv_wall_cladding_back_panel':
        s.panel = true;
      case 'tv_wall_hanging_vertical_column':
        s
          ..doors = 1
          ..glass = true
          ..shelves = 3
          ..wallHung = true
          ..z = 700;
      case 'tv_wall_horizontal_bridge':
        s
          ..flaps = 1
          ..liftUp = true
          ..wallHung = true
          ..z = 1900;
      case 'tv_fireplace_niche_module':
        s.open = true;
      case 'shoe_cabinet_tilt_flap_slim':
        s.flaps = (j['flaps_count'] as List?)?.whereType<num>().first.toInt() ?? 3;
      case 'entryway_hall_tree_bench':
        s
          ..drawers = 1
          ..drawerFront = 300
          ..shelves = 1;
      case 'library_bookcase_full_wall':
        s
          ..open = true
          ..shelves = 5;
      case 'desk_workstation_custom':
        s
          ..shape = 'desk'
          ..drawers = 3
          ..drawerFront = 180;
      case 'desk_wall_foldable_secretariat':
        s
          ..flaps = 1
          ..shelves = 2
          ..wallHung = true
          ..z = 750;
      case 'bedroom_headboard_nightstands':
        s.panel = true;
      case 'bedroom_storage_bed_base':
        s.open = false;
      case 'bedroom_vanity_dressing_table':
        s
          ..drawers = 1
          ..drawerFront = 160
          ..wallHung = true
          ..z = 600;
      case 'dining_sideboard_buffet':
        s
          ..doors = 4
          ..shelves = 1;
      case 'living_window_storage_bench':
        s
          ..drawers = 2
          ..drawerFront = 300;
      case 'arch_Moucharabieh_partition':
        s
          ..panel = true
          ..shape = 'slats';
      case 'arch_radiator_or_ac_cover':
        s.doors = 0;
      case 'arch_electrical_meter_cabinet':
        s
          ..doors = 1
          ..wallHung = true
          ..z = 1400;
      default:
        s.doors = 1;
    }
    return s;
  }
}

/// Un module posé sur le mur.
class FurnitureItem {
  final String uid;
  final String modelId;
  int width, height, depth;
  FurnitureSetup setup;
  FurnitureItem({required this.uid, required this.modelId, required this.width, required this.height, required this.depth, required this.setup});

  Map<String, dynamic> toJson() => {'uid': uid, 'model': modelId, 'w': width, 'h': height, 'd': depth, 'setup': setup.toJson()};
  factory FurnitureItem.fromJson(Map<String, dynamic> j) => FurnitureItem(
        uid: '${j['uid']}',
        modelId: '${j['model']}',
        width: (j['w'] as num).toInt(),
        height: (j['h'] as num).toInt(),
        depth: (j['d'] as num).toInt(),
        setup: FurnitureSetup.fromJson((j['setup'] as Map).cast<String, dynamic>()),
      );
}

/// Composition d'un univers : un mur et ses modules, de gauche à droite.
class FurnitureProject {
  final String universe;
  String name;
  int wallWidth, wallHeight;
  String doorSystem; // dressing : 'battantes' | 'coulissantes'
  final List<FurnitureItem> items;
  final Map<String, int> accessories; // id → quantité
  FurnitureProject({required this.universe, String? name, this.wallWidth = 3000, this.wallHeight = 2600, this.doorSystem = 'battantes', List<FurnitureItem>? items, Map<String, int>? accessories})
      : name = name ?? FurnitureUniverse.names[universe] ?? universe,
        items = items ?? [],
        accessories = accessories ?? {};

  int get usedWidth => items.fold(0, (s, i) => s + i.width);

  Map<String, dynamic> toJson() => {
        'universe': universe,
        'name': name,
        'wall_width': wallWidth,
        'wall_height': wallHeight,
        'door_system': doorSystem,
        'items': [for (final i in items) i.toJson()],
        if (accessories.isNotEmpty) 'accessories': accessories,
      };

  factory FurnitureProject.fromJson(Map<String, dynamic> j) => FurnitureProject(
        universe: '${j['universe']}',
        name: j['name'] as String?,
        wallWidth: (j['wall_width'] as num?)?.toInt() ?? 3000,
        wallHeight: (j['wall_height'] as num?)?.toInt() ?? 2600,
        doorSystem: j['door_system'] as String? ?? 'battantes',
        items: [for (final i in (j['items'] as List? ?? const [])) FurnitureItem.fromJson((i as Map).cast<String, dynamic>())],
        accessories: {for (final e in ((j['accessories'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
      );

  /// Abscisse (mm depuis la gauche du mur) de chaque module.
  double xOf(FurnitureItem it) {
    var x = 0.0;
    for (final i in items) {
      if (identical(i, it)) return x;
      x += i.width;
    }
    return x;
  }

  /// Hauteur du bas du module (0 si posé au sol).
  static int zOf(FurnitureItem it) => it.setup.wallHung ? it.setup.z : 0;

  /// Points à vérifier : largeur et hauteur du mur, porte trop large, coulissantes sur trop peu de profondeur.
  List<String> checks() {
    final out = <String>[];
    if (usedWidth > wallWidth) out.add('Les modules font $usedWidth mm de large pour un mur de $wallWidth mm');
    for (final it in items) {
      if (zOf(it) + it.height > wallHeight) out.add('Un module dépasse la hauteur du mur (${zOf(it) + it.height} mm)');
      final dw = it.setup.doors > 0 ? it.width / it.setup.doors : 0;
      if (dw > 620 && doorSystem == 'battantes') out.add('Porte de ${dw.round()} mm : 600 mm maximum par porte battante (ajoutez une porte)');
    }
    if (universe == 'dressing' && doorSystem == 'coulissantes' && items.any((i) => i.depth < 660)) {
      out.add('Portes coulissantes : profondeur totale de 660 mm conseillée (rails et vantaux)');
    }
    return out;
  }
}

/// Matériaux du débit.
const furnitureCarcass = 'MDF 18 (caisson)', furnitureFront = 'MDF 18 (façades)', furnitureBack = 'HDF 6 (fonds)';

/// Pièces de tout le projet, et quincaillerie (nom → quantité).
(List<CutPart>, Map<String, double>) furnitureCutList(FurnitureProject p) {
  const T = 18;
  final parts = <String, CutPart>{};
  final hw = <String, double>{};
  void add(String mat, String name, String tag, int a, int b, int q, {int el = 0, int es = 0, bool rotate = true}) {
    if (a <= 0 || b <= 0 || q <= 0) return;
    final (eLong, eShort) = a >= b ? (el, es) : (es, el);
    final c = CutPart(mat, name, tag, a, b, q, canRotate: rotate, edgeLong: eLong, edgeShort: eShort);
    final k = c.key;
    parts.containsKey(k) ? parts[k]!.qty += q : parts[k] = c;
  }

  void hard(String name, double q) {
    if (q > 0) hw[name] = (hw[name] ?? 0) + q;
  }

  int hingesFor(int h) => h <= 900 ? 2 : h <= 1600 ? 3 : h <= 2000 ? 4 : 5;

  for (var n = 0; n < p.items.length; n++) {
    final it = p.items[n];
    final s = it.setup;
    final W = it.width, H = it.height, D = it.depth;
    final tag = 'Module ${n + 1}';
    final front = D >= 400 ? D - 20 : D; // façade devant le caisson
    final dc = s.panel ? D : front - T;
    if (s.panel) {
      if (s.shape == 'slats') {
        final slats = (W / 86).floor(); // tasseau 36 mm + jour de 50 mm
        add(furnitureFront, 'Tasseau de claustra 36 x $D', tag, H, D, slats, el: 2);
        hard('Pivots haut et bas de lame', slats.toDouble());
      } else {
        add(furnitureFront, 'Panneau d’habillage', tag, H, W, 1, el: 2, es: 2);
        add(furnitureCarcass, 'Tasseau de fixation (vide technique)', tag, W - 2 * T, 36, 3);
      }
      continue;
    }
    if (s.shape == 'L' || s.shape == 'diagonal') {
      final w2 = s.returnWidth > 0 ? s.returnWidth : W;
      add(furnitureCarcass, 'Côté (flanc)', tag, H, dc, 2, el: 2);
      add(furnitureCarcass, 'Dos porteur mur 1', tag, H, W - T, 1);
      add(furnitureCarcass, 'Dos porteur mur 2', tag, H, w2 - 2 * T, 1);
      add(furnitureCarcass, s.shape == 'L' ? 'Dessus / dessous en L (CNC)' : 'Dessus / dessous à pan coupé (CNC)', tag, W - 2 * T, w2 - 2 * T, 2, el: 1);
      add(furnitureCarcass, s.shape == 'L' ? 'Étagère en L (CNC)' : 'Étagère à pan coupé (CNC)', tag, W - 2 * T - 2, w2 - 2 * T - 2, s.shelves, el: 1);
      if (s.shape == 'L') {
        add(furnitureFront, 'Porte pliante maître', tag, H - 4, W - dc - T - 7, 1, el: 2, es: 2);
        add(furnitureFront, 'Porte pliante esclave', tag, H - 4, w2 - dc - T - 25, 1, el: 2, es: 2);
        hard('Charnières 165° + charnière de liaison', hingesFor(H) * 2.0);
      } else {
        add(furnitureFront, 'Porte oblique 45°', tag, H - 4, (math.sqrt2 * (W - D)).round() - 6, 1, el: 2, es: 2);
        hard('Charnières pan coupé', hingesFor(H).toDouble());
      }
      hard('Barre de penderie (m)', s.rods * (W - 2 * T) / 1000);
      continue;
    }
    if (s.shape == 'desk') {
      add(furnitureFront, 'Plateau (2 x 18 mm contrecollés)', tag, W, D, 2, el: 2, es: 2);
      add(furnitureFront, 'Jambage panneau (2 x 18 mm)', tag, H - 36, D, 2, el: 2, es: 1);
      final bw = 400;
      add(furnitureCarcass, 'Côté caisson tiroirs', tag, H - 36 - 20, D - 60, 2, el: 1);
      add(furnitureCarcass, 'Dessus / dessous caisson', tag, bw - 2 * T, D - 60, 2, el: 1);
      _drawers(add, hard, tag, bw, D - 60, s.drawers, s.drawerFront);
      continue;
    }
    // caisson standard
    add(furnitureCarcass, 'Côté', tag, H, dc, 2, el: 1);
    add(furnitureCarcass, 'Dessus / dessous', tag, W - 2 * T, dc, 2, el: 1);
    add(furnitureBack, 'Fond 6 mm (rainuré)', tag, H - 2 * T + 16, W - 2 * T + 16, 1);
    final inside = W - 2 * T;
    add(furnitureCarcass, 'Étagère', tag, inside - 2, dc - 20, s.shelves + (s.rods >= 2 ? 1 : 0), el: 1);
    hard('Barre de penderie (m)', s.rods * inside / 1000);
    hard('Supports de barre', s.rods * 2.0);
    final drawerH = s.drawers * s.drawerFront;
    if (s.drawers > 0) _drawers(add, hard, tag, W, dc, s.drawers, s.drawerFront);
    if (s.flaps > 0) {
      final fh = ((H - drawerH - 4) / s.flaps).floor() - 2;
      add(furnitureFront, s.liftUp ? 'Abattant relevable' : 'Abattant', tag, W - 4, fh, s.flaps, el: 2, es: 2);
      hard(s.liftUp ? 'Vérin / compas d’abattant relevable' : 'Compas d’abattant freiné', s.flaps * 2.0);
      hard('Charnières d’abattant', s.flaps * 2.0);
    }
    if (s.doors > 0 && p.doorSystem != 'coulissantes') {
      final dw = ((W - 4 - 3 * (s.doors - 1)) / s.doors).floor();
      final dh = H - drawerH - 4;
      add(furnitureFront, s.mirror ? 'Porte (miroir collé)' : s.glass ? 'Cadre de porte vitrée' : 'Porte', tag, dh, dw, s.doors, el: 2, es: 2,
          rotate: false);
      hard('Charnières', s.doors * hingesFor(dh).toDouble());
      if (dh > 2100) hard('Redresseur de porte', s.doors.toDouble());
    }
    if (s.wallHung) hard('Paire de boîtiers de suspension', 1);
    if (!s.wallHung && H > 1500) hard('Pieds / vérins de réglage', 4);
  }
  // dressing à portes coulissantes : vantaux sur toute la largeur, chevauchement 35 mm
  if (p.doorSystem == 'coulissantes' && p.items.isNotEmpty) {
    final total = p.usedWidth;
    final h = p.items.map((i) => i.height).reduce(math.max);
    final n = math.max(2, (total / 1000).ceil());
    final w = ((total + 35 * (n - 1)) / n).ceil();
    add(furnitureFront, 'Vantail coulissant', 'Façade', h - 60, w, n, el: 2, es: 2, rotate: false);
    hard('Kit rail coulissant (2 portes)', (n / 2).ceilToDouble());
  }
  return (parts.values.toList(), hw);
}

void _drawers(void Function(String, String, String, int, int, int, {int el, int es, bool rotate}) add, void Function(String, double) hard, String tag,
    int W, int dc, int n, int fh) {
  const T = 18;
  final inner = W - 2 * T - 26; // coulisses 13 mm de chaque côté
  final bh = math.max(80, fh - 50);
  add(furnitureFront, 'Façade de tiroir', tag, W - 4, fh - 4, n, el: 2, es: 2);
  add(furnitureCarcass, 'Côté de tiroir', tag, dc - 50, bh, 2 * n, el: 1);
  add(furnitureCarcass, 'Avant / arrière de tiroir', tag, inner - 2 * T, bh, 2 * n, el: 1);
  add(furnitureBack, 'Fond de tiroir', tag, inner, dc - 50, n);
  hard('Paire de coulisses de tiroir', n.toDouble());
}

/// Débit d'un projet (scie à panneaux, réglages de l'atelier).
CutPlan furniturePlan(FurnitureProject p, CutSettings cs) => nest(furnitureCutList(p).$1, cs);
