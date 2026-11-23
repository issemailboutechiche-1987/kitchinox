/// Collection kitchinox : modèles de cuisines complets (forme, composition, style), inspirés des
/// grandes familles de cuisines que l'on trouve chez les cuisinistes (blanches, bois, colorées,
/// grises, noires, beiges, petites cuisines et kitchenettes). Noms et compositions propres à
/// kitchinox ; chaque modèle est recalculé pour la pièce de l'utilisateur.
library;

import 'catalog.dart';
import 'essentials.dart';
import 'front_profiles.dart';
import 'layout_engine.dart';
import 'project.dart';
import 'proposals.dart';

/// Meubles hauts : normaux, étagères ouvertes, vitrines aux extrémités, ou aucun (étagères).
enum Uppers { normal, open, glassEnds, glass, none }

class KitchenTemplate {
  final String id;
  final String name; // nom kitchinox
  final String family;
  final String description;
  final Set<String> shapes; // formes acceptées, par ordre d'intérêt (lin, lini, l, li, u, p)
  final String fill; // portes | tiroirs | mixte
  final Uppers uppers;
  final String front;
  final String? frontUpper, frontLower;
  final String worktop;
  final String handle; // bar | knob | gola
  final String? handleId, handleFinish;
  final int? handleSize;
  final String floor, wall;
  final String? splash;
  final String profile; // modèle de façade
  final String? islandFront, islandTop, island; // îlot : façades, plan, forme

  const KitchenTemplate({
    required this.id,
    required this.name,
    required this.family,
    required this.description,
    required this.shapes,
    this.fill = 'mixte',
    this.uppers = Uppers.normal,
    required this.front,
    this.frontUpper,
    this.frontLower,
    required this.worktop,
    this.handle = 'bar',
    this.handleId,
    this.handleFinish,
    this.handleSize,
    required this.floor,
    this.wall = 'blanc_casse',
    this.splash,
    this.profile = 'lisse',
    this.islandFront,
    this.islandTop,
    this.island,
  });

  void applyStyle(KitchenStyle s) {
    s
      ..front = front
      ..frontUpper = frontUpper
      ..frontLower = frontLower
      ..worktop = worktop
      ..handle = handle
      ..handleId = handleId
      ..handleFinish = handleFinish
      ..handleSize = handleSize
      ..floor = floor
      ..wall = wall
      ..splash = splash
      ..frontProfile = profile
      ..islandFront = islandFront
      ..islandTop = islandTop;
  }
}

const kitchenTemplates = <KitchenTemplate>[
  // ---------------------------------------------------------------- blanches
  KitchenTemplate(
      id: 'tetouan', name: 'Tétouan', family: 'Blanches',
      description: 'Blanc mat sans poignée, plan quartz, bas tout en tiroirs : épurée, rangements cachés.',
      shapes: {'l', 'lin', 'li', 'u'}, fill: 'tiroirs', front: 'blanc_mat', worktop: 'quartz_blanc', handle: 'gola',
      floor: 'beton_cire', splash: null),
  KitchenTemplate(
      id: 'saidia', name: 'Saïdia', family: 'Blanches',
      description: 'Blanc brillant laqué, plan granit noir en contraste, grands volumes de rangement.',
      shapes: {'u', 'l', 'lin', 'p'}, fill: 'tiroirs', front: 'blanc_brillant', worktop: 'granit_noir', handle: 'edgeFull',
      handleId: 'edge_pull_full_width_bar', handleFinish: 'Alu anodisé brossé', floor: 'carrelage_blanc', splash: 'inox_cred'),
  KitchenTemplate(
      id: 'rabat', name: 'Rabat', family: 'Blanches',
      description: 'Ouverte sur la vie de famille : îlot avec coin repas, blanc et marbre.',
      shapes: {'li', 'lini', 'l', 'lin'}, fill: 'mixte', front: 'blanc_mat', frontLower: 'blanc_mat', worktop: 'marbre',
      handle: 'bar', handleId: 'handle_d_pull_flat', handleFinish: 'Noir mat', floor: 'parquet_chene', splash: 'metro_blanc'),
  KitchenTemplate(
      id: 'essaouira', name: 'Essaouira', family: 'Blanches',
      description: 'Blanc et bois, étagères ouvertes au-dessus de l\'évier, ambiance bord de mer.',
      shapes: {'l', 'lin'}, fill: 'portes', uppers: Uppers.open, front: 'blanc_mat', frontLower: 'chene_clair',
      worktop: 'quartz_blanc', handle: 'knob', handleId: 'knob_round_mushroom', handleFinish: 'Laiton brossé',
      floor: 'parquet_clair', splash: 'zellige_blanc'),
  KitchenTemplate(
      id: 'tanger', name: 'Tanger', family: 'Blanches',
      description: 'Traditionnelle chaleureuse : façades blanches, vitrines aux extrémités, plan bois.',
      shapes: {'u', 'l', 'lin'}, fill: 'portes', uppers: Uppers.glassEnds, front: 'blanc_mat', worktop: 'marbre',
      handle: 'cup', handleId: 'cup_handle_shell_shaker', handleFinish: 'Noir vieilli', floor: 'tomettes', splash: 'metro_blanc'),
  // ---------------------------------------------------------------- bois
  KitchenTemplate(
      id: 'atlas', name: 'Atlas', family: 'Bois',
      description: 'Chêne naturel, plan céramique effet béton, îlot pour se retrouver.',
      shapes: {'li', 'lini', 'l', 'lin'}, fill: 'tiroirs', front: 'chene', worktop: 'beton', handle: 'gola',
      floor: 'beton_cire', splash: null),
  KitchenTemplate(
      id: 'ifrane', name: 'Ifrane', family: 'Bois',
      description: 'Esprit chalet scandinave : chêne clair, boutons, étagères ouvertes, plan quartz.',
      shapes: {'l', 'lin', 'u'}, fill: 'mixte', uppers: Uppers.open, front: 'chene_clair', worktop: 'quartz_blanc', handle: 'knob',
      handleId: 'knob_cylinder_knurled', handleFinish: 'Noir mat', floor: 'parquet_clair', splash: 'metro_blanc'),
  KitchenTemplate(
      id: 'cedre', name: 'Cèdre', family: 'Bois',
      description: 'Bois et blanc : hauts blancs, bas en chêne, plan granit gris, lumineuse.',
      shapes: {'l', 'lin', 'p'}, fill: 'mixte', front: 'blanc_mat', frontUpper: 'blanc_mat', frontLower: 'chene',
      worktop: 'granit_gris', handle: 'bar', handleId: 'handle_tubular_t_bar', handleFinish: 'Inox brossé',
      floor: 'parquet_chene', splash: 'zellige_blanc'),
  KitchenTemplate(
      id: 'chef', name: 'Toubkal', family: 'Bois',
      description: 'Pour gastronome : noyer, plan granit noir, grand plan de travail en U, tiroirs à casseroles.',
      shapes: {'u', 'p', 'li', 'lin'}, fill: 'tiroirs', front: 'noyer', worktop: 'granit_noir', handle: 'bar',
      handleId: 'handle_knurled_industrial', handleFinish: 'Noir carbone', floor: 'carrelage_gris', splash: 'inox_cred'),
  // ---------------------------------------------------------------- colorées
  KitchenTemplate(
      id: 'chefchaouen', name: 'Chefchaouen', family: 'Colorées',
      description: 'Bleu nuit sur mesure, poignées dorées, plan marbre blanc, îlot.',
      shapes: {'li', 'lini', 'l', 'lin'}, fill: 'tiroirs', front: 'bleu_nuit', worktop: 'marbre', handle: 'bar',
      handleId: 'handle_d_pull_flat', handleFinish: 'Or brossé', floor: 'carrelage_marbre', splash: 'zellige_bleu'),
  KitchenTemplate(
      id: 'oasis', name: 'Oasis', family: 'Colorées',
      description: 'Vert sauge campagne chic, boutons laiton, plan marbre, vitrines, zellige blanc.',
      shapes: {'l', 'lin'}, fill: 'portes', uppers: Uppers.glassEnds, front: 'vert_sauge', worktop: 'marbre', handle: 'knob',
      handleId: 'knob_round_mushroom', handleFinish: 'Laiton brossé', floor: 'tomettes', splash: 'zellige_blanc'),
  KitchenTemplate(
      id: 'fes', name: 'Fès', family: 'Colorées',
      description: 'Vert forêt et bois, crédence en zellige vert, sol en carreaux de ciment : esprit médina.',
      shapes: {'l', 'lin', 'u'}, fill: 'mixte', front: 'vert_foret', frontUpper: 'chene', worktop: 'marbre', handle: 'bar',
      handleId: 'handle_tubular_t_bar', handleFinish: 'Doré / Laiton brossé', floor: 'carreaux_ciment', splash: 'zellige_vert'),
  KitchenTemplate(
      id: 'marrakech', name: 'Marrakech', family: 'Colorées',
      description: 'Terracotta chaleureuse, plan béton, étagères ouvertes, murs couleur sable.',
      shapes: {'lin', 'l'}, fill: 'mixte', uppers: Uppers.open, front: 'terracotta', worktop: 'beton', handle: 'leather',
      handleId: 'leather_loop_pull', handleFinish: 'Camel naturel', floor: 'tomettes', wall: 'beige_sable', splash: 'zellige_blanc'),
  // ---------------------------------------------------------------- grises
  KitchenTemplate(
      id: 'agadir', name: 'Agadir', family: 'Grises',
      description: 'Gris galet doux et intemporel, plan quartz blanc, carreaux métro.',
      shapes: {'l', 'u'}, fill: 'mixte', front: 'gris_galet', worktop: 'quartz_blanc', handle: 'bar',
      handleId: 'handle_tubular_t_bar', handleFinish: 'Inox brossé', floor: 'carrelage_gris', splash: 'metro_blanc'),
  KitchenTemplate(
      id: 'casa', name: 'Casa', family: 'Grises',
      description: 'Esprit industriel : façades effet béton, plan céramique anthracite, mur de briques.',
      shapes: {'l', 'p', 'lin'}, fill: 'tiroirs', uppers: Uppers.open, front: 'beton_facade', worktop: 'dekton_noir', handle: 'bar',
      handleId: 'handle_knurled_industrial', handleFinish: 'Noir carbone', floor: 'beton_cire', wall: 'brique', splash: null),
  // ---------------------------------------------------------------- noires
  KitchenTemplate(
      id: 'nuit_atlas', name: 'Nuit d\'Atlas', family: 'Noires',
      description: 'Noir mat et bois au sol : sans poignée, plan céramique effet marbre, îlot.',
      shapes: {'li', 'lini', 'l'}, fill: 'tiroirs', front: 'noir_mat', worktop: 'dekton_marbre', handle: 'gola',
      floor: 'parquet_chene', splash: 'metro_blanc'),
  KitchenTemplate(
      id: 'kasbah', name: 'Kasbah', family: 'Noires',
      description: 'Traditionnelle noire dans un petit espace : boutons dorés, plan marbre.',
      shapes: {'lin', 'l', 'p'}, fill: 'portes', front: 'noir_mat', worktop: 'marbre', handle: 'knob',
      handleId: 'knob_round_mushroom', handleFinish: 'Laiton brossé', floor: 'carreaux_ciment', splash: 'zellige_blanc'),
  KitchenTemplate(
      id: 'ouarzazate', name: 'Ouarzazate', family: 'Noires',
      description: 'Anthracite ouverte et spacieuse, plan béton, grand îlot.',
      shapes: {'li', 'lini', 'u'}, fill: 'tiroirs', front: 'anthracite', worktop: 'beton', handle: 'gola',
      floor: 'beton_cire', splash: null),
  // ---------------------------------------------------------------- beiges
  KitchenTemplate(
      id: 'merzouga', name: 'Merzouga', family: 'Beiges',
      description: 'Cachemire et bois clair, minimaliste et accueillante, murs sable.',
      shapes: {'l', 'li'}, fill: 'tiroirs', front: 'cachemire', worktop: 'beton', handle: 'gola',
      floor: 'parquet_clair', wall: 'beige_sable', splash: 'zellige_blanc'),
  KitchenTemplate(
      id: 'dakhla', name: 'Dakhla', family: 'Beiges',
      description: 'Familiale, lumineuse et spacieuse : beige et blanc, îlot, plan terrazzo.',
      shapes: {'li', 'lini', 'u'}, fill: 'mixte', front: 'cachemire', frontUpper: 'blanc_mat', worktop: 'terrazzo',
      handle: 'bar', handleId: 'handle_d_pull_flat', handleFinish: 'Or brossé', floor: 'terrazzo_sol', splash: 'metro_blanc'),
  // ---------------------------------------------------------------- campagne et classiques à cadre
  KitchenTemplate(
      id: 'mogador_cadre', name: 'Mogador', family: 'À cadre',
      description: 'Bleu pétrole à cadre, coquilles chromées, îlot marbre et plans bois : campagne chaleureuse.',
      shapes: {'li', 'lini', 'l', 'u'}, fill: 'tiroirs', front: 'bleu_petrole', worktop: 'hpl_chene', handle: 'cup',
      handleId: 'cup_handle_shell_shaker', handleFinish: 'Étain brossé', floor: 'parquet_blanchi', splash: 'metro_blanc',
      profile: 'shaker', islandTop: 'marbre', island: 'tiroirs'),
  KitchenTemplate(
      id: 'ourika_cadre', name: 'Ourika', family: 'À cadre',
      description: 'Blanc mouluré, vitrines à croisillons en haut, plan bois, grand évier : classique lumineuse.',
      shapes: {'l', 'u', 'lin'}, fill: 'mixte', uppers: Uppers.glassEnds, front: 'blanc_mat', worktop: 'hpl_chene', handle: 'bar',
      handleId: 'handle_recessed_bridge', handleFinish: 'Nickel satiné', floor: 'parquet_clair', splash: 'metro_blanc', profile: 'mouluree'),
  KitchenTemplate(
      id: 'azrou_cadre', name: 'Azrou', family: 'À cadre',
      description: 'Noir à cadre, plan bois clair, mur de brique et boutons : esprit atelier.',
      shapes: {'li', 'lini', 'l'}, fill: 'tiroirs', uppers: Uppers.glassEnds, front: 'noir_mat', worktop: 'hpl_chene', handle: 'knob',
      handleId: 'knob_round_mushroom', handleFinish: 'Noir mat', floor: 'parquet_blanchi', wall: 'blanc_casse', splash: 'brique_cred',
      profile: 'shaker', island: 'tiroirs'),
  KitchenTemplate(
      id: 'amizmiz_fin', name: 'Amizmiz', family: 'À cadre',
      description: 'Cadre fin vert olive, plan pierre claire, boutons laiton : le shaker d’aujourd’hui.',
      shapes: {'l', 'li', 'u', 'lin'}, fill: 'mixte', front: 'vert_olive_facade', worktop: 'marbre_creme', handle: 'knob',
      handleId: 'knob_cylinder_knurled', handleFinish: 'Or mat', floor: 'parquet_chene', splash: 'zellige_blanc', profile: 'shaker_fin'),
  KitchenTemplate(
      id: 'sefrou_fin', name: 'Sefrou', family: 'À cadre',
      description: 'Cadre fin champignon et chêne en haut, plan marbre, poignées bronze.',
      shapes: {'l', 'lin', 'u'}, fill: 'mixte', front: 'champignon', frontUpper: 'chene', worktop: 'marbre', handle: 'bar',
      handleId: 'handle_knurled_industrial', handleFinish: 'Bronze vieilli', floor: 'carrelage_travertin', splash: 'marbre_cred', profile: 'shaker_fin'),
  // ---------------------------------------------------------------- sans poignée et matières
  KitchenTemplate(
      id: 'oualidia_eau', name: 'Oualidia', family: 'Sans poignée',
      description: 'Vert d’eau sans poignée, profils laiton, plan sable : fraîche et très contemporaine.',
      shapes: {'l', 'u', 'li'}, fill: 'tiroirs', front: 'vert_deau', worktop: 'quartz_beige', handle: 'gola', handleFinish: 'Or brossé',
      floor: 'parquet_chene', splash: 'zellige_vert'),
  KitchenTemplate(
      id: 'imlil_jade', name: 'Imlil', family: 'Sans poignée',
      description: 'Vert jade supermat sans poignée, plan effet marbre, niches ouvertes.',
      shapes: {'l', 'li', 'lin'}, fill: 'tiroirs', uppers: Uppers.open, front: 'vert_jade', worktop: 'dekton_marbre', handle: 'gola',
      handleFinish: 'Noir mat', floor: 'beton_cire', splash: null),
  KitchenTemplate(
      id: 'tinghir_sable', name: 'Tinghir', family: 'Sans poignée',
      description: 'Sable mat, plan travertin clair, colonnes toute hauteur, îlot repas.',
      shapes: {'li', 'lini', 'l'}, fill: 'tiroirs', front: 'sable', worktop: 'marbre_creme', handle: 'gola', handleFinish: 'Champagne',
      floor: 'carrelage_travertin', wall: 'lin_naturel', splash: null, island: 'repas'),
  KitchenTemplate(
      id: 'midelt_cannele', name: 'Midelt', family: 'Sans poignée',
      description: 'Bas en noyer cannelé, hauts lisses sable, îlot cascade en marbre.',
      shapes: {'li', 'lini', 'l'}, fill: 'tiroirs', front: 'noyer', frontUpper: 'sable', worktop: 'marbre_calacatta', handle: 'gola', handleFinish: 'Noir mat',
      floor: 'parquet_chene', splash: 'plan', profile: 'cannelee', island: 'cascade'),
  KitchenTemplate(
      id: 'erfoud_ocre', name: 'Erfoud', family: 'Deux tons',
      description: 'Cuisine claire et îlot ocre : une seule touche de terre au centre.',
      shapes: {'li', 'lini'}, fill: 'mixte', front: 'cachemire', worktop: 'quartz_blanc', handle: 'bar',
      handleId: 'handle_d_pull_flat', handleFinish: 'Or brossé', floor: 'parquet_clair', splash: 'zellige_blanc', profile: 'shaker_fin',
      islandFront: 'ocre', islandTop: 'marbre_creme', island: 'repas'),
  KitchenTemplate(
      id: 'ksar_prune', name: 'Ksar', family: 'Deux tons',
      description: 'Prune profond en bas, chêne en haut, marbre veiné : chaleureuse et affirmée.',
      shapes: {'l', 'li', 'u'}, fill: 'tiroirs', front: 'prune', frontUpper: 'chene_clair', worktop: 'marbre_calacatta', handle: 'edge',
      handleId: 'edge_pull_individual_cut', handleFinish: 'Or brossé', floor: 'parquet_noyer', splash: 'plan'),
  // ---------------------------------------------------------------- petites cuisines et kitchenettes
  KitchenTemplate(
      id: 'riad', name: 'Riad', family: 'Petites cuisines',
      description: 'Petite cuisine aux rangements optimisés : hauts jusqu\'au plafond, tiroirs partout.',
      shapes: {'l', 'lin', 'p'}, fill: 'tiroirs', front: 'blanc_mat', worktop: 'quartz_gris', handle: 'bar',
      handleId: 'handle_tubular_t_bar', handleFinish: 'Noir mat', floor: 'carrelage_blanc', splash: 'metro_blanc'),
  KitchenTemplate(
      id: 'medina', name: 'Médina', family: 'Petites cuisines',
      description: 'Petite cuisine stylée vert sauge, étagères ouvertes, carreaux de ciment.',
      shapes: {'lin', 'l'}, fill: 'mixte', uppers: Uppers.open, front: 'vert_sauge', worktop: 'marbre', handle: 'knob',
      handleId: 'knob_conical_tapered', handleFinish: 'Or brossé', floor: 'carreaux_ciment', splash: 'zellige_vert'),
  KitchenTemplate(
      id: 'studio', name: 'Studio', family: 'Kitchenettes',
      description: 'Kitchenette d\'étudiant : un mur, étagères au lieu des hauts, plan bois.',
      shapes: {'lin'}, fill: 'portes', uppers: Uppers.none, front: 'blanc_mat', worktop: 'granit_gris', handle: 'knob',
      handleId: 'knob_round_mushroom', handleFinish: 'Noir mat', floor: 'parquet_clair', splash: 'metro_blanc'),
  KitchenTemplate(
      id: 'kitchenette_nord', name: 'Ifrane mini', family: 'Kitchenettes',
      description: 'Kitchenette scandinave en chêne clair, vitrines, compacte et pratique.',
      shapes: {'lin', 'p'}, fill: 'mixte', uppers: Uppers.glass, front: 'chene_clair', worktop: 'corian_blanc', handle: 'edge',
      handleId: 'edge_pull_individual_cut', handleFinish: 'Noir mat anodisé', floor: 'parquet_clair', splash: null),
  // ---------------------------------------------------------------- cuisines équipées (prix de référence du marché marocain)
  KitchenTemplate(
      id: 'eq_saphir', name: 'Saphir', family: 'Cuisines équipées',
      description: 'Laqué brillant bicolore blanc et chêne, poignées barres. Référence marché : 22 900 DH la cuisine équipée.',
      shapes: {'l', 'u', 'lin'}, fill: 'mixte', front: 'blanc_brillant', frontLower: 'chene', worktop: 'quartz_blanc', handle: 'bar',
      handleId: 'handle_tubular_t_bar', handleFinish: 'Inox brossé', floor: 'carrelage_gris', splash: 'metro_blanc'),
  KitchenTemplate(
      id: 'eq_onyx', name: 'Onyx', family: 'Cuisines équipées',
      description: 'Super-mat noir anti-traces, plan effet marbre, sans poignée. Référence marché : 22 900 DH.',
      shapes: {'l', 'u', 'li'}, fill: 'tiroirs', front: 'noir_mat', worktop: 'dekton_marbre', handle: 'gola',
      floor: 'parquet_chene', splash: null),
  KitchenTemplate(
      id: 'eq_velours', name: 'Velours', family: 'Cuisines équipées',
      description: 'Mat velours taupe, profil Gola sans poignée. Référence marché : 17 900 DH ; linéaire 2,40 m dès 10 470 DH.',
      shapes: {'lin', 'l'}, fill: 'tiroirs', front: 'cachemire', worktop: 'beton', handle: 'gola',
      floor: 'parquet_clair', wall: 'beige_sable', splash: null),
  KitchenTemplate(
      id: 'eq_lumiere', name: 'Lumière', family: 'Cuisines équipées',
      description: 'Taupe mat avec étagères ouvertes en chêne et éclairage LED. Référence marché : 17 900 DH.',
      shapes: {'l', 'lin'}, fill: 'mixte', uppers: Uppers.open, front: 'cachemire', frontUpper: 'chene', worktop: 'quartz_gris', handle: 'gola',
      floor: 'parquet_clair', splash: 'zellige_blanc'),
  KitchenTemplate(
      id: 'eq_cedre', name: 'Atlas bois', family: 'Cuisines équipées',
      description: 'Décors bois chaleureux, plan granit. Référence marché : 18 900 DH ; linéaire 2,40 m dès 12 039 DH.',
      shapes: {'l', 'u', 'lin'}, fill: 'mixte', front: 'noyer', worktop: 'granit_noir', handle: 'bar',
      handleId: 'handle_tubular_t_bar', handleFinish: 'Noir mat', floor: 'carrelage_gris', splash: 'metro_blanc'),
  KitchenTemplate(
      id: 'eq_satin', name: 'Satin', family: 'Cuisines équipées',
      description: 'Mélaminé satiné gris, ouverture push-pull sans poignée. Référence marché : 18 900 DH.',
      shapes: {'l', 'lin', 'p'}, fill: 'tiroirs', front: 'gris_galet', worktop: 'quartz_blanc', handle: 'gola',
      floor: 'carrelage_blanc', splash: 'metro_blanc'),
];

/// Applique la composition des hauts du modèle (étagères ouvertes, vitrines, aucun haut).
void _applyUppers(LayoutEngine e, Uppers u) {
  if (u == Uppers.normal) return;
  final highs = e.project.items.where((c) {
    final m = e.modelOf(c);
    return m.kind == CabinetKind.wall && !m.isHoodUnit && !m.isFreeHood && m.id != 'wall_chimney_box';
  }).toList();
  highs.sort((a, b) => a.wallId != b.wallId ? a.wallId.compareTo(b.wallId) : a.s.compareTo(b.s));
  var rank = 0;
  for (final c in highs) {
    switch (u) {
      case Uppers.none:
        e.project.items.remove(c);
      case Uppers.open:
        // étagères ouvertes : niches larges sur toute la longueur (600 à 1200), sinon niche étroite
        // une sur deux : les vitrines restent des vitrines, l'ensemble n'est pas vide
        final glass = c.modelId == 'wall_glass_door' && rank.isOdd;
        rank++;
        if (glass) break;
        final id = c.width >= 600 ? 'wall_open_niche_wide' : 'wall_open_shelf';
        e.replace(c.uid, id);
      case Uppers.glass:
        e.replace(c.uid, 'wall_glass_door');
      case Uppers.glassEnds:
        final run = e.runs(c.wallId, (m) => m.kind.isHigh);
        final atEnd = run.any((r) => (c.s - r.$1).abs() < 1 || (c.right - r.$2).abs() < 1);
        if (atEnd) e.replace(c.uid, 'wall_glass_door');
      case Uppers.normal:
        break;
    }
  }
  // les remplacements plus étroits laissent parfois des vides : fileurs
  for (final g in e.gaps().where((g) => g.fillable)) {
    e.fillGap(g);
  }
}

/// Construit chaque modèle de la collection pour la pièce : la meilleure forme compatible, la
/// composition des hauts, puis le style complet. Les modèles impossibles dans la pièce sont omis.
List<(KitchenTemplate, LayoutProposal)> buildTemplates(LayoutEngine base) {
  final cache = <String, List<LayoutProposal>>{};
  final out = <(KitchenTemplate, LayoutProposal)>[];
  for (final t in kitchenTemplates) {
    final all = cache.putIfAbsent(t.fill, () => proposeLayouts(base, max: 99, fillStyle: t.fill, distinct: false));
    final pr = all.where((p) => t.shapes.contains(p.id.split('_').first)).firstOrNull;
    if (pr == null) continue;
    final project = Project.fromJson(pr.project.toJson());
    final e = LayoutEngine(base.catalog, project);
    _applyUppers(e, t.uppers);
    for (final w in project.room.walls.where((w) => w.enabled)) {
      e.placeHoods(w.id);
    }
    // forme d'îlot du modèle, gardée si elle ne gêne rien
    if (t.island != null && project.room.island != null) {
      final before = Project.fromJson(project.toJson());
      final bad = e.validate().where((i) => i.severity == Severity.error).length;
      if (!applyIslandPreset(e, t.island!) || e.workZones().$1 == null || e.workZones().$2 == null || e.validate().where((i) => i.severity == Severity.error).length > bad) {
        project.items
          ..clear()
          ..addAll(before.items);
        project.room.island = before.room.island;
        project.style
          ..islandWaterfall = false
          ..islandBack = 'lisse';
      }
    }
    if (!essentialOk(e)) continue;
    t.applyStyle(project.style);
    out.add((
      t,
      LayoutProposal(
        id: 'tpl_${t.id}',
        name: t.name,
        description: t.description,
        project: project,
        score: pr.score,
        strengths: [pr.name, ...pr.strengths.take(2)],
        warnings: pr.warnings,
        errors: pr.errors,
        worktop: pr.worktop,
        storage: pr.storage,
        triangle: pr.triangle,
      ),
    ));
  }
  return out;
}
