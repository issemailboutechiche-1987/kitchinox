// Mode AR « Voir dans ma pièce » : la cuisine (ou ses réseaux) projetée à l'échelle 1:1 dans la pièce réelle,
// par AR Quick Look de l'iPad / iPhone. La vue 3D fabrique un paquet USDZ (web/ar_export.js) ;
// ce fichier en est le contrat côté Flutter : options, statistiques, préparation et ouverture.
//
// Repère : l'origine du plan (coin des murs A et C, ou premier point du contour) porte un L rouge au sol.
// On pose ce L sur le vrai coin de la pièce : tout le reste tombe à sa place.
//
// Ouverture : Safari n'ouvre Quick Look que pendant un geste. On prépare d'abord (asynchrone),
// puis openArPackage() est appelé directement dans onPressed, sans await avant.

import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ar_page.dart';
import 'scene_export.dart' show netsSceneData;
import 'view3d_stub.dart'
    if (dart.library.js_interop) 'view3d_web.dart'
    if (dart.library.io) 'view3d_native.dart';

export 'view3d_stub.dart'
    if (dart.library.js_interop) 'view3d_web.dart'
    if (dart.library.io) 'view3d_native.dart' show arQuickLookAvailable, openArPackage;

/// Ce qui part dans la pièce réelle.
class ArOptions {
  final bool kitchen; // meubles, plans, crédence, électroménager, objets
  final bool walls; // murs, portes et fenêtres en fantôme translucide
  final bool nets; // conduits électriques, eau, évacuation, gaz et tableau
  final bool marker; // L rouge du coin de la pièce
  final int maxTexture; // côté maximal des textures (px)
  final int maxVertices; // budget de sommets du paquet
  const ArOptions({this.kitchen = true, this.walls = false, this.nets = false, this.marker = true, this.maxTexture = 1024, this.maxVertices = 1500000});

  ArOptions copyWith({bool? kitchen, bool? walls, bool? nets, bool? marker}) => ArOptions(
        kitchen: kitchen ?? this.kitchen,
        walls: walls ?? this.walls,
        nets: nets ?? this.nets,
        marker: marker ?? this.marker,
        maxTexture: maxTexture,
        maxVertices: maxVertices,
      );

  bool get isEmpty => !kitchen && !walls && !nets;

  /// Options envoyées à la vue 3D (kitchen3d.arPrepare).
  String toJson(AppState st) => jsonEncode({
        'kitchen': kitchen,
        'walls': walls,
        'nets': nets && st.project.points.isNotEmpty ? netsSceneData(st.project) : null,
        'marker': marker,
        'maxTexture': maxTexture,
        'maxVertices': maxVertices,
      });
}

/// Ce que contient le paquet préparé.
class ArStats {
  final int meshes, vertices, materials, textures, dropped, size;
  final bool quickLook; // l'appareil l'ouvre en AR (sinon : téléchargement du fichier)
  const ArStats({this.meshes = 0, this.vertices = 0, this.materials = 0, this.textures = 0, this.dropped = 0, this.size = 0, this.quickLook = false});

  factory ArStats.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return ArStats(
      meshes: n('meshes'),
      vertices: n('vertices'),
      materials: n('materials'),
      textures: n('textures'),
      dropped: n('dropped'),
      size: n('size'),
      quickLook: j['quickLook'] as bool? ?? false,
    );
  }

  String get sizeText => size >= 1 << 20 ? '${(size / (1 << 20)).toStringAsFixed(1)} Mo' : '${(size / 1024).ceil()} Ko';
}

/// Prépare le paquet de la vue 3D affichée ; null si elle n'est pas ouverte ou si l'export échoue.
Future<ArStats?> prepareAr(AppState st, ArOptions o) async {
  if (o.isEmpty) return null;
  final r = await prepareArPackage(o.toJson(st));
  if (r == null) return null;
  return ArStats.fromJson((jsonDecode(r) as Map).cast<String, dynamic>());
}

/// Ouvre l'écran du mode AR (voir docs/ar/MISSION_ANTIGRAVITY.md).
Future<void> showArSheet(BuildContext context, AppState st) => showArPageDialog(context, st);

