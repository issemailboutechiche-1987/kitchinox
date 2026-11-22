// Stock de l'atelier gardé sur l'appareil, commun à tous les projets. Chaque changement est enregistré aussitôt
// et les débits affichés se recalculent avec les chutes disponibles.
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'web_io.dart';

class StockStore extends ChangeNotifier {
  StockStore._();
  static final instance = StockStore._();
  static const _key = 'kitchinox.stock';

  final Stock stock = Stock();

  /// Projet ouvert : les chutes gardées pour un autre ne lui sont pas offertes.
  String Function() currentProject = () => '';

  /// Nom d'un projet dans le stock (« Cuisine · Client »).
  static String labelOf(Project p) => [p.name, if (p.client.label.isNotEmpty) p.client.label].join(' · ');

  /// Copie illisible : elle est gardée de côté au lieu d'être écrasée.
  bool unreadable = false;

  void load() {
    final raw = storeGet(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      stock.load(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      unreadable = true;
      storeSet('$_key.illisible', raw);
    }
  }

  AppState? _active;

  /// Branche le stock sur le débit de l'espace ouvert (cuisine, dressing…).
  void attach(AppState state) {
    if (_active == null) addListener(() => _active?.stockChanged());
    _active = state;
    currentProject = () => labelOf(state.project);
    stockSource = () => stock.availableFor(currentProject());
  }

  /// Modifie le stock et l'enregistre. Faux si l'appareil n'a pas pu l'écrire.
  bool update(void Function(Stock s) change) {
    change(stock);
    final ok = storeSet(_key, jsonEncode(stock.toJson()));
    notifyListeners();
    return ok;
  }

  /// Fichier d'échange (autre tablette, PC, copie de sécurité).
  String export() => const JsonEncoder.withIndent(' ').convert(stock.toJson());

  /// Remplace le stock par celui du fichier ; faux si ce n'est pas un fichier de stock.
  bool import(String text) {
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (j['kind'] != 'kitchinox_stock') return false;
      Stock().load(j); // lecture d'essai : un fichier abîmé ne vide pas le stock
      return update((s) => s.load(j));
    } catch (_) {
      return false;
    }
  }
}

/// Date du jour, AAAA-MM-JJ.
String stockToday() => DateTime.now().toIso8601String().substring(0, 10);
