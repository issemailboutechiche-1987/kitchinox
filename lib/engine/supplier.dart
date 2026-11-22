/// Prix d'un fournisseur de caissons et façades usinés (tarif relevé sur un devis réel),
/// pour comparer « acheter tout fait » et « fabriquer à l'atelier ».
library;

import 'dart:convert';
import 'dart:math' as math;

import 'catalog.dart';
import 'bom.dart';
import 'clearance.dart';
import 'cutting.dart';
import 'end_panels.dart';
import 'front_layout.dart';
import 'layout_engine.dart';
import 'materials.dart';
import 'media_progetti.dart';

class SupplierTariff {
  final String source;
  final double discountPct;
  final double wallA, wallB, baseA, baseB, tallOven, tallFridge;
  final (double, double, double) decor, gloss; // a, b, minimum
  final double drawerKit, drawerDiscountPct;
  const SupplierTariff({
    required this.source,
    required this.discountPct,
    required this.wallA,
    required this.wallB,
    required this.baseA,
    required this.baseB,
    required this.tallOven,
    required this.tallFridge,
    required this.decor,
    required this.gloss,
    required this.drawerKit,
    required this.drawerDiscountPct,
  });

  factory SupplierTariff.parse(String src) {
    final j = jsonDecode(src) as Map<String, dynamic>;
    final m = j['models'] as Map<String, dynamic>;
    double n(Object? v) => (v as num).toDouble();
    (double, double, double) f(Map x) => (n(x['a']), n(x['b']), n(x['min'] ?? 0));
    return SupplierTariff(
      source: '${j['source']}',
      discountPct: n(j['usual_discount_pct']),
      wallA: n(m['carcass_wall_h700']['a']),
      wallB: n(m['carcass_wall_h700']['b']),
      baseA: n(m['carcass_base']['a']),
      baseB: n(m['carcass_base']['b']),
      tallOven: n(m['tall_oven']),
      tallFridge: n(m['tall_fridge']),
      decor: f(m['front_decor']),
      gloss: f(m['front_gloss']),
      drawerKit: n(m['drawer_kit']['price']),
      drawerDiscountPct: n(m['drawer_kit']['discount_pct']),
    );
  }

  double front(double areaM2, {required bool gloss}) {
    final (a, b, mn) = gloss ? this.gloss : decor;
    return math.max(mn, a + b * areaM2);
  }
}

class SupplierQuote {
  final List<SupplyLine> lines; // prix TTC remisés
  final double gross; // TTC avant remise
  final double net; // TTC après remise
  const SupplierQuote(this.lines, this.gross, this.net);
  double get netHt => net / 1.2;

  /// Les mêmes lignes hors taxes : le devis ajoute lui-même la TVA.
  List<SupplyLine> get linesHt => [
        for (final l in lines)
          () {
            final ht = (l.unitPrice.min / 1.2 * 100).roundToDouble() / 100;
            return SupplyLine(l.section, l.name, 'prix fournisseur HT remisé', l.qty, l.unit, PriceRange(ht, ht));
          }(),
      ];
}

/// Caissons, façades, joues et kits tiroirs de la cuisine au tarif du fournisseur.
/// Le plan de travail, l'électroménager et la quincaillerie (hors tiroirs) ne sont pas compris.
SupplierQuote supplierQuote(LayoutEngine e, SupplierTariff t, {bool gloss = false}) {
  final k = 1 - t.discountPct / 100;
  final groups = <String, (double, double, String)>{}; // nom → (qté, brut unitaire cumulé, section)
  var gross = 0.0, net = 0.0;
  void add(String section, String name, double qty, double unitGross, {double? discount}) {
    if (qty <= 0 || unitGross <= 0) return;
    final kk = discount == null ? k : 1 - discount / 100;
    gross += qty * unitGross;
    net += qty * unitGross * kk;
    final key = '$section|$name|${(unitGross * kk).toStringAsFixed(2)}';
    final cur = groups[key];
    groups[key] = ((cur?.$1 ?? 0) + qty, unitGross * kk, section);
  }

  final fam = gloss ? 'MDF brillant' : 'MDF décor';
  for (final c in e.project.items) {
    final m = e.modelOf(c);
    final w = c.width / 1000, h = c.height / 1000;
    final dims = '${(c.height / 10).round()}x${(c.width / 10).round()}';
    if (m.kind.isFiller || m.kind == CabinetKind.coverPanel || m.kind == CabinetKind.islandPanel) {
      add('Façades', 'Fileur / joue $dims $fam', 1, t.front(w * h, gloss: gloss));
      continue;
    }
    if (m.isCarcass) {
      final double carcass;
      if (m.kind == CabinetKind.tall) {
        final fridge = e.isCooling(m);
        final oven = m.id.contains('oven');
        final ref = fridge ? t.tallFridge : oven ? t.tallOven : t.tallFridge;
        carcass = ref * (w / 0.6) * (c.height / 2000);
      } else if (m.kind.isHigh) {
        carcass = (t.wallA + t.wallB * w) * (c.height / 700);
      } else {
        carcass = t.baseA + t.baseB * w;
      }
      final kind = switch (m.kind) {
        CabinetKind.tall => 'Colonne',
        CabinetKind.wall || CabinetKind.cornerWall => 'Caisson haut',
        _ => 'Caisson bas',
      };
      add('Caissons', '$kind $dims latté blanc 18 mm', 1, carcass);
    }
    // façades : chaque case qui s'ouvre (portes doubles = deux portes)
    final cells = openableCells(m, c);
    if (cells.isEmpty) continue;
    final scale = cellScale(m, c);
    var drawers = 0;
    for (final cell in cells) {
      final hh = cell.h * scale / 1000;
      final n = cell.kind == CellKind.door2 ? 2 : 1;
      final ww = w / n;
      add('Façades', '${cell.kind == CellKind.drawer ? 'Façade tiroir' : 'Porte'} ${(hh * 100).round()}x${(ww * 100).round()} $fam', n.toDouble(),
          t.front(ww * hh, gloss: gloss));
      if (cell.kind == CellKind.drawer) drawers++;
    }
    add('Tiroirs', 'Fond et arrière de tiroir ${(c.width / 10).round()} cm', drawers.toDouble(), t.drawerKit, discount: t.drawerDiscountPct);
  }
  for (final j in endPanels(e)) {
    add('Façades', 'Joue ${(j.height / 10).round()}x${(j.depth / 10).round()} $fam', 1, t.front(j.height * j.depth / 1e6, gloss: gloss));
  }
  final lines = [
    for (final MapEntry(:key, :value) in groups.entries)
      SupplyLine(value.$3, key.split('|')[1], 'prix fournisseur TTC remisé', value.$1, 'pce', PriceRange(value.$2, value.$2)),
  ]..sort((a, b) => a.section.compareTo(b.section));
  return SupplierQuote(lines, gross, net);
}

/// Lignes du devis selon la gamme du projet :
/// - standard (MDF) : panneaux à la feuille, chants et découpe au tarif de l'atelier ;
/// - moyenne gamme : caissons et façades à l'article au tarif Media Progetti ;
/// - luxe (latté) : caissons, façades, joues et tiroirs facturés à l'article au tarif fournisseur,
///   le reste (plan de travail, électroménager, quincaillerie) inchangé.
List<SupplyLine> quoteLines(LayoutEngine e, MaterialsDb db, ProjectSpecs specs, CutPlan plan, Bom bom, SupplierTariff? t, {bool gloss = false}) {
  final mp = MediaProgetti.instance;
  if (specs.gamme == 'moyen' && mp != null) return mediaProgettiQuote(e, db, specs, plan, bom, mp, t);
  final base = estimate(e, db, specs, plan, bom);
  if (specs.gamme != 'luxe' || t == null) return base;
  return [
    ...supplierQuote(e, t, gloss: gloss).linesHt,
    ...base.where((l) => l.section != 'Panneaux' && l.section != 'Chants'),
  ];
}
