/// Modèles de façade et formes d'îlot.
library;

import 'layout_engine.dart';
import 'project.dart';

/// Modèles de façade : nom et largeur du cadre (mm).
const frontProfiles = <String, (String, double)>{
  'lisse': ('Lisse', 0),
  'shaker': ('À cadre (shaker)', 70),
  'shaker_fin': ('Cadre fin', 25),
  'mouluree': ('Moulurée classique', 75),
  'cannelee': ('Cannelée', 0),
};

/// Cadre d'une façade de [w] × [h] mm : 0 si elle est trop petite pour en recevoir un.
double profileFrame(String profile, double w, double h) {
  final f = frontProfiles[profile]?.$2 ?? 0;
  if (f == 0 || h < 130 || w < 150) return 0;
  // tiroirs bas : cadre réduit, il reste un panneau au centre
  final most = (h < w ? h : w) * 0.26;
  return f < most ? f : most;
}

bool framedProfile(String p) => (frontProfiles[p]?.$2 ?? 0) > 0;

/// Formes d'îlot : nom, débord repas (mm), jambages.
const islandPresets = <String, (String, String)>{
  'tiroirs': ('Îlot à tiroirs', 'Tiroirs sur toute la longueur, façades vers la salle'),
  'repas': ('Îlot repas', 'Débord de 350 mm pour les tabourets, 60 cm par personne'),
  'cascade': ('Îlot cascade', 'Le plan descend jusqu’au sol des deux côtés'),
  'cuisson': ('Îlot de cuisson', 'Plaque et four sur l’îlot, tiroirs de part et d’autre'),
  'lavage': ('Îlot évier', 'Évier sur l’îlot, portes et tiroirs'),
  'bistrot': ('Îlot bistrot', 'Dos à cadres, vitrines de rangement et débord repas'),
};

/// Compose l'îlot du projet (créé s'il n'y en a pas). Renvoie faux s'il n'y a pas la place.
bool applyIslandPreset(LayoutEngine e, String id) {
  final p = e.project;
  if (p.room.island == null) {
    final spot = e.bestIslandSpot();
    if (spot == null) return false;
    p.room.island = spot;
  }
  final isl = p.room.island!;
  final st = p.style;
  // pas de débord : l'îlot garde sa place, la profondeur change d'abord
  final want = switch (id) { 'repas' || 'bistrot' => 350.0, 'tiroirs' => 0.0, _ => isl.overhang.clamp(0.0, 300.0) };
  if (isl.y0 + Island.depth + want <= p.room.depth - 800 || want <= isl.overhang) isl.overhang = want;
  // vers la salle : le dos au mur le plus meublé (fond ou avant)
  double load(String w) => p.items.where((c) => c.wallId == w).fold<double>(0, (a, c) => a + c.width);
  isl.flip = id == 'tiroirs' && load('A') >= load('D');
  st.islandWaterfall = id == 'cascade';
  st.islandBack = id == 'bistrot' ? 'cadre' : (id == 'cascade' ? 'cannele' : 'lisse');
  p.items.removeWhere((c) => c.wallId == 'I');
  double s = 0;
  final len = isl.length;
  bool add(String model, int w) {
    final m = e.catalog.tryGet(model);
    if (m == null || s + w > len + 0.5) return false;
    try {
      final c = e.add(model, 'I', s: s, width: m.widths.nearest(w));
      s = c.right;
      return true;
    } on PlacementException {
      return false;
    }
  }

  // module central éventuel, encadré de tiroirs ou de portes
  final (String, int)? center = switch (id) {
    'cuisson' => ('base_cooktop_oven', 600),
    'lavage' => ('base_sink', 800),
    _ => null,
  };
  final fill = id == 'bistrot' ? 'base_standard_2doors' : 'base_drawers_multi';
  List<int> split(double space) {
    final m = e.catalog.tryGet(fill) ?? e.catalog['base_standard_single_door'];
    final ws = [...m.widths.values]..sort();
    return LayoutEngine.bestModules(space, ws);
  }

  if (center != null && len >= center.$2 + 400) {
    final side = (len - center.$2) / 2;
    for (final w in split(side)) {
      add(fill, w);
    }
    add(center.$1, center.$2);
    for (final w in split(len - s)) {
      add(fill, w);
    }
  } else {
    for (final w in split(len)) {
      add(fill, w);
    }
  }
  if (p.items.where((c) => c.wallId == 'I').isEmpty) e.autoFillWall('I', Band.low);
  return true;
}
