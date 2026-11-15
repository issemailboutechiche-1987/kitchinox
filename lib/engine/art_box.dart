/// Caisson paramétrique universel : la base de tout meuble en panneaux de bois.
///
/// 1. Enveloppe : 2 côtés pleine hauteur, dessous et dessus (plein ou 2 traverses) entre les côtés,
///    fond rainuré en retrait, cloué au dos ou vissé (18 mm). La face avant est libre : elle reçoit les façades.
/// 2. Squelette : séparations verticales (colonnes), puis tablettes fixes ou mobiles par colonne.
///    Les tablettes fixes et le dessous / dessus délimitent les zones de façade ; les mobiles restent à l'intérieur.
/// 3. Façades par zone : porte (charnière gauche / droite, double si large), pile de tiroirs, abattant, niche ouverte.
/// 4. Ajouts extérieurs : pieds réglables + plinthe, socle bois, suspendu ; joues de finition ; fileurs ; corniche.
/// 5. Quincaillerie : charnières selon la hauteur, coulisses selon la profondeur, taquets, poignées ou profil Gola,
///    tringle, accessoires ; visserie d'assemblage.
library;

import 'dart:math' as math;

import 'art.dart';
import 'cutting.dart';

/// Les composants communs à tous les meubles en panneaux de bois : un meuble, quel qu'il soit
/// (bas de cuisine, armoire, commode, bibliothèque, meuble TV, vasque…), n'est qu'un assemblage de ces pièces.
enum Comp {
  cote('Côtés', 'Montants gauche et droit, pleine hauteur : ils portent tout le reste.', 0xFFB7895A),
  dessous('Bas (dessous)', 'Entre les côtés ; reçoit le poids et les pieds.', 0xFF8D6E4C),
  dessus('Haut (dessus)', 'Panneau plein entre les côtés (armoire, haut, dressing).', 0xFFA47A52),
  traverse('Traverses', 'Deux bandes à la place du dessus, sous un plan de travail.', 0xFFC49A6C),
  fond('Derrière (fond)', 'Ferme et rigidifie le caisson (équerrage).', 0xFFD9CDBB),
  separation('Séparations', 'Montants intérieurs : divisent en colonnes.', 0xFF9C7A54),
  etagere('Étagères', 'Fixes (rigidifient, séparent les façades) ou mobiles sur taquets.', 0xFFE0B97A),
  porte('Portes', 'Sur charnières, à gauche, à droite ou par deux.', 0xFF3E7CB1),
  tiroir('Tiroirs', 'Façade + caisson de tiroir sur coulisses.', 0xFF2E9D8F),
  abattant('Abattants', 'Façade relevable ou basculante sur compas.', 0xFF6A5ACD),
  pied('Pieds / plinthe / socle', 'Ce qui porte le meuble au-dessus du sol.', 0xFF5C5F66),
  joue('Joues', 'Panneaux de finition qui habillent un côté visible.', 0xFFD2691E),
  fileur('Fileurs', 'Bandes de rattrapage contre un mur.', 0xFFE07B39),
  corniche('Corniche / cache-lumière', 'Finitions en haut ou sous le meuble.', 0xFF9E6B47);

  final String label, hint;
  final int color;
  const Comp(this.label, this.hint, this.color);
  bool get isFront => this == porte || this == tiroir || this == abattant;
}

/// Composant d'une pièce d'après son nom de débit.
Comp compOf(String name) {
  final n = name.toLowerCase();
  if (n.startsWith('côté de tiroir') || n.contains('tiroir')) return Comp.tiroir;
  if (n.startsWith('côté')) return Comp.cote;
  if (n.startsWith('dessous')) return Comp.dessous;
  if (n.startsWith('dessus')) return Comp.dessus;
  if (n.startsWith('traverse')) return Comp.traverse;
  if (n.startsWith('fond')) return Comp.fond;
  if (n.startsWith('séparation')) return Comp.separation;
  if (n.startsWith('étagère') || n.startsWith('tablette')) return Comp.etagere;
  if (n.startsWith('porte')) return Comp.porte;
  if (n.startsWith('abattant')) return Comp.abattant;
  if (n.startsWith('plinthe') || n.startsWith('socle') || n.startsWith('pied')) return Comp.pied;
  if (n.startsWith('joue')) return Comp.joue;
  if (n.startsWith('fileur')) return Comp.fileur;
  return Comp.corniche;
}

enum TopType { panel, stretchers }

enum BackType { groove, nailed, screwed, none }

enum CoverType { open, door, drawers, flap }

enum BaseType { legs, socle, wall, none }

enum DrawerBox { metal, wood }

extension TopTypeLabel on TopType {
  String get label => switch (this) { TopType.panel => 'Dessus plein', TopType.stretchers => 'Deux traverses' };
}

extension BackTypeLabel on BackType {
  String get label => switch (this) {
        BackType.groove => 'Rainuré en retrait',
        BackType.nailed => 'Cloué au dos',
        BackType.screwed => 'Vissé 18 mm',
        BackType.none => 'Sans fond',
      };
}

extension CoverTypeLabel on CoverType {
  String get label => switch (this) {
        CoverType.open => 'Niche ouverte',
        CoverType.door => 'Porte',
        CoverType.drawers => 'Tiroirs',
        CoverType.flap => 'Abattant',
      };
}

extension BaseTypeLabel on BaseType {
  String get label => switch (this) {
        BaseType.legs => 'Pieds réglables + plinthe',
        BaseType.socle => 'Socle en bois',
        BaseType.wall => 'Suspendu au mur',
        BaseType.none => 'Posé au sol',
      };
}

/// Tablette d'une colonne : hauteur de sa face inférieure depuis le dessus du dessous (intérieur).
class ArtShelf {
  double y;
  bool fixed;
  ArtShelf(this.y, {this.fixed = false});
  Map<String, dynamic> toJson() => {'y': y, 'fixed': fixed};
  factory ArtShelf.fromJson(Map<String, dynamic> j) => ArtShelf((j['y'] as num).toDouble(), fixed: j['fixed'] == true);
}

/// Habillage d'une zone (entre deux éléments fixes d'une colonne).
class ArtCover {
  CoverType type;
  String hinge; // porte : 'left' | 'right' | 'double' (deux portes)
  int count; // tiroirs
  List<String> accessories; // 'rod', 'spice', 'shoes', 'basket', 'led'
  ArtCover({this.type = CoverType.door, this.hinge = 'left', this.count = 3, List<String>? accessories}) : accessories = accessories ?? [];
  Map<String, dynamic> toJson() => {'type': type.name, 'hinge': hinge, 'count': count, if (accessories.isNotEmpty) 'acc': accessories};
  factory ArtCover.fromJson(Map<String, dynamic> j) => ArtCover(
        type: CoverType.values.firstWhere((t) => t.name == j['type'], orElse: () => CoverType.open),
        hinge: j['hinge'] as String? ?? 'left',
        count: (j['count'] as num?)?.toInt() ?? 3,
        accessories: [for (final a in (j['acc'] as List? ?? const [])) '$a'],
      );
}

/// Zone de façade : colonne, numéro de zone (du bas), et rectangle intérieur (mm, repère du meuble).
class ArtZone {
  final int col, row;
  final double x0, x1, y0, y1; // intérieur de la zone
  final double fx0, fx1, fy0, fy1; // rectangle extérieur couvert par la façade (recouvrement total)
  const ArtZone(this.col, this.row, this.x0, this.x1, this.y0, this.y1, this.fx0, this.fx1, this.fy0, this.fy1);
  String get id => 'c${col}z$row';
  double get width => x1 - x0;
  double get height => y1 - y0;
}

const accessoryNames = {
  'rod': 'Tringle de penderie',
  'spice': 'Range-épices coulissant',
  'shoes': 'Range-chaussures coulissant',
  'basket': 'Panier coulissant',
  'led': 'Éclairage LED',
};

class ArtBox {
  String name;
  double w, h, d; // hors-tout (sans pieds, sans façade)
  double t, tBack, tFront;
  TopType top;
  double stretcher; // largeur des traverses
  BackType back;
  double backRecess, groove; // fond rainuré : retrait depuis l'arrière, profondeur de rainure
  final List<double> seps; // séparations : position de leur face gauche depuis le bord gauche extérieur
  final Map<int, List<ArtShelf>> shelves; // tablettes par colonne
  final Map<String, ArtCover> covers; // habillage par zone
  double gap; // jeu autour des façades
  DrawerBox drawerBox;
  BaseType base;
  double baseH;
  bool cheekLeft, cheekRight;
  double fillerLeft, fillerRight;
  bool cornice, valance;
  String handle; // 'gola' | 'bar' | 'knob' | 'push'
  String carcass, front; // finitions
  ArtBox({
    this.name = 'Caisson',
    this.w = 800,
    this.h = 720,
    this.d = 560,
    this.t = 18,
    this.tBack = 6,
    this.tFront = 18,
    this.top = TopType.panel,
    this.stretcher = 100,
    this.back = BackType.groove,
    this.backRecess = 16,
    this.groove = 9,
    List<double>? seps,
    Map<int, List<ArtShelf>>? shelves,
    Map<String, ArtCover>? covers,
    this.gap = 2,
    this.drawerBox = DrawerBox.metal,
    this.base = BaseType.legs,
    this.baseH = 100,
    this.cheekLeft = false,
    this.cheekRight = false,
    this.fillerLeft = 0,
    this.fillerRight = 0,
    this.cornice = false,
    this.valance = false,
    this.handle = 'bar',
    this.carcass = 'blanc',
    this.front = 'blanc_mat',
  })  : seps = seps ?? [],
        shelves = shelves ?? {},
        covers = covers ?? {};

  // ---------------------------------------------------------------- géométrie
  int get columns => seps.length + 1;

  /// Bas du caisson depuis le sol (pieds, socle, ou suspendu).
  double get y0 => switch (base) { BaseType.legs || BaseType.socle => baseH, BaseType.wall => baseH, BaseType.none => 0 };

  /// Profondeur des panneaux de l'enveloppe (le fond cloué s'ajoute derrière).
  double get carcassDepth => back == BackType.nailed ? d - tBack : d;

  /// Face avant du fond (profondeur utile).
  double get innerDepth => switch (back) {
        BackType.groove => d - backRecess - tBack,
        BackType.nailed => d - tBack,
        BackType.screwed => d - tBack,
        BackType.none => d,
      };

  double get innerBottom => y0 + t;
  double get innerTop => y0 + h - t;

  /// Bords intérieurs gauche / droit de chaque colonne.
  List<(double, double)> get columnSpans {
    final xs = [...seps]..sort();
    final out = <(double, double)>[];
    var left = t;
    for (final s in xs) {
      out.add((left, s));
      left = s + t;
    }
    out.add((left, w - t));
    return out;
  }

  /// Étagères d'une colonne qui tiennent dans la hauteur intérieure (30 mm au moins au-dessus et au-dessous).
  List<ArtShelf> shelvesOf(int col) {
    final innerH = innerTop - innerBottom;
    return (shelves[col] ?? const <ArtShelf>[]).where((s) => s.y >= 30 && s.y + t <= innerH - 30).toList()..sort((a, b) => a.y.compareTo(b.y));
  }

  /// Retire les étagères qui ne tiennent plus (après une réduction de hauteur) ; renvoie leur nombre.
  int pruneShelves() {
    var n = 0;
    for (final c in shelves.keys.toList()) {
      final keep = shelvesOf(c);
      n += shelves[c]!.length - keep.length;
      shelves[c] = keep;
    }
    return n;
  }

  /// Zones de façade : entre le dessous, les tablettes fixes et le dessus de chaque colonne.
  List<ArtZone> get zones {
    final out = <ArtZone>[];
    final spans = columnSpans;
    for (var c = 0; c < spans.length; c++) {
      final (x0, x1) = spans[c];
      // recouvrement : bord extérieur sur les côtés, demi-épaisseur sur les séparations
      final fx0 = c == 0 ? 0.0 : x0 - t / 2, fx1 = c == spans.length - 1 ? w : x1 + t / 2;
      final cuts = [for (final s in shelvesOf(c).where((s) => s.fixed)) innerBottom + s.y];
      var bottom = innerBottom, fBottom = y0;
      var row = 0;
      for (final cy in [...cuts, innerTop]) {
        final isTop = cy == innerTop;
        final fTop = isTop ? y0 + h : cy + t / 2;
        out.add(ArtZone(c, row, x0, x1, bottom, cy, fx0, fx1, fBottom, fTop));
        bottom = cy + t;
        fBottom = cy + t / 2;
        row++;
      }
    }
    return out;
  }

  ArtCover coverOf(ArtZone z) => covers[z.id] ?? ArtCover(type: CoverType.open);

  /// Longueur de coulisse : la plus longue qui tient dans la profondeur utile.
  int get slideLength {
    const sizes = [250, 300, 350, 400, 450, 500, 550, 600];
    return sizes.where((s) => s <= innerDepth - 10).fold<int>(250, (a, b) => math.max(a, b));
  }

  static int hingesFor(double doorH) => doorH <= 900 ? 2 : doorH <= 1600 ? 3 : doorH <= 2000 ? 4 : 5;

  // ---------------------------------------------------------------- panneaux (3D et débit)
  /// Panneaux du meuble, posé à [ox] depuis la gauche ; noms pour le débit dans [names].
  List<ArtPanel> panels(String Function() newId, {double ox = 0, Map<String, String>? names}) {
    final out = <ArtPanel>[];
    ArtPanel add(String name, ArtRole role, double x, double y, double z, double pw, double ph, double pd, String finish, {String hinge = 'left'}) {
      final p = ArtPanel(id: newId(), role: role, x: ox + x, y: y, z: z, w: pw, h: ph, d: pd, finish: finish, hinge: hinge, comp: compOf(name));
      names?[p.id] = name;
      out.add(p);
      return p;
    }

    final cd = carcassDepth;
    // enveloppe
    add('Côté', ArtRole.montant, 0, y0, 0, t, h, cd, carcass);
    add('Côté', ArtRole.montant, w - t, y0, 0, t, h, cd, carcass);
    add('Dessous', ArtRole.tablette, t, y0, 0, w - 2 * t, t, cd, carcass);
    if (top == TopType.panel) {
      add('Dessus', ArtRole.tablette, t, y0 + h - t, 0, w - 2 * t, t, cd, carcass);
    } else {
      add('Traverse avant', ArtRole.tablette, t, y0 + h - t, 0, w - 2 * t, t, stretcher, carcass);
      add('Traverse arrière', ArtRole.tablette, t, y0 + h - t, cd - stretcher - (back == BackType.groove ? backRecess + tBack : 0), w - 2 * t, t, stretcher, carcass);
    }
    switch (back) {
      case BackType.groove:
        add('Fond (rainuré)', ArtRole.fond, t - groove, y0 + t - groove, d - backRecess - tBack, w - 2 * t + 2 * groove, h - 2 * t + 2 * groove, tBack, carcass);
      case BackType.nailed:
        add('Fond (cloué)', ArtRole.fond, 0, y0, d - tBack, w, h, tBack, carcass);
      case BackType.screwed:
        add('Fond (vissé)', ArtRole.fond, t, y0 + t, d - tBack, w - 2 * t, h - 2 * t, tBack, carcass);
      case BackType.none:
        break;
    }
    // séparations verticales : entre dessous et dessus, jusqu'au fond
    for (final s in [...seps]..sort()) {
      add('Séparation', ArtRole.montant, s, innerBottom, 0, t, innerTop - innerBottom, innerDepth, carcass);
    }
    // tablettes
    final spans = columnSpans;
    for (var c = 0; c < spans.length; c++) {
      final (x0, x1) = spans[c];
      for (final s in shelvesOf(c)) {
        if (s.fixed) {
          add('Étagère fixe', ArtRole.tablette, x0, innerBottom + s.y, 0, x1 - x0, t, innerDepth, carcass);
        } else {
          // tablette mobile : 1 mm de jeu de chaque côté, 20 mm en retrait de l'avant
          add('Étagère mobile', ArtRole.tablette, x0 + 1, innerBottom + s.y, 20, x1 - x0 - 2, t, innerDepth - 20, carcass);
        }
      }
    }
    // façades
    for (final z in zones) {
      final cv = coverOf(z);
      final colZones = zones.where((x) => x.col == z.col).toList();
      final isBottomZone = z.row == 0;
      final isTopZone = z.row == colZones.length - 1;
      final fx0 = z.fx0 + gap / 2, fx1 = z.fx1 - gap / 2;
      final fy0 = isBottomZone ? z.fy0 : z.fy0 + gap / 2;
      final fy1 = isTopZone ? z.fy1 - gap / 2 : z.fy1 - gap / 2;
      switch (cv.type) {
        case CoverType.door:
          final double2 = cv.hinge == 'double' || (cv.hinge != 'left' && cv.hinge != 'right' && fx1 - fx0 > 600);
          if (double2) {
            final dw = (fx1 - fx0 - gap) / 2;
            add('Porte', ArtRole.porte, fx0, fy0, -tFront, dw, fy1 - fy0, tFront, front, hinge: 'left');
            add('Porte', ArtRole.porte, fx0 + dw + gap, fy0, -tFront, dw, fy1 - fy0, tFront, front, hinge: 'right');
          } else {
            add('Porte', ArtRole.porte, fx0, fy0, -tFront, fx1 - fx0, fy1 - fy0, tFront, front, hinge: cv.hinge);
          }
        case CoverType.flap:
          add('Abattant', ArtRole.abattant, fx0, fy0, -tFront, fx1 - fx0, fy1 - fy0, tFront, front);
        case CoverType.drawers:
          final n = math.max(1, cv.count);
          final dh = (fy1 - fy0 - gap * (n - 1)) / n;
          final L = slideLength.toDouble();
          for (var i = 0; i < n; i++) {
            final fy = fy0 + i * (dh + gap);
            add('Façade de tiroir', ArtRole.tiroir, fx0, fy, -tFront, fx1 - fx0, dh, tFront, front);
            // caisson du tiroir (vue 3D seulement : son débit est calculé à part)
            final bh = math.min(dh - 40, dh < 160 ? 70.0 : (dh < 260 ? 120.0 : 180.0));
            final by = math.max(z.y0 + 1, fy + 20);
            final bx0 = z.x0 + 13, bx1 = z.x1 - 13;
            const bt = 16.0;
            final col = drawerBox == DrawerBox.metal ? 'gris' : carcass;
            add('Caisson de tiroir', ArtRole.decor, bx0, by, 0, bt, bh, L - 10, col);
            add('Caisson de tiroir', ArtRole.decor, bx1 - bt, by, 0, bt, bh, L - 10, col);
            add('Caisson de tiroir', ArtRole.decor, bx0 + bt, by, L - 10 - bt, bx1 - bx0 - 2 * bt, bh, bt, carcass);
            add('Caisson de tiroir', ArtRole.decor, bx0 + bt, by, 0, bx1 - bx0 - 2 * bt, 8, L - 10 - bt, carcass);
          }
        case CoverType.open:
          break;
      }
    }
    // ajouts extérieurs
    final frontZ = -tFront;
    switch (base) {
      case BaseType.legs:
        add('Plinthe', ArtRole.decor, 0, 0, 50, w, baseH - 3, 16, front);
        add('Plinthe côté', ArtRole.decor, 0, 0, 50, 16, baseH - 3, cd - 100, front);
        add('Plinthe côté', ArtRole.decor, w - 16, 0, 50, 16, baseH - 3, cd - 100, front);
      case BaseType.socle:
        add('Socle avant', ArtRole.decor, t, 0, 50, w - 2 * t, baseH, t, carcass);
        add('Socle arrière', ArtRole.decor, t, 0, cd - 80, w - 2 * t, baseH, t, carcass);
        add('Socle côté', ArtRole.decor, t, 0, 50 + t, t, baseH, cd - 130 - t, carcass);
        add('Socle côté', ArtRole.decor, w - 2 * t, 0, 50 + t, t, baseH, cd - 130 - t, carcass);
      case BaseType.wall || BaseType.none:
        break;
    }
    final cheekD = d + tFront; // affleure la façade
    if (cheekLeft) add('Joue de finition', ArtRole.decor, -t, 0, frontZ, t, y0 + h, cheekD, front);
    if (cheekRight) add('Joue de finition', ArtRole.decor, w, 0, frontZ, t, y0 + h, cheekD, front);
    final lx = cheekLeft ? -t : 0.0, rx = cheekRight ? w + t : w;
    if (fillerLeft > 0) add('Fileur', ArtRole.decor, lx - fillerLeft, y0, frontZ, fillerLeft, h, tFront, front);
    if (fillerRight > 0) add('Fileur', ArtRole.decor, rx, y0, frontZ, fillerRight, h, tFront, front);
    if (cornice) add('Corniche', ArtRole.decor, lx - fillerLeft, y0 + h, frontZ, (rx + fillerRight) - (lx - fillerLeft), 60, tFront + 40, front);
    if (valance) add('Cache-lumière', ArtRole.decor, 0, y0 - 40, frontZ, w, 40, tFront, front);
    return out;
  }

  /// Largeur totale, joues et fileurs compris.
  double get overallWidth => w + (cheekLeft ? t : 0) + (cheekRight ? t : 0) + fillerLeft + fillerRight;

  /// Décalage du caisson dans son encombrement (joue et fileur de gauche).
  double get leftExtra => (cheekLeft ? t : 0) + fillerLeft;

  // ---------------------------------------------------------------- débit
  List<CutPart> cutParts() {
    final names = <String, String>{};
    var n = 0;
    final ps = panels(() => 'x${n++}', names: names);
    final out = <String, CutPart>{};
    void put(CutPart c) => out.containsKey(c.key) ? out[c.key]!.qty += c.qty : out[c.key] = c;
    for (final p in ps) {
      final dims = [p.w, p.h, p.d]..sort();
      final a = dims[2].round(), b = dims[1].round();
      if (a <= 0 || b <= 0) continue;
      final name = names[p.id] ?? p.role.label;
      if (name == 'Caisson de tiroir') continue; // débité plus bas selon le type de tiroir
      final front = p.role.isFront || p.role == ArtRole.decor;
      final isBack = p.role == ArtRole.fond;
      // chants : façades 4 côtés ; caisson : chant avant (côtés, tablettes, séparations) ; fond : aucun
      final edgeLong = isBack ? 0 : (front ? 2 : 1);
      final edgeShort = isBack ? 0 : (front ? 2 : 0);
      final mat = isBack && p.thickness <= 8 ? 'HDF ${p.thickness.round()} (fonds)' : (front ? 'MDF ${p.thickness.round()} (façades)' : 'MDF ${p.thickness.round()} (caisson)');
      // rainure du fond : côtés (le long de la hauteur), dessous et dessus (le long de la largeur)
      final grooved = back == BackType.groove && (name == 'Côté' || name == 'Dessous' || name == 'Dessus');
      final along = name == 'Côté' ? p.h : p.w; // dimension le long de laquelle court la rainure
      final gLong = grooved && along.round() == a ? 1 : 0, gShort = grooved && along.round() != a ? 1 : 0;
      put(CutPart(mat, name, this.name, a, b, 1, canRotate: !front, edgeLong: edgeLong, edgeShort: edgeShort, grooveLong: gLong, grooveShort: gShort));
    }
    // caissons de tiroirs
    for (final z in zones) {
      final cv = coverOf(z);
      if (cv.type != CoverType.drawers) continue;
      final cnt = math.max(1, cv.count);
      final L = slideLength;
      final frontH = (z.fy1 - z.fy0) / cnt;
      final hb = frontH < 160 ? 70 : (frontH < 260 ? 120 : 180); // hauteur des côtés / du dos
      final cw = z.width;
      if (drawerBox == DrawerBox.metal) {
        // tiroir double paroi métal : seuls le fond et le dos sont en bois (16 mm)
        put(CutPart('MDF 16 (tiroirs)', 'Fond de tiroir', name, (cw - 75).round(), L - 10, cnt, edgeLong: 0, edgeShort: 0));
        put(CutPart('MDF 16 (tiroirs)', 'Dos de tiroir', name, (cw - 87).round(), hb, cnt, edgeLong: 1, edgeShort: 0));
      } else {
        // tiroir bois, coulisses latérales (13 mm par côté) : 2 côtés, face et dos intérieurs, fond HDF rainuré
        final bw = cw - 26;
        put(CutPart('MDF 16 (tiroirs)', 'Côté de tiroir', name, L - 10, hb, cnt * 2, edgeLong: 1, edgeShort: 0));
        put(CutPart('MDF 16 (tiroirs)', 'Face / dos de tiroir', name, (bw - 32).round(), hb, cnt * 2, edgeLong: 1, edgeShort: 0));
        put(CutPart('HDF 6 (fonds)', 'Fond de tiroir', name, (bw - 16).round(), L - 10, cnt, edgeLong: 0, edgeShort: 0));
      }
    }
    return out.values.toList();
  }

  // ---------------------------------------------------------------- quincaillerie et visserie
  List<(String, String, int)> hardware() {
    final out = <String, (String, double)>{};
    void add(String name, String usage, num q) {
      if (q > 0) out[name] = (out[name]?.$1 ?? usage, (out[name]?.$2 ?? 0) + q);
    }

    // assemblage de l'enveloppe : 4 vis par jonction de 600 mm de profondeur (une tous les 150-200 mm)
    int screwsFor(double len) => math.max(2, (len / 180).ceil());
    final cd = carcassDepth;
    final topJoints = top == TopType.panel ? 2 * screwsFor(cd) : 4 * 2; // traverses : 2 vis par bout
    final env = 2 * screwsFor(cd) + topJoints;
    add('Vis d’assemblage Confirmat Ø7 x 50 mm', 'côtés / dessous / dessus / séparations / tablettes fixes', env);
    add('Tourillons Ø8 x 35 mm + colle', 'positionnement des jonctions (2 par jonction)', 8);
    // séparations et tablettes fixes
    var inner = 0;
    for (final _ in seps) {
      inner += 2 * screwsFor(innerDepth);
    }
    for (var c = 0; c < columns; c++) {
      inner += shelvesOf(c).where((s) => s.fixed).length * 2 * screwsFor(innerDepth);
    }
    add('Vis d’assemblage Confirmat Ø7 x 50 mm', 'côtés / dessous / dessus / séparations / tablettes fixes', inner);
    final allConf = (out['Vis d’assemblage Confirmat Ø7 x 50 mm']?.$2 ?? 0);
    add('Cache-vis Confirmat (couleur caisson)', 'têtes visibles sur les côtés', allConf);
    // fond
    switch (back) {
      case BackType.groove:
        add('Fraisage rainure ${tBack.round() + 1} x ${groove.round()} mm', 'côtés, dessous, dessus (à ${backRecess.round()} mm de l’arrière)', 1);
      case BackType.nailed:
        add('Pointes / agrafes 3 x 20 mm', 'fond cloué tous les 150 mm', ((2 * (w + h)) / 150).ceil());
      case BackType.screwed:
        add('Vis aggloméré Ø4 x 40 mm', 'fond vissé 18 mm (tous les 250 mm)', ((2 * (w + h)) / 250).ceil());
      case BackType.none:
        break;
    }
    // tablettes mobiles : 4 taquets, perçage en ligne 32 mm
    var mobile = 0;
    for (var c = 0; c < columns; c++) {
      mobile += shelvesOf(c).where((s) => !s.fixed).length;
    }
    add('Taquets d’étagère Ø5 mm', '4 par étagère mobile (perçage en ligne au pas de 32 mm)', mobile * 4);
    // façades
    var fronts = 0;
    var golaLen = 0.0;
    for (final z in zones) {
      final cv = coverOf(z);
      final fw = z.fx1 - z.fx0, fh = z.fy1 - z.fy0;
      switch (cv.type) {
        case CoverType.door:
          final two = cv.hinge == 'double' || (cv.hinge != 'left' && cv.hinge != 'right' && fw > 600);
          final doors = two ? 2 : 1;
          final hn = hingesFor(fh);
          add('Charnière 110° frein intégré Ø35 + embase', 'portes ($hn par porte selon la hauteur)', doors * hn);
          add('Vis aggloméré Ø3,5 x 16 mm', 'charnières et embases (6 par charnière)', doors * hn * 6);
          fronts += doors;
          golaLen += fw;
        case CoverType.flap:
          add('Compas d’abattant freiné (paire)', 'abattant relevable', 1);
          add('Charnière 110° frein intégré Ø35 + embase', 'abattant', 2);
          add('Vis aggloméré Ø3,5 x 16 mm', 'compas et charnières', 20);
          fronts++;
          golaLen += fw;
        case CoverType.drawers:
          final cnt = math.max(1, cv.count);
          if (drawerBox == DrawerBox.metal) {
            add('Tiroir double paroi métal $slideLength mm (côtés + coulisses sous-montées frein)', 'un par tiroir', cnt);
          } else {
            add('Paire de coulisses à billes $slideLength mm sortie totale', 'tiroirs bois (une paire par tiroir)', cnt);
            add('Vis aggloméré Ø4 x 30 mm', 'assemblage des caissons de tiroir (8 par tiroir)', cnt * 8);
          }
          add('Vis aggloméré Ø3,5 x 16 mm', 'coulisses et fixation des façades (12 par tiroir)', cnt * 12);
          add('Réglage de façade de tiroir (excentrique)', '2 par tiroir', cnt * 2);
          fronts += cnt;
          golaLen += fw * cnt;
        case CoverType.open:
          break;
      }
      for (final a in cv.accessories) {
        switch (a) {
          case 'rod':
            add('Tringle de penderie ovale (coupée à ${z.width.round()} mm)', 'zone ${z.id}', 1);
            add('Supports de tringle (paire)', 'zone ${z.id}', 1);
          case 'spice':
            add('Range-épices coulissant (largeur ${z.width.round()})', 'zone ${z.id}', 1);
          case 'shoes':
            add('Range-chaussures coulissant', 'zone ${z.id}', 1);
          case 'basket':
            add('Panier fil coulissant + coulisses', 'zone ${z.id}', 1);
          case 'led':
            add('Profilé LED + ruban 24 V (${(z.width / 1000).toStringAsFixed(1)} m)', 'zone ${z.id}', 1);
        }
      }
    }
    switch (handle) {
      case 'gola':
        add('Profil Gola horizontal (m)', 'façades sans poignée ; fraisage / entaille du caisson nécessaire', (golaLen / 1000).ceil());
        add('Embouts et équerres Gola', 'extrémités du profil', 2);
      case 'push':
        add('Poussoir d’ouverture (tip-on)', 'une par façade', fronts);
      case 'knob':
        add('Bouton (vis M4 x 25 mm)', 'une par façade', fronts);
      default:
        add('Poignée barre (vis M4 x 25 mm)', 'une par façade', fronts);
    }
    // base et fixation
    switch (base) {
      case BaseType.legs:
        final legs = w <= 600 ? 4 : (w <= 1000 ? 4 : 6);
        add('Pied réglable ${(baseH - 20).round()}-${(baseH + 20).round()} mm', 'sous le dessous', legs);
        add('Clip de plinthe', 'fixation de la plinthe', 2 + (w > 1000 ? 1 : 0));
        add('Vis aggloméré Ø3,5 x 16 mm', 'pieds (4 par pied)', legs * 4);
      case BaseType.socle:
        add('Équerre de socle 30 x 30', 'socle sous le caisson', 4);
        add('Vis aggloméré Ø4 x 30 mm', 'socle', 16);
      case BaseType.wall:
        add('Suspente réglable de meuble haut (paire)', 'meuble suspendu', 1);
        add('Rail de suspension (coupé à ${w.round()} mm)', 'fixé au mur', 1);
        add('Chevilles Ø8 + vis Ø6 x 60 mm', 'rail de suspension', math.max(3, (w / 300).ceil()));
      case BaseType.none:
        break;
    }
    if (y0 + h >= 1500 && base != BaseType.wall) add('Équerre anti-basculement + cheville Ø6', 'meuble haut fixé au mur', 2);
    if (cheekLeft || cheekRight) add('Vis aggloméré Ø4 x 30 mm (par l’intérieur)', 'joues de finition (6 par joue)', 6 * ((cheekLeft ? 1 : 0) + (cheekRight ? 1 : 0)));
    if (fillerLeft > 0 || fillerRight > 0) add('Tasseau 18 x 40 + vis Ø4 x 30 mm', 'fileurs', (fillerLeft > 0 ? 1 : 0) + (fillerRight > 0 ? 1 : 0));
    return [for (final e in out.entries) (e.key, e.value.$1, e.value.$2.ceil())];
  }

  // ---------------------------------------------------------------- contrôles
  List<String> warnings() {
    final out = <String>[];
    var hidden = 0;
    for (final e in shelves.entries) {
      hidden += e.value.length - shelvesOf(e.key).length;
    }
    if (hidden > 0) out.add('$hidden étagère(s) hors de la hauteur intérieure : ignorée(s)');
    for (final (a, b) in columnSpans) {
      if (b - a < 100) out.add('Colonne trop étroite (${(b - a).round()} mm)');
      if (b - a > 1000) out.add('Colonne de ${(b - a).round()} mm : les étagères fléchissent au-delà de 900 mm, ajoutez une séparation');
    }
    for (final z in zones) {
      final cv = coverOf(z);
      final fw = z.fx1 - z.fx0, fh = z.fy1 - z.fy0;
      if (cv.type == CoverType.door && (cv.hinge == 'left' || cv.hinge == 'right') && fw > 600) out.add('Porte de ${fw.round()} mm : au-delà de 600, prévoir deux portes');
      if (cv.type == CoverType.drawers && fh / math.max(1, cv.count) < 90) out.add('Tiroirs trop bas dans la zone ${z.id}');
      if (cv.type == CoverType.drawers && innerDepth < 280) out.add('Profondeur trop faible pour des tiroirs');
      if (z.height < 60) out.add('Zone ${z.id} trop basse (${z.height.round()} mm)');
    }
    if (h > 2500) out.add('Hauteur > 2500 mm : au-delà d’une feuille standard (2800) avec les chutes, vérifier le débit');
    return out;
  }

  // ---------------------------------------------------------------- sauvegarde
  Map<String, dynamic> toJson() => {
        'name': name,
        'w': w, 'h': h, 'd': d, 't': t, 't_back': tBack, 't_front': tFront,
        'top': top.name, 'stretcher': stretcher,
        'back': back.name, 'back_recess': backRecess, 'groove': groove,
        'seps': seps,
        'shelves': {for (final e in shelves.entries) '${e.key}': [for (final s in e.value) s.toJson()]},
        'covers': {for (final e in covers.entries) e.key: e.value.toJson()},
        'gap': gap, 'drawer_box': drawerBox.name,
        'base': base.name, 'base_h': baseH,
        'cheek_left': cheekLeft, 'cheek_right': cheekRight,
        'filler_left': fillerLeft, 'filler_right': fillerRight,
        'cornice': cornice, 'valance': valance,
        'handle': handle, 'carcass': carcass, 'front': front,
      };

  factory ArtBox.fromJson(Map<String, dynamic> j) {
    double n(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    T en<T extends Enum>(List<T> vs, String k, T def) => vs.firstWhere((v) => v.name == j[k], orElse: () => def);
    return ArtBox(
      name: j['name'] as String? ?? 'Caisson',
      w: n('w', 800), h: n('h', 720), d: n('d', 560), t: n('t', 18), tBack: n('t_back', 6), tFront: n('t_front', 18),
      top: en(TopType.values, 'top', TopType.panel), stretcher: n('stretcher', 100),
      back: en(BackType.values, 'back', BackType.groove), backRecess: n('back_recess', 16), groove: n('groove', 9),
      seps: [for (final s in (j['seps'] as List? ?? const [])) (s as num).toDouble()],
      shelves: {
        for (final e in ((j['shelves'] as Map?) ?? const {}).entries)
          int.parse('${e.key}'): [for (final s in e.value as List) ArtShelf.fromJson((s as Map).cast<String, dynamic>())],
      },
      covers: {for (final e in ((j['covers'] as Map?) ?? const {}).entries) '${e.key}': ArtCover.fromJson((e.value as Map).cast<String, dynamic>())},
      gap: n('gap', 2), drawerBox: en(DrawerBox.values, 'drawer_box', DrawerBox.metal),
      base: en(BaseType.values, 'base', BaseType.legs), baseH: n('base_h', 100),
      cheekLeft: j['cheek_left'] == true, cheekRight: j['cheek_right'] == true,
      fillerLeft: n('filler_left', 0), fillerRight: n('filler_right', 0),
      cornice: j['cornice'] == true, valance: j['valance'] == true,
      handle: j['handle'] as String? ?? 'bar', carcass: j['carcass'] as String? ?? 'blanc', front: j['front'] as String? ?? 'blanc_mat',
    );
  }

  /// Lecture du format « universal_parametric_box » (JSON de description d'un caisson).
  factory ArtBox.fromUniversal(Map<String, dynamic> j, {double w = 1200, double h = 2000, double d = 560}) {
    final env = (j['structure_envelope'] as Map?)?.cast<String, dynamic>() ?? const {};
    final topJ = (env['top'] as Map?)?.cast<String, dynamic>() ?? const {};
    final backJ = (env['back'] as Map?)?.cast<String, dynamic>() ?? const {};
    final b = ArtBox(name: '${j['model'] ?? 'Caisson'}', w: w, h: h, d: d);
    if ('${topJ['type']}'.contains('stretcher') && h < 1000) b.top = TopType.stretchers;
    b.stretcher = (topJ['stretcher_width'] as num?)?.toDouble() ?? 100;
    if (backJ['active'] == false) {
      b.back = BackType.none;
    } else if ('${backJ['assembly_type']}'.contains('groove')) {
      b.back = BackType.groove;
      b.backRecess = (backJ['recess_mm'] as num?)?.toDouble() ?? 16;
      b.groove = (backJ['groove_depth_mm'] as num?)?.toDouble() ?? 9;
    }
    final grid = (j['internal_grid_subdivision'] as Map?)?.cast<String, dynamic>() ?? const {};
    final horiz = <ArtShelf>[];
    for (final dv in (grid['divisions'] as List? ?? const [])) {
      final m = (dv as Map).cast<String, dynamic>();
      for (final pRaw in (m['partitions'] as List? ?? const [])) {
        final p = (pRaw as Map).cast<String, dynamic>();
        if (m['axis'] == 'vertical' && p['position_X_from_left'] is num) b.seps.add((p['position_X_from_left'] as num).toDouble());
        if (m['axis'] == 'horizontal' && p['position_Y_from_bottom'] is num) {
          horiz.add(ArtShelf((p['position_Y_from_bottom'] as num).toDouble(), fixed: p['type'] == 'fixed'));
        }
      }
    }
    for (var c = 0; c < b.columns; c++) {
      b.shelves[c] = [for (final s in horiz) ArtShelf(s.y, fixed: s.fixed)];
    }
    // façades : zone_1, zone_2… dans l'ordre des zones (colonne par colonne, de bas en haut)
    final zs = b.zones;
    final fl = (j['front_layout_zones'] as Map?)?.cast<String, dynamic>() ?? const {};
    var k = 0;
    for (final zRaw in (fl['zones'] as List? ?? const [])) {
      if (k >= zs.length) break;
      final z = (zRaw as Map).cast<String, dynamic>();
      final type = switch ('${z['cover_type']}') { 'door' => CoverType.door, 'drawer_stack' => CoverType.drawers, 'flap' => CoverType.flap, _ => CoverType.open };
      final mech = '${z['opening_mechanism'] ?? ''}';
      b.covers[zs[k].id] = ArtCover(type: type, hinge: mech.contains('right') ? 'right' : 'left', count: (z['count'] as num?)?.toInt() ?? 3);
      final g = (z['clearance_gaps'] as Map?)?['top'];
      if (g is num) b.gap = g.toDouble();
      if ('${z['drawer_box_type']}'.contains('metal')) b.drawerBox = DrawerBox.metal;
      k++;
    }
    final ext = (j['external_additions'] as Map?)?.cast<String, dynamic>() ?? const {};
    final bs = (ext['base_support'] as Map?)?.cast<String, dynamic>() ?? const {};
    if ('${bs['type']}'.contains('legs')) b.base = BaseType.legs;
    if (bs['height_mm'] is num) b.baseH = (bs['height_mm'] as num).toDouble();
    final ch = (ext['cover_panels_cheeks'] as Map?)?.cast<String, dynamic>() ?? const {};
    b.cheekLeft = ch['left_active'] == true;
    b.cheekRight = ch['right_active'] == true;
    final fi = (ext['fillers'] as Map?)?.cast<String, dynamic>() ?? const {};
    b.fillerLeft = (fi['left_width_mm'] as num?)?.toDouble() ?? 0;
    b.fillerRight = (fi['right_width_mm'] as num?)?.toDouble() ?? 0;
    final co = (ext['cornice_or_pelmet'] as Map?)?.cast<String, dynamic>() ?? const {};
    b.cornice = co['top_cornice_active'] == true;
    b.valance = co['bottom_light_valance_active'] == true;
    final hw = (j['hardware_and_accessories'] as Map?)?.cast<String, dynamic>() ?? const {};
    if ('${(hw['handles'] as Map?)?['type']}'.contains('gola')) b.handle = 'gola';
    for (final aRaw in (hw['internal_accessories'] as List? ?? const [])) {
      final a = (aRaw as Map).cast<String, dynamic>();
      final idx = int.tryParse('${a['target_niche']}'.replaceAll(RegExp(r'\D'), ''));
      if (idx == null || idx < 1 || idx > zs.length) continue;
      final cv = b.covers.putIfAbsent(zs[idx - 1].id, () => ArtCover(type: CoverType.open));
      final id = switch ('${a['id']}') { 'hanging_rod' => 'rod', 'pullout_spice_rack' => 'spice', final x => x };
      cv.accessories.add(id);
    }
    return b;
  }

  ArtBox copy() => ArtBox.fromJson(toJson());
}

/// Modèles de départ : caissons types, chacun la même base réglée autrement.
class ArtPreset {
  final String name, description;
  final ArtBox Function() build;
  const ArtPreset(this.name, this.description, this.build);
}

final artPresets = <ArtPreset>[
  ArtPreset('Caisson bas de cuisine', '600 x 720 x 560, traverses, pieds 100 + plinthe, une porte, une tablette mobile.', () {
    return ArtBox(name: 'Bas 600', w: 600, h: 720, d: 560, top: TopType.stretchers, shelves: {
      0: [ArtShelf(330)],
    }, covers: {
      'c0z0': ArtCover(type: CoverType.door, hinge: 'left'),
    });
  }),
  ArtPreset('Bas à tiroirs', '800 x 720 x 560, trois tiroirs double paroi, profil Gola.', () {
    return ArtBox(name: 'Bas tiroirs 800', w: 800, h: 720, d: 560, top: TopType.stretchers, handle: 'gola', covers: {
      'c0z0': ArtCover(type: CoverType.drawers, count: 3),
    });
  }),
  ArtPreset('Caisson haut', '800 x 720 x 350, suspendu, deux portes, deux tablettes mobiles.', () {
    return ArtBox(name: 'Haut 800', w: 800, h: 720, d: 350, base: BaseType.wall, baseH: 1450, shelves: {
      0: [ArtShelf(220), ArtShelf(450)],
    }, covers: {
      'c0z0': ArtCover(type: CoverType.door, hinge: 'double'),
    });
  }),
  ArtPreset('Colonne de dressing', '1000 x 2200 x 580 : penderie à gauche, tablettes et tiroirs à droite.', () {
    return ArtBox(name: 'Dressing 1000', w: 1000, h: 2200, d: 580, t: 18, base: BaseType.socle, baseH: 80, seps: [500], shelves: {
      0: [ArtShelf(1800, fixed: true)],
      1: [ArtShelf(700, fixed: true), ArtShelf(1100), ArtShelf(1450), ArtShelf(1800)],
    }, covers: {
      'c0z0': ArtCover(type: CoverType.door, hinge: 'left', accessories: ['rod']),
      'c0z1': ArtCover(type: CoverType.door, hinge: 'left'),
      'c1z0': ArtCover(type: CoverType.drawers, count: 3),
      'c1z1': ArtCover(type: CoverType.door, hinge: 'right'),
    });
  }),
  ArtPreset('Bibliothèque', '1200 x 2000 x 350, trois colonnes, niches ouvertes, bas à portes.', () {
    return ArtBox(name: 'Bibliothèque', w: 1200, h: 2000, d: 350, base: BaseType.socle, baseH: 60, seps: [391, 791], shelves: {
      for (var c = 0; c < 3; c++) c: [ArtShelf(700, fixed: true), ArtShelf(1050), ArtShelf(1400)],
    }, covers: {
      for (var c = 0; c < 3; c++) 'c${c}z0': ArtCover(type: CoverType.door, hinge: c == 0 ? 'left' : 'right'),
    });
  }),
  ArtPreset('Meuble TV', '1800 x 450 x 450, suspendu, deux abattants et une niche centrale.', () {
    return ArtBox(name: 'Meuble TV', w: 1800, h: 450, d: 450, base: BaseType.wall, baseH: 250, handle: 'push', seps: [600, 1182], covers: {
      'c0z0': ArtCover(type: CoverType.flap),
      'c2z0': ArtCover(type: CoverType.flap),
    });
  }),
  ArtPreset('Commode', '1000 x 850 x 480, quatre tiroirs bois, socle.', () {
    return ArtBox(name: 'Commode', w: 1000, h: 850, d: 480, base: BaseType.socle, baseH: 80, drawerBox: DrawerBox.wood, handle: 'knob', covers: {
      'c0z0': ArtCover(type: CoverType.drawers, count: 4),
    });
  }),
  ArtPreset('Buffet', '1600 x 800 x 450, quatre portes et deux tiroirs en haut.', () {
    return ArtBox(name: 'Buffet', w: 1600, h: 800, d: 450, base: BaseType.legs, baseH: 150, seps: [791], shelves: {
      0: [ArtShelf(550, fixed: true), ArtShelf(270)],
      1: [ArtShelf(550, fixed: true), ArtShelf(270)],
    }, covers: {
      'c0z0': ArtCover(type: CoverType.door, hinge: 'double'),
      'c1z0': ArtCover(type: CoverType.door, hinge: 'double'),
      'c0z1': ArtCover(type: CoverType.drawers, count: 1),
      'c1z1': ArtCover(type: CoverType.drawers, count: 1),
    });
  }),
  ArtPreset('Colonne Buanderie', '700 x 2100 x 650, niche lave-linge / sèche-linge, tablette coulissante et placard haut.', () {
    return ArtBox(name: 'Colonne Buanderie 700', w: 700, h: 2100, d: 650, base: BaseType.legs, baseH: 100, shelves: {
      0: [ArtShelf(880, fixed: true), ArtShelf(1760, fixed: true)],
    }, covers: {
      'c0z2': ArtCover(type: CoverType.door, hinge: 'double'),
    });
  }),
  ArtPreset('Meuble Sous-Bac Buanderie', '800 x 860 x 600, deux portes battantes pour bac à laver profond.', () {
    return ArtBox(name: 'Sous-Bac 800', w: 800, h: 860, d: 600, top: TopType.stretchers, base: BaseType.legs, baseH: 100, handle: 'bar', covers: {
      'c0z0': ArtCover(type: CoverType.door, hinge: 'double'),
    });
  }),
];
