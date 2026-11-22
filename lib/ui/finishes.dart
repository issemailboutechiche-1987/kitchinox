// Finitions proposées à l'étape « Style » (façades, plans de travail, poignées, caissons),
// avec leur texture réelle quand il y en a une, plus les textures importées par l'utilisateur.

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'textures.dart';

class Finish {
  final String id;
  final String name;
  final Color color; // teinte moyenne (plans, vignettes, vues sans texture)
  final Color? grain; // veinage dessiné sur la vignette quand la texture n'est pas prête
  final String? tex; // clé de la texture (TextureBank)
  final double tile; // largeur réelle d'un motif (mm)
  final bool gloss; // laqué brillant : reflets plus marqués
  const Finish(this.id, this.name, this.color, {this.grain, this.tex, this.tile = 800, this.gloss = false});

  bool get textured => tex != null && TextureBank.instance[tex!] != null;

  /// Peinture en coordonnées mm (fil vertical pour les portes).
  Paint paint({bool vertical = false, Offset origin = Offset.zero}) => texturePaint(tex, color, tile, vertical: vertical, origin: origin);
}

const fronts = [
  Finish('blanc_mat', 'Blanc mat', Color(0xFFF4F3EF)),
  Finish('blanc_brillant', 'Blanc brillant', Color(0xFFFAFAF8), gloss: true),
  Finish('cachemire', 'Cachemire', Color(0xFFE3D9CB)),
  Finish('gris_galet', 'Gris galet', Color(0xFFBDB9B0)),
  Finish('vert_sauge', 'Vert sauge', Color(0xFF9DAE8B)),
  Finish('vert_foret', 'Vert forêt', Color(0xFF3E5446)),
  Finish('terracotta', 'Terracotta', Color(0xFFC07A5A)),
  Finish('bleu_nuit', 'Bleu nuit', Color(0xFF2F3B57)),
  Finish('bleu_petrole', 'Bleu pétrole', Color(0xFF3F5F75)),
  Finish('bleu_brume', 'Bleu brume', Color(0xFF9DB7C4)),
  Finish('vert_deau', 'Vert d’eau', Color(0xFFABBFB9)),
  Finish('vert_jade', 'Vert jade', Color(0xFF6E9385)),
  Finish('vert_olive_facade', 'Vert olive', Color(0xFF7C8062)),
  Finish('sable', 'Sable', Color(0xFFD8CBB8)),
  Finish('champignon', 'Champignon', Color(0xFFA89B8C)),
  Finish('ocre', 'Ocre', Color(0xFFC79A4B)),
  Finish('argile', 'Argile', Color(0xFFB0705A)),
  Finish('prune', 'Prune', Color(0xFF5B3A46)),
  Finish('anthracite', 'Anthracite', Color(0xFF3B3E42)),
  Finish('noir_mat', 'Noir mat', Color(0xFF232325)),
  Finish('chene', 'Chêne naturel', Color(0xFFCDA77D), grain: Color(0xFFB8905F), tex: 'wood_oak', tile: 900),
  Finish('chene_clair', 'Chêne clair', Color(0xFFE2C9A4), grain: Color(0xFFC9AC82), tex: 'wood_light', tile: 900),
  Finish('chene_fume', 'Chêne fumé', Color(0xFF8B7663), grain: Color(0xFF6E5B4B), tex: 'wood_smoked', tile: 900),
  Finish('noyer', 'Noyer', Color(0xFF7B5539), grain: Color(0xFF66452C), tex: 'wood_walnut', tile: 900),
  Finish('beton_facade', 'Effet béton', Color(0xFF9FA09C), grain: Color(0xFF8C8D89), tex: 'concrete', tile: 1200),
  Finish('inox_facade', 'Inox brossé', Color(0xFFC6CACE), grain: Color(0xFFB4B8BC), tex: 'steel', tile: 600, gloss: true),
];

/// Plans de travail : les coloris de chaque matière du tarif (voir worktop_looks.dart).
const worktops = [
  Finish('quartz_blanc', 'Quartz blanc', Color(0xFFEDEBE5), grain: Color(0xFFDAD7CF), tex: 'quartz_white', tile: 700),
  Finish('quartz_gris', 'Quartz gris perle', Color(0xFFC9C8C3), grain: Color(0xFFB2B0AA), tex: 'quartz_grey', tile: 700),
  Finish('silestone_veine', 'Quartz veiné (type Silestone)', Color(0xFFEFECE7), grain: Color(0xFFBFB8AE), tex: 'marble_white', tile: 1800),
  Finish('terrazzo', 'Quartz effet terrazzo', Color(0xFFE5DED3), grain: Color(0xFFC9A28A), tex: 'terrazzo', tile: 800),
  Finish('quartz_anthracite', 'Quartz anthracite', Color(0xFF4A4C4F), grain: Color(0xFF63666A), tex: 'quartz_dark', tile: 700),
  Finish('quartz_beige', 'Quartz beige Sahara', Color(0xFFDCCFB9), grain: Color(0xFFC3B294), tex: 'quartz_beige', tile: 700),
  Finish('marbre', 'Marbre blanc Carrare', Color(0xFFE8E4DE), grain: Color(0xFFBFB8AE), tex: 'marble_white', tile: 1400),
  Finish('marbre_calacatta', 'Marbre Calacatta doré', Color(0xFFF1ECE2), grain: Color(0xFFB58A4C), tex: 'marble_gold', tile: 1600),
  Finish('marbre_creme', 'Marbre Crema Marfil', Color(0xFFE6D8C0), grain: Color(0xFFC4AA84), tex: 'marble_cream', tile: 1400),
  Finish('marbre_emperador', 'Marbre Emperador brun', Color(0xFF4F3B30), grain: Color(0xFFC9B49A), tex: 'marble_brown', tile: 1400),
  Finish('marbre_noir', 'Marbre noir Marquina', Color(0xFF2B2B2E), grain: Color(0xFF8E8D8A), tex: 'marble_black', tile: 1400),
  Finish('marbre_vert', 'Marbre vert', Color(0xFF2F4A3F), grain: Color(0xFF9FB3A5), tex: 'marble_green', tile: 1400),
  Finish('granit_rose', 'Granit rose Porrino', Color(0xFFC3A08F), grain: Color(0xFF8E6B5C), tex: 'granite_pink', tile: 500),
  Finish('granit_zimbabwe', 'Granit noir Zimbabwe', Color(0xFF1E1F21), grain: Color(0xFF38393C), tex: 'granite_black', tile: 380),
  Finish('granit_labrador', 'Granit Labrador bleu', Color(0xFF34404C), grain: Color(0xFF7FA3C2), tex: 'granite_blue', tile: 500),
  Finish('granit_cuir', 'Granit tranche cuir', Color(0xFF4A443D), grain: Color(0xFF6E6457), tex: 'granite_leather', tile: 600),
  Finish('granit_noir', 'Granit noir absolu', Color(0xFF2A2B2D), grain: Color(0xFF3D3E41), tex: 'granite_black', tile: 500),
  Finish('granit_gris', 'Granit gris', Color(0xFF9A9894), grain: Color(0xFF6E6C69), tex: 'granite_grey', tile: 500),
  Finish('beton', 'Céramique effet béton (type Dekton)', Color(0xFF9FA09C), grain: Color(0xFF8C8D89), tex: 'concrete_smooth', tile: 2400),
  Finish('dekton_noir', 'Céramique anthracite (type Dekton)', Color(0xFF3A3B3D), grain: Color(0xFF2C2D2F), tex: 'concrete_dark', tile: 2400),
  Finish('dekton_marbre', 'Céramique effet marbre (type Dekton)', Color(0xFFF0EEEA), grain: Color(0xFFC4BEB4), tex: 'marble_white', tile: 2200),
  Finish('onyx_blanc', 'Onyx blanc', Color(0xFFF1EDE2), grain: Color(0xFFD9CDB2), tex: 'onyx_white', tile: 1200),
  Finish('onyx_miel', 'Onyx miel', Color(0xFFD7A75E), grain: Color(0xFFF3DFB4), tex: 'onyx_honey', tile: 1200),
  Finish('onyx_vert', 'Onyx vert', Color(0xFFA9C29B), grain: Color(0xFFEFF3E2), tex: 'onyx_green', tile: 1200),
  Finish('hpl_noir', 'Compact noir', Color(0xFF2A2A2C)),
  Finish('hpl_blanc', 'Compact blanc', Color(0xFFF2F1ED)),
  Finish('hpl_chene', 'Postformé chêne', Color(0xFFCDA77D), grain: Color(0xFFB8905F), tex: 'wood_oak', tile: 900),
  Finish('hpl_beton', 'Postformé béton', Color(0xFF9FA09C), grain: Color(0xFF8C8D89), tex: 'concrete', tile: 1200),
  Finish('corian_blanc', 'Solid surface blanc (type Corian)', Color(0xFFF5F4F1)),
  Finish('corian_gris', 'Solid surface gris (type Corian)', Color(0xFFBEBDB9)),
];

const carcasses = [
  Finish('blanc', 'Blanc', Color(0xFFF7F7F5)),
  Finish('gris', 'Gris clair', Color(0xFFD5D5D2)),
  Finish('chene', 'Chêne', Color(0xFFCDA77D), tex: 'wood_oak', tile: 900),
  Finish('noir', 'Noir', Color(0xFF2B2B2B)),
];

/// Sols : parquets, carrelages, carreaux de ciment, béton ciré, terrazzo, pierre.
const floors = [
  Finish('parquet_clair', 'Parquet chêne clair', Color(0xFFE2C9A4), tex: 'parquet_light', tile: 2160),
  Finish('parquet_chene', 'Parquet chêne naturel', Color(0xFFC9A273), tex: 'parquet_oak', tile: 2160),
  Finish('parquet_noyer', 'Parquet noyer', Color(0xFF6E4A31), tex: 'parquet_walnut', tile: 2160),
  Finish('parquet_blanchi', 'Parquet chêne blanchi', Color(0xFFEDE3D4), tex: 'parquet_light', tile: 2160),
  Finish('parquet_fume', 'Parquet chêne fumé', Color(0xFF5A4638), tex: 'wood_smoked', tile: 2160),
  Finish('carrelage_blanc', 'Carrelage blanc 60 x 60', Color(0xFFEDECE8), tex: 'tile_white', tile: 1200),
  Finish('carrelage_gris', 'Carrelage gris 60 x 60', Color(0xFF9A9B97), tex: 'tile_grey', tile: 1200),
  Finish('carrelage_anthracite', 'Carrelage ardoise anthracite', Color(0xFF3B3D40), tex: 'concrete_dark', tile: 1200),
  Finish('carrelage_marbre', 'Carrelage marbre Calacatta', Color(0xFFE9E6E0), tex: 'tile_marble', tile: 1200),
  Finish('carrelage_marbre_noir', 'Carrelage marbre noir Marquina', Color(0xFF242426), tex: 'marble_black', tile: 1200),
  Finish('carrelage_travertin', 'Carrelage travertin beige', Color(0xFFDFD7CA), tex: 'tile_marble', tile: 1200),
  Finish('tomettes', 'Tomettes terre cuite', Color(0xFFB8653F), tex: 'tile_terracotta', tile: 800),
  Finish('carreaux_ciment', 'Carreaux de ciment', Color(0xFFD9D2C4), tex: 'cement', tile: 800),
  Finish('beton_cire', 'Béton ciré clair', Color(0xFFA3A39E), tex: 'concrete_smooth', tile: 3000),
  Finish('beton_cire_sombre', 'Béton ciré anthracite', Color(0xFF424447), tex: 'concrete_dark', tile: 3000),
  Finish('terrazzo_sol', 'Terrazzo classique', Color(0xFFE5DED3), tex: 'terrazzo', tile: 1000),
  Finish('terrazzo_blanc', 'Terrazzo blanc éclat', Color(0xFFF0EEE9), tex: 'terrazzo', tile: 1000),
];

/// Murs : peintures intérieures, papier peint, carrelage, briques, béton, zellige.
const walls = [
  Finish('blanc_casse', 'Blanc cassé', Color(0xFFF1EFEA)),
  Finish('blanc_pur', 'Blanc pur éclatant', Color(0xFFF8F9FA)),
  Finish('gris_perle', 'Gris perle', Color(0xFFD9D9D6)),
  Finish('beige_sable', 'Beige sable', Color(0xFFE6D8C3)),
  Finish('greige_moderne', 'Greige contemporain', Color(0xFFD2CBC1)),
  Finish('lin_naturel', 'Lin naturel', Color(0xFFDDD4C5)),
  Finish('vert_sauge_mur', 'Vert sauge', Color(0xFFB7C4AA)),
  Finish('vert_foret', 'Vert forêt', Color(0xFF2C4A3E)),
  Finish('vert_olive', 'Vert olive', Color(0xFF556B47)),
  Finish('bleu_ciel', 'Bleu ciel', Color(0xFFC9DCE6)),
  Finish('bleu_canard', 'Bleu canard', Color(0xFF144D58)),
  Finish('bleu_nuit', 'Bleu nuit profond', Color(0xFF1B2838)),
  Finish('terracotta_mur', 'Terracotta toscane', Color(0xFFD49A7C)),
  Finish('argile_rose', 'Terre d\'argile', Color(0xFFC48674)),
  Finish('rose_poudre', 'Rose poudré', Color(0xFFE8CBC4)),
  Finish('ocre_soleil', 'Ocre chaleureux', Color(0xFFD4973B)),
  Finish('anthracite_mur', 'Gris anthracite', Color(0xFF383C40)),
  Finish('brique', 'Brique rouge loft', Color(0xFFA5533A), tex: 'brick', tile: 900),
  Finish('brique_blanche', 'Brique blanche peinte', Color(0xFFEAE7E1), tex: 'subway', tile: 900),
  Finish('beton_mur', 'Béton ciré mural', Color(0xFF9FA09C), tex: 'concrete', tile: 2000),
  Finish('carrelage_faience', 'Faïence blanche brillante', Color(0xFFF5F6F8), tex: 'subway', tile: 600),
  Finish('carrelage_marbre_mur', 'Carrelage Marbre mural', Color(0xFFEBE8E3), tex: 'marble_white', tile: 1200),
  Finish('marbre_noir_mural', 'Marbre noir Marquina', Color(0xFF242426), tex: 'marble_black', tile: 1200),
  Finish('zellige_mural', 'Zellige vert émeraude', Color(0xFF2E6B57), tex: 'zellige_green', tile: 500),
  Finish('zellige_blanc_mural', 'Zellige blanc nacré', Color(0xFFF2EFE6), tex: 'zellige_white', tile: 500),
  Finish('zellige_bleu_mural', 'Zellige bleu indigo', Color(0xFF2E5E86), tex: 'zellige_blue', tile: 500),
];

/// Crédences : carreaux métro, zellige, carreaux de ciment, marbre, inox, brique.
const splashes = [
  Finish('metro_blanc', 'Carreaux métro blancs', Color(0xFFF7F7F4), tex: 'subway', tile: 600),
  Finish('metro_vert', 'Carreaux métro verts', Color(0xFF5E8A74), tex: 'subway_green', tile: 600),
  Finish('zellige_vert', 'Zellige vert', Color(0xFF2E6B57), tex: 'zellige_green', tile: 500),
  Finish('zellige_blanc', 'Zellige blanc', Color(0xFFF2EFE6), tex: 'zellige_white', tile: 500),
  Finish('zellige_bleu', 'Zellige bleu', Color(0xFF2E5E86), tex: 'zellige_blue', tile: 500),
  Finish('carreaux_ciment_cred', 'Carreaux de ciment', Color(0xFFD9D2C4), tex: 'cement', tile: 800),
  Finish('marbre_cred', 'Marbre blanc', Color(0xFFE8E4DE), tex: 'marble_white', tile: 1400),
  Finish('inox_cred', 'Inox brossé', Color(0xFFC9CCCF), tex: 'steel', tile: 600, gloss: true),
  Finish('brique_cred', 'Brique', Color(0xFFA5533A), tex: 'brick', tile: 900),
];

const handles = [
  ('bar', 'Barre inox', Icons.horizontal_rule),
  ('knob', 'Bouton', Icons.circle_outlined),
  ('gola', 'Sans poignée (gorge)', Icons.space_bar),
];

/// Nom de la poignée du style (catalogue détaillé si choisi, sinon type de base) : jamais d'erreur sur un type inconnu.
String handleName(KitchenStyle s, [HandleCatalog? db]) =>
    db?.byId(s.handleId)?.name ??
    handles.where((h) => h.$1 == s.handle).firstOrNull?.$2 ??
    switch (s.handle) { 'xxl' => 'Poignée XXL', 'push' => 'Ouverture pousser-lâcher', final x => 'Poignée $x' };

Finish finishById(List<Finish> list, String id) => list.firstWhere((f) => f.id == id, orElse: () => list.first);

Finish _custom(CustomTexture t) => Finish('tex:${t.id}', t.name, Color(t.color), tex: 'custom:${t.id}', tile: t.tile.toDouble());

/// Façades disponibles : intégrées + textures importées pour les façades.
List<Finish> frontFinishes(KitchenStyle s) => [...fronts, for (final t in s.textures) if (t.forFront) _custom(t)];

/// Plans de travail disponibles : intégrés + textures importées pour le plan.
List<Finish> worktopFinishes(KitchenStyle s) => [...worktops, for (final t in s.textures) if (t.forWorktop) _custom(t)];

List<Finish> floorFinishes(KitchenStyle s) => [...floors, for (final t in s.textures) if (t.forFloor) _custom(t)];
List<Finish> wallFinishes(KitchenStyle s) => [...walls, for (final t in s.textures) if (t.forWall) _custom(t)];
List<Finish> splashFinishes(KitchenStyle s) => [...splashes, for (final t in s.textures) if (t.forWall) _custom(t)];

Finish floorFinish(KitchenStyle s) => finishById(floorFinishes(s), s.floor);
Finish wallFinish(KitchenStyle s) => finishById(wallFinishes(s), s.wall);

/// Crédence : sa finition, sinon celle des murs.
Finish splashFinish(KitchenStyle s) =>
    splashMatchesTop(s)
        ? worktopFinish(s, s.worktop)
        : s.splash == null ? wallFinish(s) : finishById([...splashFinishes(s), ...wallFinishes(s)], s.splash!);

Finish frontFinish(KitchenStyle s, String id) => finishById(frontFinishes(s), id);
Finish worktopFinish(KitchenStyle s, String id) => finishById(worktopFinishes(s), id);

/// Finition de façade d'un caisson posé (la sienne, celle des hauts / bas, ou la générale).
Finish frontOfItem(KitchenStyle s, PlacedCabinet c, CabinetModel m) => frontFinish(s, s.frontOf(c, high: m.kind.isHigh));

/// Branche le débit sur les finitions : une façade décor (bois, pierre, texture importée) est
/// débitée dans son propre panneau ; une façade à fil de bois ne pivote pas sur le panneau.
void installCutHooks() {
  frontDecorOf = (id) {
    if (id.startsWith('tex:')) return 'Panneau décor (texture importée)';
    final f = fronts.where((x) => x.id == id).firstOrNull;
    return f?.tex == null ? null : 'MDF plaqué ${f!.name.toLowerCase()}';
  };
  // fil du bois, veinage du marbre ou décor imprimé : la pièce garde son sens ; couleur unie : rotation libre
  frontGrainLocked = (id) => id.startsWith('tex:') || fronts.where((x) => x.id == id).firstOrNull?.tex != null;
  carcassGrainLocked = (id) => carcasses.where((x) => x.id == id).firstOrNull?.tex != null;
}

/// Couleur d'une finition de poignée (d'après son nom).
Color handleFinishColor(String? finish) {
  final f = (finish ?? '').toLowerCase();
  if (f.contains('noir') || f.contains('carbone')) return const Color(0xFF26272A);
  if (f.contains('gunmetal') || f.contains('anthracite') || f.contains('titane')) return const Color(0xFF55585D);
  if (f.contains('or ') || f.startsWith('or') || f.contains('doré') || f.contains('laiton') || f.contains('champagne')) return const Color(0xFFC6A157);
  if (f.contains('bronze') || f.contains('cuivre') || f.contains('cognac') || f.contains('chocolat')) return const Color(0xFF8C5A3C);
  if (f.contains('camel')) return const Color(0xFFB98A55);
  if (f.contains('blanc')) return const Color(0xFFF2F2EE);
  if (f.contains('chêne') || f.contains('noyer')) return const Color(0xFF9C7350);
  return const Color(0xFFB4B9BF); // inox, chrome, nickel, alu
}

/// Apparence de la poignée du style : (rendu, taille en mm, couleur).
(String, double, Color) handleLook(KitchenStyle s, HandleCatalog? cat) {
  final h = cat?.byId(s.handleId);
  final size = (s.handleSize ?? h?.defaultSize ?? 160).toDouble();
  final finish = s.handleFinish ?? ((h?.finishes.isEmpty ?? true) ? null : h!.finishes.first);
  if (s.handle == 'gola') return (s.handle, size, golaColor(s, frontFinish(s, s.frontLower ?? s.front).color));
  return (s.handle, size, handleFinishColor(finish));
}

/// Poignée prête à dessiner.
class HandleLook {
  final String kind, orient, pos;
  final double size;
  final Color color;
  final bool pair;
  const HandleLook(this.kind, this.size, this.color, {this.orient = 'auto', this.pos = 'auto', this.pair = false});
  String get key => '$kind|$size|${color.toARGB32()}|$orient|$pos|$pair';
}

/// Poignées d'un meuble : ses portes, ses tiroirs.
typedef HandleSet = ({HandleLook door, HandleLook drawer});

HandleLook lookOfChoice(HandleChoice c, HandleCatalog? cat, {Color front = const Color(0xFFF2F2EE)}) {
  final h = cat?.byId(c.id);
  final size = (c.size ?? h?.defaultSize ?? 160).toDouble();
  final finish = c.finish ?? ((h?.finishes.isEmpty ?? true) ? null : h!.finishes.first);
  return HandleLook(c.kind, size, finish == HandleCatalog.golaLikeFront ? shade(front, -0.04) : handleFinishColor(finish), orient: c.orient, pos: c.pos, pair: c.pair);
}

HandleSet handleSetOf(KitchenStyle s, HandleCatalog? cat, CabinetModel m, {Color front = const Color(0xFFF2F2EE)}) {
  HandleLook at(String zone) {
    final c = s.handleAt(zone);
    if (c.kind == 'gola') return HandleLook('gola', 160, golaColor(s, front));
    return lookOfChoice(c, cat, front: front);
  }

  return (door: at(LayoutEngine.handleZone(m.kind)), drawer: at('tiroir'));
}

/// Couleur du profil Gola ([front] : couleur de la façade, quand il lui est assorti).
Color golaColor(KitchenStyle s, Color front) => switch (s.handleFinish) {
      null || 'Aluminium' => const Color(0xFFB9BDC2),
      'Champagne' => const Color(0xFFD9C8A5),
      'Inox brossé' => const Color(0xFF9FA4A9),
      HandleCatalog.golaLikeFront => shade(front, -0.04),
      final f => handleFinishColor(f),
    };

/// Profil métallique (pas laqué) : il brille en 3D.
bool golaMetal(KitchenStyle s) => !const {'Noir mat', 'Anthracite', 'Blanc', HandleCatalog.golaLikeFront}.contains(s.handleFinish);

/// Couleur de trait lisible sur une teinte donnée.
Color lineOn(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.lightness > 0.55
      ? hsl.withLightness((hsl.lightness - 0.32).clamp(0, 1)).toColor()
      : hsl.withLightness((hsl.lightness + 0.25).clamp(0, 1)).toColor();
}

Color shade(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}
