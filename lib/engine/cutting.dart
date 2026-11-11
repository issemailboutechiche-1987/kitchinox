/// Débit des caissons (liste des pièces) et plan de découpe sur panneaux (scie à panneaux).
///
/// Règles de construction (modifiables dans [CutSettings]) :
/// - caisson en panneau de [carcassThickness] mm, façades MDF de [doorThickness] mm ;
/// - la profondeur des pièces du caisson = profondeur du meuble - épaisseur de la porte
///   (600 - 18 = 582 mm) : la porte vient devant ;
/// - bas : 2 côtés pleine hauteur, 1 dessous, 2 traverses de 100 mm (dessous du plan de travail) ;
/// - hauts et colonnes : 2 côtés, 1 dessus, 1 dessous ;
/// - façades : jeu de [frontGap] mm sur la hauteur et la largeur.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'catalog.dart';
import 'corners.dart';
import 'end_panels.dart';
import 'front_layout.dart';
import 'layout_engine.dart';

class CutSettings {
  int sheetLength;
  int sheetWidth;
  int kerf; // trait de scie
  int trim; // recoupe des bords du panneau
  int carcassThickness;
  int doorThickness;
  int frontGap; // jeu vertical total d'une façade
  int gapH; // jeu horizontal total d'une façade
  int gapBetween; // jeu entre deux portes d'un même caisson
  int golaTop, golaMid; // retraits des façades basses avec profil Gola (haut / intermédiaire)
  /// Décalage de la rainure du fond depuis le chant arrière (mm).
  static const grooveOffset = 16;
  bool backPanel; // fond arrière rainuré
  int backThickness, grooveDepth;
  String backMaterial;
  String drawerSystem; // 'bois' (caisson de tiroir en panneaux) | 'metal' (côtés métal, fond et dos bois)
  String drawerMaterial; // panneau 16 mm des tiroirs métalliques
  int railWidth;
  String carcassMaterial;
  String frontMaterial;
  bool includeShelves; // étagères dans le débit
  bool includeRails; // traverses au lieu d'un dessus plein
  int method; // méthode SketchCut : 1 par longueur, 2 par largeur, 3 optimale
  String machine; // 'scie' (scie à panneaux : bandes puis tronçons) | 'cnc' (imbrication libre)

  CutSettings({
    this.sheetLength = 2800,
    this.sheetWidth = 2100,
    this.kerf = 4,
    this.trim = 4,
    this.carcassThickness = 18,
    this.doorThickness = 18,
    this.frontGap = 4,
    this.gapH = 4,
    this.gapBetween = 3,
    this.golaTop = 35,
    this.golaMid = 30,
    this.backPanel = true,
    this.backThickness = 6,
    this.grooveDepth = 9,
    this.backMaterial = 'HDF 6 mm',
    this.drawerSystem = 'bois',
    this.drawerMaterial = 'MDF 16 mm',
    this.railWidth = 100,
    this.carcassMaterial = 'MDF',
    this.frontMaterial = 'MDF',
    this.includeShelves = false,
    this.includeRails = false,
    this.method = 1,
    this.machine = 'scie',
  });

  Map<String, dynamic> toJson() => {
    'sheet_length': sheetLength,
    'sheet_width': sheetWidth,
    'kerf': kerf,
    'trim': trim,
    'carcass_thickness': carcassThickness,
    'door_thickness': doorThickness,
    'front_gap': frontGap,
    'gap_h': gapH,
    'gap_between': gapBetween,
    'gola_top': golaTop,
    'gola_mid': golaMid,
    'back_panel': backPanel,
    'cut_v': 2, // version 2 : fonds rainurés par défaut
    'back_thickness': backThickness,
    'groove_depth': grooveDepth,
    'back_material': backMaterial,
    'drawer_system': drawerSystem,
    'drawer_material': drawerMaterial,
    'rail_width': railWidth,
    'carcass_material': carcassMaterial,
    'front_material': frontMaterial,
    'include_shelves': includeShelves,
    'include_rails': includeRails,
    'method': method,
    'machine': machine,
  };

  factory CutSettings.fromJson(Map<String, dynamic> j) {
    final d = CutSettings();
    return CutSettings(
      sheetLength: j['sheet_length'] ?? d.sheetLength,
      sheetWidth: j['sheet_width'] ?? d.sheetWidth,
      kerf: j['kerf'] ?? d.kerf,
      trim: j['trim'] ?? d.trim,
      carcassThickness: j['carcass_thickness'] ?? d.carcassThickness,
      doorThickness: j['door_thickness'] ?? d.doorThickness,
      frontGap: j['front_gap'] ?? d.frontGap,
      gapH: j['gap_h'] ?? d.gapH,
      gapBetween: j['gap_between'] ?? d.gapBetween,
      golaTop: j['gola_top'] ?? d.golaTop,
      golaMid: j['gola_mid'] ?? d.golaMid,
      // anciens réglages (sans version) : fond rainuré, comme en atelier
      backPanel: j['cut_v'] == null ? true : (j['back_panel'] ?? d.backPanel),
      backThickness: j['back_thickness'] ?? d.backThickness,
      grooveDepth: j['groove_depth'] ?? d.grooveDepth,
      backMaterial: j['back_material'] ?? d.backMaterial,
      drawerSystem: j['drawer_system'] ?? d.drawerSystem,
      drawerMaterial: j['drawer_material'] ?? d.drawerMaterial,
      railWidth: j['rail_width'] ?? d.railWidth,
      carcassMaterial: j['carcass_material'] ?? d.carcassMaterial,
      frontMaterial: j['front_material'] ?? d.frontMaterial,
      includeShelves: j['include_shelves'] ?? d.includeShelves,
      includeRails: j['include_rails'] ?? d.includeRails,
      method: j['method'] ?? d.method,
      machine: j['machine'] ?? d.machine,
    );
  }
}

/// Une pièce à débiter (quantité regroupée).
class CutPart {
  final String material;
  final String name; // ex. « Côté », « Porte »
  final String cabinet; // repère + désignation du meuble
  final int length; // le plus grand côté
  final int width;
  int qty;
  final bool canRotate;
  final int edgeLong; // nombre de chants sur les longueurs (0, 1, 2)
  final int edgeShort; // nombre de chants sur les largeurs
  final int grooveLong; // rainure parallèle à la longueur (fond arrière), 0 ou 1
  final int grooveShort; // rainure parallèle à la largeur
  CutPart(this.material, this.name, this.cabinet, int a, int b, this.qty,
      {this.canRotate = true, this.edgeLong = 0, this.edgeShort = 0, this.grooveLong = 0, this.grooveShort = 0})
    : length = math.max(a, b),
      width = math.min(a, b);

  String get key => '$material|$name|$cabinet|$length|$width|$canRotate|$edgeLong|$edgeShort|$grooveLong|$grooveShort';

  /// Longueur de rainure (mm) pour une pièce.
  int get grooveLength => grooveLong * length + grooveShort * width;
  int get area => length * width;

  /// Longueur de chant (mm) pour une pièce.
  int get edgeLength => edgeLong * length + edgeShort * width;

  /// Chant à plaquer, ex. « 1 x 750 » ou « 2 x 747 + 2 x 597 ».
  String get edgeText => [if (edgeLong > 0) '$edgeLong x $length', if (edgeShort > 0) '$edgeShort x $width'].join(' + ');
}

/// Panneau des façades selon leur finition (null = matière des façades des réglages).
/// L'interface le renseigne : un décor bois ou pierre est un panneau à part.
String? Function(String finishId)? frontDecorOf;

/// Finition à fil (bois) : les façades ne pivotent pas sur le panneau.
bool Function(String finishId)? frontGrainLocked;

/// Caissons dans un décor à fil (bois) : leurs pièces ne pivotent pas. Branché par l'interface.
bool Function(String carcassId)? carcassGrainLocked;

/// Liste des pièces de toute la cuisine, regroupées, numérotées dans l'ordre des repères.
List<CutPart> cutList(LayoutEngine e, CutSettings cs, Map<String, int> reperes) {
  final parts = <String, CutPart>{};
  final T = cs.carcassThickness, gap = cs.frontGap; // jeu vertical
  final items = [...e.project.items]..stableSort((a, b) => (reperes[a.uid] ?? 0).compareTo(reperes[b.uid] ?? 0));

  for (final c in items) {
    final m = e.modelOf(c);
    final rep = reperes[c.uid];
    final tag = rep == null ? m.name : 'Rep. $rep - ${m.name}';
    // el : chants le long du côté a ; es : chants le long du côté b
    final finishId = e.project.style.frontOf(c, high: m.kind.isHigh);
    final grain = frontGrainLocked?.call(finishId) ?? false;
    final frMat = frontDecorOf?.call(finishId) ?? cs.frontMaterial;
    final car = cs.carcassMaterial;
    final carcassGrain = carcassGrainLocked?.call(e.project.style.carcass) ?? false;
    // ga : rainure du fond le long du côté a (côtés, dessus / dessous quand le fond est rainuré)
    void add(String mat, String name, int a, int b, int qty, {int el = 0, int es = 0, bool rotate = true, int ga = 0}) {
      if (a <= 0 || b <= 0 || qty <= 0) return;
      // façade à fil : la longueur (hauteur de la porte) reste dans le sens du fil du panneau
      if (mat == frMat && grain) rotate = false;
      if (mat == car && carcassGrain) rotate = false;
      final (eLong, eShort) = a >= b ? (el, es) : (es, el);
      final g = cs.backPanel ? ga : 0;
      final (gLong, gShort) = a >= b ? (g, 0) : (0, g);
      final p = CutPart(mat, name, tag, a, b, qty, canRotate: rotate, edgeLong: eLong, edgeShort: eShort, grooveLong: gLong, grooveShort: gShort);
      final k = p.key;
      if (parts.containsKey(k)) {
        parts[k]!.qty += qty;
      } else {
        parts[k] = p;
      }
    }

    final fr = frMat;
    final H = c.height, W = c.width;
    final dc = c.depth - cs.doorThickness; // profondeur du caisson (porte devant)
    final inner = W - 2 * T;
    final gh = cs.gapH, gb = cs.gapBetween;
    // profil Gola sur les bas : la première façade (en haut) perd golaTop, les suivantes golaMid
    final gola = e.project.style.handle == 'gola' && m.kind.isLow;
    var firstFront = true;
    int vg() {
      final g = gola ? (firstFront ? cs.golaTop : cs.golaMid) : gap;
      firstFront = false;
      return g;
    }

    int fw(int count, [int? width]) => count <= 1 ? (width ?? W) - gh : ((width ?? W) - gh - gb * (count - 1)) ~/ count;
    final g2 = cs.grooveDepth;
    void back(int len, int wid) {
      if (cs.backPanel) add(cs.backMaterial, 'Fond arrière ${cs.backThickness} mm (rainuré)', len, wid, 1);
    }

    // caisson : 2 côtés (H x profondeur) + dessus et dessous (largeur - 2 épaisseurs x profondeur),
    // chant sur l'unique chant visible : la face avant
    // étagères : en retrait du fond rainuré (décalage + épaisseur du fond + 2 mm de jeu)
    final int shelfD = cs.backPanel ? dc - math.max(20, CutSettings.grooveOffset + cs.backThickness + 2) : dc - 20;
    void carcassBase({bool shelf = true}) {
      add(car, 'Côté', H, dc, 2, el: 1, ga: 1);
      if (cs.includeRails) {
        add(car, 'Dessous', inner, dc, 1, el: 1, ga: 1);
        add(car, 'Traverse', inner, cs.railWidth, 2, el: 1);
      } else {
        add(car, 'Dessus / dessous', inner, dc, 2, el: 1, ga: 1);
      }
      if (shelf && cs.includeShelves) add(car, 'Étagère', inner - 2, shelfD, 1, el: 1);
      back(H - T + g2, inner + 2 * g2);
    }

    void carcassBox(int shelves) {
      add(car, 'Côté', H, dc, 2, el: 1, ga: 1);
      add(car, 'Dessus / dessous', inner, dc, 2, el: 1, ga: 1);
      if (shelves > 0 && cs.includeShelves) add(car, 'Étagère', inner - 2, shelfD, shelves, el: 1);
      back(H - 2 * T + 2 * g2, inner + 2 * g2);
      // colonne : tablette fixe médiane (rigidité)
      if (m.kind == CabinetKind.tall && H > 1800) add(car, 'Tablette fixe médiane', inner, cs.backPanel ? shelfD + 2 : dc, 1, el: 1);
    }

    void doors(int count, {int? height, int? width}) {
      final h = (height ?? H) - vg();
      final w = fw(count, width);
      add(fr, count == 1 ? 'Porte' : 'Porte (x$count)', h, w, count, el: 2, es: 2);
    }

    void drawerFronts(List<double> ratios, {int? total}) {
      final tot = total ?? H;
      final sum = ratios.fold<double>(0, (a, b) => a + b);
      for (final r in ratios) {
        final fh = (tot * r / sum).round();
        add(fr, 'Façade tiroir', fh - vg(), W - gh, 1, el: 2, es: 2);
        if (cs.drawerSystem == 'metal') {
          // tiroir à côtés métal (type Tandembox) : seuls le fond et le dos sont en bois 16 mm
          final nominal = (((dc - 50) / 50).floor() * 50).clamp(270, 650);
          final backH = fh < 200
              ? 84
              : fh < 300
              ? 116
              : 167;
          add(cs.drawerMaterial, 'Fond tiroir métal', nominal - 10, W - 2 * T - 75, 1);
          add(cs.drawerMaterial, 'Dos tiroir métal', backH, W - 2 * T - 87, 1, el: 1);
        } else {
          // caisson de tiroir : 2 côtés + avant/arrière (coulisses 13 mm de chaque côté)
          final bh = math.max(80, fh - 60);
          add(car, 'Côté tiroir', dc - 80, bh, 2, el: 1);
          add(car, 'Avant / arrière tiroir', inner - 26 - 2 * T, bh, 2, el: 1);
          add(car, 'Fond tiroir', inner - 26 - 2 * T, dc - 80 - 2 * T, 1);
        }
      }
    }

    final twoDoors = c.opening == 'double_hinged' || m.id.contains('double_door') || W >= 800;

    // façade composée (catalogue ou personnalisée) : caisson + une pièce par case
    final rows = rowsOf(m, c);
    if (rows != null) {
      final cells = cellsOf(rows, H);
      if (m.kind.isLow) {
        carcassBase(shelf: !cells.any((x) => x.kind == CellKind.drawer));
      } else {
        carcassBox(m.kind.isHigh ? math.max(1, H ~/ 300 - 1) : 4);
      }
      for (var i = 0; i < cells.length; i++) {
        final x = cells[i];
        final h = x.h.round();
        switch (x.kind) {
          case CellKind.door:
            add(fr, 'Porte', h - vg(), fw(1), 1, el: 2, es: 2);
          case CellKind.door2:
            add(fr, 'Porte (x2)', h - vg(), fw(2), 2, el: 2, es: 2);
          case CellKind.glass:
            final n = W >= 800 ? 2 : 1;
            add(fr, n == 2 ? 'Porte vitrée - cadre (x2)' : 'Porte vitrée - cadre', h - vg(), fw(n), n, el: 2, es: 2);
          case CellKind.flap:
            add(fr, 'Porte relevable', h - vg(), fw(1), 1, el: 2, es: 2);
          case CellKind.panel:
            add(fr, 'Panneau fixe', h - vg(), fw(1), 1, el: 2, es: 2);
          case CellKind.drawer:
            drawerFronts([1], total: h);
          case CellKind.niche:
          case CellKind.appliance:
            break;
        }
        // tablette fixe entre deux cases (pas entre deux tiroirs)
        if (i > 0 && !(x.kind == CellKind.drawer && cells[i - 1].kind == CellKind.drawer)) {
          add(
            car,
            x.kind == CellKind.niche || cells[i - 1].kind == CellKind.niche ? 'Tablette de niche' : 'Tablette de séparation',
            inner,
            dc,
            1,
            el: 1,
          );
        }
      }
      continue;
    }

    switch (m.kind) {
      case CabinetKind.base:
        switch (m.id) {
          case 'base_drawers_multi':
            carcassBase(shelf: false);
            drawerFronts(switch (c.variant) {
              '2_deep_drawers' => [1, 1],
              '1_low_2_deep' => [0.6, 1.2, 1.2],
              '4_drawers' => [1, 1, 1, 1],
              _ => [1, 1, 1],
            });
          case 'base_cooktop_oven':
            carcassBase(shelf: true); // l'étagère porte le four
            drawerFronts([1], total: (H * 0.28).round());
          case 'base_sink':
            carcassBase(shelf: false);
            doors(twoDoors ? 2 : 1);
          case 'base_pullout_spice':
            carcassBase(shelf: false);
            doors(1);
          case 'base_integrated_dishwasher_door':
            doors(1); // façade seule sur l'appareil
          default:
            carcassBase();
            doors(twoDoors ? 2 : 1);
        }
      case CabinetKind.wall:
        final shelves = math.max(1, H ~/ 300 - 1);
        carcassBox(shelves);
        switch (m.id) {
          case 'wall_open_shelf':
            break;
          case 'wall_lift_up':
            add(fr, 'Porte relevable', H - vg(), fw(1), 1, el: 2, es: 2);
          case 'wall_integrated_hood':
            doors(1, height: (H * 0.8).round());
          default:
            doors(twoDoors ? 2 : 1);
        }
      case CabinetKind.tall:
        switch (m.id) {
          case 'tall_integrated_fridge':
            carcassBox(1);
            final split = switch (c.variant) {
              '50_50' => 0.5,
              'single_door' => 1.0,
              _ => 0.7,
            };
            doors(1, height: (H * split).round());
            if (split < 1) doors(1, height: H - (H * split).round());
          case 'tall_oven_microwave':
            carcassBox(3); // supports des niches
            doors(1, height: (H * 0.2).round());
            drawerFronts([1, 1], total: (H * 0.36).round());
          default:
            carcassBox(4);
            if (H > 1800) {
              doors(1, height: H ~/ 2);
              doors(1, height: H - H ~/ 2);
            } else {
              doors(1);
            }
        }
      case CabinetKind.cornerBase:
      case CabinetKind.cornerWall:
        // formules d'angle (L 90°, pan coupé 45°, borgne) ; Gola : portes basses raccourcies de 35 mm
        final golaCorner = e.project.style.handle == 'gola' && m.kind == CabinetKind.cornerBase;
        for (final (kind, name, a, b, q, el, es) in cornerCutList(m, c, T: T, td: cs.doorThickness, gap: gap, gola: golaCorner)) {
          if (kind == 'fond') {
            add(cs.backMaterial, '$name (${cs.backThickness} mm)', a, b, q);
          } else {
            add(kind == 'facade' ? fr : car, name, a, b, q, el: el, es: es);
          }
        }
      case CabinetKind.fillerBase:
      case CabinetKind.fillerWall:
        add(fr, 'Fileur', H, W, 1, el: 2, es: 0);
      case CabinetKind.coverPanel:
        add(fr, 'Joue de finition', H, c.depth, 1, el: 2, es: 2);
      case CabinetKind.islandPanel:
        add(fr, 'Habillage îlot', W, H, 1, el: 2, es: 2);
    }
  }
  // joues de finition automatiques : panneau de façade, chant sur la face avant et les bouts visibles
  if (e.project.style.endPanels) {
    for (final j in endPanels(e)) {
      final finishId = j.high ? (e.project.style.frontUpper ?? e.project.style.front) : (e.project.style.frontLower ?? e.project.style.front);
      final mat = frontDecorOf?.call(finishId) ?? cs.frontMaterial;
      final grain = frontGrainLocked?.call(finishId) ?? false;
      final p = CutPart(
        mat,
        'Joue de finition',
        'Joue ${j.high ? 'haut' : 'bas'} mur ${j.wallId}',
        j.height.round(),
        j.depth.round(),
        1,
        canRotate: !grain,
        edgeLong: 1,
        edgeShort: j.high ? 2 : 1,
      );
      if (parts.containsKey(p.key)) {
        parts[p.key]!.qty += 1;
      } else {
        parts[p.key] = p;
      }
    }
  }
  return parts.values.toList();
}

// ---------------------------------------------------------------------------
// Optimisation de la découpe (guillotine, meilleur ajustement)
// ---------------------------------------------------------------------------

class SheetPlacement {
  final CutPart part;
  final int index; // n° de la pièce dans la liste (1..n)
  final double x, y; // mm depuis le coin du panneau
  final int dx, dy; // dimensions posées
  final bool rotated;
  const SheetPlacement(this.part, this.index, this.x, this.y, this.dx, this.dy, this.rotated);
}

class _Free {
  double x, y, w, h;
  _Free(this.x, this.y, this.w, this.h);
}

class CutSheet {
  final int number;
  final String material;
  final int length, width;
  final List<SheetPlacement> placements = [];
  final List<_Free> _free = [];

  /// Longueur des traits de scie de la feuille (mm), calculée par l'optimiseur « scie ».
  double cutLen = 0;

  /// Nombre de bandes (refentes sur toute la longueur) pour la scie à panneaux.
  int strips = 0;
  CutSheet(this.number, this.material, this.length, this.width, int trim) {
    _free.add(_Free(trim.toDouble(), trim.toDouble(), (length - 2 * trim).toDouble(), (width - 2 * trim).toDouble()));
  }

  int get partsArea => placements.fold(0, (a, p) => a + p.dx * p.dy);
  double get usage => partsArea / (length * width);

  /// Chutes réutilisables (rectangles libres d'au moins 100 x 100 mm).
  List<(double, double, double, double)> get remnants => [
    for (final f in _free)
      if (f.w >= 100 && f.h >= 100) (f.x, f.y, f.w, f.h),
  ];
}

class CutPlan {
  final CutSettings settings;
  final List<CutPart> parts;
  final List<CutSheet> sheets;
  final List<CutPart> notPlaced;
  const CutPlan(this.settings, this.parts, this.sheets, this.notPlaced);

  int get partCount => parts.fold(0, (a, p) => a + p.qty);
  double get partsArea => parts.fold<double>(0, (a, p) => a + p.area * p.qty) / 1e6;
  double sheetsArea(String material) => sheets.where((s) => s.material == material).fold<double>(0, (a, s) => a + s.length * s.width) / 1e6;
  List<String> get materials => {for (final p in parts) p.material}.toList();

  /// Longueur de coupe (m) : traits réels pour la scie à panneaux, sinon deux traits par pièce.
  double get cutLength =>
      sheets.fold<double>(0, (a, s) => a + (s.cutLen > 0 ? s.cutLen : s.placements.fold<double>(0, (b, p) => b + p.dx + p.dy))) / 1000;

  /// Longueur de coupe d'un matériau (m).
  double cutLengthOf(String material) =>
      sheets
          .where((s) => s.material == material)
          .fold<double>(0, (a, s) => a + (s.cutLen > 0 ? s.cutLen : s.placements.fold<double>(0, (b, p) => b + p.dx + p.dy))) /
      1000;

  /// Longueur de chant (m) par matériau.
  double edgeLength(String material) => parts.where((p) => p.material == material).fold<double>(0, (a, p) => a + p.edgeLength * p.qty) / 1000;
}

/// Place les pièces sur des panneaux, matériau par matériau.
/// Optimise le débit : essaie plusieurs règles de placement (plus petit reste sur le côté court,
/// meilleure surface ; tri par longueur ou par surface) et garde celle qui use le moins de
/// panneaux, puis celle qui laisse la plus grande chute réutilisable.
/// Tri stable (à égalité, l'ordre d'arrivée est gardé), identique sur toutes les plateformes.
/// Le tri de `List.sort` diffère : instable dans Dart VM, stable (tri natif) dans le navigateur ;
/// avec lui, une même cuisine donnait un débit différent sur tablette et en natif.
extension StableSort<T> on List<T> {
  void stableSort(int Function(T a, T b) compare) {
    final n = length;
    if (n < 2) return;
    var src = List<T>.of(this);
    var dst = List<T>.of(this);
    // tri par insertion des blocs de 16, puis fusions successives
    const run = 16;
    for (var lo = 0; lo < n; lo += run) {
      final hi = lo + run < n ? lo + run : n;
      for (var i = lo + 1; i < hi; i++) {
        final x = src[i];
        var j = i - 1;
        while (j >= lo && compare(src[j], x) > 0) {
          src[j + 1] = src[j];
          j--;
        }
        src[j + 1] = x;
      }
    }
    for (var w = run; w < n; w *= 2) {
      for (var lo = 0; lo < n; lo += 2 * w) {
        final mid = lo + w < n ? lo + w : n, hi = lo + 2 * w < n ? lo + 2 * w : n;
        var i = lo, j = mid, k = lo;
        while (i < mid && j < hi) {
          dst[k++] = compare(src[j], src[i]) < 0 ? src[j++] : src[i++];
        }
        while (i < mid) {
          dst[k++] = src[i++];
        }
        while (j < hi) {
          dst[k++] = src[j++];
        }
      }
      final t = src;
      src = dst;
      dst = t;
    }
    setAll(0, src);
  }
}

CutPlan nest(List<CutPart> parts, CutSettings cs) => cs.machine == 'cnc' ? _nestFree(parts, cs) : _nestStrips(parts, cs);

// ---------------------------------------------------------------------------
// Cache et calcul hors du fil de l'interface
// ---------------------------------------------------------------------------

/// Clé d'un débit : réglages + pièces (mêmes pièces, mêmes réglages → même plan).
String nestKey(List<CutPart> parts, CutSettings cs) => '${jsonEncode(cs.toJson())}|${parts.map((p) => '${p.key}x${p.qty}').join(';')}';

final _nestMemo = <String, CutPlan>{};

/// Débit déjà calculé pour cette clé (ou null).
CutPlan? nestPeek(String key) => _nestMemo[key];

/// Mémorise un débit (les 12 derniers : pages cuisine, meuble d'art, mobilier, PDF).
void nestRemember(String key, CutPlan plan) {
  _nestMemo.remove(key);
  _nestMemo[key] = plan;
  while (_nestMemo.length > 12) {
    _nestMemo.remove(_nestMemo.keys.first);
  }
}

/// Comme [nest], sans recalcul quand les pièces et les réglages n'ont pas changé.
CutPlan nestCached(List<CutPart> parts, CutSettings cs) {
  final key = nestKey(parts, cs);
  final hit = _nestMemo[key];
  if (hit != null) {
    nestRemember(key, hit);
    return hit;
  }
  final plan = nest(parts, cs);
  nestRemember(key, plan);
  return plan;
}

Map<String, Object?> cutPartToJson(CutPart p) => {
      'm': p.material, 'n': p.name, 'c': p.cabinet, 'l': p.length, 'w': p.width, 'q': p.qty, 'r': p.canRotate,
      'el': p.edgeLong, 'es': p.edgeShort, 'gl': p.grooveLong, 'gs': p.grooveShort,
    };

CutPart cutPartFromJson(Map<String, dynamic> j) => CutPart('${j['m']}', '${j['n']}', '${j['c']}', j['l'] as int, j['w'] as int, j['q'] as int,
    canRotate: j['r'] as bool, edgeLong: j['el'] as int, edgeShort: j['es'] as int, grooveLong: j['gl'] as int, grooveShort: j['gs'] as int);

/// Demande de débit à envoyer à un fil de calcul (Web Worker, Isolate) : texte JSON compact.
String nestRequest(int id, List<CutPart> parts, CutSettings cs) =>
    jsonEncode({'id': id, 'cs': cs.toJson(), 'parts': [for (final p in parts) cutPartToJson(p)]});

/// Exécute une demande de débit (côté fil de calcul) et renvoie le plan en JSON.
/// Les pièces sont désignées par leur rang dans la demande : rien de lourd ne transite.
String nestJob(String request) {
  final j = jsonDecode(request) as Map<String, dynamic>;
  final parts = [for (final x in j['parts'] as List) cutPartFromJson(x as Map<String, dynamic>)];
  final cs = CutSettings.fromJson(j['cs'] as Map<String, dynamic>);
  final plan = nest(parts, cs);
  final at = Map<CutPart, int>.identity();
  for (var i = 0; i < parts.length; i++) {
    at[parts[i]] = i;
  }
  return jsonEncode({
    'id': j['id'],
    'sheets': [
      for (final s in plan.sheets)
        {
          'n': s.number, 'm': s.material, 'l': s.length, 'w': s.width, 'st': s.strips, 'cut': s.cutLen,
          'free': [for (final f in s._free) [f.x, f.y, f.w, f.h]],
          'pl': [for (final p in s.placements) [at[p.part], p.index, p.x, p.y, p.dx, p.dy, p.rotated ? 1 : 0]],
        },
    ],
    'np': [for (final p in plan.notPlaced) at[p]],
  });
}

/// Plan reconstruit à partir de la réponse du fil de calcul, avec les pièces d'origine.
CutPlan nestFromResponse(Map<String, dynamic> j, List<CutPart> parts, CutSettings cs) {
  final sheets = <CutSheet>[];
  for (final x in j['sheets'] as List) {
    final m = x as Map<String, dynamic>;
    final s = CutSheet(m['n'] as int, '${m['m']}', m['l'] as int, m['w'] as int, 0)
      ..strips = m['st'] as int
      ..cutLen = (m['cut'] as num).toDouble();
    s._free
      ..clear()
      ..addAll([
        for (final f in m['free'] as List)
          _Free((f[0] as num).toDouble(), (f[1] as num).toDouble(), (f[2] as num).toDouble(), (f[3] as num).toDouble()),
      ]);
    for (final p in m['pl'] as List) {
      s.placements.add(SheetPlacement(parts[p[0] as int], p[1] as int, (p[2] as num).toDouble(), (p[3] as num).toDouble(), p[4] as int,
          p[5] as int, p[6] == 1));
    }
    sheets.add(s);
  }
  return CutPlan(cs, parts, sheets, [for (final i in j['np'] as List) parts[i as int]]);
}

CutPlan _nestFree(List<CutPart> parts, CutSettings cs) {
  CutPlan? best;
  double bestRemnant = -1;
  for (final (areaFit, byArea) in const [(false, false), (true, true), (true, false), (false, true)]) {
    final plan = _nestWith(parts, cs, areaFit: areaFit, sortByArea: byArea);
    final remnant = plan.sheets.isEmpty ? 0.0 : plan.sheets.map((s) => s._free.fold<double>(0, (m, f) => math.max(m, f.w * f.h))).reduce(math.max);
    final better =
        best == null ||
        plan.notPlaced.length < best.notPlaced.length ||
        (plan.notPlaced.length == best.notPlaced.length &&
            (plan.sheets.length < best.sheets.length || (plan.sheets.length == best.sheets.length && remnant > bestRemnant * 1.05)));
    if (better) {
      best = plan;
      bestRemnant = remnant;
    }
  }
  return best!;
}

CutPlan _nestWith(List<CutPart> parts, CutSettings cs, {required bool areaFit, required bool sortByArea}) {
  final sheets = <CutSheet>[];
  final notPlaced = <CutPart>[];
  final kerf = cs.kerf.toDouble();
  final usableL = cs.sheetLength - 2 * cs.trim, usableW = cs.sheetWidth - 2 * cs.trim;

  for (final mat in {for (final p in parts) p.material}) {
    final own = <CutSheet>[];
    // une entrée par pièce physique, les plus grandes d'abord
    final pieces =
        <(CutPart, int)>[
          for (var i = 0; i < parts.length; i++)
            if (parts[i].material == mat)
              for (var q = 0; q < parts[i].qty; q++) (parts[i], i + 1),
        ]..stableSort((a, b) {
          if (sortByArea) {
            final c = b.$1.area.compareTo(a.$1.area);
            return c != 0 ? c : math.max(b.$1.length, b.$1.width).compareTo(math.max(a.$1.length, a.$1.width));
          }
          final c = b.$1.length.compareTo(a.$1.length);
          return c != 0 ? c : b.$1.area.compareTo(a.$1.area);
        });

    for (final (part, idx) in pieces) {
      final fits = (part.length <= usableL && part.width <= usableW) || (part.canRotate && part.width <= usableL && part.length <= usableW);
      if (!fits) {
        notPlaced.add(part);
        continue;
      }
      var placed = false;
      for (final sheet in [...own, null]) {
        final s = sheet ?? (CutSheet(sheets.length + 1, mat, cs.sheetLength, cs.sheetWidth, cs.trim));
        // meilleur rectangle libre (plus petit reste sur le côté court)
        _Free? best;
        var bestScore = double.infinity;
        var bestRot = false;
        for (final f in s._free) {
          for (final rot in part.canRotate ? [false, true] : [false]) {
            final w = (rot ? part.width : part.length).toDouble(), h = (rot ? part.length : part.width).toDouble();
            if (w <= f.w && h <= f.h) {
              final score = areaFit ? f.w * f.h - w * h : math.min(f.w - w, f.h - h);
              if (score < bestScore) {
                bestScore = score;
                best = f;
                bestRot = rot;
              }
            }
          }
        }
        if (best == null) continue;
        if (sheet == null) {
          own.add(s);
          sheets.add(s);
        }
        final w = bestRot ? part.width : part.length, h = bestRot ? part.length : part.width;
        s.placements.add(SheetPlacement(part, idx, best.x, best.y, w, h, bestRot));
        // découpe guillotine : on coupe d'abord sur le côté qui laisse la plus grande chute
        s._free.remove(best);
        final rightW = best.w - w - kerf, bottomH = best.h - h - kerf;
        if (rightW * best.h >= best.w * bottomH) {
          if (rightW > 0) s._free.add(_Free(best.x + w + kerf, best.y, rightW, best.h));
          if (bottomH > 0) s._free.add(_Free(best.x, best.y + h + kerf, w.toDouble(), bottomH));
        } else {
          if (bottomH > 0) s._free.add(_Free(best.x, best.y + h + kerf, best.w, bottomH));
          if (rightW > 0) s._free.add(_Free(best.x + w + kerf, best.y, rightW, h.toDouble()));
        }
        placed = true;
        break;
      }
      if (!placed) notPlaced.add(part);
    }
  }
  return CutPlan(cs, parts, sheets, notPlaced);
}

// ---------------------------------------------------------------------------
// Export SketchCut PRO (.sct, format <V3.0>) : pièces à optimiser dans SketchCut
// ---------------------------------------------------------------------------

/// Fichier .sct d'un matériau : les pièces sont « non découpées », SketchCut calcule le plan.
String toSct(CutPlan plan, String material, {String order = 'kitchinox', String thickness = '18', DateTime? date}) {
  final cs = plan.settings;
  final d = date ?? DateTime.now();
  String b(bool v) => v ? '1' : '0';
  final parts = plan.parts.where((p) => p.material == material).toList();
  final out = <String>[
    '<V3.0>',
    '1',
    '${cs.sheetLength}X${cs.sheetWidth}_0',
    '${cs.method}X${cs.kerf}X${cs.trim}_True',
    order,
    '${d.month}/${d.day}/${d.year}',
    '',
    material,
    thickness,
    '2',
    '',
    '0.4',
    '',
    '1',
    '',
    '<Parts>${parts.length}',
  ];
  for (final p in parts) {
    out.add('${p.length}X${p.width}X${p.qty}');
    out.add('${p.edgeLong}X${p.edgeShort}_${p.grooveLong}X${p.grooveShort}');
    final name = '${p.name} ${p.cabinet}'.replaceAll('\n', ' ');
    out.add('${b(p.canRotate)}0$name');
    for (var i = 0; i < p.qty; i++) {
      out.add('000_0X-1X-1');
    }
  }
  // profondeur de rainure, décalage depuis le chant arrière, largeur (épaisseur du fond + 1 mm de jeu)
  out.addAll(['<USnips>0', '<NSnips>0', '${cs.grooveDepth}', '${CutSettings.grooveOffset}', '${cs.backThickness + 1}']);
  return '${out.join('\r\n')}\r\n';
}

// ---------------------------------------------------------------------------
// Scie à panneaux : débit en bandes (comme SketchCut)
// 1. refentes sur toute la longueur de la feuille → bandes de la largeur des pièces ;
// 2. tronçonnage de chaque bande → colonnes ;
// 3. recoupe dans une colonne quand plusieurs pièces étroites s'y empilent.
// Toutes les coupes traversent la pièce en cours : réalisable sur une scie à panneaux.
// ---------------------------------------------------------------------------

class _Col {
  final double x, len;
  double usedW = 0;
  final List<(CutPart, int, double, double, double, bool)> items = []; // pièce, n°, y relatif, long., larg., tournée
  _Col(this.x, this.len);
}

class _Strip {
  final double y, w;
  double used = 0;
  final List<_Col> cols = [];
  _Strip(this.y, this.w);
}

class _SSheet {
  double usedW = 0;
  final List<_Strip> strips = [];
}

CutPlan _nestStrips(List<CutPart> parts, CutSettings cs) {
  if (cs.method != 3) return _stripsAlong(parts, cs, cs.method == 2 ? const [false] : const [true]);
  // optimale : bandes dans le sens de la longueur, de la largeur, et les deux mêlés ; pour chaque matériau
  // le meilleur des trois. Jamais moins bien que « par longueur » ou « par largeur » (le choix glouton
  // de la feuille la plus pleine, sens mêlés, peut coûter une feuille à la fin).
  final strip = _bestPerMaterial(parts, cs, [
    _stripsAlong(parts, cs, const [true]),
    _stripsAlong(parts, cs, const [false]),
    _stripsAlong(parts, cs, const [true, false]),
  ]);
  // aussi la guillotine libre (première coupe dans un sens ou l'autre, à chaque niveau)
  final free = _nestFree(parts, cs);
  final better = free.notPlaced.length < strip.notPlaced.length ||
      (free.notPlaced.length == strip.notPlaced.length && free.sheets.length < strip.sheets.length);
  return better ? free : strip;
}

/// Meilleur plan de chaque matériau parmi [plans] : moins de pièces refusées, moins de feuilles,
/// puis feuilles les plus pleines ; feuilles renumérotées dans l'ordre.
CutPlan _bestPerMaterial(List<CutPart> parts, CutSettings cs, List<CutPlan> plans) {
  final sheets = <CutSheet>[];
  final notPlaced = <CutPart>[];
  for (final mat in {for (final p in parts) p.material}) {
    CutPlan? best;
    (int, int, double)? bestKey;
    for (final plan in plans) {
      final sh = plan.sheets.where((s) => s.material == mat);
      final key = (
        plan.notPlaced.where((p) => p.material == mat).length,
        sh.length,
        -sh.fold<double>(0, (a, s) => a + s.usage * s.usage),
      );
      final better = bestKey == null ||
          key.$1 < bestKey.$1 ||
          (key.$1 == bestKey.$1 && (key.$2 < bestKey.$2 || (key.$2 == bestKey.$2 && key.$3 < bestKey.$3 - 1e-9)));
      if (better) {
        best = plan;
        bestKey = key;
      }
    }
    for (final s in best!.sheets.where((s) => s.material == mat)) {
      final c = CutSheet(sheets.length + 1, mat, s.length, s.width, 0)
        ..strips = s.strips
        ..cutLen = s.cutLen;
      c._free
        ..clear()
        ..addAll(s._free);
      c.placements.addAll(s.placements);
      sheets.add(c);
    }
    notPlaced.addAll(best.notPlaced.where((p) => p.material == mat));
  }
  return CutPlan(cs, parts, sheets, notPlaced);
}

CutPlan _stripsAlong(List<CutPart> parts, CutSettings cs, List<bool> along) {
  // ancien débit à 3 niveaux (bandes, tronçons, empilement) : gardé comme candidat
  CutPlan? old;
  double oldRem = -1;
  for (final a in along) {
    for (final order in const ['width', 'length', 'area']) {
      final plan = _stripRun(parts, cs, alongLength: a, order: order);
      final rem = plan.sheets.isEmpty ? 0.0 : plan.sheets.expand((s) => s._free).fold<double>(0, (m, f) => math.max(m, f.w * f.h));
      final better =
          old == null ||
          plan.notPlaced.length < old.notPlaced.length ||
          (plan.notPlaced.length == old.notPlaced.length &&
              (plan.sheets.length < old.sheets.length || (plan.sheets.length == old.sheets.length && rem > oldRem * 1.05)));
      if (better) {
        old = plan;
        oldRem = rem;
      }
    }
  }
  // débit guillotine complet, matériau par matériau
  final sheets = <CutSheet>[];
  final notPlaced = <CutPart>[];
  for (final mat in {for (final p in parts) p.material}) {
    final g = _guillBest(parts, mat, cs, sheets.length + 1, along);
    final o = old!.sheets.where((s) => s.material == mat).toList();
    final oNot = old.notPlaced.where((p) => p.material == mat).length;
    final useOld = oNot < g.notPlaced.length || (oNot == g.notPlaced.length && o.length < g.sheets.length);
    if (useOld) {
      for (final s in o) {
        final c = CutSheet(sheets.length + 1, mat, s.length, s.width, 0)
          ..strips = s.strips
          ..cutLen = s.cutLen;
        c._free
          ..clear()
          ..addAll(s._free);
        c.placements.addAll(s.placements);
        sheets.add(c);
      }
      notPlaced.addAll(old.notPlaced.where((p) => p.material == mat));
    } else {
      sheets.addAll(g.sheets);
      notPlaced.addAll(g.notPlaced);
    }
  }
  return CutPlan(cs, parts, sheets, notPlaced);
}

CutPlan _stripRun(List<CutPart> parts, CutSettings cs, {required bool alongLength, required String order}) {
  final kerf = cs.kerf.toDouble(), trim = cs.trim.toDouble();
  final stripLen = (alongLength ? cs.sheetLength : cs.sheetWidth) - 2 * trim;
  final across = (alongLength ? cs.sheetWidth : cs.sheetLength) - 2 * trim;
  final sheets = <CutSheet>[];
  final notPlaced = <CutPart>[];

  for (final mat in {for (final p in parts) p.material}) {
    final pieces = <(CutPart, int)>[
      for (var i = 0; i < parts.length; i++)
        if (parts[i].material == mat)
          for (var q = 0; q < parts[i].qty; q++) (parts[i], i + 1),
    ];
    // orientations possibles : (longueur le long de la bande, largeur en travers, tournée)
    List<(double, double, bool)> orients(CutPart p) {
      // le fil (longueur de la pièce) suit la longueur de la feuille
      final natural = alongLength ? (p.length.toDouble(), p.width.toDouble(), false) : (p.width.toDouble(), p.length.toDouble(), true);
      final turned = alongLength ? (p.width.toDouble(), p.length.toDouble(), true) : (p.length.toDouble(), p.width.toDouble(), false);
      return [natural, if (p.canRotate && p.length != p.width) turned];
    }

    pieces.stableSort((x, y) {
      final ox = orients(x.$1).first, oy = orients(y.$1).first;
      final c = switch (order) {
        'length' => oy.$1.compareTo(ox.$1),
        'area' => (y.$1.area).compareTo(x.$1.area),
        _ => oy.$2.compareTo(ox.$2),
      };
      if (c != 0) return c;
      final c2 = oy.$1.compareTo(ox.$1);
      return c2 != 0 ? c2 : oy.$2.compareTo(ox.$2);
    });

    final own = <_SSheet>[];
    for (final (part, idx) in pieces) {
      final opts = orients(part).where((o) => o.$1 <= stripLen && o.$2 <= across).toList();
      if (opts.isEmpty) {
        notPlaced.add(part);
        continue;
      }
      var placed = false;
      for (final sh in [...own, null]) {
        final sheet = sh ?? _SSheet();
        // meilleure place dans cette feuille : (score, action)
        double bestScore = double.infinity;
        void Function()? action;
        for (final (l, w, rot) in opts) {
          for (final st in sheet.strips) {
            // a) empiler dans une colonne existante (3e coupe)
            for (final col in st.cols) {
              final y = col.usedW == 0 ? 0.0 : col.usedW + kerf;
              if (l <= col.len + 0.01 && y + w <= st.w + 0.01) {
                final score = (col.len - l) * w + (st.w - y - w) * 0.01;
                if (score < bestScore) {
                  bestScore = score;
                  action = () {
                    col.items.add((part, idx, y, l, w, rot));
                    col.usedW = y + w;
                  };
                }
              }
            }
            // b) nouvelle colonne au bout de la bande (tronçonnage)
            final x = st.used == 0 ? 0.0 : st.used + kerf;
            if (w <= st.w + 0.01 && x + l <= stripLen + 0.01) {
              final score = (st.w - w) * l + 1;
              if (score < bestScore) {
                bestScore = score;
                action = () {
                  final col = _Col(x, l)..usedW = w;
                  col.items.add((part, idx, 0, l, w, rot));
                  st.cols.add(col);
                  st.used = x + l;
                };
              }
            }
          }
          // c) nouvelle bande (refente)
          final y0 = sheet.usedW == 0 ? 0.0 : sheet.usedW + kerf;
          if (y0 + w <= across + 0.01) {
            final score = 1e12 + (across - y0 - w) + (stripLen - l) * 1e-3;
            if (score < bestScore) {
              bestScore = score;
              action = () {
                final st = _Strip(y0, w);
                final col = _Col(0, l)..usedW = w;
                col.items.add((part, idx, 0, l, w, rot));
                st.cols.add(col);
                st.used = l;
                sheet.strips.add(st);
                sheet.usedW = y0 + w;
              };
            }
          }
        }
        if (action == null) continue;
        action();
        if (sh == null) own.add(sheet);
        placed = true;
        break;
      }
      if (!placed) notPlaced.add(part);
    }

    // feuilles réelles : placements, chutes et longueur de coupe
    for (final sh in own) {
      final s = CutSheet(sheets.length + 1, mat, cs.sheetLength, cs.sheetWidth, cs.trim);
      s._free.clear();
      s.strips = sh.strips.length;
      // (x le long de la bande, y en travers) → coordonnées de la feuille
      void free(double x, double y, double l, double w) {
        if (l < 1 || w < 1) return;
        s._free.add(alongLength ? _Free(trim + x, trim + y, l, w) : _Free(trim + y, trim + x, w, l));
      }

      var cut = 0.0;
      for (final st in sh.strips) {
        cut += stripLen; // refente
        for (final col in st.cols) {
          cut += st.w; // tronçonnage
          for (final (part, idx, y, l, w, rot) in col.items) {
            final px = col.x, py = st.y + y;
            s.placements.add(
              alongLength
                  ? SheetPlacement(part, idx, trim + px, trim + py, l.round(), w.round(), rot)
                  : SheetPlacement(part, idx, trim + py, trim + px, w.round(), l.round(), rot),
            );
            if (col.items.length > 1) cut += col.len; // recoupe dans la colonne
            if (l < col.len - 0.5) {
              cut += w; // mise à longueur
              free(px + l + kerf, py, col.len - l - kerf, w);
            }
          }
          free(col.x, st.y + col.usedW + kerf, col.len, st.w - col.usedW - kerf);
        }
        free(st.used + kerf, st.y, stripLen - st.used - kerf, st.w);
      }
      free(0, sh.usedW + kerf, stripLen, across - sh.usedW - kerf);
      s.cutLen = cut;
      sheets.add(s);
    }
  }
  return CutPlan(cs, parts, sheets, notPlaced);
}

// ---------------------------------------------------------------------------
// Scie à panneaux, comme SketchCut : bandes sur toute la longueur (refentes),
// puis découpe guillotine sans limite de profondeur dans chaque bande
// (tronçon, refente, re-tronçon…). Plusieurs ordres et règles sont essayés.
// ---------------------------------------------------------------------------

class _GRect {
  final double x, y, w, h; // x le long de la bande, y en travers
  const _GRect(this.x, this.y, this.w, this.h);
}

class _GSheet {
  double remY = 0; // début de la partie non refendue
  int strips = 0;
  double cut = 0;
  final List<_GRect> free = [];
  final List<(CutPart, int, double, double, double, double, bool)> items = []; // pièce, n°, x, y, l, w, tournée
}

CutPlan _guillRun(
  List<(CutPart, int)> pieces,
  String mat,
  CutSettings cs,
  int firstNumber, {
  required bool alongLength,
  required int fit,
  required int split,
  bool wideStrip = false, int maxSheets = 1 << 30,
}) {
  final k = cs.kerf.toDouble(), trim = cs.trim.toDouble();
  final L = (alongLength ? cs.sheetLength : cs.sheetWidth) - 2 * trim;
  final W = (alongLength ? cs.sheetWidth : cs.sheetLength) - 2 * trim;
  final own = <_GSheet>[];
  final notPlaced = <CutPart>[];

  List<(double, double, bool)> orients(CutPart p) {
    final natural = alongLength ? (p.length.toDouble(), p.width.toDouble(), false) : (p.width.toDouble(), p.length.toDouble(), true);
    final turned = alongLength ? (p.width.toDouble(), p.length.toDouble(), true) : (p.length.toDouble(), p.width.toDouble(), false);
    return [natural, if (p.canRotate && p.length != p.width) turned];
  }

  double score(_GRect r, double l, double w) => switch (fit) {
    0 => math.min(r.w - l, r.h - w), // plus petit reste sur le côté court
    1 => r.w * r.h - l * w, // meilleure surface
    _ => math.max(r.w - l, r.h - w), // plus petit reste sur le côté long
  };

  void place(_GSheet s, _GRect r, CutPart part, int idx, double l, double w, bool rot) {
    s.free.remove(r);
    s.items.add((part, idx, r.x, r.y, l, w, rot));
    final rw = r.w - l - k, bh = r.h - w - k;
    // tronçon d'abord (coupe en travers sur toute la hauteur du rectangle) ou refente d'abord
    final crossFirst = switch (split) {
      0 => rw * r.h >= r.w * bh, // garde la plus grande chute
      1 => rw <= bh, // coupe le long de l'axe le plus court
      _ => true,
    };
    if (crossFirst) {
      if (rw > 0) {
        s.free.add(_GRect(r.x + l + k, r.y, rw, r.h));
        s.cut += r.h;
      }
      if (bh > 0) {
        s.free.add(_GRect(r.x, r.y + w + k, l, bh));
        s.cut += l;
      }
    } else {
      if (bh > 0) {
        s.free.add(_GRect(r.x, r.y + w + k, r.w, bh));
        s.cut += r.w;
      }
      if (rw > 0) {
        s.free.add(_GRect(r.x + l + k, r.y, rw, w));
        s.cut += w;
      }
    }
  }

  for (final (part, idx) in pieces) {
    final opts = orients(part).where((o) => o.$1 <= L + 0.01 && o.$2 <= W + 0.01).toList();
    if (opts.isEmpty) {
      notPlaced.add(part);
      continue;
    }
    var done = false;
    for (final sh in [...own, if (own.length < maxSheets) null]) {
      final s = sh ?? _GSheet();
      _GRect? bestR;
      (double, double, bool)? bestO;
      var best = double.infinity;
      for (final o in opts) {
        for (final r in s.free) {
          if (o.$1 <= r.w + 0.01 && o.$2 <= r.h + 0.01) {
            final sc = score(r, o.$1, o.$2);
            if (sc < best) {
              best = sc;
              bestR = r;
              bestO = o;
            }
          }
        }
      }
      if (bestR == null) {
        // nouvelle bande sur toute la longueur, de la largeur de la pièce
        (double, double, bool)? o;
        for (final c in opts) {
          final y0 = s.remY == 0 ? 0.0 : s.remY + k;
          if (y0 + c.$2 <= W + 0.01 && (o == null || (wideStrip ? c.$2 > o.$2 : c.$2 < o.$2))) o = c;
        }
        if (o != null) {
          final y0 = s.remY == 0 ? 0.0 : s.remY + k;
          final strip = _GRect(0, y0, L, o.$2);
          s.free.add(strip);
          s.remY = y0 + o.$2;
          s.strips++;
          s.cut += L;
          bestR = strip;
          bestO = o;
        }
      }
      if (bestR == null || bestO == null) continue;
      place(s, bestR, part, idx, bestO.$1, bestO.$2, bestO.$3);
      if (sh == null) own.add(s);
      done = true;
      break;
    }
    if (!done) notPlaced.add(part);
  }

  final sheets = <CutSheet>[];
  for (final g in own) {
    final s = CutSheet(firstNumber + sheets.length, mat, cs.sheetLength, cs.sheetWidth, cs.trim);
    s._free.clear();
    s.strips = g.strips;
    s.cutLen = g.cut;
    for (final (part, idx, x, y, l, w, rot) in g.items) {
      s.placements.add(
        alongLength
            ? SheetPlacement(part, idx, trim + x, trim + y, l.round(), w.round(), rot)
            : SheetPlacement(part, idx, trim + y, trim + x, w.round(), l.round(), rot),
      );
    }
    void free(double x, double y, double l, double w) {
      if (l < 1 || w < 1) return;
      s._free.add(alongLength ? _Free(trim + x, trim + y, l, w) : _Free(trim + y, trim + x, w, l));
    }

    for (final r in g.free) {
      free(r.x, r.y, r.w, r.h);
    }
    final y0 = g.remY + k;
    free(0, y0, L, W - y0);
    sheets.add(s);
  }
  return CutPlan(cs, const [], sheets, notPlaced);
}

/// Meilleur débit guillotine d'un matériau : ordres de tri, règles de placement et de coupe, essais mélangés.
CutPlan _guillBest(List<CutPart> parts, String mat, CutSettings cs, int firstNumber, List<bool> along) {
  final pieces = <(CutPart, int)>[
    for (var i = 0; i < parts.length; i++)
      if (parts[i].material == mat)
        for (var q = 0; q < parts[i].qty; q++) (parts[i], i + 1),
  ];
  final orders = <List<(CutPart, int)>>[
    [...pieces]..stableSort((a, b) => b.$1.width.compareTo(a.$1.width) != 0 ? b.$1.width.compareTo(a.$1.width) : b.$1.length.compareTo(a.$1.length)),
    [...pieces]..stableSort((a, b) => b.$1.length.compareTo(a.$1.length) != 0 ? b.$1.length.compareTo(a.$1.length) : b.$1.width.compareTo(a.$1.width)),
    [...pieces]..stableSort((a, b) => b.$1.area.compareTo(a.$1.area)),
    [...pieces]..stableSort((a, b) => (b.$1.length + b.$1.width).compareTo(a.$1.length + a.$1.width)),
  ];
  // essais mélangés (graine fixe : même résultat à chaque calcul)
  final rnd = math.Random(17);
  final extra = math.max(6, 1600 ~/ math.max(1, pieces.length));
  for (var i = 0; i < extra; i++) {
    final base = [...orders[i % 3]];
    // permutations locales : garde le tri global, mélange les voisins
    for (var j = 0; j < base.length - 1; j++) {
      if (rnd.nextDouble() < 0.35) {
        final t = base[j];
        base[j] = base[j + 1];
        base[j + 1] = t;
      }
    }
    orders.add(base);
  }
  CutPlan? best;
  double bestKey = -1;
  for (final a in along) {
    for (final o in orders) {
      for (var fit = 0; fit < 3; fit++) {
        for (var split = 0; split < 3; split++) {
          for (final wide in const [false, true]) {
            final p = _guillRun(o, mat, cs, firstNumber, alongLength: a, fit: fit, split: split, wideStrip: wide);
            // moins de pièces refusées, moins de feuilles, puis feuilles pleines en premier, puis grande chute
            final fill = p.sheets.fold<double>(0, (s, x) => s + x.usage * x.usage);
            final rem = p.sheets.expand((s) => s._free).fold<double>(0, (m, f) => math.max(m, f.w * f.h)) / 1e9;
            final key = -p.notPlaced.length * 1e6 - p.sheets.length * 1e3 + fill + rem * 1e-3;
            if (best == null || key > bestKey + 1e-9) {
              best = p;
              bestKey = key;
            }
          }
        }
      }
    }
  }
  // feuille par feuille : la feuille la plus pleine possible, puis les pièces restantes
  var rest = [...pieces];
  final sheets = <CutSheet>[];
  final refused = <CutPart>[];
  final rnd2 = math.Random(29);
  while (rest.isNotEmpty) {
    final tries = <List<(CutPart, int)>>[
      [...rest]..stableSort((a, b) => b.$1.width.compareTo(a.$1.width) != 0 ? b.$1.width.compareTo(a.$1.width) : b.$1.length.compareTo(a.$1.length)),
      [...rest]..stableSort((a, b) => b.$1.length.compareTo(a.$1.length) != 0 ? b.$1.length.compareTo(a.$1.length) : b.$1.width.compareTo(a.$1.width)),
      [...rest]..stableSort((a, b) => b.$1.area.compareTo(a.$1.area)),
    ];
    final n = math.max(8, 2400 ~/ math.max(1, rest.length));
    for (var i = 0; i < n; i++) {
      final base = [...tries[i % 3]];
      final pSwap = 0.15 + 0.5 * rnd2.nextDouble();
      for (var j = 0; j < base.length - 1; j++) {
        if (rnd2.nextDouble() < pSwap) {
          final t = base[j];
          base[j] = base[j + 1];
          base[j + 1] = t;
        }
      }
      // parfois une grande pièce passe devant : d'autres bandes de départ
      if (base.length > 2 && rnd2.nextDouble() < 0.3) base.insert(0, base.removeAt(rnd2.nextInt(base.length)));
      tries.add(base);
    }
    CutSheet? bestSheet;
    var bestArea = -1.0;
    for (final a in along) {
      for (final o in tries) {
        for (var fit = 0; fit < 3; fit++) {
          for (var split = 0; split < 3; split++) {
            for (final wide in const [false, true]) {
              final p = _guillRun(o, mat, cs, firstNumber + sheets.length, alongLength: a, fit: fit, split: split, wideStrip: wide, maxSheets: 1);
              if (p.sheets.isEmpty) continue;
              final sh = p.sheets.first;
              final area = sh.partsArea.toDouble() + sh._free.fold<double>(0, (m, f) => math.max(m, f.w * f.h)) * 1e-6;
              if (area > bestArea) {
                bestArea = area;
                bestSheet = sh;
              }
            }
          }
        }
      }
    }
    for (final a in along) {
      final bs = _beamSheet(rest, mat, cs, firstNumber + sheets.length, a);
      if (bs == null) continue;
      final area = bs.partsArea.toDouble() + bs._free.fold<double>(0, (m, f) => math.max(m, f.w * f.h)) * 1e-6;
      if (area > bestArea) {
        bestArea = area;
        bestSheet = bs;
      }
    }
    if (bestSheet == null) {
      refused.addAll(rest.map((x) => x.$1));
      break;
    }
    sheets.add(bestSheet);
    for (final pl in bestSheet.placements) {
      final at = rest.indexWhere((x) => identical(x.$1, pl.part) && x.$2 == pl.index);
      if (at >= 0) rest.removeAt(at);
    }
    rest = [...rest];
  }
  final bySheet = CutPlan(cs, const [], sheets, refused);
  final fillA = best!.sheets.fold<double>(0, (s, x) => s + x.usage * x.usage);
  final fillB = sheets.fold<double>(0, (s, x) => s + x.usage * x.usage);
  final keyA = -best.notPlaced.length * 1e6 - best.sheets.length * 1e3 + fillA;
  final keyB = -refused.length * 1e6 - sheets.length * 1e3 + fillB;
  return keyB > keyA ? bySheet : best;
}

// ---------------------------------------------------------------------------
// Choix des bandes d'une feuille (recherche en faisceau) : on essaie plusieurs suites de
// largeurs de bande ; chaque bande est remplie en guillotine libre ; la feuille la plus pleine gagne.
// ---------------------------------------------------------------------------

class _BItem {
  final CutPart part;
  final int idx;
  final double x, y, l, w;
  final bool rot;
  const _BItem(this.part, this.idx, this.x, this.y, this.l, this.w, this.rot);
}

/// État de la recherche : une feuille refendue en [strips] bandes. Pour ne pas recopier des milliers
/// de listes à chaque niveau, l'état ne garde que SA bande et un lien vers l'état parent ; les listes
/// complètes (pièces, chutes, restes) ne sont construites que pour les états gardés.
class _BState {
  final _BState? parent;
  final List<_BItem> stripItems; // pièces de la dernière bande
  final List<_GRect> stripFree; // chutes de la dernière bande
  final List<(CutPart, int)> _cand; // pièces candidates de la bande (ordre essayé)
  final Set<int>? _used; // indices de [_cand] posés dans la bande
  List<(CutPart, int)>? _rest;
  final double usedY; // largeur refendue (bandes + traits)
  final int strips;
  final double area, cut;
  _BState.root(List<(CutPart, int)> pieces)
      : parent = null,
        stripItems = const [],
        stripFree = const [],
        _cand = pieces,
        _used = null,
        _rest = pieces,
        usedY = 0,
        strips = 0,
        area = 0,
        cut = 0;
  _BState(this.parent, this.stripItems, this.stripFree, this._cand, this._used, this.usedY, this.strips, this.area, this.cut);

  /// Pièces restant à poser (calculées une fois, seulement si l'état est développé).
  List<(CutPart, int)> get rest => _rest ??= [for (var i = 0; i < _cand.length; i++) if (!_used!.contains(i)) _cand[i]];

  List<_BItem> get items => [...?parent?.items, ...stripItems];
  List<_GRect> get free => [...?parent?.free, ...stripFree];
}

/// Remplit une bande [L] x [w] (origine y0) avec les pièces dans l'ordre donné ; guillotine libre.
(List<_BItem>, List<_GRect>, double, double, Set<int>) _fillStrip(
    double L, double w, double y0, List<(CutPart, int)> pieces, double k, bool alongLength, int fit) {
  final free = <_GRect>[_GRect(0, y0, L, w)];
  final items = <_BItem>[];
  final used = <int>{};
  var area = 0.0, cut = 0.0;
  for (var i = 0; i < pieces.length; i++) {
    final (p, idx) = pieces[i];
    final pl = p.length.toDouble(), pw = p.width.toDouble();
    // orientation naturelle (fil le long de la feuille), puis tournée si permis
    final l0 = alongLength ? pl : pw, w0 = alongLength ? pw : pl;
    final twoWays = p.canRotate && p.length != p.width;
    // les chutes d'une bande ne dépassent jamais sa largeur : pièce trop large dans les deux sens, inutile de chercher
    if (w0 > w + 0.01 && (!twoWays || l0 > w + 0.01)) continue;
    _GRect? br;
    var bl = 0.0, bw = 0.0;
    var brot = false;
    var best = double.infinity;
    for (var turn = 0; turn < (twoWays ? 2 : 1); turn++) {
      final ol = turn == 0 ? l0 : w0, ow = turn == 0 ? w0 : l0;
      final orot = turn == 0 ? !alongLength : alongLength;
      for (final r in free) {
        if (ol <= r.w + 0.01 && ow <= r.h + 0.01) {
          final sc = fit == 0 ? math.min(r.w - ol, r.h - ow) : r.w * r.h - ol * ow;
          if (sc < best) {
            best = sc;
            br = r;
            bl = ol;
            bw = ow;
            brot = orot;
          }
        }
      }
    }
    if (br == null) continue;
    final l = bl, ww = bw, rot = brot;
    free.remove(br);
    items.add(_BItem(p, idx, br.x, br.y, l, ww, rot));
    used.add(i);
    area += l * ww;
    final rw = br.w - l - k, bh = br.h - ww - k;
    if (rw * br.h >= br.w * bh) {
      if (rw > 0) {
        free.add(_GRect(br.x + l + k, br.y, rw, br.h));
        cut += br.h;
      }
      if (bh > 0) {
        free.add(_GRect(br.x, br.y + ww + k, l, bh));
        cut += l;
      }
    } else {
      if (bh > 0) {
        free.add(_GRect(br.x, br.y + ww + k, br.w, bh));
        cut += br.w;
      }
      if (rw > 0) {
        free.add(_GRect(br.x + l + k, br.y, rw, ww));
        cut += ww;
      }
    }
  }
  return (items, free, area, cut, used);
}

/// Meilleure feuille (une seule) par recherche en faisceau sur les largeurs de bande.
CutSheet? _beamSheet(List<(CutPart, int)> pieces, String mat, CutSettings cs, int number, bool alongLength, {int beam = 40}) {
  final k = cs.kerf.toDouble(), trim = cs.trim.toDouble();
  final L = (alongLength ? cs.sheetLength : cs.sheetWidth) - 2 * trim;
  final W = (alongLength ? cs.sheetWidth : cs.sheetLength) - 2 * trim;
  int byArea((CutPart, int) a, (CutPart, int) b) => b.$1.area.compareTo(a.$1.area);
  int byLen((CutPart, int) a, (CutPart, int) b) => b.$1.length.compareTo(a.$1.length) != 0 ? b.$1.length.compareTo(a.$1.length) : b.$1.width.compareTo(a.$1.width);
  int byWid((CutPart, int) a, (CutPart, int) b) => b.$1.width.compareTo(a.$1.width) != 0 ? b.$1.width.compareTo(a.$1.width) : b.$1.length.compareTo(a.$1.length);

  var states = [_BState.root(pieces)];
  _BState bestEnd = states.first;
  while (states.isNotEmpty) {
    final next = <_BState>[];
    for (final st in states) {
      final rest0 = st.rest;
      final y0 = st.usedY == 0 ? 0.0 : st.usedY + k;
      // largeurs possibles : la dimension en travers de chaque pièce restante (et tournée)
      final widths = <double>{};
      for (final (p, _) in rest0) {
        final a = alongLength ? p.width.toDouble() : p.length.toDouble();
        final b = alongLength ? p.length.toDouble() : p.width.toDouble();
        if (y0 + a <= W + 0.01) widths.add(a);
        if (p.canRotate && b <= L + 0.01 && y0 + b <= W + 0.01) widths.add(b);
      }
      // les trois tris ne dépendent pas de la largeur de bande : faits une fois par état
      final sorted = widths.isEmpty ? const <List<(CutPart, int)>>[] : [for (final order in [byWid, byArea, byLen]) [...rest0]..stableSort(order)];
      // dimensions en travers de chaque pièce (sens naturel, tournée), dans l'ordre de chaque tri
      final crossA = [for (final l in sorted) Float64List.fromList([for (final x in l) alongLength ? x.$1.width.toDouble() : x.$1.length.toDouble()])];
      final crossB = [for (final l in sorted) Float64List.fromList([for (final x in l) alongLength ? x.$1.length.toDouble() : x.$1.width.toDouble()])];
      final canRot = [for (final l in sorted) [for (final x in l) x.$1.canRotate]];
      var expanded = false;
      for (final w in widths) {
        // pièces qui tiennent dans la bande, dans trois ordres
        for (var o = 0; o < sorted.length; o++) {
          final base = sorted[o];
          // celles dont la largeur est exactement celle de la bande d'abord
          // (même tri, mêmes comparaisons qu'avant : la clé 0/1 est seulement calculée une fois par pièce)
          final ca = crossA[o], cb = crossB[o], rot = canRot[o];
          final key = Uint8List(base.length);
          for (var i = 0; i < base.length; i++) {
            key[i] = ((ca[i] - w).abs() < 0.5 || (rot[i] && (cb[i] - w).abs() < 0.5)) ? 0 : 1;
          }
          // tri stable sur une clé 0/1 = partition : largeur exacte d'abord, ordre gardé dans chaque groupe
          final cand = [
            for (var i = 0; i < base.length; i++)
              if (key[i] == 0) base[i],
            for (var i = 0; i < base.length; i++)
              if (key[i] != 0) base[i],
          ];
          for (final fit in const [0, 1]) {
            final (items, free, area, cut, used) = _fillStrip(L, w, y0, cand, k, alongLength, fit);
            if (items.isEmpty) continue;
            next.add(_BState(st, items, free, cand, used, y0 + w, st.strips + 1, st.area + area, st.cut + L + cut));
            expanded = true;
          }
        }
      }
      if (!expanded && st.area > bestEnd.area) bestEnd = st;
    }
    // garde les meilleurs : surface posée, puis largeur refendue la plus petite
    next.stableSort((a, b) {
      // chute produite jusqu'ici (bandes refendues moins pièces posées) : la plus petite d'abord
      final wa = a.usedY * L - a.area, wb = b.usedY * L - b.area;
      final c = wa.compareTo(wb);
      return c != 0 ? c : b.area.compareTo(a.area);
    });
    final seen = <String>{};
    states = [];
    for (final s in next) {
      final key = '${s.area.round()}|${s.usedY.round()}';
      if (seen.add(key)) states.add(s);
      if (states.length >= beam) break;
    }
    for (final s in states) {
      if (s.area > bestEnd.area) bestEnd = s;
    }
  }
  if (bestEnd.strips == 0) return null;
  final s = CutSheet(number, mat, cs.sheetLength, cs.sheetWidth, cs.trim);
  s._free.clear();
  s.strips = bestEnd.strips;
  s.cutLen = bestEnd.cut;
  void free(double x, double y, double l, double w) {
    if (l < 1 || w < 1) return;
    s._free.add(alongLength ? _Free(trim + x, trim + y, l, w) : _Free(trim + y, trim + x, w, l));
  }

  for (final it in bestEnd.items) {
    s.placements.add(alongLength
        ? SheetPlacement(it.part, it.idx, trim + it.x, trim + it.y, it.l.round(), it.w.round(), it.rot)
        : SheetPlacement(it.part, it.idx, trim + it.y, trim + it.x, it.w.round(), it.l.round(), it.rot));
  }
  for (final r in bestEnd.free) {
    free(r.x, r.y, r.w, r.h);
  }
  final yEnd = bestEnd.usedY + k;
  free(0, yEnd, L, W - yEnd);
  return s;
}
