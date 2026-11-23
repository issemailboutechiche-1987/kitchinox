/// Fichier d'atelier : les panneaux débités avec chaque pièce à sa place, numérotée comme ses étiquettes
/// (code-barres du PDF « Générer codes » et QR du projet). L'opérateur touche la pièce qu'il vient de couper :
/// son étiquette s'imprime et la pièce passe « coupée ».
library;

import 'cutting.dart';

/// Code-barres d'une pièce : n° de projet (4 chiffres), n° de pièce de la liste (3), exemplaire (3).
/// Le même que sur les étiquettes.
String labelCode(String projId, int part, int copy) => '$projId${part.toString().padLeft(3, '0')}${copy.toString().padLeft(3, '0')}';

/// QR du projet (première étiquette).
String projectQr(String projId, String project, String client, int pieces) {
  final p = project.length > 25 ? project.substring(0, 25) : project;
  final c = client.length > 20 ? client.substring(0, 20) : client;
  return 'KXD1|$projId|$p|$c|$pieces';
}

class WorkshopPiece {
  final String code; // code-barres de l'étiquette
  final int part, copy, copies; // n° dans la liste, exemplaire, nombre d'exemplaires
  final String name, cabinet;
  final int length, width; // cotes de la pièce
  final double x, y; // position sur la feuille (mm)
  final int dx, dy; // cotes posées
  final bool rotated;
  final int edgeLong, edgeShort;
  const WorkshopPiece(this.code, this.part, this.copy, this.copies, this.name, this.cabinet, this.length, this.width, this.x, this.y, this.dx,
      this.dy, this.rotated, this.edgeLong, this.edgeShort);

  /// Numéro écrit sur le schéma : n° de pièce, et l'exemplaire s'il y en a plusieurs.
  String get mark => copies > 1 ? '$part.$copy' : '$part';

  Map<String, dynamic> toJson() => {
        'code': code, 'p': part, 'c': copy, 'q': copies, 'n': name, 'm': cabinet, 'l': length, 'w': width,
        'x': x, 'y': y, 'dx': dx, 'dy': dy, if (rotated) 'r': true, if (edgeLong > 0) 'el': edgeLong, if (edgeShort > 0) 'es': edgeShort,
      };

  factory WorkshopPiece.fromJson(Map<String, dynamic> j) => WorkshopPiece(
        '${j['code']}', j['p'] as int, j['c'] as int, j['q'] as int? ?? 1, '${j['n']}', '${j['m'] ?? ''}', j['l'] as int, j['w'] as int,
        (j['x'] as num).toDouble(), (j['y'] as num).toDouble(), j['dx'] as int, j['dy'] as int, j['r'] == true, j['el'] as int? ?? 0, j['es'] as int? ?? 0);
}

class WorkshopSheet {
  final int number;
  final String material;
  final int thickness, length, width;
  final String? stockId; // chute du stock
  final List<WorkshopPiece> pieces;
  const WorkshopSheet(this.number, this.material, this.thickness, this.length, this.width, this.stockId, this.pieces);

  Map<String, dynamic> toJson() => {
        'n': number, 'm': material, 't': thickness, 'l': length, 'w': width, if (stockId != null) 'stock': stockId,
        'pieces': [for (final p in pieces) p.toJson()],
      };

  factory WorkshopSheet.fromJson(Map<String, dynamic> j) => WorkshopSheet(j['n'] as int, '${j['m']}', j['t'] as int? ?? 18, j['l'] as int,
      j['w'] as int, j['stock'] as String?, [for (final p in j['pieces'] as List) WorkshopPiece.fromJson((p as Map).cast<String, dynamic>())]);
}

class WorkshopJob {
  static const kind = 'kitchinox-atelier';
  final String project, client, projId;
  final DateTime created;
  final List<WorkshopSheet> sheets;
  final Set<String> done; // codes des pièces coupées
  WorkshopJob(this.project, this.client, this.projId, this.created, this.sheets, [Set<String>? done]) : done = done ?? {};

  Iterable<WorkshopPiece> get pieces => sheets.expand((s) => s.pieces);
  int get pieceCount => sheets.fold(0, (a, s) => a + s.pieces.length);
  String get qr => projectQr(projId, project, client, pieceCount);

  /// Pièce d'un code-barres lu (douchette) ou saisi.
  WorkshopPiece? byCode(String code) => pieces.where((p) => p.code == code.trim()).firstOrNull;

  /// Fichier d'atelier d'un plan de découpe : chaque pièce physique avec son code d'étiquette.
  factory WorkshopJob.fromPlan(CutPlan plan, {required String project, String client = '', required String projId, DateTime? created}) {
    final copies = <int, int>{};
    final sheets = <WorkshopSheet>[];
    for (final s in plan.sheets) {
      final pieces = <WorkshopPiece>[];
      for (final pl in s.placements) {
        final copy = copies[pl.index] = (copies[pl.index] ?? 0) + 1;
        final p = pl.part;
        pieces.add(WorkshopPiece(labelCode(projId, pl.index, copy), pl.index, copy, p.qty, p.name, p.cabinet, p.length, p.width, pl.x, pl.y, pl.dx,
            pl.dy, pl.rotated, p.edgeLong, p.edgeShort));
      }
      sheets.add(WorkshopSheet(s.number, s.material, plan.settings.thicknessFor(s.material), s.length, s.width, s.stockId, pieces));
    }
    return WorkshopJob(project, client, projId, created ?? DateTime.now(), sheets);
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'version': 1,
        'project': project,
        'client': client,
        'projId': projId,
        'created': created.toIso8601String(),
        'sheets': [for (final s in sheets) s.toJson()],
        'done': [...done],
      };

  /// Fichier d'atelier ? (un .kin peut aussi être un projet)
  static bool isJob(Map<String, dynamic> j) => j['kind'] == kind;

  factory WorkshopJob.fromJson(Map<String, dynamic> j) => WorkshopJob(
        '${j['project'] ?? ''}',
        '${j['client'] ?? ''}',
        '${j['projId'] ?? '0000'}',
        DateTime.tryParse('${j['created']}') ?? DateTime.now(),
        [for (final s in j['sheets'] as List) WorkshopSheet.fromJson((s as Map).cast<String, dynamic>())],
        {for (final c in (j['done'] as List? ?? const [])) '$c'},
      );
}
