// Fichier de débit (.sct, Excel) importé dans le mode Art : les pièces se posent à plat, en rangées, prêtes à être liées.
import 'dart:math' as math;

import 'art.dart';

class CutFilePart {
  final String name;
  final double length, width, thickness;
  final int qty;
  const CutFilePart(this.name, this.length, this.width, {this.qty = 1, this.thickness = 18});
}

/// Pose les pièces à plat (épaisseur en hauteur), en rangées de 5 m au plus, 50 mm entre elles.
List<ArtPanel> layoutCutParts(List<CutFilePart> parts, {double x0 = 0, required String Function() newId, String? material}) {
  const gap = 50.0, rowMax = 5000.0;
  final out = <ArtPanel>[];
  var x = x0, z = 0.0, rowDepth = 0.0;
  for (final p in parts) {
    for (var k = 0; k < p.qty; k++) {
      final l = math.max(p.length, p.width), w = math.min(p.length, p.width);
      if (x > x0 && x + l > x0 + rowMax) {
        x = x0;
        z += rowDepth + gap;
        rowDepth = 0;
      }
      out.add(ArtPanel(id: newId(), role: ArtRole.decor, x: x, y: 0, z: z, w: l, h: p.thickness, d: w, material: material, finish: 'blanc', note: p.name));
      x += l + gap;
      rowDepth = math.max(rowDepth, w);
    }
  }
  return out;
}
