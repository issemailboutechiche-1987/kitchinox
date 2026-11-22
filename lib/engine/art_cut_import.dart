// Fichier de débit importé dans le mode Art : une pièce par ligne (CSV « nom ; longueur ; largeur ; quantité ; épaisseur »)
// ou JSON (liste de pièces, débit manuel kitchinox). Les pièces se posent à plat, en rangées, prêtes à être liées.
import 'dart:convert';
import 'dart:math' as math;

import 'art.dart';

class CutFilePart {
  final String name;
  final double length, width, thickness;
  final int qty;
  const CutFilePart(this.name, this.length, this.width, {this.qty = 1, this.thickness = 18});
}

double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.trim().replaceAll(',', '.'));

/// Lit un fichier de débit : CSV (séparateur ; , ou tabulation, en-tête facultatif) ou JSON.
List<CutFilePart> parseCutFile(String text) {
  final t = text.trim();
  if (t.isEmpty) return const [];
  if (t.startsWith('{') || t.startsWith('[')) {
    try {
      final j = jsonDecode(t);
      final list = j is List ? j : (j is Map ? (j['parts'] ?? j['pieces'] ?? (j['manual_cut'] is Map ? j['manual_cut']['parts'] : null)) : null);
      if (list is! List) return const [];
      return [
        for (final e in list.whereType<Map>())
          if ((_num(e['length'] ?? e['l'] ?? e['longueur']) ?? 0) > 0 && (_num(e['width'] ?? e['w'] ?? e['largeur']) ?? 0) > 0)
            CutFilePart(
              '${e['name'] ?? e['d'] ?? e['desc'] ?? e['nom'] ?? 'Pièce'}',
              _num(e['length'] ?? e['l'] ?? e['longueur'])!,
              _num(e['width'] ?? e['w'] ?? e['largeur'])!,
              qty: (_num(e['qty'] ?? e['q'] ?? e['quantite']) ?? 1).round().clamp(1, 200),
              thickness: _num(e['thickness'] ?? e['t'] ?? e['epaisseur']) ?? 18,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
  final out = <CutFilePart>[];
  for (final raw in const LineSplitter().convert(t)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final sep = line.contains(';') ? ';' : line.contains('\t') ? '\t' : ',';
    final cells = [for (final c in line.split(sep)) c.trim().replaceAll('"', '')];
    // repère le 1er nombre : ce qui précède est le nom
    final firstNum = cells.indexWhere((c) => _num(c) != null);
    if (firstNum < 0 || cells.length < firstNum + 2) continue; // en-tête ou ligne vide
    final l = _num(cells[firstNum]), w = _num(cells[firstNum + 1]);
    if (l == null || w == null || l <= 0 || w <= 0) continue;
    final q = cells.length > firstNum + 2 ? _num(cells[firstNum + 2]) : null;
    final th = cells.length > firstNum + 3 ? _num(cells[firstNum + 3]) : null;
    final name = firstNum > 0 ? cells.sublist(0, firstNum).join(' ') : 'Pièce ${out.length + 1}';
    out.add(CutFilePart(name.isEmpty ? 'Pièce ${out.length + 1}' : name, l, w, qty: (q ?? 1).round().clamp(1, 200), thickness: th ?? 18));
  }
  return out;
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
