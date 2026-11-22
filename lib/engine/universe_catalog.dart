/// Catalogue du planificateur pour un autre univers (dressing, bain, tv, intérieur) : chaque module de
/// assets/data/furniture/*.json devient un modèle de caisson (bas, suspendu ou colonne), avec ses tailles,
/// sa composition de façade et sa hauteur de pose. Le planificateur de la cuisine sert alors tel quel
/// (pièce, implantation, plan, vue de face, 3D, style, récapitulatif, débit).
library;

import 'catalog.dart';
import 'furniture.dart';

/// Rangement du module : 'base' (posé au sol, bas), 'wall' (suspendu), 'tall' (colonne / grand meuble).
String universeShelf(FurnitureModel m) {
  final s = m.setup;
  final h = m.heights.reduce((a, b) => a > b ? a : b);
  if (s.wallHung) return 'wall';
  if (s.panel || h >= 1400) return 'tall';
  return 'base';
}

/// Composition de façade (du haut vers le bas) tirée de la composition du module.
List<Map<String, dynamic>> universeFrontLayout(FurnitureSetup s) {
  final rows = <Map<String, dynamic>>[];
  if (s.rows.isNotEmpty) return s.rows;
  if (s.panel) return [{'k': 'panel', 'h': 0}];
  for (var i = 0; i < s.flaps; i++) {
    rows.add({'k': 'flap', 'h': 0});
  }
  if (s.flaps == 0) {
    if (s.doors == 0 || s.open) {
      if (s.drawers == 0 || s.shelves > 0 || s.rods > 0) rows.add({'k': 'niche', 'h': 0});
    } else {
      rows.add({'k': s.glass ? 'glass' : (s.doors >= 2 ? 'door2' : 'door'), 'h': 0});
    }
  }
  for (var i = 0; i < s.drawers; i++) {
    rows.add({'k': 'drawer', 'h': s.drawerFront});
  }
  if (rows.isEmpty) rows.add({'k': 'niche', 'h': 0});
  return rows;
}

/// Catalogue (format assets/catalog.json) d'un univers.
Map<String, dynamic> universeCatalogJson(FurnitureUniverse u) {
  final shelves = <String, List<Map<String, dynamic>>>{'base': [], 'wall': [], 'tall': [], 'corner': []};
  final tallHeights = {for (final m in u.models) if (universeShelf(m) == 'tall') ...m.heights}.toList()..sort();
  for (final m in u.models) {
    // dressing d'angle (en L, pan coupé) : un vrai meuble d'angle, aux deux bras
    if (m.setup.shape == 'L' || m.setup.shape == 'diagonal') {
      shelves['corner']!.add({
        'id': m.id,
        'name': m.name,
        if (m.setup.shape == 'L') ...{'width_left': m.widths, 'width_right': m.widths.first} else 'footprint': '${m.widths.first}x${m.widths.first}',
        'available_heights': tallHeights.isEmpty ? m.heights : tallHeights,
        'depth': m.depths.first,
        'door_type': m.setup.shape == 'L' ? 'bifold_corner_door' : 'single_door',
        'snapping': const {'corner_anchor': 'inner_90', 'floor_support': true},
      });
      continue;
    }
    final shelf = universeShelf(m);
    final heights = m.heights;
    shelves[shelf]!.add({
      'id': m.id,
      'name': m.name,
      'available_widths': m.widths,
      if (shelf == 'base') ...{'available_heights': heights, 'free_height': true} else 'available_heights': heights,
      'depth': m.depths.first,
      'front_layout': universeFrontLayout(m.setup),
      if (m.setup.wallHung) 'mount_z': m.setup.z,
      if (m.setup.floor) 'mount_z': 0,
      if (m.setup.doors > 0) 'opening_options': const ['hinged_left', 'hinged_right'],
      'description': m.category.isEmpty ? null : m.category,
      'snapping': {'requires_wall': true, 'floor_support': shelf != 'wall' && !m.setup.floor},
    });
  }
  const names = {
    'base': 'Meubles bas (posés au sol)',
    'wall': 'Meubles suspendus',
    'tall': 'Colonnes et grands meubles',
    'corner': 'Meubles d’angle',
  };
  const ids = {'base': 'base_cabinets', 'wall': 'wall_cabinets', 'tall': 'tall_cabinets', 'corner': 'corner_tall_cabinets'};
  return {
    'system': u.id,
    'unit_metric': 'mm',
    'categories': [
      for (final e in shelves.entries)
        if (e.value.isNotEmpty) {'id': ids[e.key], 'name': names[e.key], 'items': e.value},
    ],
  };
}

Catalog universeCatalog(FurnitureUniverse u) => Catalog.fromJson(universeCatalogJson(u));
