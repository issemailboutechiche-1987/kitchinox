// Meubles favoris (étoile) : catalogue de la cuisine et des univers, meubles et recettes du mode Art.
// Gardés sur l'appareil ; les favoris passent en tête des listes et ont leur filtre.
import 'dart:convert';

import 'package:flutter/material.dart';

import 'i18n.dart';
import 'web_io.dart';

class Favorites extends ChangeNotifier {
  Favorites._() {
    try {
      final raw = storeGet(_key);
      if (raw != null) _ids.addAll((jsonDecode(raw) as List).map((e) => '$e'));
    } catch (_) {
      // copie illisible : on repart sans favoris
    }
  }
  static final instance = Favorites._();
  static const _key = 'favorites_v1';
  final Set<String> _ids = {};

  /// [id] : « cuisine:base_standard_single_door », « art:preset:Caisson bas de cuisine », « art:recipe:bas_1p »…
  bool has(String id) => _ids.contains(id);

  void toggle(String id) {
    if (!_ids.remove(id)) _ids.add(id);
    storeSet(_key, jsonEncode(_ids.toList()));
    notifyListeners();
  }

  /// Favoris d'abord, l'ordre d'origine ensuite.
  List<T> sorted<T>(List<T> list, String Function(T) idOf) => [...list.where((x) => has(idOf(x))), ...list.where((x) => !has(idOf(x)))];
}

/// Étoile à toucher pour mettre (ou retirer) un meuble en favori.
class FavoriteStar extends StatelessWidget {
  final String id;
  final double size;
  const FavoriteStar({super.key, required this.id, this.size = 22});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Favorites.instance,
        builder: (context, _) {
          final on = Favorites.instance.has(id);
          return IconButton(
            key: ValueKey('fav_$id'),
            visualDensity: VisualDensity.compact,
            tooltip: on ? tr('Retirer des favoris') : tr('Ajouter aux favoris'),
            icon: Icon(on ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: on ? const Color(0xFFF5A524) : null),
            onPressed: () => Favorites.instance.toggle(id),
          );
        },
      );
}
