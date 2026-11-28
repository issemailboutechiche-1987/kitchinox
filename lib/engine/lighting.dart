// Calcul de l'éclairage selon les normes : combien de lumière il faut, avec quels luminaires, combien,
// et où les poser. Méthode des lumens (EN 12464-1, IES, DOE) :
//   flux = lux visés × surface (m²) ÷ (UF × MF), × coefficient de hauteur sous plafond
// UF : facteur d'utilisation (couleur des murs) ; MF : facteur de maintenance (vapeur et graisse en cuisine).
// Normes : docs/lighting/lighting_engineering_standards.json ; luminaires : docs/lighting/lighting_sources_catalog.json
// (fournis par l'atelier).
import 'dart:math' as math;

import 'layout_engine.dart';
import 'project.dart';

// ============================================================================ normes

/// Une zone d'éclairage et sa norme.
class LightZone {
  final String id, name;
  final int luxMin, lux, luxMax;
  final String cct, cri, ip, placement;
  const LightZone(this.id, this.name, this.luxMin, this.lux, this.luxMax, {this.cct = '2700–3000 K', this.cri = 'IRC ≥ 90', this.ip = 'IP20', this.placement = ''});
}

/// Normes par pièce (zone générale en premier).
const lightZones = <String, List<LightZone>>{
  'cuisine': [
    LightZone('kitchen_general', 'Éclairage général', 150, 200, 300,
        ip: 'IP20 (IP44 près de la cuisson et de l’évier)',
        placement: 'Spots espacés de 1000 à 1200 mm, alignés à 550–650 mm du mur (bord avant du plan de travail).'),
    LightZone('kitchen_worktop', 'Plan de travail (sous meubles hauts)', 400, 500, 750,
        cct: '3000–4000 K', cri: 'IRC ≥ 90, R9 ≥ 50', ip: 'IP44 (IP65 au-dessus de l’évier)',
        placement: 'Profilé alu 10×10 mm avec diffuseur opale, à 50–100 mm du bord avant du caisson haut.'),
    LightZone('kitchen_island', 'Îlot', 300, 450, 500, placement: 'Suspensions à 750–850 mm au-dessus du plan, espacées de 600 à 800 mm.'),
    LightZone('kitchen_sink_cooktop', 'Évier et cuisson', 400, 500, 700, cct: '3000–4000 K', ip: 'IP44 / IP65 (évier) ; résistant à la chaleur (hotte)'),
    LightZone('kitchen_interior_cabinet', 'Intérieur des vitrines', 100, 150, 200, placement: 'Capteur d’ouverture de porte.'),
    LightZone('kitchen_plinth', 'Plinthe (effet flottant, veilleuse)', 20, 35, 50, cri: '—', ip: 'IP65'),
  ],
  'bain': [
    LightZone('bathroom_general', 'Général plafond', 200, 250, 300, cct: '3000–4000 K', ip: 'IP44'),
    LightZone('bathroom_mirror', 'Miroir', 400, 500, 600, cct: '3000–4000 K', cri: 'IRC ≥ 95', ip: 'IP44 (classe II en volume 2)',
        placement: '2 appliques verticales de chaque côté, à 1600–1700 mm du sol.'),
  ],
  'buanderie': [LightZone('laundry_work', 'Général et plan de pliage', 300, 400, 500, cct: '4000 K', cri: 'IRC ≥ 85', ip: 'IP44')],
  'dressing': [
    LightZone('dressing_general', 'Général et miroir', 200, 300, 400, cct: '3000–4000 K', cri: 'IRC ≥ 95'),
    LightZone('dressing_interior', 'Intérieur des caissons et penderies', 150, 250, 300, cct: '3000 K',
        placement: 'Saignée verticale 10×10 mm sur les montants, à 40–60 mm du bord avant.'),
  ],
  'tv': [
    LightZone('living_general', 'Ambiance salon', 100, 150, 200),
    LightZone('tv_bias_lighting', 'Rétroéclairage du meuble TV', 20, 40, 60, cri: '—'),
  ],
  'interieur': [LightZone('living_general', 'Ambiance', 100, 150, 200)],
};

/// Corniche indirecte : zone d'ambiance (complète l'éclairage général).
const coveZone = LightZone('cove', 'Corniche indirecte (plafond)', 0, 0, 0, cri: 'IRC ≥ 90', placement: 'Ruban caché dans une gorge, lumière renvoyée par le plafond (UGR très bas).');

/// Facteur d'utilisation selon la couleur des murs.
const roomTones = <String, (String, double)>{
  'clair': ('Murs clairs (blanc)', 0.75),
  'moyen': ('Murs moyens (beige, bois)', 0.65),
  'fonce': ('Murs foncés (anthracite, noir)', 0.50),
};

/// Coefficient de hauteur sous plafond.
double heightFactor(double ceilingMm) {
  final h = ceilingMm / 1000;
  if (h <= 2.6) return 1.0;
  if (h <= 3.0) return 1.15;
  if (h <= 3.6) return 1.30;
  return 1.50;
}

// ============================================================================ luminaires

/// Un luminaire du catalogue. Pour un ruban (perM), les watts et les lumens sont au mètre.
class LightSource {
  final String id, label, name, group, shape; // label : nom simple affiché ; name : nom technique (conseils) // group : general | island | worktop | plinth | cove | cabinet | dressing
  final double wMin, wTyp, wMax;
  final int lmMin, lmTyp, lmMax;
  final bool perM;
  final List<int> beams, ccts;
  final List<String> ips;
  final int cri;
  final int? ugr;
  final List<int> lengths; // longueurs proposées (réglettes, suspensions linéaires), mm
  final String note;
  const LightSource(this.id, this.label, this.name, this.group, this.shape,
      {required this.wMin,
      required this.wTyp,
      required this.wMax,
      required this.lmMin,
      required this.lmTyp,
      required this.lmMax,
      this.perM = false,
      this.beams = const [],
      this.ccts = const [3000],
      this.ips = const ['IP20'],
      this.cri = 90,
      this.ugr,
      this.lengths = const [],
      this.note = ''});

  int lm(String power) => power == 'min' ? lmMin : power == 'max' ? lmMax : lmTyp;
  double w(String power) => power == 'min' ? wMin : power == 'max' ? wMax : wTyp;
}

/// Catalogue des luminaires (cuisine, chambre et intérieurs).
const lightSources = <LightSource>[
  // ---- plafond : éclairage général
  LightSource('spot_led_gu10_std', 'Spot encastré', 'Spot LED encastré GU10', 'general', 'spot',
      wMin: 4.5, wTyp: 5, wMax: 7, lmMin: 350, lmTyp: 450, lmMax: 700, beams: [36, 60], ccts: [2700, 3000, 4000], ips: ['IP20', 'IP44', 'IP65'], ugr: 22),
  LightSource('spot_led_cob_darklight', 'Spot anti-éblouissement', 'Spot COB Dark-Light / Trimless (anti-éblouissement)', 'general', 'darklight',
      wMin: 7, wTyp: 10, wMax: 12, lmMin: 650, lmTyp: 900, lmMax: 1150, beams: [24, 36, 50], ccts: [2700, 3000], ips: ['IP20', 'IP44'], cri: 92, ugr: 16,
      note: 'Source reculée : pas d’éblouissement direct (UGR < 19). Idéal en gamme luxe.'),
  LightSource('projecteur_rail_led', 'Projecteur sur rail', 'Projecteur LED orientable sur rail', 'general', 'track',
      wMin: 10, wTyp: 15, wMax: 25, lmMin: 900, lmTyp: 1400, lmMax: 2400, beams: [15, 24, 36], ccts: [3000, 4000], ugr: 19),
  LightSource('rail_magnetique_48v', 'Rail magnétique', 'Projecteur / barre sur rail magnétique 48 V', 'general', 'magnetic',
      wMin: 6, wTyp: 12, wMax: 24, lmMin: 500, lmTyp: 1050, lmMax: 2100, beams: [24, 36, 110], ccts: [2700, 3000, 4000], ugr: 18),
  LightSource('dalle_panneau_led', 'Dalle lumineuse', 'Dalle / panneau LED', 'general', 'panel',
      wMin: 18, wTyp: 24, wMax: 40, lmMin: 1800, lmTyp: 2400, lmMax: 4200, beams: [120], ccts: [3000, 4000], ips: ['IP20', 'IP44'], cri: 80, ugr: 19),
  LightSource('plafonnier_led_diffusant', 'Plafonnier', 'Plafonnier LED diffusant', 'general', 'ceiling',
      wMin: 15, wTyp: 22, wMax: 32, lmMin: 1500, lmTyp: 2200, lmMax: 3200, beams: [120, 160], ccts: [2700, 3000, 4000], ips: ['IP20', 'IP44'], cri: 85, ugr: 21),
  LightSource('ampoule_led_e27_e14', 'Ampoule', 'Ampoule LED E27 / E14 (douille, lustre)', 'general', 'bulb',
      wMin: 4, wTyp: 9, wMax: 15, lmMin: 450, lmTyp: 806, lmMax: 1521, beams: [270, 360], ccts: [2200, 2700, 3000, 4000], cri: 80),
  LightSource('spot_halogene_gu10_mr16', 'Spot halogène (ancien)', 'Spot halogène GU10 / MR16 (rénovation)', 'general', 'spot',
      wMin: 35, wTyp: 50, wMax: 50, lmMin: 250, lmTyp: 400, lmMax: 450, beams: [35, 40], ccts: [2700], cri: 99, ugr: 24,
      note: 'Consomme 8 à 10 fois plus qu’un spot LED et chauffe : à remplacer par du LED IRC 90+.'),
  // ---- îlot
  LightSource('suspension_ilot_focale', 'Suspensions', 'Suspensions focales', 'island', 'pendant',
      wMin: 6, wTyp: 10, wMax: 15, lmMin: 500, lmTyp: 850, lmMax: 1350, beams: [60, 120], ccts: [2700, 3000]),
  LightSource('suspension_lineaire_ilot', 'Suspension linéaire', 'Suspension linéaire', 'island', 'linear',
      wMin: 24, wTyp: 32, wMax: 45, lmMin: 2200, lmTyp: 3000, lmMax: 4200, beams: [90, 110], ccts: [2700, 3000], ugr: 18, lengths: [1200, 1500, 1800]),
  // ---- plan de travail
  LightSource('ruban_led_cob_plan_travail', 'Ruban lumineux', 'Ruban LED COB 24 V sous meuble haut', 'worktop', 'strip',
      wMin: 12, wTyp: 14, wMax: 16, lmMin: 1100, lmTyp: 1350, lmMax: 1550, perM: true, beams: [120, 180], ccts: [3000, 4000], ips: ['IP44', 'IP65']),
  LightSource('reglette_led_sous_meuble', 'Réglettes', 'Réglette LED sous meuble (capteur main)', 'worktop', 'bar',
      wMin: 8, wTyp: 12, wMax: 18, lmMin: 800, lmTyp: 1200, lmMax: 1800, beams: [120], ccts: [3000, 4000], ips: ['IP20', 'IP44'], cri: 85, lengths: [600, 900, 1200]),
  // ---- ambiance et meubles
  LightSource('ruban_led_plinthe_sous_lit', 'Plinthe lumineuse', 'Ruban LED de plinthe IP65', 'plinth', 'strip',
      wMin: 4.8, wTyp: 4.8, wMax: 7.2, lmMin: 400, lmTyp: 450, lmMax: 650, perM: true, beams: [120], ccts: [2200, 2700, 3000], ips: ['IP65'], cri: 80),
  LightSource('ruban_led_corniche_indirect', 'Lumière indirecte', 'Ruban LED de corniche (indirect)', 'cove', 'strip',
      wMin: 6, wTyp: 9.6, wMax: 12, lmMin: 550, lmTyp: 900, lmMax: 1150, perM: true, beams: [120], ccts: [2700, 3000], ugr: 10),
  LightSource('mini_spot_meuble_vitrine', 'Mini-spots de vitrine', 'Mini-spot extraplat de vitrine', 'cabinet', 'puck',
      wMin: 2, wTyp: 3, wMax: 4, lmMin: 180, lmTyp: 260, lmMax: 350, beams: [60, 100], ccts: [2700, 3000], ips: ['IP20', 'IP44']),
  LightSource('barre_penderie_dressing_led', 'Penderie lumineuse', 'Barre de penderie / profilé LED à détecteur', 'dressing', 'strip',
      wMin: 5, wTyp: 8, wMax: 10, lmMin: 450, lmTyp: 750, lmMax: 950, perM: true, beams: [120], ccts: [3000, 4000], cri: 95),
];

LightSource? lightSourceById(String id) => lightSources.where((s) => s.id == id).firstOrNull;
List<LightSource> lightSourcesFor(String group) => [for (final s in lightSources) if (s.group == group) s];

/// Couleur d'aperçu d'une température (K).
int cctColor(int k) => k <= 2200
    ? 0xFF9E44
    : k <= 2700
        ? 0xFFD2A1
        : k <= 3000
            ? 0xFFE4C4
            : k <= 4000
                ? 0xFFF4E8
                : 0xF4F8FF;

/// Les choix d'éclairage du projet (menu Plafond).
class LightingChoice {
  String general; // luminaire du plafond
  String power; // 'min' | 'typical' | 'max'
  int cct; // K
  int? beam; // degrés (null : celui du milieu)
  String? ip; // null : selon la pièce
  String island; // luminaire de l'îlot ('none' : rien)
  String worktop; // sous les meubles hauts ('none' : rien)
  bool plinth, cove, cabinet, dressing;
  bool placed; // posés au plafond (bouton « Poser » ou « Calcul automatique ») : sinon les réseaux n'en mettent pas

  LightingChoice({
    this.general = 'spot_led_gu10_std',
    this.power = 'typical',
    this.cct = 3000,
    this.beam,
    this.ip,
    this.island = 'suspension_ilot_focale',
    this.worktop = 'ruban_led_cob_plan_travail',
    this.plinth = false,
    this.cove = false,
    this.cabinet = true,
    this.dressing = true,
    this.placed = false,
  });

  LightSource get generalSource => lightSourceById(general) ?? lightSources.first;

  Map<String, dynamic> toJson() => {
        'general': general,
        'power': power,
        'cct': cct,
        if (beam != null) 'beam': beam,
        if (ip != null) 'ip': ip,
        'island': island,
        'worktop': worktop,
        if (plinth) 'plinth': true,
        if (cove) 'cove': true,
        if (!cabinet) 'cabinet': false,
        if (!dressing) 'dressing': false,
        if (placed) 'placed': true,
      };

  factory LightingChoice.fromJson(Map<String, dynamic>? j) {
    if (j == null) return LightingChoice();
    return LightingChoice(
      general: j['general'] as String? ?? 'spot_led_gu10_std',
      power: j['power'] as String? ?? 'typical',
      cct: (j['cct'] as num?)?.toInt() ?? 3000,
      beam: (j['beam'] as num?)?.toInt(),
      ip: j['ip'] as String?,
      island: j['island'] as String? ?? 'suspension_ilot_focale',
      worktop: j['worktop'] as String? ?? 'ruban_led_cob_plan_travail',
      plinth: j['plinth'] as bool? ?? false,
      cove: j['cove'] as bool? ?? false,
      cabinet: j['cabinet'] as bool? ?? true,
      dressing: j['dressing'] as bool? ?? true,
      placed: j['placed'] as bool? ?? false,
    );
  }
}

// ============================================================================ résultat

/// Un luminaire posé au plafond (x le long de la largeur, y dans la profondeur, mm).
class LightSpot {
  final double x, y;
  final int lumens;
  final String kind; // forme : spot, darklight, track, magnetic, panel, ceiling, bulb, pendant, linear
  final String source;
  final int cct;
  final double length; // suspension linéaire, rail (mm)
  final int heads; // rail : nombre de projecteurs
  final bool alongY; // rail orienté dans la profondeur de la pièce (sinon dans la largeur)
  const LightSpot(this.x, this.y, this.lumens, this.kind, {this.source = '', this.cct = 3000, this.length = 0, this.heads = 1, this.alongY = false});
}

/// Un ruban LED (sous les meubles hauts, en plinthe, en corniche, dans les penderies).
class LightStrip {
  final String zone, wallId;
  final double length; // mm
  final int lmPerM;
  final double wPerM;
  const LightStrip(this.zone, this.wallId, this.length, this.lmPerM, this.wPerM);
  double get watts => length / 1000 * wPerM;
  int get lumens => (length / 1000 * lmPerM).round();

  /// Transformateur 24 V : puissance du ruban + 20 %, arrondie à une taille du commerce.
  int get driverW => const [20, 30, 60, 100, 150, 200].firstWhere((d) => d >= watts * 1.2, orElse: () => ((watts * 1.2 / 50).ceil() * 50));

  /// 24 V : 5 m alimentés par un bout, 10 m par les deux.
  String get feed => length <= 5000 ? 'alimenté par un bout' : length <= 10000 ? 'alimenté par les deux bouts' : 'à couper en tronçons de 5 m';
}

/// Un texte du calcul, traduisible : modèle français ({0}, {1}…) et valeurs (les textes sont traduits aussi).
class LightText {
  final String key;
  final List<Object> args;
  final LightText? detail; // le détail technique, pour les conseils
  const LightText(this.key, [this.args = const [], this.detail]);

  /// Le texte rempli ; [tr] traduit le modèle et les valeurs textuelles.
  String fill([String Function(String)? tr]) {
    var out = tr == null ? key : tr(key);
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      out = out.replaceAll('{$i}', a is String ? (tr == null ? a : tr(a)) : '$a');
    }
    return out;
  }

  @override
  String toString() => fill();
}

String _wf(double w) => w.toStringAsFixed(w % 1 == 0 ? 0 : 1).replaceAll('.', ',');

/// Résultat d'une zone : ce qu'il faut et ce qui est prévu.
class ZoneResult {
  final LightZone zone;
  final double area; // m² éclairés
  final int lumensNeeded;
  final int lumensPlanned;
  final LightText setup; // ce qui est prévu, en détail (technique)
  final LightText? brief; // ce qui est prévu, en mots simples
  final double watts;
  const ZoneResult(this.zone, this.area, this.lumensNeeded, this.lumensPlanned, this.setup, {this.watts = 0, this.brief});
  LightText get summary => brief ?? setup;
  bool get ok => lumensPlanned >= lumensNeeded * 0.95;
}

class LightingPlan {
  final String universe, tone;
  final double area, ceiling, uf, mf, hk;
  final LightingChoice choice;
  final List<ZoneResult> zones;
  final List<LightSpot> spots;
  final List<LightStrip> strips;
  final List<LightText> notes;
  const LightingPlan(this.universe, this.tone, this.area, this.ceiling, this.uf, this.mf, this.hk, this.choice, this.zones, this.spots, this.strips, this.notes);

  int get totalLumens => zones.fold<int>(0, (t, z) => t + z.lumensPlanned);
  double get totalWatts => zones.fold<double>(0, (t, z) => t + z.watts);
}

/// Flux nécessaire (lm) pour [lux] sur [areaM2] : méthode des lumens.
int lumensFor(int lux, double areaM2, double uf, double mf, {double hk = 1}) => (lux * areaM2 / (uf * mf) * hk).ceil();

String _m(double mm) => (mm / 1000).toStringAsFixed(2).replaceAll('.', ',');

// ============================================================================ calcul

/// Calcule l'éclairage de la pièce avec les luminaires choisis, et place les luminaires du plafond.
LightingPlan planLighting(LayoutEngine e, {String? tone, LightingChoice? choice}) {
  final p = e.project;
  final room = p.room;
  final ch = choice ?? p.specs.lighting;
  final uni = lightZones.containsKey(p.universe) ? p.universe : 'interieur';
  final zones = lightZones[uni]!;
  final t = roomTones.containsKey(tone ?? p.specs.roomTone) ? (tone ?? p.specs.roomTone) : 'clair';
  final uf = roomTones[t]!.$2;
  final mf = uni == 'cuisine' ? 0.80 : 0.85;
  final hk = heightFactor(room.height);
  final area = room.area;
  final results = <ZoneResult>[];
  final spots = <LightSpot>[];
  final strips = <LightStrip>[];
  final notes = <LightText>[];
  final kitchen = uni == 'cuisine';

  // ---- corniche indirecte : le long du périmètre, la moitié de sa lumière compte pour l'éclairage général
  var coveLm = 0;
  if (ch.cove) {
    final src = lightSourceById('ruban_led_corniche_indirect')!;
    final perimeter = room.walls.fold<double>(0, (t, w) => t + w.length);
    final s = LightStrip(coveZone.id, '', perimeter, src.lm(ch.power), src.w(ch.power));
    strips.add(s);
    coveLm = s.lumens;
    results.add(ZoneResult(coveZone, area, 0, s.lumens, LightText('{0} sur {1} m ({2} lm/m)', [src.name, _m(perimeter), src.lm(ch.power)]), watts: s.watts,
        brief: const LightText('Lumière indirecte tout autour du plafond')));
  }

  // ---- éclairage général : luminaires du plafond
  final general = zones.first;
  final need = lumensFor(general.lux, area, uf, mf, hk: hk);
  final src = ch.generalSource;
  final flux = src.lm(ch.power);
  final needFix = math.max(0, need - coveLm ~/ 2);
  final count = needFix == 0 ? 0 : math.max(1, (needFix / flux).ceil());
  final rows = kitchen && const {'spot', 'darklight', 'bulb'}.contains(src.shape);
  final cct = src.ccts.contains(ch.cct) ? ch.cct : src.ccts.reduce((a, b) => (a - 3000).abs() <= (b - 3000).abs() ? a : b);
  final rail = const {'track', 'magnetic'}.contains(src.shape);
  // projecteurs : un rail continu par linéaire de meubles (parallèle au plan de travail), têtes régulièrement
  // espacées ; sinon des luminaires alignés au bord avant du plan, puis une grille pour le reste
  final at = count == 0 || rail ? const <(double, double)>[] : _generalPositions(e, count, rows);
  for (final (x, y) in at) {
    spots.add(LightSpot(x, y, flux, src.shape, source: src.id, cct: cct));
  }
  if (rail && count > 0) spots.addAll(_rails(e, count, flux, src, cct));
  final fixtures = rail ? spots.where((s) => s.source == src.id).fold<int>(0, (t, s) => t + s.heads) : at.length;
  final beam = src.beams.isEmpty ? null : (src.beams.contains(ch.beam) ? ch.beam : src.beams[src.beams.length ~/ 2]);
  final ip = ch.ip != null && src.ips.contains(ch.ip) ? ch.ip! : (uni == 'bain' && src.ips.contains('IP44') ? 'IP44' : src.ips.first);
  results.add(ZoneResult(general, area, need, flux * fixtures + coveLm ~/ 2,
      beam == null
          ? LightText('{0} × {1}, {2} W, {3} lm, {4} K, {5}', [fixtures, src.name, _wf(src.w(ch.power)), flux, cct, ip])
          : LightText('{0} × {1}, {2} W, {3} lm, {4} K, faisceau {5}°, {6}', [fixtures, src.name, _wf(src.w(ch.power)), flux, cct, beam, ip]),
      watts: src.w(ch.power) * fixtures,
      brief: rail
          ? LightText('{0} projecteurs sur {1} rail(s)', [fixtures, spots.where((s) => s.source == src.id).length])
          : LightText('{0} × {1}', [fixtures, src.label])));
  if (src.note.isNotEmpty) notes.add(LightText(src.note));
  if (kitchen && (src.ugr ?? 0) > 19) {
    notes.add(LightText('Ce luminaire peut éblouir au plan de travail : le spot anti-éblouissement est plus confortable.', const [],
        LightText('{0} : UGR {1} — au-dessus de 19, la lumière peut éblouir au plan de travail.', [src.name, src.ugr!])));
  }
  if (src.cri < 90) {
    notes.add(LightText('Les couleurs (aliments, bois) seront moins fidèles : choisissez un luminaire au meilleur rendu des couleurs.', const [],
        LightText('{0} : IRC {1} — la norme demande au moins 90 en cuisine et en chambre.', [src.name, src.cri])));
  }

  if (kitchen) {
    // ---- plan de travail : sous chaque linéaire de meubles hauts
    final worktop = zones[1];
    final ws = lightSourceById(ch.worktop);
    var wtArea = 0.0, wtLm = 0, wtW = 0.0, total = 0.0, modules = <int>[];
    for (final w in room.walls.where((w) => w.enabled)) {
      for (final (a, b) in e.runs(w.id, (m) => m.kind.isHigh)) {
        if (b - a < 400) continue;
        wtArea += (b - a) / 1000 * 0.6;
        total += b - a;
        if (ws == null) continue;
        if (ws.perM) {
          final s = LightStrip(worktop.id, w.id, b - a, ws.lm(ch.power), ws.w(ch.power));
          strips.add(s);
          wtLm += s.lumens;
          wtW += s.watts;
        } else {
          // réglettes : les plus longues d'abord, sur la longueur du linéaire moins 100 mm
          var left = b - a - 100;
          for (final l in [...ws.lengths]..sort((x, y) => y.compareTo(x))) {
            while (left >= l) {
              modules.add(l);
              left -= l;
            }
          }
          if (left >= 300 && modules.isEmpty) modules.add(ws.lengths.first);
        }
      }
    }
    if (ws != null && !ws.perM) {
      // flux et puissance d'une réglette : du plus court au plus long modèle
      for (final l in modules) {
        final k = ws.lengths.length < 2 ? 1.0 : (l - ws.lengths.first) / (ws.lengths.last - ws.lengths.first);
        wtLm += (ws.lmMin + (ws.lmMax - ws.lmMin) * k).round();
        wtW += ws.wMin + (ws.wMax - ws.wMin) * k;
      }
    }
    if (wtArea > 0) {
      final wtNeed = lumensFor(worktop.lux, wtArea, uf, mf);
      final setup = ws == null
          ? const LightText('Rien sous les meubles hauts')
          : ws.perM
              ? LightText('{0}, {1} W/m (~{2} lm/m) sur {3} m', [ws.name, _wf(ws.w(ch.power)), ws.lm(ch.power), _m(total)])
              : LightText('{0} × {1} ({2})', [modules.length, ws.name, modules.map((l) => '$l mm').join(', ')]);
      results.add(ZoneResult(worktop, wtArea, wtNeed, wtLm, setup,
          watts: wtW,
          brief: ws == null
              ? const LightText('Rien sous les meubles hauts')
              : ws.perM
                  ? const LightText('Ruban lumineux sous les meubles hauts')
                  : LightText('{0} réglettes sous les meubles hauts', [modules.length])));
    }
    // ---- îlot : suspensions
    final isl = room.island;
    final is_ = lightSourceById(ch.island);
    if (isl != null) {
      final island = zones[2];
      final iArea = isl.length / 1000 * Island.depth / 1000;
      final iNeed = lumensFor(island.lux, iArea, uf, mf);
      final cx = isl.x0 + isl.length / 2, cy = isl.y0 + Island.depth / 2;
      if (is_ == null) {
        results.add(ZoneResult(island, iArea, iNeed, 0, const LightText('Rien au-dessus de l’îlot')));
      } else if (is_.shape == 'linear') {
        // longueur : celle du catalogue la plus proche des 2/3 de l'îlot
        final want = isl.length * 2 / 3;
        final len = is_.lengths.reduce((a, b) => (a - want).abs() <= (b - want).abs() ? a : b).toDouble();
        final lm = is_.lm(ch.power);
        spots.add(LightSpot(cx, cy, lm, 'linear', source: is_.id, cct: cct, length: len));
        results.add(ZoneResult(island, iArea, iNeed, lm, LightText('1 × {0} de {1} mm, {2} lm, à 750–850 mm au-dessus du plan', [is_.name, len.round(), lm]), watts: is_.w(ch.power),
            brief: const LightText('Une suspension linéaire au-dessus de l’îlot')));
      } else {
        final lm = is_.lm(ch.power);
        final n = math.max(isl.length >= 1800 ? 3 : isl.length >= 1200 ? 2 : 1, (iNeed / lm).ceil()).clamp(1, 5);
        final step = math.min(800.0, isl.length / n);
        for (var i = 0; i < n; i++) {
          spots.add(LightSpot(cx + (i - (n - 1) / 2) * step, cy, lm, 'pendant', source: is_.id, cct: cct));
        }
        results.add(ZoneResult(island, iArea, iNeed, lm * n, LightText('{0} × {1} de {2} lm, à 750–850 mm au-dessus du plan', [n, is_.name, lm]), watts: is_.w(ch.power) * n,
            brief: LightText('{0} suspensions au-dessus de l’îlot', [n])));
      }
    }
    // ---- vitrines : un mini-spot par caisson vitré
    final glass = p.items.where((c) => e.modelOf(c).id.contains('glass')).toList();
    if (ch.cabinet && glass.isNotEmpty) {
      final z = zones[4];
      final ps = lightSourceById('mini_spot_meuble_vitrine')!;
      final gArea = glass.fold<double>(0, (t, c) => t + c.width / 1000 * 0.3);
      results.add(ZoneResult(z, gArea, lumensFor(z.lux, gArea, uf, mf), ps.lm(ch.power) * glass.length, LightText('{0} × {1}, {2} lm', [glass.length, ps.name, ps.lm(ch.power)]),
          watts: ps.w(ch.power) * glass.length, brief: LightText('{0} mini-spots dans les vitrines', [glass.length])));
    }
    // ---- plinthe : ruban d'ambiance sous les bas
    if (ch.plinth) {
      var plinth = 0.0;
      for (final w in room.walls.where((w) => w.enabled)) {
        for (final (a, b) in _ownRuns(e, w.id)) {
          plinth += b - a;
        }
      }
      if (plinth > 0) {
        final z = zones.last;
        final ps = lightSourceById('ruban_led_plinthe_sous_lit')!;
        final s = LightStrip(z.id, '', plinth, ps.lm(ch.power), ps.w(ch.power));
        strips.add(s);
        final pArea = plinth / 1000 * 0.5;
        results.add(ZoneResult(z, pArea, lumensFor(z.lux, pArea, uf, mf), s.lumens, LightText('{0}, {1} W/m sur {2} m', [ps.name, _wf(ps.w(ch.power)), _m(plinth)]), watts: s.watts,
            brief: const LightText('Plinthe lumineuse sous les meubles bas')));
      }
    }
  }
  if (uni == 'dressing' && ch.dressing) {
    final z = zones[1];
    final ds = lightSourceById('barre_penderie_dressing_led')!;
    final len = p.items.fold<double>(0, (t, c) => t + c.width);
    if (len > 0) {
      final s = LightStrip(z.id, '', len, ds.lm(ch.power), ds.w(ch.power));
      strips.add(s);
      final dArea = len / 1000 * 0.6;
      results.add(ZoneResult(z, dArea, lumensFor(z.lux, dArea, uf, mf), s.lumens, LightText('{0} sur {1} m', [ds.name, _m(len)]), watts: s.watts,
          brief: const LightText('Penderies lumineuses')));
    }
  }
  return LightingPlan(uni, t, area, room.height, uf, mf, hk, ch, results, spots, strips, notes);
}

/// Places de [count] luminaires du plafond. En cuisine ([rows]) : d'abord une ligne à 600 mm de chaque mur
/// équipé de meubles bas (au bord avant du plan de travail, jamais dans le dos de la personne), espacés
/// d'environ 1100 mm ; puis une grille pour le reste. Sinon : une grille régulière.
List<(double, double)> _generalPositions(LayoutEngine e, int count, bool rows) {
  final room = e.project.room;
  final out = <(double, double)>[];
  if (rows) {
    final runs = <(Wall, double, double)>[
      for (final w in room.walls.where((w) => w.enabled && w.straight))
        for (final (a, b) in _ownRuns(e, w.id))
          if (b - a >= 500) (w, a, b),
    ];
    final natural = [for (final (_, a, b) in runs) math.max(1, ((b - a) / 1100).round())];
    final r = natural.fold<int>(0, (t, k) => t + k);
    // moins de luminaires que de places au bord du plan : on les répartit selon la longueur des linéaires
    var share = natural;
    if (count < r) {
      final total = runs.fold<double>(0, (t, x) => t + x.$3 - x.$2);
      share = [for (final (_, a, b) in runs) ((b - a) / total * count).floor()];
      var left = count - share.fold<int>(0, (t, k) => t + k);
      for (var i = 0; left > 0; i = (i + 1) % share.length, left--) {
        share[i]++;
      }
    }
    for (var i = 0; i < runs.length; i++) {
      final (w, a, b) = runs[i];
      for (var k = 0; k < share[i]; k++) {
        final s = a + (b - a) * (k + 0.5) / share[i];
        final x = w.x0 + w.dx * s + w.nx * 600, y = w.y0 + w.dy * s + w.ny * 600;
        if (room.contains(x, y) && !_overIsland(room, x, y) && out.every((q) => _d(q, (x, y)) > 600)) out.add((x, y));
      }
    }
  }
  // le reste : grille, à distance des luminaires déjà posés
  final rest = count - out.length;
  if (rest > 0) {
    for (var n = rest; n <= rest * 4 + 4; n++) {
      final free = [
        for (final q in _grid(room, n, 500))
          if (!_overIsland(room, q.$1, q.$2) && out.every((o) => _d(o, q) > 900)) q,
      ];
      if (free.length >= rest || n == rest * 4 + 4) {
        // les plus proches du centre de la zone libre d'abord : la grille reste équilibrée
        out.addAll(free.take(rest));
        break;
      }
    }
  }
  if (out.isEmpty) out.add((room.width / 2, room.depth / 2));
  return out;
}

/// Rails de projecteurs : un rail par linéaire de meubles bas, à 700 mm du mur (au-dessus du bord avant du plan),
/// de la longueur du linéaire moins 300 mm à chaque bout ; les [count] têtes se répartissent selon les longueurs,
/// au moins deux par rail. Sans meubles : un rail au milieu de la pièce, dans sa longueur.
List<LightSpot> _rails(LayoutEngine e, int count, int flux, LightSource src, int cct) {
  final room = e.project.room;
  final runs = <(Wall, double, double)>[
    for (final w in room.walls.where((w) => w.enabled && w.straight && w.orthogonal))
      for (final (a, b) in _ownRuns(e, w.id))
        if (b - a >= 900) (w, a, b),
  ];
  final out = <LightSpot>[];
  if (runs.isEmpty) {
    final alongY = room.depth > room.width;
    final len = (alongY ? room.depth : room.width) - 1000;
    out.add(LightSpot(room.width / 2, room.depth / 2, flux * count, src.shape, source: src.id, cct: cct, length: len, heads: count, alongY: alongY));
    return out;
  }
  final total = runs.fold<double>(0, (t, r) => t + r.$3 - r.$2);
  var left = count;
  for (var i = 0; i < runs.length; i++) {
    final (w, a, b) = runs[i];
    final share = i == runs.length - 1 ? left : math.max(2, ((b - a) / total * count).round());
    final n = math.max(2, share);
    left -= share;
    final len = math.max(600.0, b - a - 600);
    final mid = (a + b) / 2;
    final x = w.x0 + w.dx * mid + w.nx * 700, y = w.y0 + w.dy * mid + w.ny * 700;
    out.add(LightSpot(x, y, flux * n, src.shape, source: src.id, cct: cct, length: len, heads: n, alongY: w.dy.abs() > 0.5));
  }
  return out;
}

/// Linéaires de meubles bas qui portent vraiment un meuble de ce mur (les meubles d'angle d'un mur voisin
/// apparaissent aussi dans les linéaires : sans ce tri, on posait des luminaires le long de murs vides).
List<(double, double)> _ownRuns(LayoutEngine e, String wallId) => [
      for (final (a, b) in e.runs(wallId, (m) => m.kind.isLow))
        if (e.project.items.any((c) => c.wallId == wallId && e.modelOf(c).kind.isLow && c.right > a + 1 && c.s < b - 1)) (a, b),
    ];

double _d((double, double) a, (double, double) b) => math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

bool _overIsland(Room room, double x, double y) {
  final isl = room.island;
  if (isl == null) return false;
  return x > isl.x0 - 200 && x < isl.x0 + isl.length + 200 && y > isl.y0 - 200 && y < isl.y0 + Island.depth + 200;
}

/// Grille régulière d'environ [n] points dans la pièce, à [margin] mm au moins des murs.
List<(double, double)> _grid(Room room, int n, double margin) {
  final w = math.max(1.0, room.width - 2 * margin), d = math.max(1.0, room.depth - 2 * margin);
  final cols = math.max(1, (math.sqrt(n * w / d)).round());
  final rows = math.max(1, (n / cols).ceil());
  return [
    for (var r = 0; r < rows; r++)
      for (var c = 0; c < cols; c++)
        if (room.contains(margin + w * (c + 0.5) / cols, margin + d * (r + 0.5) / rows)) (margin + w * (c + 0.5) / cols, margin + d * (r + 0.5) / rows),
  ];
}

/// Choix automatique des luminaires pour la pièce, selon les normes : au plafond, le luminaire (et sa
/// puissance) dont le nombre tombe au plus près d'un luminaire par 1,2 m² environ (spots espacés de
/// 1000 à 1200 mm), sans éblouir (UGR ≤ 19 en cuisine), avec un IRC d'au moins 90 ; jamais d'halogène.
/// Température : 3000 K (4000 K en buanderie). Îlot : suspensions focales, linéaire si l'îlot est long.
LightingChoice autoLighting(LayoutEngine e) {
  final p = e.project;
  final uni = lightZones.containsKey(p.universe) ? p.universe : 'interieur';
  final kitchen = uni == 'cuisine';
  final room = p.room;
  final uf = roomTones[p.specs.roomTone]?.$2 ?? 0.75;
  final mf = kitchen ? 0.80 : 0.85;
  final need = lumensFor(lightZones[uni]!.first.lux, room.area, uf, mf, hk: heightFactor(room.height));
  final ideal = math.max(1.0, room.area / 1.2);
  LightSource? best;
  var bestPower = 'typical';
  var bestScore = double.infinity;
  for (final s in lightSourcesFor('general')) {
    if (s.id.contains('halogene')) continue;
    for (final power in const ['min', 'typical', 'max']) {
      final n = (need / s.lm(power)).ceil();
      // spots et rails : au plus près de l'idéal ; dalle et plafonnier : peu nombreux, mais éblouissement et IRC comptent
      var score = (n - ideal).abs() / ideal;
      if (s.cri < 90) score += 1.0;
      if (kitchen && (s.ugr ?? 19) > 19) score += 0.6;
      if (const {'panel', 'ceiling', 'bulb'}.contains(s.shape)) score += 0.4; // éclairage moins réparti
      if (power != 'typical') score += 0.05;
      if (score < bestScore) {
        bestScore = score;
        best = s;
        bestPower = power;
      }
    }
  }
  final src = best ?? lightSources.first;
  final cct = uni == 'buanderie' ? 4000 : 3000;
  final isl = room.island;
  final glass = p.items.any((c) => e.modelOf(c).id.contains('glass'));
  return LightingChoice(
    general: src.id,
    power: bestPower,
    cct: src.ccts.contains(cct) ? cct : src.ccts.first,
    island: isl != null && isl.length >= 1800 ? 'suspension_lineaire_ilot' : 'suspension_ilot_focale',
    worktop: 'ruban_led_cob_plan_travail',
    plinth: false,
    cove: false,
    cabinet: glass,
    dressing: true,
  );
}

/// Contrôles de l'éclairage (page Contrôles) : seulement quand des luminaires sont posés (réseaux affichés).
/// Messages simples, détail technique entre parenthèses.
List<(String code, bool warning, LightText text)> lightingChecks(LayoutEngine e) {
  final p = e.project;
  if (!p.networks) return const [];
  final plan = planLighting(e);
  final out = <(String, bool, LightText)>[];
  for (final z in plan.zones) {
    if (z.lumensNeeded == 0 || z.ok) continue;
    out.add(('light_low', true,
        LightText('{0} : pas assez de lumière ({1} lm prévus pour {2} lm, norme {3} lux)', [z.zone.name, z.lumensPlanned, z.lumensNeeded, z.zone.lux])));
  }
  for (final z in plan.zones) {
    if (z.lumensNeeded == 0 || z.lumensPlanned <= z.lumensNeeded * 2.2 || z.zone.id.contains('worktop')) continue;
    out.add(('light_high', false, LightText('{0} : beaucoup plus de lumière que nécessaire ({1} lm pour {2} lm) : une intensité plus douce suffit', [z.zone.name, z.lumensPlanned, z.lumensNeeded])));
  }
  for (final n in plan.notes) {
    out.add(('light_note', false, n.detail == null ? n : LightText('{0} ({1})', [n.fill(), n.detail!.fill()])));
  }
  return out;
}

/// Réglages effectifs d'un point lumineux du plafond : les siens, sinon ceux choisis pour la pièce.
class PointLight {
  final LightSource source;
  final String power;
  final int cct;
  final int? beam;
  const PointLight(this.source, this.power, this.cct, this.beam);
  int get lumens => source.lm(power);
  double get watts => source.w(power);
}

PointLight pointLightOf(LightingChoice ch, {String? fix, String? power, int? cct, int? beam}) {
  final src = lightSourceById(fix ?? ch.general) ?? ch.generalSource;
  final k = cct ?? ch.cct;
  final b = beam ?? ch.beam;
  return PointLight(
    src,
    power ?? ch.power,
    src.ccts.contains(k) ? k : src.ccts.reduce((a, c) => (a - k).abs() <= (c - k).abs() ? a : c),
    src.beams.isEmpty ? null : (src.beams.contains(b) ? b : src.beams[src.beams.length ~/ 2]),
  );
}
