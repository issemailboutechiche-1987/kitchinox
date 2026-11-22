/// Stock de l'atelier : feuilles entières et chutes réutilisables.
/// Le débit se sert dans les chutes avant d'ouvrir une feuille neuve ; une découpe validée retire du stock ce
/// qu'elle a utilisé et y range ses propres chutes.
library;

import 'dart:math' as math;

import 'cutting.dart';

/// Nom de panneau comparable : « MDF (façades) », « MDF 18 (caisson) » et « MDF 18 mm » désignent le même panneau.
String stockMaterial(String material) {
  var m = material.toLowerCase();
  m = m.replaceAll(RegExp(r'\d{3,4}\s*[x×]\s*\d{3,4}'), ' ');
  m = m.replaceAll(RegExp(r'\((façades?|caissons?|fonds?)\)'), ' ');
  m = m.replaceAll(RegExp(r'(?<![\d.,])\d{1,2}\s*mm\b'), ' ');
  m = m.replaceAll('·', ' ').replaceAll(RegExp(r'\(\s*\)'), ' ').trim();
  m = m.replaceAll(RegExp(r'\s\d{1,2}$'), '');
  return m.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Feuille entière ou chute rangée à l'atelier.
class StockPiece {
  final String id; // C-0012 (chute), F-0003 (feuilles)
  String material;
  int thickness;
  int length, width; // [length] : dans le sens de la longueur de la feuille d'origine (sens du fil)
  int qty;
  bool offcut;
  String place; // emplacement : rayon, mur…
  String origin; // projet d'où vient la chute
  String reserved; // projet pour lequel elle est gardée ('' : libre)
  String date; // AAAA-MM-JJ
  StockPiece({
    required this.id,
    required this.material,
    required this.thickness,
    required this.length,
    required this.width,
    this.qty = 1,
    this.offcut = true,
    this.place = '',
    this.origin = '',
    this.reserved = '',
    this.date = '',
  });

  double get area => length * width / 1e6 * qty;

  bool matches(String mat, int t) => thickness == t && stockMaterial(material) == stockMaterial(mat);

  StockPiece copy() => StockPiece.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'm': material,
        't': thickness,
        'l': length,
        'w': width,
        if (qty != 1) 'q': qty,
        if (!offcut) 'sheet': true,
        if (place.isNotEmpty) 'place': place,
        if (origin.isNotEmpty) 'from': origin,
        if (reserved.isNotEmpty) 'for': reserved,
        if (date.isNotEmpty) 'date': date,
      };

  factory StockPiece.fromJson(Map<String, dynamic> j) => StockPiece(
        id: '${j['id']}',
        material: '${j['m']}',
        thickness: (j['t'] as num).toInt(),
        length: (j['l'] as num).toInt(),
        width: (j['w'] as num).toInt(),
        qty: (j['q'] as num?)?.toInt() ?? 1,
        offcut: j['sheet'] != true,
        place: j['place'] as String? ?? '',
        origin: j['from'] as String? ?? '',
        reserved: j['for'] as String? ?? '',
        date: j['date'] as String? ?? '',
      );

  /// Texte du code QR de l'étiquette.
  String get qr => 'KXS1|$id|$material|$thickness|${length}x$width';

  /// Numéro lu dans un code QR d'étiquette, ou le texte tel quel.
  static String idFromScan(String text) {
    final p = text.trim().split('|');
    return p.length > 1 && p.first == 'KXS1' ? p[1].trim() : text.trim();
  }
}

/// Mouvement de stock : une découpe validée, annulable.
class StockMove {
  final String id, project, date;
  final List<StockPiece> taken; // chutes utilisées et feuilles prises (avec leur quantité)
  final List<StockPiece> added; // chutes rangées
  final int bought; // feuilles neuves achetées pour cette découpe
  bool undone;
  StockMove(this.id, this.project, this.date, this.taken, this.added, {this.bought = 0, this.undone = false});

  Map<String, dynamic> toJson() => {
        'id': id,
        'project': project,
        'date': date,
        'taken': [for (final p in taken) p.toJson()],
        'added': [for (final p in added) p.toJson()],
        'bought': bought,
        if (undone) 'undone': true,
      };

  static List<StockPiece> _list(Object? v) => [for (final x in (v as List? ?? const [])) StockPiece.fromJson((x as Map).cast<String, dynamic>())];

  factory StockMove.fromJson(Map<String, dynamic> j) => StockMove('${j['id']}', '${j['project']}', '${j['date']}', _list(j['taken']), _list(j['added']),
      bought: (j['bought'] as num?)?.toInt() ?? 0, undone: j['undone'] == true);
}

/// Feuilles neuves demandées par un plan, par panneau.
class SheetNeed {
  final String material;
  final int thickness, length, width;
  final int needed; // feuilles neuves du plan
  final int inStock; // dont disponibles à l'atelier
  const SheetNeed(this.material, this.thickness, this.length, this.width, this.needed, this.inStock);
  int get toBuy => math.max(0, needed - inStock);
}

/// Le stock de l'atelier (données ; l'écran et l'enregistrement sont dans l'interface).
class Stock {
  final List<StockPiece> pieces = [];
  final List<StockMove> moves = [];
  int nextOffcut = 1, nextSheet = 1, nextMove = 1;
  int minLength = 300, minWidth = 150; // chute gardée à partir de cette taille (grand côté, petit côté)

  List<StockPiece> get offcuts => [for (final p in pieces) if (p.offcut) p];
  List<StockPiece> get sheets => [for (final p in pieces) if (!p.offcut) p];

  StockPiece? byId(String id) {
    final k = id.toLowerCase();
    for (final p in pieces) {
      if (p.id.toLowerCase() == k) return p;
    }
    return null;
  }

  String _newId(bool offcut) {
    String id;
    do {
      id = offcut ? 'C-${'${nextOffcut++}'.padLeft(4, '0')}' : 'F-${'${nextSheet++}'.padLeft(4, '0')}';
    } while (byId(id) != null || moves.any((m) => m.added.any((p) => p.id == id)));
    return id;
  }

  /// Ajoute une pièce ; des feuilles entières identiques s'ajoutent à la pile existante.
  StockPiece add({
    required String material,
    required int thickness,
    required int length,
    required int width,
    int qty = 1,
    bool offcut = true,
    String place = '',
    String origin = '',
    String date = '',
  }) {
    if (!offcut) {
      for (final p in pieces) {
        if (!p.offcut && p.matches(material, thickness) && p.length == length && p.width == width && p.place == place) {
          p.qty += qty;
          return p;
        }
      }
    }
    final p = StockPiece(
        id: _newId(offcut), material: material, thickness: thickness, length: length, width: width, qty: offcut ? 1 : qty, offcut: offcut,
        place: place, origin: origin, date: date);
    pieces.add(p);
    return p;
  }

  /// Chutes utilisables par le projet [project] : libres, ou gardées pour lui.
  List<StockPiece> availableFor(String project) => [
        for (final p in pieces)
          if (p.offcut && (p.reserved.isEmpty || p.reserved == project)) p.copy(),
      ];

  /// Feuilles neuves du plan, celles qu'on a déjà, celles à acheter.
  List<SheetNeed> needs(CutPlan plan, {String project = ''}) {
    final out = <SheetNeed>[];
    final left = <String, int>{for (final p in pieces) if (!p.offcut && (p.reserved.isEmpty || p.reserved == project)) p.id: p.qty};
    final groups = <(String, int, int, int), int>{};
    for (final s in plan.sheets.where((s) => !s.fromStock)) {
      final k = (s.material, plan.settings.thicknessFor(s.material), s.length, s.width);
      groups[k] = (groups[k] ?? 0) + 1;
    }
    for (final e in groups.entries) {
      final (mat, t, l, w) = e.key;
      var have = 0;
      for (final p in sheets) {
        if (!left.containsKey(p.id) || !p.matches(mat, t) || p.length != l || p.width != w) continue;
        final n = math.min(left[p.id]!, e.value - have);
        have += n;
        left[p.id] = left[p.id]! - n;
      }
      out.add(SheetNeed(mat, t, l, w, e.value, have));
    }
    return out;
  }

  /// Chutes que laissera [plan], assez grandes pour être gardées.
  List<StockPiece> leftovers(CutPlan plan, {String project = '', String date = ''}) {
    final out = <StockPiece>[];
    for (final s in plan.sheets) {
      if (s.placements.isEmpty) continue;
      for (final (_, _, w, h) in s.remnants) {
        final l = w.floor(), b = h.floor();
        if (math.max(l, b) < minLength || math.min(l, b) < minWidth) continue;
        out.add(StockPiece(
            id: '', material: s.material, thickness: plan.settings.thicknessFor(s.material), length: l, width: b, origin: project, date: date));
      }
    }
    return out;
  }

  /// Dernière découpe validée (non annulée) de ce projet.
  StockMove? lastCut(String project) => moves.where((m) => !m.undone && m.project == project).lastOrNull;

  /// Valide la découpe de [plan] : retire les chutes et les feuilles utilisées, range les chutes [keep].
  StockMove validate(CutPlan plan, {required String project, required String date, required List<StockPiece> keep}) {
    final taken = <StockPiece>[];
    for (final s in plan.sheets) {
      final p = s.stockId == null ? null : byId(s.stockId!);
      if (p == null) continue;
      taken.add(p.copy());
      pieces.remove(p);
    }
    final needs = this.needs(plan, project: project);
    for (final n in needs) {
      var left = n.needed - n.toBuy;
      for (final p in [...sheets]) {
        if (left <= 0) break;
        if (!p.matches(n.material, n.thickness) || p.length != n.length || p.width != n.width) continue;
        if (p.reserved.isNotEmpty && p.reserved != project) continue;
        final q = math.min(left, p.qty);
        taken.add(p.copy()..qty = q);
        p.qty -= q;
        left -= q;
        if (p.qty == 0) pieces.remove(p);
      }
    }
    final added = [
      for (final k in keep)
        add(material: k.material, thickness: k.thickness, length: k.length, width: k.width, place: k.place, origin: project, date: date).copy(),
    ];
    final move = StockMove('M${nextMove++}', project, date, taken, added, bought: needs.fold(0, (a, n) => a + n.toBuy));
    moves.add(move);
    return move;
  }

  /// Annule une découpe validée : rend ce qui a été pris, retire les chutes rangées (si elles y sont encore).
  /// Renvoie les numéros des chutes rangées qui ne sont plus là (déjà utilisées ailleurs).
  List<String> undo(StockMove move) {
    if (move.undone) return const [];
    final gone = <String>[];
    for (final a in move.added) {
      final p = byId(a.id);
      if (p == null) {
        gone.add(a.id);
      } else {
        pieces.remove(p);
      }
    }
    for (final t in move.taken) {
      final p = byId(t.id);
      if (p != null && !p.offcut) {
        p.qty += t.qty;
      } else if (p == null) {
        pieces.add(t.copy());
      }
    }
    move.undone = true;
    return gone;
  }

  Map<String, dynamic> toJson() => {
        'kind': 'kitchinox_stock',
        'pieces': [for (final p in pieces) p.toJson()],
        'moves': [for (final m in moves.skip(math.max(0, moves.length - 200))) m.toJson()],
        'next_offcut': nextOffcut,
        'next_sheet': nextSheet,
        'next_move': nextMove,
        'min_length': minLength,
        'min_width': minWidth,
      };

  void load(Map<String, dynamic> j) {
    final ps = [for (final x in (j['pieces'] as List? ?? const [])) StockPiece.fromJson((x as Map).cast<String, dynamic>())];
    final ms = [for (final x in (j['moves'] as List? ?? const [])) StockMove.fromJson((x as Map).cast<String, dynamic>())];
    pieces
      ..clear()
      ..addAll(ps);
    moves
      ..clear()
      ..addAll(ms);
    nextOffcut = (j['next_offcut'] as num?)?.toInt() ?? 1;
    nextSheet = (j['next_sheet'] as num?)?.toInt() ?? 1;
    nextMove = (j['next_move'] as num?)?.toInt() ?? 1;
    minLength = (j['min_length'] as num?)?.toInt() ?? 300;
    minWidth = (j['min_width'] as num?)?.toInt() ?? 150;
  }
}
