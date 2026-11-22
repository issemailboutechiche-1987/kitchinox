// Moteur de montage du mode Art (docs/mode_art_moteur.md, § 1, 5, 6 et 9) :
// chants nommés par leur position finale, solveur des liaisons (ordre libre, conflits, pièces orphelines),
// support au sol (pieds + plinthe) et découpe d'une feuille à la guillotine pour une liste de pièces.
import 'dart:math' as math;

import 'art.dart';

/// Chant ou face nommé par sa normale dans le monde : (axe, sens).
const sideAxes = <String, (int, int)>{
  'gauche': (0, -1),
  'droite': (0, 1),
  'bas': (1, -1),
  'haut': (1, 1),
  'avant': (2, -1),
  'arriere': (2, 1),
};

/// « +X », « -Y », « +Z »… → (axe, sens).
(int, int)? parseDir(String s) {
  final m = RegExp(r'^([+-])([XYZ])$').firstMatch(s.trim().toUpperCase());
  if (m == null) return null;
  return ('XYZ'.indexOf(m.group(2)!), m.group(1) == '+' ? 1 : -1);
}

double _lo(ArtPanel p, int a) => a == 0 ? p.x : a == 1 ? p.y : p.z;
double _hi(ArtPanel p, int a) => a == 0 ? p.right : a == 1 ? p.top : p.back;

/// Support au sol du meuble monté autour de [anchor] : pieds réglables (le meuble monte de [height])
/// et plinthe [plinth] posée devant, en retrait de [retreat] depuis la face des portes.
class ArtSupport {
  String type; // pieds | socle | aucun
  String anchor; // pièce de référence du meuble (le dessous)
  double height;
  String? plinth;
  double retreat;
  ArtSupport({this.type = 'pieds', required this.anchor, this.height = 100, this.plinth, this.retreat = 50});

  Map<String, dynamic> toJson() => {'type': type, 'anchor': anchor, 'height': height, if (plinth != null) 'plinth': plinth, 'retreat': retreat};
  factory ArtSupport.fromJson(Map<String, dynamic> j) => ArtSupport(
        type: j['type'] as String? ?? 'pieds',
        anchor: j['anchor'] as String,
        height: (j['height'] as num?)?.toDouble() ?? 100,
        plinth: j['plinth'] as String?,
        retreat: (j['retreat'] as num?)?.toDouble() ?? 50,
      );
}

/// Résultat du montage : pièces placées et messages.
class SolveResult {
  final List<ArtPanel> panels;
  final List<String> conflicts; // liaisons incohérentes (boucle qui ne ferme pas)
  final List<EdgeLink> unresolved; // liaisons dont la pièce de référence n'a jamais été placée
  final Set<String> placed; // pièces placées par une liaison (ou de référence)
  const SolveResult(this.panels, this.conflicts, this.unresolved, this.placed);
  bool get ok => conflicts.isEmpty && unresolved.isEmpty;
}

/// Applique la liaison [l] : place [a] contre [b] (chant de b nommé résolu sur sa géométrie actuelle).
/// Faux si le chant nommé n'existe pas sur b.
bool applyLink(ArtPanel a, ArtPanel b, EdgeLink l) {
  var eb = l.eb;
  if (l.bSide != null) {
    final s = sideAxes[l.bSide!];
    if (s == null) return false;
    eb = ArtProject.edgeWithNormal(b, s.$1, s.$2);
  }
  if (eb == 0) return false;
  return ArtProject.linkEdges(a, l.ea, b, eb,
      align: l.align, offset: l.offset, over: l.over, outside: l.outside, front: l.kind == 'articule', inset: l.inset);
}

/// Monte les pièces [flat] selon [links], quel que soit leur ordre :
/// - les pièces de référence (b d'une liaison sans être a d'aucune) ne bougent pas ;
/// - une liaison s'applique dès que sa pièce b est placée ;
/// - une pièce déjà placée par une autre liaison n'est pas déplacée : on vérifie que la nouvelle liaison
///   tombe au même endroit (écart > 0,5 mm → conflit) ;
/// - enfin le meuble est posé sur son [support].
SolveResult solveAssembly(List<ArtPanel> flat, List<EdgeLink> links, {ArtSupport? support}) {
  final out = [for (final p in flat) p.copy(id: p.id)];
  final byId = {for (final p in out) p.id: p};
  final original = {for (final p in flat) p.id: p};
  final aIds = {for (final l in links) l.a};
  final placed = <String>{for (final l in links) if (!aIds.contains(l.b) && byId.containsKey(l.b)) l.b};
  final pending = [for (final l in links) if (byId.containsKey(l.a) && byId.containsKey(l.b) && l.a != l.b) l];
  final conflicts = <String>[];
  var progress = true;
  while (progress && pending.isNotEmpty) {
    progress = false;
    for (final l in [...pending]) {
      if (!placed.contains(l.b)) continue;
      pending.remove(l);
      progress = true;
      final a = byId[l.a]!, b = byId[l.b]!;
      if (placed.contains(l.a)) {
        // deuxième liaison sur une pièce déjà placée : elle doit tomber au même endroit
        final test = original[l.a]!.copy(id: l.a);
        if (!applyLink(test, b, l)) {
          conflicts.add('${a.note ?? a.id} : chant « ${l.bSide ?? l.eb} » introuvable sur ${b.note ?? b.id}');
          continue;
        }
        final gap = [for (var k = 0; k < 3; k++) math.max((_lo(test, k) - _lo(a, k)).abs(), (_hi(test, k) - _hi(a, k)).abs())].reduce(math.max);
        if (gap > 0.5) conflicts.add('${a.note ?? a.id} / ${b.note ?? b.id} : les deux liaisons ne concordent pas (${gap.round()} mm)');
        continue;
      }
      if (!applyLink(a, b, l)) {
        conflicts.add('${a.note ?? a.id} : chant « ${l.bSide ?? l.eb} » introuvable sur ${b.note ?? b.id}');
        continue;
      }
      placed.add(l.a);
    }
  }
  if (support != null && byId.containsKey(support.anchor)) _applySupport(out, links, support);
  _clearOfOthers(out, {...placed, if (support?.plinth != null) support!.plinth!});
  return SolveResult(out, conflicts, pending, placed);
}

/// Le meuble monté ne doit pas traverser les pièces restées à plat (chutes de la feuille) :
/// s'il en touche une, il est posé à droite de tout le reste, à 300 mm.
void _clearOfOthers(List<ArtPanel> out, Set<String> group) {
  final mine = [for (final p in out) if (group.contains(p.id)) p];
  final others = [for (final p in out) if (!group.contains(p.id)) p];
  if (mine.isEmpty || others.isEmpty) return;
  bool hit(ArtPanel a, ArtPanel b) => [0, 1, 2].every((k) => math.min(_hi(a, k), _hi(b, k)) - math.max(_lo(a, k), _lo(b, k)) > 0.5);
  if (!mine.any((m) => others.any((o) => hit(m, o)))) return;
  final dx = others.map((p) => p.right).reduce(math.max) + 300 - mine.map((p) => p.x).reduce(math.min);
  final dz = -mine.map((p) => p.z).reduce(math.min);
  for (final p in mine) {
    p
      ..x += dx
      ..z += dz;
  }
}

/// Pose le meuble sur ses pieds : toutes les pièces reliées à l'ancre montent de la hauteur des pieds ;
/// la plinthe se dresse devant, sur toute la largeur du caisson, en retrait depuis la face des portes.
void _applySupport(List<ArtPanel> out, List<EdgeLink> links, ArtSupport s) {
  final byId = {for (final p in out) p.id: p};
  // pièces du meuble : composante connexe de l'ancre (liaisons dans les deux sens)
  final group = <String>{s.anchor};
  var grew = true;
  while (grew) {
    grew = false;
    for (final l in links) {
      if (group.contains(l.a) != group.contains(l.b)) {
        group
          ..add(l.a)
          ..add(l.b);
        grew = true;
      }
    }
  }
  group.remove(s.plinth);
  final parts = [for (final id in group) ?byId[id]];
  if (parts.isEmpty) return;
  final lift = s.type == 'pieds' || s.type == 'socle' ? s.height : 0.0;
  final floor = parts.map((p) => p.y).reduce(math.min);
  for (final p in parts) {
    p.y += lift - floor; // le dessous à la hauteur des pieds (au sol sans pieds)
  }
  final pl = s.plinth == null ? null : byId[s.plinth];
  if (pl == null || lift <= 0) return;
  final structure = parts.where((p) => !p.role.isFront).toList();
  final x0 = structure.map((p) => p.x).reduce(math.min), x1 = structure.map((p) => p.right).reduce(math.max);
  final front = parts.map((p) => p.z).reduce(math.min); // face des portes
  final dims = [pl.w, pl.h, pl.d]..sort();
  final t = dims[0], hh = dims[1], len = dims[2];
  pl
    ..w = len
    ..h = hh
    ..d = t
    ..x = x0 + (x1 - x0 - len) / 2
    ..y = 0
    ..z = front + s.retreat
    ..role = ArtRole.plinthe;
}

/// Coupe la feuille [sheet] (pièce libre à plat de [art]) en [pieces] (nom, longueur en X, largeur en Z),
/// à la guillotine : bandes en Z (la plus large d'abord), pièces en X dans chaque bande, recoupe en Z.
/// Si tout ne tient pas, [extraSheet] pose une feuille de plus (même format) et la coupe continue dessus.
/// Renvoie les pièces dans l'ordre demandé, ou null si elles ne tiennent pas (rien n'est coupé).
List<ArtPanel>? cutPiecesFromSheet(ArtProject art, ArtPanel sheet, List<(String, double, double)> pieces,
    {double kerf = 4, ArtPanel Function()? extraSheet}) {
  // 1. plan : bandes de profondeur décroissante, pièces rangées en X (premier qui convient)
  final order = [for (var i = 0; i < pieces.length; i++) i]..sort((a, b) => pieces[b].$3.compareTo(pieces[a].$3));
  final bands = <(double, List<int>)>[]; // (profondeur, indices)
  double used(List<int> idx) => idx.fold<double>(0, (a, i) => a + pieces[i].$2 + kerf);
  for (final i in order) {
    final (_, lo, la) = pieces[i];
    if (lo > sheet.w + 0.01 || la > sheet.d + 0.01) return null;
    var done = false;
    for (final (depth, idx) in bands) {
      if (la <= depth + 0.01 && used(idx) + lo <= sheet.w + kerf + 0.01) {
        idx.add(i);
        done = true;
        break;
      }
    }
    if (!done) bands.add((la, [i]));
  }
  // 2. bandes réparties sur les feuilles (la première qui a encore la profondeur)
  final perSheet = <List<(double, List<int>)>>[[]];
  final room = <double>[sheet.d + kerf];
  for (final band in bands) {
    var k = room.indexWhere((r) => r >= band.$1 + kerf - 0.01);
    if (k < 0) {
      if (extraSheet == null) return null;
      perSheet.add([]);
      room.add(sheet.d + kerf);
      k = room.length - 1;
    }
    perSheet[k].add(band);
    room[k] -= band.$1 + kerf;
  }
  final sheets = [sheet, for (var k = 1; k < perSheet.length; k++) extraSheet!()];

  // 3. coupes réelles dans l'ordre de la scie, feuille par feuille
  final result = List<ArtPanel?>.filled(pieces.length, null);
  for (var k = 0; k < sheets.length; k++) {
    var rest = sheets[k];
    for (final (depth, idx) in perSheet[k]) {
      ArtPanel strip;
      if (rest.d - depth > kerf + 1) {
        final (a, b) = art.splitPanel(rest, 2, rest.z + depth + kerf / 2, kerf);
        strip = a;
        rest = b;
      } else {
        strip = rest..d = depth; // reste plus mince qu'un trait de scie : il part en sciure
      }
      var row = strip;
      for (final i in idx) {
        final (name, lo, la) = pieces[i];
        ArtPanel piece;
        if (row.w - lo > kerf + 1) {
          final (a, b) = art.splitPanel(row, 0, row.x + lo + kerf / 2, kerf);
          piece = a;
          row = b;
        } else {
          piece = row..w = lo; // reste plus mince qu'un trait de scie : il part en sciure
        }
        if (piece.d - la > kerf + 1) {
          final (a, b) = art.splitPanel(piece, 2, piece.z + la + kerf / 2, kerf);
          piece = a;
          b.note = 'Chute';
        } else {
          piece.d = la;
        }
        piece.note = name;
        result[i] = piece;
      }
      if (!result.contains(row)) row.note = 'Chute';
    }
    if (!result.contains(rest)) rest.note = 'Chute';
  }
  return [for (final p in result) p!];
}
