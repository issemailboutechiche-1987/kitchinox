/// Visserie, fixations et fournitures de pose : tout ce qu'il faut pour monter les caissons et les poser
/// (diamètre x longueur des vis, chevilles, rail mural, équerres anti-basculement, taquets, cache-vis...).
/// Règles d'atelier pour panneaux de 18 mm ; quantités arrondies au-dessus, avec une marge de 10 %.
library;

import 'dart:math' as math;

import 'catalog.dart';
import 'cutting.dart';
import 'layout_engine.dart';
import 'materials.dart';

/// Une fourniture de montage : désignation (avec dimensions), usage, quantité, unité.
class AssemblyItem {
  final String section; // 'Visserie et fixations' | 'Pose'
  final String name, usage, unit;
  final int qty;
  const AssemblyItem(this.section, this.name, this.usage, this.qty, this.unit);
}

int _hinges(int h) => h <= 900 ? 2 : h <= 1600 ? 3 : h <= 2000 ? 4 : 5;

/// Visserie et fournitures de pose du projet (d'après les caissons posés et la liste de débit).
List<AssemblyItem> assemblyList(LayoutEngine e, List<CutPart> parts) {
  final p = e.project;
  final cs = p.cut;
  final acc = <String, (String, String, String, double)>{}; // clé → (section, nom, usage, quantité) ; unité dans la clé
  void add(String section, String name, String usage, double q, {String unit = 'pce'}) {
    if (q <= 0) return;
    final k = '$section|$name|$unit';
    final prev = acc[k];
    acc[k] = (section, name, prev == null ? usage : prev.$3, (prev?.$4 ?? 0) + q);
  }

  const vis = 'Visserie et fixations', pose = 'Pose';
  int perJoint(int depth) => math.max(2, (depth / 200).ceil()); // une vis tous les 200 mm, 2 au moins

  var floorItems = 0, wallRun = 0.0, wallItems = 0, talls = 0;
  for (final c in p.items) {
    final m = e.modelOf(c);
    if (!m.isCarcass) {
      // fileurs et joues : vissés sur le caisson voisin
      if (m.kind.isFiller) add(vis, 'Vis aggloméré Ø4 x 30 mm (tête fraisée, Pozi)', 'fileurs vissés sur les caissons voisins', 4);
      if (m.kind == CabinetKind.coverPanel || m.kind == CabinetKind.islandPanel) {
        add(vis, 'Vis aggloméré Ø3,5 x 30 mm', 'joues et habillages vissés depuis l’intérieur des caissons', 6);
      }
      continue;
    }
    final d = c.depth - cs.doorThickness;
    final corner = m.kind.isCorner;
    // assemblage du caisson : côtés sur dessus / dessous (ou traverses)
    final joints = corner ? 8 : 4;
    final rails = m.kind.isLow && cs.includeRails;
    final confirmats = rails ? 2 * perJoint(d) + 2 * 2 * 2 : joints * perJoint(d);
    add(vis, 'Vis d’assemblage Confirmat Ø7 x 50 mm (clé 4 pans)', 'assemblage des caissons (côtés sur dessus, dessous, traverses)', confirmats.toDouble());
    add(vis, 'Cache-vis Confirmat (couleur caisson)', 'sur les têtes visibles', confirmats.toDouble());
    // caissons voisins liés entre eux
    final next = p.items.where((o) => o.wallId == c.wallId && (o.s - c.right).abs() < 2 && e.modelOf(o).isCarcass && o.z == c.z);
    if (next.isNotEmpty) add(vis, 'Vis de liaison de caissons M5 x 30/35 mm (paire mâle-femelle)', 'caissons voisins liés entre eux', 4);
    if (m.floorSupport) floorItems++;
    if (m.kind.isHigh) {
      wallRun += c.width;
      wallItems++;
    }
    if (m.kind == CabinetKind.tall || c.height >= 1500) talls++;
  }

  // étagères réglables : 4 taquets ; façades : charnières et coulisses vissées
  final shelves = parts.where((x) => x.name.startsWith('Étagère')).fold<int>(0, (a, x) => a + x.qty);
  add(vis, 'Taquets d’étagère Ø5 mm (métal, avec ergot)', 'étagères réglables (crémaillère de trous Ø5, pas de 32 mm)', shelves * 4.0);
  var hinges = 0, drawers = 0, handles = 0;
  for (final x in parts) {
    final n = x.name.toLowerCase();
    if (n.startsWith('porte') || n.startsWith('cadre de porte')) {
      hinges += _hinges(x.length) * x.qty;
      handles += x.qty;
    }
    if (n.contains('façade tiroir') || n.contains('façade de tiroir')) {
      drawers += x.qty;
      handles += x.qty;
    }
    if (n.startsWith('abattant') || n.contains('relevable')) handles += x.qty;
  }
  add(vis, 'Vis aggloméré Ø3,5 x 16 mm (tête cylindrique)', 'charnières : 2 vis pour l’embase, 2 vis pour le boîtier Ø35', hinges * 4.0);
  add(vis, 'Vis aggloméré Ø3,5 x 16 mm (tête cylindrique)', 'coulisses et fixation des façades de tiroir (10 par tiroir)', drawers * 10.0);
  if (p.style.handle != 'gola' && p.style.handle != 'push') {
    add(vis, 'Vis de poignée M4 x 25 mm (façade 18 mm)', 'poignées : 2 vis par poignée barre', handles * 2.0);
  } else {
    add(vis, 'Vis aggloméré Ø3,5 x 16 mm (tête cylindrique)', 'profils Gola : une vis tous les 300 mm', (p.items.fold<double>(0, (a, c) => a + c.width) / 300).ceilToDouble());
  }

  // pieds réglables : platine vissée
  if (floorItems > 0) {
    final legs = floorItems * 4;
    add(vis, 'Vis aggloméré Ø3,5 x 16 mm (tête cylindrique)', 'platines des pieds réglables (4 vis par pied)', legs * 4.0);
    add(pose, 'Clips de plinthe', 'plinthe clipsée sur les pieds avant', legs / 2);
  }
  // éléments hauts : rail mural + suspensions
  if (wallItems > 0) {
    final rail = (wallRun / 2000).ceil();
    add(pose, 'Rail de suspension mural galvanisé (barre de 2 m)', 'éléments hauts accrochés sur rail', rail.toDouble(), unit: 'barre');
    final fix = (wallRun / 400).ceil() + 2 * rail;
    add(pose, 'Chevilles nylon Ø8 x 50 mm + vis Ø6 x 60 mm', 'rail mural : une fixation tous les 400 mm (brique creuse : chevilles à expansion)', fix.toDouble());
    add(pose, 'Paire de suspensions réglables (3D)', 'une paire par élément haut', wallItems.toDouble(), unit: 'paire');
  }
  // colonnes et grands meubles : anti-basculement
  if (talls > 0) {
    add(pose, 'Équerre anti-basculement (acier zingué)', 'colonnes et grands meubles fixés au mur', talls * 2.0);
    add(pose, 'Chevilles nylon Ø6 x 40 mm + vis Ø5 x 50 mm', 'équerres anti-basculement', talls * 2.0);
    add(vis, 'Vis aggloméré Ø4 x 16 mm', 'équerres anti-basculement côté caisson', talls * 4.0);
  }
  // plan de travail (cuisine)
  if (e.kitchen) {
    final baseRun = p.items.where((c) => e.modelOf(c).kind.isLow && e.modelOf(c).isCarcass).fold<double>(0, (a, c) => a + c.width);
    if (baseRun > 0) {
      final n = (baseRun / 600).ceil() * 3;
      add(pose, 'Équerres de fixation de plan de travail', 'trois par caisson bas, vissées sous le plan', n.toDouble());
      add(vis, 'Vis aggloméré Ø4 x 16 mm', 'équerres de plan de travail (2 par équerre)', n * 2.0);
      add(pose, 'Silicone sanitaire translucide (cartouche 300 ml)', 'joints plan de travail / crédence et évier', math.max(1, (baseRun / 4000).ceil()).toDouble(),
          unit: 'cartouche');
    }
  }
  if (p.universe == 'bain') {
    add(pose, 'Silicone sanitaire anti-moisissure (cartouche 300 ml)', 'joints vasque / mur et chants exposés', 1, unit: 'cartouche');
  }
  if (p.items.isNotEmpty) {
    add(pose, 'Cales de réglage plastique (assortiment)', 'mise de niveau et d’aplomb', 1, unit: 'sachet');
  }

  return [
    for (final e in acc.entries)
      AssemblyItem(e.value.$1, e.value.$2, e.value.$3, (e.value.$4 * (e.value.$1 == vis ? 1.1 : 1)).ceil(), e.key.split('|').last),
  ]..sort((a, b) => a.section.compareTo(b.section) != 0 ? b.section.compareTo(a.section) : a.name.compareTo(b.name));
}

/// Les mêmes fournitures en lignes d'estimation (prix à saisir : non chiffrées).
List<SupplyLine> assemblySupplyLines(LayoutEngine e, List<CutPart> parts) => [
      for (final a in assemblyList(e, parts)) SupplyLine(a.section, a.name, a.usage, a.qty.toDouble(), a.unit, PriceRange.zero),
    ];
