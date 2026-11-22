/// Débit manuel (comme SketchCut) : on saisit la feuille, la méthode et la liste des pièces,
/// sans passer par la cuisine dessinée.
library;

import 'dart:convert';

import 'cutting.dart';
import 'stock.dart';

class ManualPart {
  int length, width, qty;
  bool rotate; // la pièce peut pivoter sur la feuille (sans fil)
  int edgeLong, edgeShort; // chants : 0, 1 ou 2 sur chaque dimension
  String desc;
  ManualPart({this.length = 0, this.width = 0, this.qty = 1, this.rotate = true, this.edgeLong = 0, this.edgeShort = 0, this.desc = ''});

  Map<String, dynamic> toJson() => {'l': length, 'w': width, 'q': qty, 'r': rotate, 'el': edgeLong, 'es': edgeShort, 'd': desc};
  factory ManualPart.fromJson(Map<String, dynamic> j) => ManualPart(
        length: (j['l'] as num?)?.toInt() ?? 0,
        width: (j['w'] as num?)?.toInt() ?? 0,
        qty: (j['q'] as num?)?.toInt() ?? 1,
        rotate: j['r'] as bool? ?? true,
        edgeLong: (j['el'] as num?)?.toInt() ?? 0,
        edgeShort: (j['es'] as num?)?.toInt() ?? 0,
        desc: j['d'] as String? ?? '',
      );
}

class ManualCut {
  String order;
  String material;
  int thickness;
  int sheetLength, sheetWidth, kerf, trim;
  int method; // 1 par longueur, 2 par largeur, 3 optimale
  /// Matière à fil ou à veinage (bois, marbre, décor) : aucune pièce ne pivote.
  bool grain;
  final List<ManualPart> parts;

  /// Chutes du stock au moment de la découpe validée (plan figé).
  List<StockPiece>? stockFrozen;

  ManualCut({
    this.order = 'Débit manuel',
    this.material = 'MDF 18',
    this.thickness = 18,
    this.sheetLength = 2800,
    this.sheetWidth = 2100,
    this.kerf = 4,
    this.trim = 4,
    this.method = 1,
    this.grain = false,
    List<ManualPart>? parts,
  }) : parts = parts ?? [];

  CutSettings get settings => CutSettings(
      sheetLength: sheetLength, sheetWidth: sheetWidth, kerf: kerf, trim: trim, method: method, machine: 'scie',
      carcassMaterial: material, carcassThickness: thickness, doorThickness: thickness, stockFrozen: stockFrozen);

  /// Pièces valides pour l'optimiseur (la rotation est coupée sur une matière à fil).
  List<CutPart> get cutParts => [
        for (final p in parts)
          if (p.length > 0 && p.width > 0 && p.qty > 0)
            // la longueur saisie reste la longueur de la pièce (sens du fil) ; chants rapportés aux côtés
            CutPart(material, p.desc.isEmpty ? 'Pièce' : p.desc, order, p.length, p.width, p.qty,
                canRotate: p.rotate && !grain,
                edgeLong: p.length >= p.width ? p.edgeLong : p.edgeShort,
                edgeShort: p.length >= p.width ? p.edgeShort : p.edgeLong),
      ];

  CutPlan plan() => nest(cutParts, settings);

  Map<String, dynamic> toJson() => {
        'order': order,
        'material': material,
        'thickness': thickness,
        'sheet_length': sheetLength,
        'sheet_width': sheetWidth,
        'kerf': kerf,
        'trim': trim,
        'method': method,
        'grain': grain,
        if (stockFrozen != null) 'stock_frozen': [for (final p in stockFrozen!) p.toJson()],
        'parts': [for (final p in parts) p.toJson()],
      };

  factory ManualCut.fromJson(Map<String, dynamic> j) {
    final d = ManualCut();
    int i(String k, int def) => (j[k] as num?)?.toInt() ?? def;
    return ManualCut(
      order: j['order'] as String? ?? d.order,
      material: j['material'] as String? ?? d.material,
      thickness: i('thickness', d.thickness),
      sheetLength: i('sheet_length', d.sheetLength),
      sheetWidth: i('sheet_width', d.sheetWidth),
      kerf: i('kerf', d.kerf),
      trim: i('trim', d.trim),
      method: i('method', d.method),
      grain: j['grain'] as bool? ?? false,
      parts: [for (final p in (j['parts'] as List? ?? const [])) ManualPart.fromJson((p as Map).cast<String, dynamic>())],
    )..stockFrozen = j['stock_frozen'] == null ? null : [for (final p in j['stock_frozen'] as List) StockPiece.fromJson((p as Map).cast<String, dynamic>())];
  }

  /// Lit un fichier SketchCut PRO (.sct, format V3.0) : feuille, méthode, trait, recoupe, pièces.
  factory ManualCut.fromSct(String text) {
    final lines = const LineSplitter().convert(text);
    final job = ManualCut();
    String at(int i) => i < lines.length ? lines[i].trim() : '';
    final sheet = RegExp(r'^(\d+)X(\d+)').firstMatch(at(2));
    if (sheet != null) {
      job.sheetLength = int.parse(sheet.group(1)!);
      job.sheetWidth = int.parse(sheet.group(2)!);
    }
    final m = RegExp(r'^(\d+)X(\d+)X(\d+)').firstMatch(at(3));
    if (m != null) {
      job.method = int.parse(m.group(1)!).clamp(1, 3);
      job.kerf = int.parse(m.group(2)!);
      job.trim = int.parse(m.group(3)!);
    }
    if (at(4).isNotEmpty) job.order = at(4);
    if (at(7).isNotEmpty) job.material = at(7);
    job.thickness = int.tryParse(at(8)) ?? job.thickness;
    final start = lines.indexWhere((l) => l.trim().startsWith('<Parts>'));
    if (start < 0) return job;
    final dims = RegExp(r'^(\d+)X(\d+)X(\d+)$');
    for (var i = start + 1; i < lines.length; i++) {
      final l = lines[i].trim();
      if (l.startsWith('<')) break; // fin de la liste des pièces
      final d = dims.firstMatch(l);
      if (d == null) continue;
      final edges = RegExp(r'^(\d)X(\d)').firstMatch(at(i + 1));
      final name = at(i + 2);
      job.parts.add(ManualPart(
        length: int.parse(d.group(1)!),
        width: int.parse(d.group(2)!),
        qty: int.parse(d.group(3)!),
        edgeLong: int.tryParse(edges?.group(1) ?? '') ?? 0,
        edgeShort: int.tryParse(edges?.group(2) ?? '') ?? 0,
        rotate: name.isEmpty || name[0] != '0',
        desc: name.length > 2 ? name.substring(2) : '',
      ));
      i += 2;
    }
    return job;
  }
}
