/// Correction proposée pour chaque problème détecté : une action automatique quand c'est possible
/// (combler un vide, poser la hotte, recentrer, inverser les charnières, ajuster une largeur...),
/// sinon une indication concrète de ce qu'il faut faire.
library;

import 'i18n_hook.dart';
import 'dart:math' as math;

import 'access.dart';
import 'brands_sizes.dart';
import 'clearance.dart';
import 'layout_engine.dart';
import 'materials.dart';
import 'catalog.dart';
import 'networks.dart';
import 'project.dart';
import 'room_objects.dart';

class IssueFix {
  final String? label; // texte du bouton (null : pas d'action automatique)
  final String hint; // ce qu'il faut faire / ce que fait la correction
  final bool Function()? apply; // renvoie vrai si le projet a changé
  const IssueFix(this.hint, {this.label, this.apply});
}

IssueFix fixFor(LayoutEngine e, Issue i, {MaterialsDb? db}) {
  final p = e.project;
  PlacedCabinet? item(int k) => i.uids.length > k ? p.byUid(i.uids[k]) : null;
  final c = item(0);
  bool moved(MoveResult r) => r.moved;

  switch (i.code) {
    case 'filler_gap':
      return IssueFix(L('Pose des fileurs (50 à 200 mm) dans les vides trop petits pour un caisson.'), label: L('Combler'), apply: () {
        final gaps = e.gaps().where((g) => g.fillable).toList();
        for (final g in gaps) {
          e.fillGap(g);
        }
        return gaps.isNotEmpty;
      });
    case 'corner_filler':
      return IssueFix(L('Décale l\'élément de 50 mm pour laisser un fileur dans l\'angle (les portes et tiroirs doivent pouvoir s\'ouvrir).'),
          label: L('Décaler'), apply: () {
        if (c == null) return false;
        final w = p.room.wall(c.wallId);
        final towardEnd = c.right > w.length - 600.5;
        final r = e.move(c.uid, s: c.s + (towardEnd ? -50 : 50));
        if (r.moved) {
          final gs = e.gaps().where((g) => g.fillable && g.wallId == c.wallId).toList();
          for (final g in gs) {
            e.fillGap(g);
          }
        }
        return r.moved;
      });
    case 'hob_no_hood':
      return IssueFix(L('Pose un caisson de hotte au-dessus de la plaque, aligné sur les autres hauts. S\'il n\'y a pas la place (fenêtre, colonne), déplacez la plaque.'), label: L('Poser la hotte'), apply: () => c != null && e.placeHoods(c.wallId) > 0);
    case 'hood_offset':
    case 'hood_low':
    case 'hood_narrow':
      return IssueFix(L('Recentre la hotte sur la plaque, à sa largeur, et l\'aligne sur les hauts (650 mm au-dessus de la plaque).'),
          label: L('Recentrer'), apply: () {
        final hood = p.items.where((x) => i.uids.contains(x.uid) && e.modelOf(x).isHoodUnit).firstOrNull;
        final hob = p.items.where((x) => i.uids.contains(x.uid) && e.cooks(x) && e.modelOf(x).kind.isLow).firstOrNull ??
            p.items.where((x) => hood != null && x.wallId == hood.wallId && e.cooks(x) && e.modelOf(x).kind.isLow).firstOrNull;
        if (hood == null || hob == null) return false;
        final m = e.modelOf(hood);
        final (z, h) = e.hoodPlacement(m, hood.wallId);
        e.resize(hood.uid, width: math.max(hob.width, m.widths.nearest(hob.width)), height: h);
        return moved(e.move(hood.uid, s: hob.s + hob.width / 2 - hood.width / 2, z: z));
      });
    case 'open_blocked':
      return IssueFix(L('Inverse les charnières si cela libère la porte. Sinon : ajoutez un fileur de 50 mm entre le meuble et l\'obstacle, ou échangez le meuble avec un voisin (glissez l\'un sur l\'autre).'), label: L('Charnières'), apply: () => improveHinges(e) > 0);
    case 'open_pair':
      return IssueFix(L('Les deux ne peuvent pas être ouverts ensemble : éloignez-les d\'un caisson, ou acceptez la gêne (ouverture l\'un après l\'autre).'));
    case 'layout_invalid':
      return IssueFix(L('Revient à la composition du catalogue pour ce meuble.'), label: L('Rétablir'), apply: () {
        if (c == null) return false;
        c.layout = null;
        return true;
      });
    case 'wall_appliance':
      return IssueFix(L('Retire l\'appareil de l\'élément haut (un haut ne reçoit pas d\'appareil).'), label: L('Retirer'), apply: () {
        if (c == null) return false;
        c.appliances = const [];
        return true;
      });
    case 'dishwasher_width':
    case 'appliance_width':
    case 'appliance_cabinet':
      return IssueFix(L('Ajuste la largeur du caisson à l\'appareil choisi.'), label: L('Ajuster'), apply: () {
        if (c == null || db == null) return false;
        for (final id in appliancesOf(e.modelOf(c), c)) {
          final a = db.appliances[id];
          if (a == null) continue;
          final target = a.category == 'dishwashers' && a.niche != null ? a.niche!.$1 : a.cabinetWidth ?? a.minCabinetWidth;
          if (target != null && target != c.width) return moved(e.resize(c.uid, width: target));
        }
        return false;
      });
    case 'sink_hob_close':
      final minDist = (SizeCatalog.rule('cuisine', ['safety_landing_zones', 'min_distance_sink_to_cooktop']) ?? 600).round();
      return IssueFix(
        L('Éloigne la plaque de l\'évier pour laisser {0} mm de plan (échange avec un meuble voisin).', [minDist]),
        label: L('Échanger'),
        apply: () {
          final sink = item(0), hob = item(1);
          if (sink == null || hob == null) return false;
          final minD = minDist.toDouble();
          final curGap = hob.s >= sink.right ? hob.s - sink.right : (sink.s >= hob.right ? sink.s - hob.right : 0.0);
          if (curGap >= minD) return false;

          // Stratégie 1 : échanger la plaque avec un meuble bas voisin à l'opposé de l'évier
          final dir = hob.s >= sink.s ? 1 : -1;
          PlacedCabinet? neighbor;
          if (dir > 0) {
            neighbor = p.items.where((b) {
              if (b.uid == hob.uid || b.uid == sink.uid || b.wallId != hob.wallId) return false;
              final mb = e.modelOf(b);
              if (mb.kind.isCorner || mb.kind.isFiller || mb.kind != CabinetKind.base) return false;
              if (e.isCooking(mb) || e.isWashing(mb)) return false;
              return (b.s - hob.right).abs() < 25;
            }).firstOrNull;
          } else {
            neighbor = p.items.where((b) {
              if (b.uid == hob.uid || b.uid == sink.uid || b.wallId != hob.wallId) return false;
              final mb = e.modelOf(b);
              if (mb.kind.isCorner || mb.kind.isFiller || mb.kind != CabinetKind.base) return false;
              if (e.isCooking(mb) || e.isWashing(mb)) return false;
              return (hob.s - b.right).abs() < 25;
            }).firstOrNull;
          }

          if (neighbor != null) {
            final res = e.trySwap(hob.uid, neighbor.s + neighbor.width / 2);
            if (res != null && res.moved) {
              // Réaligner la hotte si présente au-dessus de la plaque
              for (final hood in p.items.where((h) => h.wallId == hob.wallId && e.modelOf(h).isHoodUnit)) {
                e.move(hood.uid, s: hob.s + hob.width / 2 - hood.width / 2);
              }
              return true;
            }
          }

          // Stratégie 2 : si la plaque est en bout de linéaire avec espace libre à l'opposé
          final needed = minD - curGap;
          if (needed > 0) {
            final targetS = hob.s + dir * needed;
            final res = e.move(hob.uid, s: targetS);
            if (res.moved) {
              for (final hood in p.items.where((h) => h.wallId == hob.wallId && e.modelOf(h).isHoodUnit)) {
                e.move(hood.uid, s: hob.s + hob.width / 2 - hood.width / 2);
              }
              return true;
            }
          }

          return false;
        },
      );
    case 'oven_fridge':
      return IssueFix(L('Séparez le four du réfrigérateur par un caisson (150 à 300 mm) ou échangez l\'un des deux avec un voisin (glissez l\'un sur l\'autre).'));
    case 'wall_too_low':
      return IssueFix(L('Remonte l\'élément haut à la hauteur standard (crédence de 60 cm).'), label: L('Remonter'), apply: () {
        if (c == null) return false;
        return moved(e.move(c.uid, z: e.std.wallBottomDefault.toDouble()));
      });
    case 'hob_near_wall':
    case 'hob_near_tall':
      return IssueFix(L('Laissez 300 mm de plan entre la plaque et le mur ou la colonne : échangez la plaque avec un caisson voisin (glissez l\'un sur l\'autre) ou insérez un caisson de 300 mm.'));
    case 'hob_window':
      return IssueFix(L('Pas de plaque sous une fenêtre (rideaux, courant d\'air) : échangez la plaque avec un caisson voisin.'));
    case 'dishwasher_far':
      return IssueFix(L('Placez le lave-vaisselle contre l\'évier (glissez-le sur le caisson voisin de l\'évier pour les échanger).'));
    case 'triangle_short':
    case 'triangle_long':
    case 'triangle_perimeter':
      return IssueFix(L('Évier, plaque et froid doivent être espacés de 1,2 à 2,7 m (4 à 7,9 m au total) : échangez des meubles par glisser, ou utilisez « Propositions de cuisine ».'));
    case 'zone_wash':
    case 'zone_cook':
    case 'zone_cool':
      return IssueFix(L('Il manque une zone de travail : ajoutez l\'élément depuis le catalogue ou utilisez « Propositions de cuisine ».'));
    case 'door_access':
    case 'door_access_tight':
      final target = i.code == 'door_access' ? accessMin - 25.0 : accessAdvised - 25.0;
      return IssueFix(
          L('Dégage l’entrée : retire le meuble bas ou la colonne le plus proche de la porte (et les hauts au-dessus) jusqu’à obtenir {0} mm de passage. L’évier, la cuisson et le froid ne sont jamais retirés.', [target.round() + 25]),
          label: L('Dégager l’entrée'), apply: () {
        final before = p.items.length;
        clearDoorAccess(e, min: target);
        return p.items.length != before;
      });
    case 'aisle':
    case 'aisle_tight':
    case 'island_aisle':
    case 'island_aisle_tight':
      // pas de place libre pour l'îlot dans cette pièce : on propose de le retirer
      if (i.code == 'island_aisle' && p.room.island != null && e.bestIslandSpot() == null) {
        return IssueFix(L('Pas de place pour un îlot avec 1 m de passage tout autour : retire l\'îlot et ses caissons.'), label: L('Retirer l\'îlot'),
            apply: () {
          p.items.removeWhere((c) => c.wallId == 'I');
          p.room.island = null;
          return true;
        });
      }
      return IssueFix(L('Replace l\'îlot dans l\'espace libre avec 1 m de passage au moins (ou réduisez sa longueur).'), label: L('Replacer l\'îlot'),
          apply: () {
        final isl = p.room.island;
        if (isl == null) return false;
        final spot = e.bestIslandSpot();
        if (spot == null) return false;
        try {
          e.setIsland(x0: spot.x0, y0: spot.y0, length: math.min(isl.length, spot.length));
          return true;
        } on PlacementException {
          return false;
        }
      });
    case 'net_sink':
      return IssueFix(L('Écarte la prise de la zone de l\'évier.'), label: L('Écarter'), apply: () {
        final pt = i.uids.map(p.pointByUid).whereType<NetPoint>().firstOrNull;
        final sink = i.uids.map(p.byUid).whereType<PlacedCabinet>().firstOrNull;
        if (pt == null || sink == null) return false;
        final left = sink.s - 150, right = sink.right + 150;
        pt
          ..s = (pt.s - left).abs() < (right - pt.s).abs() && left > 100 ? left : right
          ..auto = false;
        return true;
      });
    case 'net_plan':
    case 'net_count':
    case 'net_water':
    case 'net_dishwasher':
    case 'net_oven':
    case 'net_fridge':
    case 'net_hob_feed':
      return IssueFix(L('Recalcule les points de réseau d\'après l\'implantation.'), label: L('Recalculer'), apply: () {
        p.networks = true;
        applyNetworks(e);
        return true;
      });
    case 'drain_far':
    case 'water_far':
    case 'dishwasher_drain_far':
      return IssueFix(L('Rapprochez l\'évier (et le lave-vaisselle) de l\'évacuation existante : échangez-le avec un caisson plus proche, ou utilisez « Propositions de cuisine » qui en tiennent compte. Sinon, prévoyez une pente de 1 à 3 cm/m ou une pompe de relevage.'));
    case 'water_unknown':
      return IssueFix(L('Menu Réseaux → « Arrivée d\'eau existante » et « Évacuation existante », puis placez-les sur le mur.'));
    case 'appliance_niche':
    case 'fridge_niche':
      return IssueFix(L('Choisissez un appareil plus petit, ou un caisson plus large / plus haut.'));
    case 'overlap':
    case 'outside':
    case 'ceiling':
    case 'width':
    case 'height':
      return IssueFix(L('Déplacez ou redimensionnez l\'élément (fiche de l\'élément).'));
    default:
      return IssueFix(L('Ouvrez l\'élément concerné pour le modifier.'));
  }
}

/// Distance (mm) dans le plan entre deux points posés sur des murs.
double _planDist(Room room, String w1, double s1, String w2, double s2) {
  (double, double) at(String w, double s) {
    if (w == 'P') return (s, 0);
    return room.wall(w).toPlan(s, 0);
  }

  final (x1, y1) = at(w1, s1);
  final (x2, y2) = at(w2, s2);
  return math.sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2));
}

/// Usage des points de réseau déjà présents dans la pièce (arrivée d'eau, évacuation existantes).
const existingUse = 'existant';

/// Emplacement de l'évier et du lave-vaisselle par rapport à l'eau et à l'évacuation existantes.
List<Issue> waterChecks(LayoutEngine e) {
  if (!e.kitchen) return const [];
  final p = e.project;
  final out = <Issue>[];
  final sinks = p.items.where((c) => e.washes(c)).toList();
  if (sinks.isEmpty) return out;
  final existing = p.points.where((x) => x.use == existingUse && !x.hidden).toList();
  final drains = existing.where((x) => x.kind == NetKind.drain).toList();
  final supplies = existing.where((x) => x.kind == NetKind.waterCold || x.kind == NetKind.waterHot).toList();
  if (drains.isEmpty && supplies.isEmpty) {
    out.add(Issue(Severity.info, 'water_unknown',
        L('Indiquez l\'arrivée d\'eau et l\'évacuation existantes (menu Réseaux) pour vérifier l\'emplacement de l\'évier')));
    return out;
  }
  double nearest(List<NetPoint> pts, PlacedCabinet c) =>
      pts.map((x) => _planDist(p.room, c.wallId, c.s + c.width / 2, x.wallId, x.s)).fold(double.infinity, math.min);
  for (final s in sinks) {
    final d = nearest(drains, s);
    if (d.isFinite && d > 3000) {
      out.add(Issue(Severity.warning, 'drain_far',
          L('Évier à {0} m de l\'évacuation existante : pente de 1 à 3 cm/m difficile, rapprocher l\'évier', [(d / 1000).toStringAsFixed(1)]), [s.uid]));
    } else if (d.isFinite && d > 1500) {
      out.add(Issue(Severity.info, 'drain_far',
          L('Évier à {0} m de l\'évacuation existante : prévoir la pente de l\'évacuation (1 à 3 cm/m)', [(d / 1000).toStringAsFixed(1)]), [s.uid]));
    }
    final w = nearest(supplies, s);
    if (w.isFinite && w > 4000) {
      out.add(Issue(Severity.warning, 'water_far', L('Évier à {0} m de l\'arrivée d\'eau existante', [(w / 1000).toStringAsFixed(1)]), [s.uid]));
    }
  }
  for (final dw in p.items.where((c) => e.modelOf(c).id == 'base_integrated_dishwasher_door')) {
    final d = nearest(drains, dw);
    if (d.isFinite && d > 2000) {
      out.add(Issue(Severity.warning, 'dishwasher_drain_far',
          L('Lave-vaisselle à {0} m de l\'évacuation : le tuyau de vidange ne doit pas dépasser 1,5 à 2 m', [(d / 1000).toStringAsFixed(1)]), [dw.uid]));
    }
  }
  return out;
}

/// Distance moyenne des appareils à eau (sanitaires, vasques, lave-linge) à l'évacuation existante
/// (ou, à défaut, à l'arrivée d'eau existante), en mm ; null si rien n'est indiqué ou rien à raccorder.
double? wetDrainDistance(LayoutEngine e) {
  final p = e.project;
  final ex = p.points.where((x) => x.use == existingUse && !x.hidden).toList();
  final drains = ex.where((x) => x.kind == NetKind.drain || x.kind == NetKind.drainWc).toList();
  final refs = drains.isNotEmpty ? drains : ex.where((x) => x.kind.network == 'water').toList();
  if (refs.isEmpty) return null;
  final at = <(String, double)>[
    for (final (w, s, _, kind, _) in fixtureWaterPoints(p.room, p.objects))
      if (kind == 'evac') (w, s),
    for (final c in p.items)
      if (c.modelId.contains('vanity') || c.modelId.contains('washing_machine')) (c.wallId, c.s + c.width / 2),
  ];
  if (at.isEmpty) return null;
  var sum = 0.0;
  for (final (w, s) in at) {
    sum += refs.map((x) => _planDist(p.room, w, s, x.wallId, x.s)).fold(double.infinity, math.min);
  }
  return sum / at.length;
}

/// Distance de l'évier le plus proche à l'évacuation existante (mm), ou null si inconnue.
double? sinkDrainDistance(LayoutEngine e) {
  final p = e.project;
  final drains = p.points.where((x) => x.use == existingUse && x.kind == NetKind.drain && !x.hidden).toList();
  if (drains.isEmpty) return null;
  var best = double.infinity;
  for (final s in p.items.where((c) => e.washes(c))) {
    for (final d in drains) {
      best = math.min(best, _planDist(p.room, s.wallId, s.s + s.width / 2, d.wallId, d.s));
    }
  }
  return best.isFinite ? best : null;
}
