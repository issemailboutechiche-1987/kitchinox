/// Meubles d'angle : formats normalisés à 4 paramètres (W1 / W2 / H / D) et formules de débit
/// (angle en L à 90°, angle à pan coupé 45°, angle droit borgne), d'après
/// assets/data/corner_cabinets.json et assets/data/corner_cut_rules.json.
library;

import 'dart:math' as math;

import 'catalog.dart';
import 'project.dart';

/// Un format d'angle : W1 le long du mur, W2 sur le retour (L, pan coupé) ;
/// pour un angle borgne, W1 = encombrement mural (caisson + fileur) et [carcass] la longueur du caisson.
class CornerSize {
  final int w1, w2;
  final int? carcass, filler;
  const CornerSize(this.w1, this.w2, {this.carcass, this.filler});
  String get code => '$w1/$w2';
}

/// Formats proposés pour chaque modèle d'angle du catalogue.
const cornerSizes = <String, List<CornerSize>>{
  'corner_base_l_shaped': [CornerSize(880, 880), CornerSize(900, 900), CornerSize(800, 900), CornerSize(900, 1050)],
  'corner_base_diagonal': [CornerSize(900, 900), CornerSize(1050, 1050)],
  'corner_base_blind': [
    CornerSize(1050, 650, carcass: 1000, filler: 50),
    CornerSize(1100, 650, carcass: 1050, filler: 50),
    CornerSize(1250, 650, carcass: 1200, filler: 50),
  ],
  'corner_tall_l_shaped': [CornerSize(900, 900), CornerSize(1000, 1000)],
  'corner_tall_blind': [
    CornerSize(1050, 650, carcass: 1000, filler: 50),
    CornerSize(1250, 650, carcass: 1200, filler: 50),
  ],
  'corner_wall_l_shaped': [CornerSize(600, 600), CornerSize(680, 680)],
  'corner_wall_diagonal': [CornerSize(600, 600), CornerSize(680, 680)],
  'corner_wall_blind': [
    CornerSize(700, 400, carcass: 680, filler: 30),
    CornerSize(800, 400, carcass: 780, filler: 30),
    CornerSize(1000, 400, carcass: 980, filler: 30),
  ],
};

/// Règles communes (corner_cut_rules.json).
class CornerRules {
  static const golaDeduction = 35; // hauteur de porte en moins avec un profil Gola
  static const masterClearance = 7; // porte maître (fixée au montant)
  static const slaveClearance = 25; // porte esclave (porte la poignée)
  static const doorBumper = 2; // tampon de porte
  static const diagonalDoorClearance = 6;
}

/// Pièce d'angle : (matériau « caisson » | « façade » | « fond »), nom, longueur, largeur, quantité, chants long / court.
typedef CornerPart = (String, String, int, int, int, int, int);

/// Liste de débit d'un meuble d'angle. [T] épaisseur caisson, [td] épaisseur porte, [gap] jeu vertical des portes.
List<CornerPart> cornerCutList(CabinetModel m, PlacedCabinet c, {required int T, required int td, required int gap, required bool gola}) {
  final low = m.kind == CabinetKind.cornerBase || m.kind == CabinetKind.cornerTall;
  final H = c.height;
  final D = c.depth - td - CornerRules.doorBumper; // profondeur du caisson nu : 580 en bas, 350 en haut
  final hd = gola ? H - CornerRules.golaDeduction : H - gap; // hauteur des portes
  final out = <CornerPart>[];
  void add(String mat, String name, int a, int b, int q, {int el = 0, int es = 0}) {
    if (a > 0 && b > 0 && q > 0) out.add((mat, name, a, b, q, el, es));
  }

  switch (m.shape) {
    case CabinetShape.lShape:
      final w1 = c.width, w2 = c.widthRight ?? c.width;
      add('caisson', 'Côté (flanc)', H, D, 2, el: 2, es: 2);
      add('caisson', 'Dos porteur mur 1', H, w1 - T, 1);
      add('caisson', 'Dos porteur mur 2', H, w2 - 2 * T, 1);
      add('caisson', low ? 'Fond en L (découpe CNC)' : 'Fond et dessus en L (découpe CNC)', w1 - 2 * T, w2 - 2 * T, low ? 1 : 2, el: 1);
      if (low) add('caisson', 'Traverse haute', w1 - 2 * T, 100, 2, el: 1);
      add('caisson', 'Étagère en L (découpe CNC)', w1 - 2 * T - 2, w2 - 2 * T - 2, 1, el: 1);
      add('facade', 'Porte maître (pliante)', hd, (w1 - D) - td - CornerRules.masterClearance, 1, el: 2, es: 2);
      add('facade', 'Porte esclave (pliante, poignée)', hd, (w2 - D) - td - CornerRules.slaveClearance, 1, el: 2, es: 2);
    case CabinetShape.diagonal:
      final w1 = c.width, w2 = c.widthRight ?? c.width;
      add('caisson', 'Côté (flanc)', H, D, 2, el: 2, es: 2);
      add('caisson', 'Dos mur 1', H, w1 - T, 1);
      add('caisson', 'Dos mur 2', H, w2 - 2 * T, 1);
      add('caisson', 'Fond et dessus à pan coupé 45°', w1 - 2 * T, w2 - 2 * T, 2, el: 1);
      add('caisson', 'Étagère à pan coupé', w1 - 2 * T - 20, w2 - 2 * T - 20, 1, el: 1);
      // ouverture diagonale : entre les deux façades voisines (profondeur porte comprise)
      final diag = math.sqrt(math.pow(w1 - c.depth, 2) + math.pow(w2 - c.depth, 2));
      add('facade', 'Porte oblique 45° (chants biseautés)', hd, (diag - CornerRules.diagonalDoorClearance).round(), 1, el: 2, es: 2);
    default:
      // angle droit borgne : caisson droit, panneau fixe sous le retour, porte d'accès, fileur d'angle
      final std = (cornerSizes[m.id] ?? const []).where((s) => s.carcass == c.width).firstOrNull;
      final cw = c.width;
      final filler = std?.filler ?? (low ? 50 : 30);
      final fp = cw + filler; // encombrement mural
      add('caisson', 'Côté', H, D, 2, el: 2, es: 2);
      if (low) {
        add('caisson', 'Dessous', cw - 2 * T, D, 1, el: 1);
        add('caisson', 'Traverse haute', cw - 2 * T, 100, 2, el: 1);
      } else {
        add('caisson', 'Dessus / dessous', cw - 2 * T, D, 2, el: 1);
      }
      add('caisson', 'Montant central (charnières)', H - 2 * T, 100, 1, el: 1);
      final blind = (D + td) - (fp - cw) + filler;
      add('caisson', 'Panneau fixe d’angle mort', H - 4, blind, 1, el: 2, es: 2);
      add('facade', 'Fileur d’angle à 90°', hd, filler + td, 2, el: 2, es: 2);
      add('fond', 'Fond arrière 6 mm', H - T + 9, cw - 2 * T + 18, 1);
      add('facade', 'Porte d’accès', hd, cw - blind - 4, 1, el: 2, es: 2);
  }
  return out;
}

/// Largeur de la partie accessible (porte) d'un angle borgne, depuis le côté ouvert.
double blindDoorWidth(CabinetModel m, PlacedCabinet c, {int td = 18}) {
  final std = (cornerSizes[m.id] ?? const []).where((s) => s.carcass == c.width).firstOrNull;
  final low = m.kind == CabinetKind.cornerBase || m.kind == CabinetKind.cornerTall;
  final filler = std?.filler ?? (low ? 50 : 30);
  final D = c.depth - td - CornerRules.doorBumper;
  final blind = (D + td) - filler + filler;
  return (c.width - blind - 4).toDouble();
}
