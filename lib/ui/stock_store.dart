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
  static const _cols = ['Référence', 'Panneau', 'Épaisseur', 'Longueur', 'Largeur', 'Quantité', 'Chute', 'Emplacement', 'Origine', 'Réservé pour', 'Date'];

  /// Stock en classeur Excel (une ligne par chute ou par lot de feuilles).
  Uint8List exportXlsx() => xlsxTable('Stock', [
        _cols,
        for (final p in stock.pieces) [p.id, p.material, p.thickness, p.length, p.width, p.qty, p.offcut ? 'oui' : 'non', p.place, p.origin, p.reserved, p.date],
      ], widths: const [12, 28, 10, 10, 10, 10, 8, 18, 22, 22, 12]);

  /// Remplace les feuilles et les chutes par celles du classeur ; faux si ce n'est pas un stock kitchinox.
  bool importXlsx(List<int> bytes) {
    final rows = readXlsx(bytes)?.firstOrNull?.$2;
    if (rows == null || rows.isEmpty || rows.first.length < 6 || rows.first[0] != _cols[0] || rows.first[1] != _cols[1]) return false;
    final pieces = <Map<String, dynamic>>[];
    for (final r in rows.skip(1)) {
      String at(int i) => i < r.length ? r[i].trim() : '';
      int? n(int i) => double.tryParse(at(i).replaceAll(',', '.'))?.round();
      if (at(1).isEmpty) continue;
      if (n(2) == null || n(3) == null || n(4) == null) return false;
      pieces.add({
        'id': at(0).isEmpty ? 'X-${pieces.length + 1}' : at(0), 'm': at(1), 't': n(2), 'l': n(3), 'w': n(4), 'q': n(5) ?? 1,
        if (at(6).toLowerCase() == 'non') 'sheet': true, 'place': at(7), 'from': at(8), 'for': at(9), 'date': at(10),
      });
    }
    return import(jsonEncode({...stock.toJson(), 'pieces': pieces}));
  }

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
