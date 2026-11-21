// Accessoires de meubles (range-épices, casseroliers, poubelles, penderies, poignées, pieds)
// choisis à la quantité et ajoutés à l'estimation. Prix publics relevés au Maroc (fourchettes).
import 'dart:convert';

import 'materials.dart';

class FurnitureAccessory {
  final String id, name, category;
  final int? width;
  final PriceRange price;
  const FurnitureAccessory(this.id, this.name, this.category, this.price, {this.width});
}

class FurnitureAccessoryCategory {
  final String id, name;
  final List<FurnitureAccessory> items;
  const FurnitureAccessoryCategory(this.id, this.name, this.items);
}

class FurnitureAccessories {
  static List<FurnitureAccessoryCategory> categories = const [];
  static String source = '';
  static final Map<String, FurnitureAccessory> byId = {};

  static void parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    source = j['source'] as String? ?? '';
    byId.clear();
    categories = [
      for (final c in (j['categories'] as List).cast<Map<String, dynamic>>())
        FurnitureAccessoryCategory(c['id'] as String, c['name'] as String, [
          for (final it in (c['items'] as List).cast<Map<String, dynamic>>())
            byId[it['id'] as String] = FurnitureAccessory(
              it['id'] as String,
              it['name'] as String,
              c['name'] as String,
              PriceRange((it['min'] as num).toDouble(), (it['max'] as num).toDouble()),
              width: it['width'] as int?,
            ),
        ]),
    ];
  }
}

/// Lignes d'estimation des accessoires choisis (id → quantité).
List<SupplyLine> furnitureAccessoryLines(Map<String, int> chosen) => [
      for (final e in chosen.entries)
        if (e.value > 0 && FurnitureAccessories.byId[e.key] != null)
          SupplyLine('Accessoires', FurnitureAccessories.byId[e.key]!.name, FurnitureAccessories.byId[e.key]!.category, e.value.toDouble(), 'pce',
              FurnitureAccessories.byId[e.key]!.price),
    ];
