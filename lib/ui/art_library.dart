// Bibliothèque des meubles créés dans l'atelier : un meuble enregistré (ses panneaux, ramenés à l'origine)
// se réutilise dans l'atelier (insérer) et se pose comme objet dans les autres modes (cuisine, dressing,
// salle de bain, meuble TV, intérieur, buanderie), où il se dessine en 3D panneau par panneau.
// Gardée d'une session à l'autre, pour tous les projets.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart' show ChangeNotifier, Color;

import '../engine/engine.dart';
import 'web_io.dart';

/// Catégorie des objets de la bibliothèque dans le panneau Objets.
const libraryCategory = 'Ma bibliothèque';

class LibraryItem {
  final String id, name;
  final List<ArtPanel> panels; // coin bas avant gauche de l'ensemble en (0, 0, 0)
  const LibraryItem(this.id, this.name, this.panels);

  double _ext(double Function(ArtPanel) f) => panels.isEmpty ? 0 : panels.map(f).reduce(math.max);
  int get w => _ext((p) => p.right).round();
  int get h => _ext((p) => p.top).round();
  int get d => _ext((p) => p.back).round();

  /// Objet du catalogue correspondant (référence `lib:<id>`).
  CatalogObject get asObject => CatalogObject('lib:$id', name, libraryCategory, '', '', math.max(1, w), math.max(1, h), math.max(1, d), true);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'panels': [for (final p in panels) p.toJson()]};
  factory LibraryItem.fromJson(Map<String, dynamic> j) => LibraryItem('${j['id']}', '${j['name']}',
      [for (final p in (j['panels'] as List? ?? const [])) ArtPanel.fromJson((p as Map).cast<String, dynamic>())]);

  /// Copie des panneaux posée en (x, y, z), avec de nouveaux identifiants.
  List<ArtPanel> placedAt(double x, double y, double z, String Function() newId) => [
        for (final p in panels)
          p.copy(id: newId())
            ..x = p.x + x
            ..y = p.y + y
            ..z = p.z + z,
      ];
}

class ArtLibrary extends ChangeNotifier {
  ArtLibrary._();
  static final instance = ArtLibrary._();
  static const _key = 'kitchinox.library';

  final List<LibraryItem> items = [];
  List<CatalogObject>? _catalog; // catalogue d'objets partagé par tous les modes

  LibraryItem? byRef(String ref) => ref.startsWith('lib:') ? items.where((i) => 'lib:${i.id}' == ref).firstOrNull : null;

  void load() {
    items.clear();
    final raw = storeGet(_key);
    if (raw == null) return;
    try {
      items.addAll([for (final j in (jsonDecode(raw) as List)) LibraryItem.fromJson((j as Map).cast<String, dynamic>())]);
    } catch (_) {
      // bibliothèque illisible : vide
    }
    _sync();
  }

  /// Relie la bibliothèque au catalogue d'objets des modes : ses meubles y apparaissent.
  void attach(List<CatalogObject> catalog) {
    _catalog = catalog;
    _sync();
  }

  void _sync() {
    final c = _catalog;
    if (c != null) {
      c.removeWhere((o) => o.id.startsWith('lib:'));
      c.addAll(items.map((i) => i.asObject));
    }
    for (final i in items) {
      CatalogObject.byId['lib:${i.id}'] = i.asObject;
    }
  }

  bool _save() {
    final ok = storeSet(_key, jsonEncode([for (final i in items) i.toJson()]));
    _sync();
    notifyListeners();
    return ok;
  }

  /// Enregistre [panels] sous [name] (ramenés à l'origine) ; renvoie l'élément créé.
  LibraryItem add(String name, List<ArtPanel> panels) {
    final x0 = panels.map((p) => p.x).reduce(math.min), y0 = panels.map((p) => p.y).reduce(math.min), z0 = panels.map((p) => p.z).reduce(math.min);
    var k = 0;
    final item = LibraryItem(
      '${DateTime.now().millisecondsSinceEpoch}',
      name.trim().isEmpty ? 'Meuble' : name.trim(),
      [
        for (final p in panels)
          p.copy(id: 'l${k++}')
            ..x = p.x - x0
            ..y = p.y - y0
            ..z = p.z - z0,
      ],
    );
    items.add(item);
    _save();
    return item;
  }

  void remove(String id) {
    items.removeWhere((i) => i.id == id);
    _catalog?.removeWhere((o) => o.id == 'lib:$id');
    _save();
  }

  /// Panneaux d'un objet posé (repère local de l'objet : x de -w/2 à w/2, y depuis le sol, z depuis le dos),
  /// mis aux cotes de l'objet s'il a été redimensionné. Pour la vue 3D.
  List<Map<String, Object>> panelsFor(RoomObject o, Color Function(String finish) color) {
    final it = byRef(o.ref);
    if (it == null) return const [];
    final sx = it.w == 0 ? 1.0 : o.w / it.w, sy = it.h == 0 ? 1.0 : o.h / it.h, sz = it.d == 0 ? 1.0 : o.d / it.d;
    return [
      for (final p in it.panels)
        {
          'x0': p.x * sx - o.w / 2,
          'x1': p.right * sx - o.w / 2,
          'y0': p.y * sy,
          'y1': p.top * sy,
          // l'atelier compte z depuis l'avant ; l'objet, depuis le dos (contre le mur)
          'z0': o.d - p.back * sz,
          'z1': o.d - p.z * sz,
          'color': color(p.finish).toARGB32() & 0xFFFFFF,
        },
    ];
  }
}
