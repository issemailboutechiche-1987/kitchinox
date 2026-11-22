/// Catalogue des poignées (marché marocain, prix en MAD) : barres, boutons, profils sur chant,
/// cuvettes encastrées, prises de main usinées, coquilles, barres XXL.
/// Sert au choix dans le style, au dessin des façades, aux perçages et à l'estimation.
library;

import 'dart:convert';

import 'materials.dart';

/// Façon de dessiner / poser la poignée.
enum HandleRender {
  bar, // barre, étrier, arceau (2 points)
  knob, // bouton (1 point)
  edge, // profil sur le chant (lèvre) de longueur donnée
  edgeFull, // profil continu sur toute la largeur
  jProfile, // profil coiffant en J
  recess, // cuvette rectangulaire encastrée
  recessRound, // cuvette ronde encastrée
  groove, // gorge usinée en J dans la façade
  chamfer, // chant biseauté à 45°
  pocket, // encoche usinée sur la face
  cup, // coquille
  leather, // languette cuir
  xxl, // barre verticale pleine hauteur
  gola, // sans poignée : profil Gola sur le caisson
  push; // sans poignée : ouverture par pression

  /// Rendu dessiné ('bar', 'knob'…) : celui gardé dans le style.
  String get kind => name;
}

/// Endroits où la poignée peut être différente.
const handleZones = {'haut': 'Meubles hauts', 'bas': 'Meubles bas', 'colonne': 'Colonnes', 'tiroir': 'Tiroirs'};

/// Une poignée choisie : modèle, taille, finition, sens et place.
class HandleChoice {
  String kind; // rendu
  String? id;
  int? size;
  String? finish;
  String orient; // 'auto' | 'v' (verticale) | 'h' (horizontale)
  String pos; // 'auto' (près du bord) | 'centre'
  bool pair; // deux poignées sur les tiroirs larges (800 mm et plus)
  HandleChoice({this.kind = 'bar', this.id, this.size, this.finish, this.orient = 'auto', this.pos = 'auto', this.pair = false});

  HandleChoice copy() => HandleChoice.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'k': kind,
        if (id != null) 'id': id,
        if (size != null) 's': size,
        if (finish != null) 'f': finish,
        if (orient != 'auto') 'o': orient,
        if (pos != 'auto') 'p': pos,
        if (pair) 'x2': true,
      };

  factory HandleChoice.fromJson(Map<String, dynamic> j) => HandleChoice(
        kind: j['k'] as String? ?? 'bar',
        id: j['id'] as String?,
        size: (j['s'] as num?)?.toInt(),
        finish: j['f'] as String?,
        orient: j['o'] as String? ?? 'auto',
        pos: j['p'] as String? ?? 'auto',
        pair: j['x2'] == true,
      );
}

class HandleModel {
  final String id;
  final String name;
  final String familyId;
  final String familyName;
  final HandleRender render;
  final List<int> sizes; // entraxes, longueurs ou diamètres proposés (mm)
  final String sizeLabel; // « Entraxe », « Longueur », « Diamètre »
  final List<String> finishes;
  final PriceRange price; // par poignée, par barre de 3 m ([perBar]) ou usinage par porte ([perDoorMilling])
  final bool perBar;
  final bool perDoorMilling;
  final int holes; // perçages par poignée
  final double? holeDiameter;
  final String? routing; // usinage CNC (cuvettes, gorges)
  final int? projection;

  const HandleModel({
    required this.id,
    required this.name,
    required this.familyId,
    required this.familyName,
    required this.render,
    this.sizes = const [],
    this.sizeLabel = 'Entraxe',
    this.finishes = const [],
    this.price = PriceRange.zero,
    this.perBar = false,
    this.perDoorMilling = false,
    this.holes = 0,
    this.holeDiameter,
    this.routing,
    this.projection,
  });

  int get defaultSize {
    if (sizes.isEmpty) return 0;
    for (final pref in [160, 128, 29, 25, 300, 1200]) {
      if (sizes.contains(pref)) return pref;
    }
    return sizes[sizes.length ~/ 2];
  }

  /// Perçage / usinage à indiquer à l'atelier.
  String drillingText(int size) {
    if (routing != null) return routing!;
    if (holes == 2) return '2 perçages Ø${_n(holeDiameter ?? 4.5)} traversants, entraxe $size mm';
    if (holes == 1) return '1 perçage Ø${_n(holeDiameter ?? 4.5)} traversant';
    return '';
  }

  static String _n(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v'.replaceAll('.', ',');
}

class HandleCatalog {
  final List<HandleModel> items;
  final List<int> screwLengths;
  const HandleCatalog(this.items, [this.screwLengths = const []]);

  /// Sans poignée (profil Gola), toujours proposé en plus du catalogue.
  static const gola = HandleModel(
      id: 'gola', name: 'Sans poignée (profil Gola)', familyId: 'gola', familyName: 'Sans poignée', render: HandleRender.gola, finishes: golaFinishes);

  /// Couleurs du profil Gola (la dernière suit la façade).
  static const golaFinishes = ['Aluminium', 'Inox brossé', 'Noir mat', 'Anthracite', 'Blanc', 'Champagne', 'Or brossé', 'Bronze', golaLikeFront];
  static const golaLikeFront = 'Comme les façades';

  /// Sans poignée : ouverture par pression (loqueteau), la façade reste lisse.
  static const push = HandleModel(id: 'push', name: 'Sans poignée (ouverture par pression)', familyId: 'gola', familyName: 'Sans poignée', render: HandleRender.push);

  HandleModel? byId(String? id) => id == gola.id ? gola : id == push.id ? push : items.where((h) => h.id == id).firstOrNull;

  List<(String, String, List<HandleModel>)> get families {
    final out = <(String, String, List<HandleModel>)>[];
    for (final h in items) {
      final f = out.where((x) => x.$1 == h.familyId).firstOrNull;
      if (f == null) {
        out.add((h.familyId, h.familyName, [h]));
      } else {
        f.$3.add(h);
      }
    }
    out.add(('gola', 'Sans poignée', [gola, push]));
    return out;
  }

  static HandleCatalog parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final out = <HandleModel>[];
    for (final f in (j['handle_families'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final fid = f['family_id'] as String;
      final famDrill = (f['door_drilling'] as Map?)?.cast<String, dynamic>();
      for (final it in (f['items'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        final id = it['id'] as String;
        List<int> ints(Object? v) => v is List ? [for (final x in v) if (x is num) x.toInt()] : v is num ? [v.toInt()] : const [];
        var sizes = ints(it['standard_center_to_center_mm']);
        var label = 'Entraxe';
        if (sizes.isEmpty && it['center_to_center_mm'] != null) sizes = ints(it['center_to_center_mm']);
        if (sizes.isEmpty && it['available_lengths_mm'] != null) {
          sizes = ints(it['available_lengths_mm']);
          label = 'Longueur';
        }
        if (sizes.isEmpty && it['diameters_mm'] != null) {
          sizes = ints(it['diameters_mm']);
          label = 'Diamètre';
        }
        if (sizes.isEmpty && it['compatible_door_widths_mm'] != null) label = 'Largeur de porte';
        final render = switch (fid) {
          'knobs' => HandleRender.knob,
          'appliance_and_oversized_pulls' => HandleRender.xxl,
          _ => switch (id) {
              'edge_pull_individual_cut' => HandleRender.edge,
              'edge_pull_full_width_bar' => HandleRender.edgeFull,
              'edge_wrap_j_profile_edge' => HandleRender.jProfile,
              'flush_pull_rectangular_box' => HandleRender.recess,
              'flush_pull_circular_ring' => HandleRender.recessRound,
              'milled_j_pull_finger_groove' => HandleRender.groove,
              'milled_45_degree_chamfer' => HandleRender.chamfer,
              'milled_geometric_finger_pocket' => HandleRender.pocket,
              'cup_handle_shell_shaker' => HandleRender.cup,
              'leather_loop_pull' => HandleRender.leather,
              _ => HandleRender.bar,
            },
        };
        final drill = (it['door_drilling'] as Map?)?.cast<String, dynamic>() ?? famDrill;
        final perBar = it['pricing_mad_per_bar_3m'] != null;
        final milling = it['milling_cost_mad_per_door'] != null;
        final price = PriceRange.fromJson(it['pricing_mad_per_unit'] ?? it['pricing_mad_per_bar_3m'] ?? it['milling_cost_mad_per_door']) ?? PriceRange.zero;
        String? routing;
        if (it['routing_cutout_mm'] is Map) {
          final r = (it['routing_cutout_mm'] as Map).cast<String, dynamic>();
          routing = 'Défonçage CNC ${r['width']} x ${r['height']} mm, profondeur ${r['depth']} mm';
        } else if (it['routing_bore_diameter_mm'] != null) {
          routing = 'Lamage CNC Ø${it['routing_bore_diameter_mm']} mm, profondeur ${it['routing_depth_mm']} mm';
        } else if (it['milling_profile'] != null) {
          routing = 'Usinage CNC : ${it['milling_profile']}';
        } else if (it['screw_type'] != null || f['screw_type'] != null) {
          routing = 'Vissé sur le chant arrière (vis ${(it['screw_type'] ?? f['screw_type']).toString().replaceAll('wood_screw_', '').replaceAll('_countersunk', ' tête fraisée')})';
        }
        out.add(HandleModel(
          id: id,
          name: it['name'] as String? ?? id,
          familyId: fid,
          familyName: f['family_name'] as String? ?? fid,
          render: render,
          sizes: sizes,
          sizeLabel: label,
          finishes: [
            for (final x in [...(it['finishes'] as List? ?? const []), ...(it['leather_colors'] as List? ?? const [])]) '$x'
          ],
          price: price,
          perBar: perBar,
          perDoorMilling: milling,
          holes: (drill?['holes_count'] as num?)?.toInt() ?? 0,
          holeDiameter: (f['drilling_hole_diameter_mm'] as num?)?.toDouble() ?? 4.5,
          routing: routing,
          projection: (it['projection_depth_mm'] as num?)?.toInt(),
        ));
      }
    }
    final screws = ((j['standard_screws'] as Map?)?['lengths_mm'] as List? ?? const []).map((e) => (e as num).toInt()).toList();
    return HandleCatalog(out, screws);
  }
}
