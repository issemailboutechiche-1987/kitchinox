/// Propositions d'implantation : au lieu d'équiper tous les murs, on compose des cuisines éprouvées
/// (linéaire, en L, en U, parallèle, avec ou sans îlot) selon les principes des cuisinistes :
/// - enchaînement froid → préparation → lavage → préparation → cuisson ;
/// - évier sous la fenêtre, lave-vaisselle contre l'évier, colonnes groupées en bout de linéaire ;
/// - triangle d'activité entre 4 et 7,9 m, plan de travail continu de part et d'autre de la plaque ;
/// - îlot dans l'espace libre avec des passages de 1 à 1,2 m.
/// Chaque proposition est construite sur une copie du projet, puis notée.
library;

import 'dart:math' as math;

import 'access.dart';
import 'catalog.dart';
import 'clearance.dart';
import 'fixes.dart';
import 'layout_engine.dart';
import 'project.dart';

class LayoutProposal {
  final String id;
  final String name;
  final String description;
  final Project project; // projet complet prêt à appliquer
  final double score;
  final List<String> strengths;
  final List<String> warnings;
  final int errors;
  final double worktop; // longueur de plan de travail (mm)
  final int storage; // nombre de rangements (caissons hors appareils et fileurs)
  final double? triangle; // périmètre (mm)

  const LayoutProposal({
    required this.id,
    required this.name,
    required this.description,
    required this.project,
    required this.score,
    required this.strengths,
    required this.warnings,
    required this.errors,
    required this.worktop,
    required this.storage,
    this.triangle,
  });
}

/// Compositions candidates : (identifiant, nom, murs, îlot, style de remplissage, description).
List<(String, String, Set<String>, bool, String, String)> _candidates(Room r) {
  final out = <(String, String, Set<String>, bool, String, String)>[];
  String n(String w) => Room.wallNames[w]!.toLowerCase();
  // murs droits de la pièce (une pièce à contour libre peut en avoir plus de 4)
  final order = [for (final w in r.order) if (r.outline == null || r.wall(w).orthogonal) w];
  final k = order.length;
  // linéaires : sur chaque mur assez long
  for (final w in order) {
    if (r.wall(w).length >= 2400) {
      out.add(('lin_$w', 'Linéaire · ${n(w)}', {w}, false, 'mixte', 'Tout sur un mur : simple et économique, idéal pour les petites pièces.'));
      out.add(('lini_$w', 'Linéaire + îlot · ${n(w)}', {w}, true, 'tiroirs',
          'Le mur porte les colonnes et l\'évier, l\'îlot donne du plan de travail et un coin repas.'));
    }
  }
  // en L : deux murs voisins
  for (var i = 0; i < k; i++) {
    final a = order[i], b = order[(i + 1) % k];
    if (r.nextOf(a) != b) continue; // pas voisins (un arc ou un mur oblique entre les deux)
    out.add(('l_$a$b', 'En L · ${n(a)} + ${n(b)}', {a, b}, false, 'mixte', 'La forme la plus polyvalente : triangle compact, angle exploité.'));
    out.add(('li_$a$b', 'En L + îlot · ${n(a)} + ${n(b)}', {a, b}, true, 'tiroirs', 'Le L ferme l\'espace de travail, l\'îlot ouvre sur la pièce.'));
  }
  // en U : trois murs
  for (var i = 0; i < (k >= 3 ? k : 0); i++) {
    final ws = {order[i], order[(i + 1) % k], order[(i + 2) % k]};
    if (r.nextOf(order[i]) != order[(i + 1) % k] || r.nextOf(order[(i + 1) % k]) != order[(i + 2) % k]) continue;
    const short = {'A': 'fond', 'B': 'droite', 'C': 'gauche', 'D': 'avant'};
    out.add(('u_${ws.join()}', 'En U · ${ws.map((w) => short[w]).join(', ')}', ws, false, 'tiroirs',
        'Un maximum de rangements et de plan de travail, tout à portée de main.'));
  }
  // parallèle (couloir) : pièce rectangulaire
  if (r.outline != null) return out;
  out.add(('p_AD', 'Parallèle · fond + avant', {'A', 'D'}, false, 'mixte', 'Deux linéaires face à face : efficace dans une pièce en longueur.'));
  out.add(('p_BC', 'Parallèle · gauche + droite', {'B', 'C'}, false, 'mixte', 'Deux linéaires face à face : efficace dans une pièce en longueur.'));
  return out;
}

/// Construit et note les propositions ; renvoie les meilleures, une par forme.
/// [fillStyle] impose le style de remplissage ; [distinct] garde une seule proposition par forme ;
/// [kinds] limite aux formes données (préfixes : lin, lini, l, li, u, p).
List<LayoutProposal> proposeLayouts(LayoutEngine base, {int max = 6, String? fillStyle, bool distinct = true, Set<String>? kinds}) {
  final src = base.project;
  final results = <LayoutProposal>[];
  for (final (id, name, walls, island, style0, desc) in _candidates(src.room)) {
    if (kinds != null && !kinds.contains(id.split('_').first)) continue;
    final style = fillStyle ?? style0;
    // une porte sur tous les murs retenus : on évite d'équiper autour d'elle
    final p = Project.fromJson(src.toJson())..items.clear();
    // on garde l'arrivée d'eau et l'évacuation existantes de la pièce
    p.points.removeWhere((x) => x.use != existingUse);
    p.room.island = null;
    for (final w in p.room.order) {
      p.room.setWallEnabled(w, walls.contains(w));
    }
    final e = LayoutEngine(base.catalog, p)..fillStyle = style;
    try {
      // un îlot éventuel est posé après les murs (il prend l'espace libre restant)
      for (final w in walls) {
        e.autoFillWall(w, Band.low);
      }
      for (final w in walls) {
        e.autoFillWall(w, Band.high);
      }
      if (island) {
        final isl = e.bestIslandSpot();
        if (isl == null) continue;
        p.room.island = isl;
        e.autoFillWall('I', Band.low);
      }
    } on PlacementException {
      continue;
    }
    if (p.items.isEmpty) continue;
    if (!clearDoorAccess(e)) continue; // l'entrée dans la cuisine doit rester praticable
    improveHinges(e);
    final issues = [...e.validate(), ...openingChecks(e), ...accessChecks(e), ...designChecks(e), ...waterChecks(e)];
    final errors = issues.where((i) => i.severity == Severity.error).length;
    final warnings = issues.where((i) => i.severity == Severity.warning).toList();
    final (wash, cook, cool) = e.workZones();
    if (wash == null || cook == null || cool == null) continue; // il faut les trois zones
    final legs = e.triangleLegs();
    final tri = legs == null ? null : legs.$1 + legs.$2 + legs.$3;

    // plan de travail utile : linéaires bas moins évier et plaque
    var worktop = 0.0;
    for (final w in [...walls, if (island) 'I']) {
      for (final (a, b) in e.runs(w, (m) => m.kind.isLow)) {
        worktop += b - a;
      }
    }
    for (final c in p.items) {
      final m = e.modelOf(c);
      if (e.isWashing(m) || (e.isCooking(m) && m.kind.isLow)) worktop -= c.width;
    }
    final storage = p.items.where((c) {
      final m = e.modelOf(c);
      return m.isCarcass && !m.kind.isFiller && !e.isWashing(m) && !e.isCooking(m) && !e.isCooling(m) && m.id != 'base_integrated_dishwasher_door';
    }).length;

    final strengths = <String>[];
    var score = 0.0;
    score -= errors * 60.0 + warnings.length * 4.0;
    // ouverture bloquée : défaut de conception à éviter ; lave-vaisselle gêné : à éviter aussi
    score -= issues.where((i) => i.code == 'open_blocked').length * 25.0;
    score -= issues.where((i) => i.code == 'open_pair' && i.severity == Severity.warning).length * 10.0;
    if (tri != null && tri >= 4000 && tri <= 7900) {
      score += 25;
      strengths.add('Triangle d\'activité de ${(tri / 1000).toStringAsFixed(1)} m');
    } else if (tri != null) {
      score -= 15;
    }
    score += math.min(worktop, 4500) / 150; // jusqu'à 30 points
    score += math.min(storage, 18) * 1.2;
    if (worktop >= 3000) strengths.add('${(worktop / 1000).toStringAsFixed(1)} m de plan de travail libre');
    if (storage >= 10) strengths.add('$storage rangements');
    if (island) {
      strengths.add('Îlot de ${(p.room.island!.length / 1000).toStringAsFixed(1)} m avec coin repas');
      score += 8;
    }
    final sinkUnderWindow = p.items.any((c) =>
        e.isWashing(e.modelOf(c)) && p.openings.any((o) => !o.isDoor && o.wallId == c.wallId && o.s < c.right && c.s < o.right));
    if (sinkUnderWindow) {
      strengths.add('Évier sous la fenêtre');
      score += 6;
    }
    // évier proche de l'évacuation existante (pente d'écoulement)
    final drain = sinkDrainDistance(e);
    if (drain != null) {
      score -= drain / 150;
      if (drain <= 1500) strengths.add('Évier près de l’évacuation existante');
    }
    // pièce : les formes trop « lourdes » pour la surface perdent des points
    final area = p.room.width * p.room.depth / 1e6;
    if (walls.length == 3 && area < 9) score -= 10;
    if (island && area < 14) score -= 12;
    if (walls.length == 1 && !island && area > 14) score -= 6;

    results.add(LayoutProposal(
      id: id,
      name: name,
      description: desc,
      project: p,
      score: score,
      strengths: strengths,
      warnings: [for (final w in warnings.take(3)) w.message],
      errors: errors,
      worktop: worktop,
      storage: storage,
      triangle: tri,
    ));
  }
  results.sort((a, b) => b.score.compareTo(a.score));
  // une seule proposition par forme (linéaire, L, U, parallèle, avec ou sans îlot)
  final seen = <String>{};
  final out = <LayoutProposal>[];
  for (final r in results) {
    final kind = r.id.split('_').first;
    if (!distinct || seen.add(kind)) out.add(r);
    if (out.length >= max) break;
  }
  return out;
}

/// Applique une proposition au projet (murs, îlot, éléments ; le reste du projet est conservé).
void applyProposal(LayoutEngine e, LayoutProposal pr) {
  final p = e.project;
  final q = pr.project;
  for (final w in p.room.order) {
    p.room.setWallEnabled(w, q.room.isWallEnabled(w));
  }
  p.room.island = q.room.island == null ? null : Island.fromJson(q.room.island!.toJson());
  p.items
    ..clear()
    ..addAll([for (final c in q.items) c.copy()]);
  // objets de la composition (sanitaires, canapé, téléviseur…)
  p.objects
    ..clear()
    ..addAll([for (final o in q.objects) o.copy()]);
  p.points.removeWhere((x) => x.auto);
}

/// Nombre d'éléments de chaque rôle (pour la fiche de la proposition).
String proposalSummary(LayoutEngine base, LayoutProposal pr) {
  final e = LayoutEngine(base.catalog, pr.project);
  final talls = pr.project.items.where((c) => e.modelOf(c).kind == CabinetKind.tall).length;
  final highs = pr.project.items.where((c) => e.modelOf(c).kind.isHigh && !e.modelOf(c).kind.isFiller).length;
  return '${pr.project.items.length} éléments · $talls colonne(s) · $highs haut(s)';
}
