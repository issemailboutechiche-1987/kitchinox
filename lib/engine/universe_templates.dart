/// Compositions proposées pour le dressing, la salle de bain / WC et le meuble TV : modèles nommés,
/// rangés par famille, déclinés en palettes de finitions ; chacun est recalculé pour le mur le plus adapté
/// de la pièce : modules optionnels retirés par paires (symétrie), largeurs élargies pour absorber la place
/// restante, modules de remplissage, surmeubles posés sur les colonnes, éléments suspendus centrés.
library;

import 'dart:math' as math;

import 'catalog.dart';
import 'essentials.dart';
import 'fixes.dart';
import 'front_layout.dart';
import 'layout_engine.dart';
import 'project.dart';
import 'proposal_objects.dart';
import 'proposals.dart';

/// Un emplacement : un module, sa largeur souhaitée, et sa position (au sol, au-dessus d'un autre, sur une colonne).
class Slot {
  final String id;
  final int w; // largeur souhaitée (la plus proche du catalogue)
  final int? h; // hauteur souhaitée
  final bool optional; // retiré si le mur est trop court (par paires aux deux extrémités)
  final int? above; // suspendu, centré au-dessus de l'emplacement n°
  final int? onTop; // surmeuble posé sur la colonne n° (même largeur)
  final bool open; // niches ouvertes au lieu des portes du module
  const Slot(this.id, this.w, {this.h, this.optional = false, this.above, this.onTop, this.open = false});
}

/// Palette de finitions : façades, poignées, caissons, sol, murs.
class Palette {
  final String name;
  final Map<String, String> style;
  const Palette(this.name, this.style);
}

class UniverseTemplate {
  final String id, name, family, description;
  final List<Slot> slots;
  final String? fill; // module répété pour remplir la place restante
  final bool center; // composition centrée sur le mur (meuble TV) ou d'un angle à l'autre
  final Palette signature; // finitions du modèle
  const UniverseTemplate(this.id, this.name, this.family, this.description, this.slots, this.signature, {this.fill, this.center = false});
}

Map<String, String> _s(String front, String handle, String carcass, String floor, String wall) =>
    {'front': front, 'handle': handle, 'carcass': carcass, 'floor': floor, 'wall': wall};

/// Palettes proposées en plus de la signature de chaque modèle.
final universePalettes = <String, List<Palette>>{
  'dressing': [
    Palette('Blanc pur', _s('blanc_mat', 'gola', 'blanc', 'parquet_clair', 'blanc_casse')),
    Palette('Chêne naturel', _s('chene', 'gola', 'chene', 'parquet_chene', 'beige_sable')),
    Palette('Noyer et noir', _s('noyer', 'gola', 'noir', 'parquet_noyer', 'gris_perle')),
    Palette('Vert sauge', _s('vert_sauge', 'knob', 'blanc', 'parquet_clair', 'blanc_casse')),
    Palette('Cachemire', _s('cachemire', 'bar', 'blanc', 'parquet_chene', 'beige_sable')),
    Palette('Anthracite', _s('anthracite', 'bar', 'noir', 'beton_cire', 'gris_perle')),
  ],
  'bain': [
    Palette('Blanc spa', _s('blanc_brillant', 'gola', 'blanc', 'carrelage_blanc', 'blanc_casse')),
    Palette('Bois clair', _s('chene_clair', 'gola', 'blanc', 'terrazzo_sol', 'beige_sable')),
    Palette('Vert forêt', _s('vert_foret', 'knob', 'blanc', 'carreaux_ciment', 'vert_sauge_mur')),
    Palette('Béton', _s('beton_facade', 'gola', 'gris', 'beton_cire', 'beton_mur')),
    Palette('Terracotta', _s('terracotta', 'bar', 'blanc', 'tomettes', 'blanc_casse')),
    Palette('Noyer', _s('noyer', 'gola', 'noir', 'carrelage_marbre', 'gris_perle')),
  ],
  'tv': [
    Palette('Noyer', _s('noyer', 'gola', 'noir', 'parquet_noyer', 'beige_sable')),
    Palette('Laque blanche', _s('blanc_brillant', 'gola', 'blanc', 'parquet_clair', 'blanc_casse')),
    Palette('Béton', _s('beton_facade', 'gola', 'gris', 'beton_cire', 'gris_perle')),
    Palette('Terracotta', _s('terracotta', 'knob', 'blanc', 'parquet_chene', 'terracotta_mur')),
    Palette('Noir mat', _s('noir_mat', 'gola', 'noir', 'carrelage_gris', 'beton_mur')),
    Palette('Chêne fumé', _s('chene_fume', 'gola', 'noir', 'parquet_chene', 'gris_perle')),
  ],
  'buanderie': [
    Palette('Blanc immaculé', _s('blanc_mat', 'gola', 'blanc', 'carrelage_blanc', 'blanc_casse')),
    Palette('Chêne et blanc', _s('blanc_mat', 'bar', 'chene', 'parquet_clair', 'beige_sable')),
    Palette('Vert d’eau / Sauge', _s('vert_sauge', 'bar', 'blanc', 'carreaux_ciment', 'blanc_casse')),
    Palette('Gris moderne', _s('gris_galet', 'gola', 'gris', 'beton_cire', 'gris_perle')),
    Palette('Bleu azur', _s('bleu_nuit', 'bar', 'blanc', 'carrelage_marbre', 'blanc_casse')),
  ],
};

const universeTemplates = <String, List<UniverseTemplate>>{
  'dressing': [
    UniverseTemplate('atlas', 'Atlas', 'Classique',
        'Penderie longue, double penderie, lingère à tiroirs et colonne chaussures ; surmeubles sur toute la longueur.',
        [
          Slot('wardrobe_long_hanging', 800),
          Slot('wardrobe_double_hanging', 1000),
          Slot('wardrobe_linen_drawers_tower', 600),
          Slot('wardrobe_shoe_column', 600, optional: true),
          Slot('wardrobe_top_box', 800, onTop: 0, optional: true),
          Slot('wardrobe_top_box', 1000, onTop: 1, optional: true),
        ],
        Palette('Signature blanc', {'front': 'blanc_mat', 'handle': 'bar', 'carcass': 'blanc', 'floor': 'parquet_clair', 'wall': 'blanc_casse'}),
        fill: 'wardrobe_shelves_column'),
    UniverseTemplate('ifrane', 'Ifrane', 'Bois chaleureux', 'Double penderie au centre, lingère et étagères de part et d’autre, profil Gola.',
        [Slot('wardrobe_shelves_column', 600, optional: true), Slot('wardrobe_double_hanging', 1000), Slot('wardrobe_hanging_drawers', 800), Slot('wardrobe_linen_drawers_tower', 600, optional: true)],
        Palette('Signature chêne', {'front': 'chene', 'handle': 'gola', 'carcass': 'chene', 'floor': 'parquet_chene', 'wall': 'beige_sable'}),
        fill: 'wardrobe_long_hanging'),
    UniverseTemplate('zagora', 'Zagora', 'Ouvert (walk-in)', 'Sans portes, ambiance boutique : penderies et étagères visibles, extrémités ouvertes.',
        [
          Slot('wardrobe_open_end_shelf', 350, optional: true),
          Slot('wardrobe_long_hanging', 1000, open: true),
          Slot('wardrobe_linen_drawers_tower', 800),
          Slot('wardrobe_double_hanging', 1000, open: true),
          Slot('wardrobe_open_end_shelf', 350, optional: true),
        ],
        Palette('Signature noyer', {'front': 'noyer', 'handle': 'gola', 'carcass': 'noir', 'floor': 'parquet_noyer', 'wall': 'gris_perle'}),
        fill: 'wardrobe_shelves_column'),
    UniverseTemplate('asilah', 'Asilah', 'Miroir', 'Portes miroir toute hauteur aux extrémités, penderies au centre : la pièce paraît deux fois plus grande.',
        [Slot('wardrobe_mirror_door_column', 600, optional: true), Slot('wardrobe_double_hanging', 1000), Slot('wardrobe_linen_drawers_tower', 600), Slot('wardrobe_mirror_door_column', 600, optional: true)],
        Palette('Signature cachemire', {'front': 'cachemire', 'handle': 'bar', 'carcass': 'blanc', 'floor': 'carrelage_marbre', 'wall': 'blanc_casse'}),
        fill: 'wardrobe_long_hanging'),
    UniverseTemplate('riad', 'Riad', 'Symétrique', 'Composition en miroir autour d’une lingère centrale : penderies de chaque côté, chaussures aux extrémités.',
        [
          Slot('wardrobe_shoe_column', 450, optional: true),
          Slot('wardrobe_long_hanging', 800),
          Slot('wardrobe_linen_drawers_tower', 800),
          Slot('wardrobe_long_hanging', 800),
          Slot('wardrobe_shoe_column', 450, optional: true),
        ],
        Palette('Signature sauge', {'front': 'vert_sauge', 'handle': 'knob', 'carcass': 'blanc', 'floor': 'parquet_clair', 'wall': 'blanc_casse'})),
    UniverseTemplate('toubkal', 'Toubkal', 'Grande hauteur', 'Pour plafonds hauts : pantographes, lingère et surmeubles jusqu’au plafond.',
        [
          Slot('wardrobe_pantograph_column', 900),
          Slot('wardrobe_linen_drawers_tower', 600),
          Slot('wardrobe_pantograph_column', 900, optional: true),
          Slot('wardrobe_top_box', 600, onTop: 1, optional: true),
        ],
        Palette('Signature anthracite', {'front': 'anthracite', 'handle': 'gola', 'carcass': 'noir', 'floor': 'beton_cire', 'wall': 'gris_perle'}),
        fill: 'wardrobe_shelves_column'),
    UniverseTemplate('chefchaouen', 'Chefchaouen', 'Couleur', 'Bleu nuit et laiton : penderie avec tiroirs intérieurs, étagères, colonne linge sale.',
        [Slot('wardrobe_shelves_column', 500), Slot('wardrobe_hanging_drawers', 900), Slot('wardrobe_laundry_column', 500, optional: true)],
        Palette('Signature bleu nuit', {'front': 'bleu_nuit', 'handle': 'bar', 'carcass': 'blanc', 'floor': 'parquet_chene', 'wall': 'blanc_casse'}),
        fill: 'wardrobe_long_hanging'),
    UniverseTemplate('kenitra', 'Kénitra', 'Compact', 'Petit mur : une penderie et une lingère, tout le nécessaire en moins de 1,5 m.',
        [Slot('wardrobe_long_hanging', 800), Slot('wardrobe_linen_drawers_tower', 600)],
        Palette('Signature galet', {'front': 'gris_galet', 'handle': 'knob', 'carcass': 'blanc', 'floor': 'parquet_clair', 'wall': 'blanc_casse'})),
    UniverseTemplate('medina', 'Médina', 'Chambre d’ado', 'Penderie basse à tiroirs, étagères et chaussures : rangement complet pour une petite chambre.',
        [Slot('wardrobe_hanging_drawers', 800), Slot('wardrobe_shelves_column', 450), Slot('wardrobe_shoe_column', 450, optional: true)],
        Palette('Signature terracotta', {'front': 'terracotta', 'handle': 'knob', 'carcass': 'blanc', 'floor': 'parquet_clair', 'wall': 'blanc_casse'})),
  ],
  'bain': [
    UniverseTemplate('oualidia', 'Oualidia', 'Suspendu', 'Vasque suspendue, armoire de toilette miroir au-dessus, colonne linge.',
        [Slot('bath_vanity_single_basin_wall_hung', 800), Slot('bath_mirror_medicine_cabinet', 800, above: 0), Slot('bath_tall_linen_column', 350, optional: true)],
        Palette('Signature blanc', {'front': 'blanc_brillant', 'handle': 'gola', 'carcass': 'blanc', 'floor': 'carrelage_blanc', 'wall': 'blanc_casse'})),
    UniverseTemplate('mogador', 'Mogador', 'Double vasque', 'Double vasque, grande armoire miroir, deux demi-colonnes symétriques.',
        [Slot('bath_semi_column', 350, optional: true), Slot('bath_vanity_double_basin_wall_hung', 1400), Slot('bath_mirror_medicine_cabinet', 1200, above: 1), Slot('bath_semi_column', 350, optional: true)],
        Palette('Signature chêne clair', {'front': 'chene_clair', 'handle': 'gola', 'carcass': 'blanc', 'floor': 'terrazzo_sol', 'wall': 'beige_sable'})),
    UniverseTemplate('taghazout', 'Taghazout', 'WC et gain de place', 'Lave-mains faible profondeur, étagère au-dessus, meuble au-dessus du WC.',
        [Slot('bath_vanity_compact_hand_basin', 450), Slot('bath_open_shelf_wall', 400, above: 0, optional: true), Slot('bath_wc_over_cabinet', 600)],
        Palette('Signature sauge', {'front': 'vert_sauge', 'handle': 'knob', 'carcass': 'blanc', 'floor': 'carreaux_ciment', 'wall': 'blanc_casse'})),
    UniverseTemplate('hammam', 'Hammam', 'Spa et buanderie', 'Vasque 3 tiroirs, étagère serviettes, colonne lave-linge et sèche-linge superposés.',
        [Slot('bath_vanity_drawers_3', 1000), Slot('bath_open_shelf_wall', 800, above: 0), Slot('bath_washing_machine_column', 650, optional: true)],
        Palette('Signature noyer', {'front': 'noyer', 'handle': 'gola', 'carcass': 'noir', 'floor': 'beton_cire', 'wall': 'beton_mur'})),
    UniverseTemplate('essaouira_bain', 'Essaouira', 'Sur pieds', 'Vasque sur pieds, armoire miroir, colonne suspendue.',
        [Slot('bath_vanity_floor_standing', 800), Slot('bath_mirror_medicine_cabinet', 800, above: 0), Slot('bath_tall_linen_column', 400, optional: true)],
        Palette('Signature bleu nuit', {'front': 'bleu_nuit', 'handle': 'bar', 'carcass': 'blanc', 'floor': 'carreaux_ciment', 'wall': 'blanc_casse'})),
    UniverseTemplate('agadir', 'Agadir', 'Lumineux', 'Vasque suspendue large, demi-colonne et étagères ouvertes : léger et facile à nettoyer.',
        [Slot('bath_vanity_single_basin_wall_hung', 1000), Slot('bath_open_shelf_wall', 1000, above: 0), Slot('bath_semi_column', 400, optional: true)],
        Palette('Signature terracotta', {'front': 'terracotta', 'handle': 'bar', 'carcass': 'blanc', 'floor': 'tomettes', 'wall': 'blanc_casse'})),
    UniverseTemplate('fes_bain', 'Fès', 'Grande famille', 'Vasque 3 tiroirs, armoire miroir, colonne linge et colonne buanderie.',
        [Slot('bath_tall_linen_column', 400, optional: true), Slot('bath_vanity_drawers_3', 1200), Slot('bath_mirror_medicine_cabinet', 1000, above: 1), Slot('bath_washing_machine_column', 650, optional: true)],
        Palette('Signature vert forêt', {'front': 'vert_foret', 'handle': 'bar', 'carcass': 'blanc', 'floor': 'carreaux_ciment', 'wall': 'vert_sauge_mur'})),
    UniverseTemplate('dakhla', 'Dakhla', 'Compact', 'Salle d’eau d’appoint : vasque 60, miroir, demi-colonne.',
        [Slot('bath_vanity_single_basin_wall_hung', 600), Slot('bath_mirror_medicine_cabinet', 600, above: 0), Slot('bath_semi_column', 300, optional: true)],
        Palette('Signature béton', {'front': 'beton_facade', 'handle': 'gola', 'carcass': 'gris', 'floor': 'beton_cire', 'wall': 'beton_mur'})),
  ],
  'tv': [
    UniverseTemplate('majorelle', 'Majorelle', 'Suspendu', 'Banc suspendu, pont relevable au-dessus de l’écran, deux colonnes vitrées.',
        [Slot('tv_wall_hanging_vertical_column', 400, optional: true), Slot('tv_low_bench_floating', 2000), Slot('tv_wall_horizontal_bridge', 1500, above: 1), Slot('tv_wall_hanging_vertical_column', 400, optional: true)],
        Palette('Signature bleu nuit', {'front': 'bleu_nuit', 'handle': 'gola', 'carcass': 'noir', 'floor': 'parquet_chene', 'wall': 'blanc_casse'}),
        center: true),
    UniverseTemplate('kasbah', 'Kasbah', 'Bibliothèque', 'Meuble TV sur socle encadré de deux bibliothèques toute hauteur, pont au-dessus.',
        [Slot('tv_side_bookcase', 600, optional: true), Slot('tv_low_bench_floor_standing', 1800), Slot('tv_wall_horizontal_bridge', 1800, above: 1, optional: true), Slot('tv_side_bookcase', 600, optional: true)],
        Palette('Signature chêne', {'front': 'chene', 'handle': 'knob', 'carcass': 'chene', 'floor': 'parquet_chene', 'wall': 'terracotta_mur'}),
        center: true),
    UniverseTemplate('saiss', 'Saïss', 'Cheminée', 'Caisson cheminée au centre, étagère flottante au-dessus, cubes niches de part et d’autre.',
        [Slot('tv_open_cube', 400, optional: true), Slot('tv_fireplace_niche_module', 1500), Slot('tv_floating_shelf', 1200, above: 1), Slot('tv_open_cube', 400, optional: true)],
        Palette('Signature béton', {'front': 'beton_facade', 'handle': 'gola', 'carcass': 'gris', 'floor': 'beton_cire', 'wall': 'gris_perle'}),
        center: true),
    UniverseTemplate('chellah', 'Chellah', 'Minimal', 'Banc suspendu laqué et une étagère flottante : épuré, rapide à poser.',
        [Slot('tv_low_bench_floating', 1800), Slot('tv_floating_shelf', 1200, above: 0, optional: true)],
        Palette('Signature laque', {'front': 'blanc_mat', 'handle': 'gola', 'carcass': 'blanc', 'floor': 'parquet_clair', 'wall': 'blanc_casse'}),
        center: true),
    UniverseTemplate('riad_tv', 'Riad', 'Mur complet', 'Mur TV complet : bibliothèques, bloc tiroirs, banc suspendu et pont.',
        [
          Slot('tv_side_bookcase', 500, optional: true),
          Slot('tv_drawer_unit_floating', 800),
          Slot('tv_low_bench_floating', 1800),
          Slot('tv_wall_horizontal_bridge', 1500, above: 2, optional: true),
          Slot('tv_side_bookcase', 500, optional: true),
        ],
        Palette('Signature noyer', {'front': 'noyer', 'handle': 'gola', 'carcass': 'noir', 'floor': 'parquet_noyer', 'wall': 'beige_sable'}),
        center: true),
    UniverseTemplate('ouarzazate_tv', 'Ouarzazate', 'Asymétrique', 'Banc long décalé, colonne vitrée d’un côté, cubes en cascade de l’autre.',
        [Slot('tv_wall_hanging_vertical_column', 450), Slot('tv_low_bench_floating', 2400), Slot('tv_open_cube', 400, above: 1, optional: true)],
        Palette('Signature terracotta', {'front': 'terracotta', 'handle': 'knob', 'carcass': 'blanc', 'floor': 'parquet_chene', 'wall': 'beige_sable'}),
        center: true),
    UniverseTemplate('casa_tv', 'Casa', 'Urbain', 'Bloc tiroirs et banc sur socle, étagère flottante : sobre, noir mat.',
        [Slot('tv_low_bench_floor_standing', 1600), Slot('tv_floating_shelf', 1000, above: 0, optional: true), Slot('tv_drawer_unit_floating', 600, optional: true)],
        Palette('Signature noir', {'front': 'noir_mat', 'handle': 'gola', 'carcass': 'noir', 'floor': 'carrelage_gris', 'wall': 'beton_mur'}),
        center: true),
  ],
  'buanderie': [
    UniverseTemplate('buand_duo', 'Duo Fonctionnel', 'Côte-à-côte',
        'Lave-linge et sèche-linge côte-à-côte sous plan continu, bac à laver profond et meuble haut relevable sécurisé.',
        [
          Slot('laundry_washer_dryer_side_by_side', 1300),
          Slot('laundry_sink_deep_basin', 600),
          Slot('laundry_detergent_wall_unit', 800, above: 1, optional: true),
          Slot('laundry_sorting_baskets_cabinet', 600, optional: true),
        ],
        Palette('Signature blanc et chêne', {'front': 'blanc_mat', 'handle': 'gola', 'carcass': 'chene', 'floor': 'carrelage_blanc', 'wall': 'blanc_casse'}),
        fill: 'laundry_sorting_baskets_cabinet'),
    UniverseTemplate('buand_tour', 'Tour & Colonnes', 'Gain de place',
        'Colonne machines superposées, armoire balais et aspirateur, bac à laver et tringle de séchage murale.',
        [
          Slot('laundry_washer_dryer_column', 650),
          Slot('laundry_broom_vacuum_tower', 600, optional: true),
          Slot('laundry_sink_deep_basin', 600),
          Slot('laundry_drying_rack_hanging_rod', 800, above: 2, optional: true),
        ],
        Palette('Signature sauge', {'front': 'vert_sauge', 'handle': 'bar', 'carcass': 'blanc', 'floor': 'carreaux_ciment', 'wall': 'blanc_casse'}),
        fill: 'laundry_linen_tower'),
    UniverseTemplate('buand_expert', 'Buanderie Complète', 'Luxe & Organisation',
        'Colonne superposée, meuble tri sélectif, bac inox sous plan, table à repasser escamotable en tiroir et armoire lingère.',
        [
          Slot('laundry_washer_dryer_column', 650),
          Slot('laundry_sorting_baskets_cabinet', 600),
          Slot('laundry_sink_deep_basin', 600),
          Slot('laundry_ironing_board_drawer', 600, optional: true),
          Slot('laundry_linen_tower', 600, optional: true),
          Slot('laundry_detergent_wall_unit', 800, above: 2, optional: true),
        ],
        Palette('Signature gris galet', {'front': 'gris_galet', 'handle': 'gola', 'carcass': 'gris', 'floor': 'beton_cire', 'wall': 'gris_perle'}),
        fill: 'laundry_sorting_baskets_cabinet'),
    UniverseTemplate('buand_compact', 'Cellier Compact', 'Petit espace',
        'Moins de 2 mètres : colonne machines superposées et meuble sous bac avec meuble haut pour détergents.',
        [
          Slot('laundry_washer_dryer_column', 650),
          Slot('laundry_sink_deep_basin', 600),
          Slot('laundry_detergent_wall_unit', 600, above: 1, optional: true),
        ],
        Palette('Signature blanc pur', {'front': 'blanc_mat', 'handle': 'bar', 'carcass': 'blanc', 'floor': 'carrelage_blanc', 'wall': 'blanc_casse'})),
  ],
};

int _nearest(List<int> v, int want) => v.reduce((a, b) => (a - want).abs() <= (b - want).abs() ? a : b);

/// Compositions recalculées pour la pièce : (famille, proposition).
/// [withStyle] faux : vos finitions, un modèle par composition (onglet « Selon votre pièce »).
/// [withStyle] vrai : la finition signature de chaque modèle, puis deux autres palettes (collection).
List<(String, LayoutProposal)> proposeUniverse(LayoutEngine original, {bool withStyle = true}) {
  final out = <(String, LayoutProposal)>[];
  // porte obligatoire, en face du mur principal ; l'eau obligatoire en salle de bain
  final src = Project.fromJson(original.project.toJson());
  final base = LayoutEngine(original.catalog, src);
  if (!src.openings.any((o) => o.isDoor)) {
    final items = [...src.items], objects = [...src.objects];
    src.items.clear();
    src.objects.clear();
    final main = ([...src.room.walls.where((w) => w.enabled)]..sort((a, b) => b.length != a.length ? b.length.compareTo(a.length) : src.room.order.indexOf(a.id).compareTo(src.room.order.indexOf(b.id)))).firstOrNull?.id;
    ensureDoor(base, avoid: {?main}, on: src.room.outline == null ? _facing[main] : null);
    src.items.addAll(items);
    src.objects.addAll(objects);
  }
  final walls = [for (final w in src.room.walls.where((w) => w.enabled)) w]..sort((a, b) => b.length.compareTo(a.length));
  final templates = universeTemplates[src.universe] ?? const <UniverseTemplate>[];
  final palettes = universePalettes[src.universe] ?? const <Palette>[];
  for (var n = 0; n < templates.length; n++) {
    final tp = templates[n];
    final looks = !withStyle
        ? <Palette?>[null]
        : <Palette?>[
            tp.signature,
            // deux autres palettes, différentes de la signature, tournantes d'un modèle à l'autre
            ...[for (var k = 0; k < palettes.length; k++) palettes[(n + k) % palettes.length]].where((p) => p.style['front'] != tp.signature.style['front']).take(2),
          ];
    LayoutProposal? best;
    String? bestWall;
    for (final w in walls) {
      final pr = _fit(base, tp, w.id, null);
      if (pr != null && (best == null || pr.score > best.score)) {
        best = pr;
        bestWall = w.id;
      }
    }
    if (best == null) continue;
    for (final look in looks) {
      final pr = look == null ? best : _fit(base, tp, bestWall!, look);
      if (pr != null) out.add((tp.family, pr));
    }
  }
  if (src.universe == 'dressing') out.addAll(_cornerDressings(base, templates, withStyle));
  out.sort((a, b) => b.$2.score.compareTo(a.$2.score));
  return out;
}

const _facing = {'A': 'D', 'D': 'A', 'B': 'C', 'C': 'B'};

/// Profondeur d'un dressing : les modules d'un mur voisin commencent après l'angle.
const dressingDepth = 600.0;

/// Dressings sur plusieurs murs, en L ou en U : un meuble d'angle en L à chaque angle (tout reste accessible),
/// les modules des deux murs partent de ses bras.
List<(String, LayoutProposal)> _cornerDressings(LayoutEngine base, List<UniverseTemplate> templates, bool withStyle) {
  final room = base.project.room;
  final model = base.catalog.tryGet('wardrobe_corner_L_90');
  final order = [for (final id in room.order) if (room.wall(id).enabled) id];
  if (model == null || order.length < 2) return const [];
  bool door(String id) => base.project.openings.any((o) => o.isDoor && o.wallId == id);
  // mur du fond : le plus long sans porte
  final ids = [...order]..sort((x, y) {
      final d = (door(x) ? 1 : 0).compareTo(door(y) ? 1 : 0);
      if (d != 0) return d;
      final l = room.wall(y).length.compareTo(room.wall(x).length);
      return l != 0 ? l : order.indexOf(x).compareTo(order.indexOf(y));
    });
  final a = ids.first;
  final next = room.nextOf(a), prev = room.prevOf(a);
  final la = room.wall(a).length;
  final w1 = model.widths.first.toDouble(), w2 = (model.widthRight ?? model.widths.first).toDouble();
  bool usable(String id) => room.isWallEnabled(id) && room.wall(id).orthogonal;
  final out = <(String, LayoutProposal)>[];
  LayoutProposal named(LayoutProposal pr, String id, String name, String desc, double bonus, String strength) => LayoutProposal(
        id: '${pr.id}_$id',
        name: name,
        description: desc,
        project: pr.project,
        score: pr.score + bonus,
        strengths: [strength, ...pr.strengths],
        warnings: pr.warnings,
        errors: pr.errors,
        worktop: 0,
        storage: pr.storage,
      );
  // meuble d'angle au bout du mur [wall] (son bras droit est sur le mur suivant), à la hauteur des colonnes
  bool corner(Project p, String wall) {
    final e = LayoutEngine(base.catalog, p);
    final talls = p.items.where((c) => e.modelOf(c).kind == CabinetKind.tall).map((c) => c.height);
    final h = talls.isEmpty ? null : model.heights.nearest(talls.reduce(math.max));
    try {
      e.add(model.id, wall, s: room.wall(wall).length - w1, height: h);
      return true;
    } on PlacementException {
      return false;
    }
  }

  for (final tp in templates.where((t) => !t.center)) {
    final look = withStyle ? tp.signature : null;
    if (!usable(next) || la < w1 + 800 || room.wall(next).length < w2 + 500) continue;
    // en L : fond + mur suivant
    final pa = _fit(base, tp, a, look, avail: la - w1);
    if (pa != null && corner(pa.project, a)) {
      final pl = _fit(base, tp, next, look, into: pa.project, start: w2, avail: room.wall(next).length - w2);
      if (pl != null && essentialOk(LayoutEngine(base.catalog, pl.project))) {
        out.add(('Dressing en L',
            named(pl, 'L', '${tp.name} en L', '${tp.description} Composition en L sur deux murs, meuble d’angle en L : tout est accessible.', 8,
                'Dressing en L : ${(la / 1000).toStringAsFixed(1)} m × ${(room.wall(next).length / 1000).toStringAsFixed(1)} m, angle en L')));
      }
    }
    // en U : fond + les deux murs voisins
    if (prev == next || !usable(prev) || la < w1 + w2 + 600 || room.wall(prev).length < w1 + 500 || la - 2 * dressingDepth < 800) continue;
    final pu = _fit(base, tp, a, look, start: w2, avail: la - w1 - w2);
    if (pu == null || !corner(pu.project, a) || !corner(pu.project, prev)) continue;
    final pn = _fit(base, tp, next, look, into: pu.project, start: w2, avail: room.wall(next).length - w2);
    if (pn == null) continue;
    final pp = _fit(base, tp, prev, look, into: pn.project, avail: room.wall(prev).length - w1);
    if (pp == null || !essentialOk(LayoutEngine(base.catalog, pp.project))) continue;
    out.add(('Dressing en U',
        named(pp, 'U', '${tp.name} en U', '${tp.description} Composition en U sur trois murs, deux meubles d’angle en L : tout est accessible.', 12,
            'Dressing en U : fond ${(la / 1000).toStringAsFixed(1)} m, côtés ${(room.wall(next).length / 1000).toStringAsFixed(1)} et ${(room.wall(prev).length / 1000).toStringAsFixed(1)} m')));
  }
  return out;
}

LayoutProposal? _fit(LayoutEngine base, UniverseTemplate tp, String wallId, Palette? look, {Project? into, double start = 0, double? avail}) {
  final cat = base.catalog;
  final src = base.project;
  final L = avail ?? src.room.wall(wallId).length;
  final roomH = src.room.height;
  bool ok(int i) => cat.tryGet(tp.slots[i].id) != null;
  final ground = [for (var i = 0; i < tp.slots.length; i++) if (tp.slots[i].above == null && tp.slots[i].onTop == null && ok(i)) i];
  final widths = <int, int>{for (final i in ground) i: _nearest(cat[tp.slots[i].id].widths.values, tp.slots[i].w)};
  int total() => widths.values.fold(0, (a, b) => a + b);
  // trop long : optionnels retirés par paires (premier et dernier) pour garder la symétrie, puis un à un
  final opts = [for (final i in ground) if (tp.slots[i].optional) i];
  while (total() > L && opts.isNotEmpty) {
    final last = opts.removeLast();
    widths.remove(last);
    if (opts.isNotEmpty && total() > L - 1 && opts.first < ground.length ~/ 2 && last >= ground.length ~/ 2) widths.remove(opts.removeAt(0));
  }
  // puis largeurs réduites, du plus large au plus étroit
  for (final i in [...widths.keys]..sort((a, b) => widths[b]!.compareTo(widths[a]!))) {
    if (total() <= L) break;
    final smaller = cat[tp.slots[i].id].widths.values.where((x) => x < widths[i]!).toList();
    if (smaller.isNotEmpty) widths[i] = smaller.reduce(math.max);
  }
  for (final i in widths.keys.toList()) {
    if (total() <= L) break;
    widths[i] = cat[tp.slots[i].id].widths.values.reduce(math.min);
  }
  if (total() > L || widths.isEmpty) return null;
  // modules de remplissage (pas pour le meuble TV, centré) : remplit parfaitement le mur
  final fills = <int>[];
  final fm = tp.fill == null ? null : cat.tryGet(tp.fill!);
  if (fm != null && !tp.center) {
    var rest = L - total();
    while (rest >= 300) {
      final fit = fm.widths.values.where((x) => x <= rest).toList();
      if (fit.isEmpty) break;
      final wv = fit.reduce(math.max);
      fills.add(wv);
      rest -= wv;
      if (fills.length >= 8) break;
    }
  }
  // place restante absorbée : chaque module passe à la largeur supérieure du catalogue tant que ça tient
  if (!tp.center) {
    var rest = L - total() - fills.fold<int>(0, (a, b) => a + b);
    var changed = true;
    while (changed && rest > 0) {
      changed = false;
      for (final i in widths.keys) {
        final up = cat[tp.slots[i].id].widths.values.where((x) => x > widths[i]! && x - widths[i]! <= rest).toList();
        if (up.isEmpty) continue;
        final nv = up.reduce(math.min);
        rest -= nv - widths[i]!;
        widths[i] = nv;
        changed = true;
      }
    }
  }

  final p = into != null ? Project.fromJson(into.toJson()) : (Project.fromJson(src.toJson())..items.clear());
  // on garde l'arrivée d'eau et l'évacuation existantes : la composition se rapproche d'elles
  p.points.removeWhere((x) => x.use != existingUse);
  p.room.island = null;
  final e = LayoutEngine(cat, p);
  final placed = <int, PlacedCabinet>{};
  // plus petit surmeuble prévu (s'il y en a)
  final boxes = [for (final sl in tp.slots) if (sl.onTop != null && cat.tryGet(sl.id) != null) cat[sl.id].heights.values.reduce(math.min)];
  final boxMin = boxes.isEmpty ? null : boxes.reduce(math.min);
  int heightFor(CabinetModel m, Slot s, {double? maxTop}) {
    final hs = m.heights.values;
    if (s.h != null) return _nearest(hs, s.h!);
    final z = (m.mountZ ?? (m.kind == CabinetKind.tall ? 100 : 0)).toDouble();
    var limit = maxTop ?? roomH - 100;
    // surmeubles prévus : toutes les colonnes s'arrêtent à la même hauteur pour laisser la place au surmeuble
    if (maxTop == null && m.kind == CabinetKind.tall && boxMin != null && roomH - 20 - boxMin - z >= 1900) limit = roomH - 20 - boxMin;
    final fit = hs.where((h) => z + h <= limit).toList();
    if (m.kind == CabinetKind.tall) return fit.isEmpty ? hs.reduce(math.min) : fit.reduce(math.max);
    return fit.isEmpty ? hs.reduce(math.min) : _nearest(fit, hs.first);
  }

  try {
    final used = total() + fills.fold<int>(0, (a, b) => a + b);
    var s = start + (tp.center ? (L - used) / 2 : 0.0);
    final order = [...widths.keys]..sort();
    final seq = <(int?, String, int)>[for (final i in order) (i, tp.slots[i].id, widths[i]!)];
    final at = seq.length > 1 ? seq.length - 1 : seq.length;
    seq.insertAll(at, [for (final wv in fills) (null, tp.fill!, wv)]);
    for (final (i, id, wv) in seq) {
      final m = cat[id];
      final c = e.add(id, wallId, s: s, width: wv, height: heightFor(m, i == null ? Slot(id, wv) : tp.slots[i]));
      if (i != null && tp.slots[i].open) c.layout = [FrontRow(CellKind.niche)];
      if (i != null) placed[i] = c;
      s = c.right;
    }
    for (var i = 0; i < tp.slots.length; i++) {
      final sl = tp.slots[i];
      final base0 = sl.above ?? sl.onTop;
      if (base0 == null || placed[base0] == null || !ok(i)) continue;
      final under = placed[base0]!;
      final m = cat[sl.id];
      try {
        if (sl.onTop != null) {
          // surmeuble : même largeur que la colonne, posé dessus, jusqu'au plafond moins 20 mm
          final room = roomH - under.top - 20;
          final hs = m.heights.values.where((h) => h <= room).toList();
          if (hs.isEmpty) continue;
          e.add(sl.id, wallId, s: under.s, z: under.top, width: m.widths.nearest(under.width), height: hs.reduce(math.max));
        } else {
          final fitting = m.widths.values.where((x) => x <= under.width).toList();
          final wv = _nearest(fitting.isEmpty ? m.widths.values : fitting, sl.w);
          e.add(sl.id, wallId, s: under.s + (under.width - wv) / 2, width: wv, height: heightFor(m, sl));
        }
      } on PlacementException {
        if (!sl.optional) rethrow;
      }
    }
  } on PlacementException {
    return null;
  }
  // objets de la composition : sanitaires, canapé, téléviseur, tapis…
  final objs = into != null ? 0 : placeTemplateObjects(e, tp.id, wallId, placed);
  // salle de bain : l'eau est obligatoire, tout est raccordé
  if (p.universe == 'bain') {
    ensureWater(e);
    ensureBathNetworks(e);
  }
  final objNames = [
    for (final o in p.objects)
      if (o.fixture != null) o.fixture!.name.split(' ').first,
  ];
  final st = p.style;
  final style = look?.style;
  if (style != null) {
    st
      ..front = style['front'] ?? st.front
      ..frontUpper = null
      ..frontLower = null
      ..handle = style['handle'] ?? st.handle
      ..handleId = null
      ..carcass = style['carcass'] ?? st.carcass
      ..floor = style['floor'] ?? st.floor
      ..wall = style['wall'] ?? st.wall;
  }
  final grounded = p.items.where((c) => e.modelOf(c).kind != CabinetKind.wall || e.modelOf(c).mountZ == null || c.z < 1000);
  final run = grounded.fold<double>(0, (a, c) => a + c.width);
  final span = p.items.isEmpty ? 0.0 : p.items.map((c) => c.right).reduce(math.max) - p.items.map((c) => c.s).reduce(math.min);
  final leftover = L - span;
  final warnings = [for (final i in e.validate().where((i) => i.severity == Severity.error)) i.message];

  // Adéquation de la composition avec la surface de la pièce choisie
  final areaM2 = (src.room.width * src.room.depth) / 1000000.0;
  var areaBonus = 0.0;
  if (areaM2 < 4.5) {
    // Petite pièce (< 4.5 m²) : valorise les modèles compacts et fonctionnels
    if (span <= 2400) areaBonus += 35.0;
    if (span > 3400) areaBonus -= 30.0;
  } else if (areaM2 < 9.0) {
    // Pièce moyenne (4.5 - 9 m²) : équilibre idéal entre 2 et 3.8 m
    if (span >= 2000 && span <= 3800) areaBonus += 30.0;
  } else {
    // Grande pièce (> 9 m²) : valorise les grandes compositions riches en rangement
    if (span >= 2800) areaBonus += 40.0;
    if (span < 1800) areaBonus -= 25.0;
  }

  final strengths = <String>[
    if (areaM2 < 4.5 && span <= 2400) 'Parfaitement adapté à la surface (${areaM2.toStringAsFixed(1)} m²)'
    else if (areaM2 >= 9.0 && span >= 2800) 'Grand volume pour belle surface (${areaM2.toStringAsFixed(1)} m²)',
    if (!tp.center && leftover < 50) 'Mur exploité d’un bout à l’autre (${(span / 1000).toStringAsFixed(2).replaceAll('.', ',')} m)'
    else if (tp.center) 'Centré sur le mur $wallId (${(span / 1000).toStringAsFixed(2).replaceAll('.', ',')} m)'
    else '${(span / 1000).toStringAsFixed(2).replaceAll('.', ',')} m sur le mur $wallId',
    if (p.items.any((c) => c.z > 1900)) 'Surmeubles jusqu’au plafond',
    if (objNames.isNotEmpty) 'Inclus : ${objNames.join(', ')}'
    else if (objs > 0) '$objs objet(s) de décoration inclus',
    if (look != null) 'Finitions : ${look.name}',
  ];
  // préférence : mur bien rempli (ou bien centré), peu de restes, pas d'erreur
  // appareils à eau loin de l'évacuation existante : 1 point de moins par 10 cm (au plus 40)
  final wetD = wetDrainDistance(e);
  if (wetD != null && wetD < 1200) strengths.add('Près de l’évacuation existante (${(wetD / 1000).toStringAsFixed(1).replaceAll('.', ',')} m)');
  final score = (tp.center ? 60.0 + math.min(span / L, 0.8) * 20 : 100.0 * span / L) -
      (leftover > 0 && leftover < 300 && !tp.center ? 10 : 0) -
      warnings.length * 25 -
      (wetD == null ? 0 : math.min(40, wetD / 100)) +
      areaBonus;
  return LayoutProposal(
    id: '${tp.id}_${wallId}_${look?.name ?? 'vous'}',
    name: look == null || look == tp.signature ? tp.name : '${tp.name} · ${look.name}',
    description: tp.description,
    project: p,
    score: score,
    strengths: strengths,
    warnings: warnings,
    errors: warnings.length,
    worktop: 0,
    storage: run.round(),
  );
}
