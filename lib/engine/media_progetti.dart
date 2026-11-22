/// Tarif Media Progetti (Casablanca), moyenne gamme : caissons blancs Alvic et portes Istanbul ép. 19, à l'article.
/// Prix TTC relevés sur trois devis du 30/12/2023 (assets/data/media_progetti.json) ; le devis les compte hors taxes.
/// Une taille qui n'est pas au tarif est estimée entre les tailles voisines, et marquée « estimé ».
library;

import 'dart:convert';
import 'dart:math' as math;

import 'bom.dart';
import 'catalog.dart';
import 'clearance.dart';
import 'corners.dart';
import 'cutting.dart';
import 'end_panels.dart';
import 'front_layout.dart';
import 'layout_engine.dart';
import 'materials.dart';
import 'supplier.dart';

/// Prix TTC d'un article ; [exact] : au tarif, sinon estimé ; [ref] : référence du fournisseur (vide si estimé).
typedef MpPrice = ({double price, bool exact, String ref});

class MpItem {
  final String ref, line, type;
  final int h, w, d;
  final double price;
  final bool handle; // porte à poignée intégrée
  const MpItem(this.ref, this.line, this.type, this.h, this.w, this.d, this.price, this.handle);
}

class MediaProgetti {
  static MediaProgetti? instance;
  final String supplier, tier, city, activity, date, doorHandle, doorPlain;
  final List<String> sources;
  final double vat;
  final Map<String, String> lines; // alvic, alvic_hydro → désignation
  final List<MpItem> carcasses, doors;
  const MediaProgetti._(this.supplier, this.tier, this.city, this.activity, this.date, this.doorHandle, this.doorPlain, this.sources, this.vat, this.lines,
      this.carcasses, this.doors);

  static MediaProgetti parse(String src) {
    final j = jsonDecode(src) as Map<String, dynamic>;
    MpItem item(Map m) => MpItem('${m['ref']}', '${m['line'] ?? ''}', '${m['type'] ?? 'porte'}', (m['h'] as num).toInt(), (m['w'] as num).toInt(),
        (m['d'] as num?)?.toInt() ?? 19, (m['price'] as num).toDouble(), m['handle'] == true);
    return instance = MediaProgetti._(
      '${j['supplier']}',
      '${j['tier']}',
      '${j['city']}',
      '${j['activity']}',
      '${j['date']}',
      '${j['door_handle']}',
      '${j['door_plain']}',
      [for (final s in j['sources'] as List) '$s'],
      (j['vat'] as num).toDouble(),
      {for (final e in (j['lines'] as Map).entries) '${e.key}': '${e.value}'},
      [for (final m in j['carcasses'] as List) item(m as Map)],
      [for (final m in j['doors'] as List) item(m as Map)],
    );
  }

  /// Prix hors taxes.
  double ht(double ttc) => (ttc / (1 + vat / 100) * 100).roundToDouble() / 100;

  /// Valeur en [x] d'une suite de points triés ; hors des points, proportionnelle au dernier connu.
  static double _interp(List<(double, double)> pts, double x) {
    if (x <= pts.first.$1) return pts.length > 1 ? math.max(pts.first.$2 * x / pts.first.$1, pts.first.$2 - (pts[1].$2 - pts[0].$2) / (pts[1].$1 - pts[0].$1) * (pts.first.$1 - x)) : pts.first.$2 * x / pts.first.$1;
    for (var i = 1; i < pts.length; i++) {
      final (x0, y0) = pts[i - 1];
      final (x1, y1) = pts[i];
      if (x <= x1) return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
    }
    return pts.last.$2 * x / pts.last.$1;
  }

  List<MpItem> _of(String line, String type) => [for (final i in carcasses) if (i.line == line && i.type == type) i];

  /// Prix d'un caisson à la hauteur [h] dans une suite de même type, par largeur.
  double _width(List<MpItem> row, int w) {
    final pts = [for (final i in row) (i.w.toDouble(), i.price)]..sort((a, b) => a.$1.compareTo(b.$1));
    return _interp(pts, w.toDouble());
  }

  /// Caisson [type] (bas, evier, four, haut, surhotte, colonne, angle_bas_l, angle_haut_l, angle_haut_c) de la ligne [line].
  MpPrice carcass(String line, String type, int w, int h) {
    for (final i in carcasses) {
      if (i.line != line || i.w != w || i.h != h) continue;
      if (i.type == type || (type == 'colonne' && i.type == 'semi_colonne')) return (price: i.price, exact: true, ref: i.ref);
    }
    MpPrice est(double v) => (price: v, exact: false, ref: '');
    switch (type) {
      case 'colonne':
        final row = [..._of(line, 'semi_colonne'), ..._of(line, 'colonne')]..sort((a, b) => a.h.compareTo(b.h));
        return est(_interp([for (final i in row) (i.h.toDouble(), i.price)], h.toDouble()) * w / 600);
      case 'surhotte':
        final row = _of(line, type);
        final near = row.reduce((a, b) => (a.w - w).abs() <= (b.w - w).abs() ? a : b);
        return est(near.price * w / near.w * math.max(0.8, h / near.h));
      case 'haut':
        final at700 = _width([for (final i in _of(line, type)) if (i.h == 700) i], w);
        if (h <= 700) return est(at700 * math.max(0.6, h / 700));
        // au-dessus : les hauteurs 900 ne sont tarifées qu'en hydrofuge, on garde leur rapport à la hauteur 700
        final k = _width([for (final i in _of('alvic_hydro', type)) if (i.h == 900) i], w) / _width([for (final i in _of('alvic_hydro', type)) if (i.h == 700) i], w);
        return est(h <= 900 ? at700 * (1 + (k - 1) * (h - 700) / 200) : at700 * k * h / 900);
      case 'four':
        final i = _of(line, type).first;
        return est(i.price * w / i.w * h / i.h);
      default:
        final row = _of(line, type);
        if (type.startsWith('angle')) {
          // une seule largeur au tarif : proportion de la largeur, et de la hauteur entre celles du tarif
          row.sort((a, b) => a.h.compareTo(b.h));
          final at = row.length == 1 ? row.first.price * h / row.first.h : _interp([for (final i in row) (i.h.toDouble(), i.price)], h.toDouble());
          return est(math.max(at, row.first.price * 0.5) * w / row.first.w);
        }
        return est(_width(row, w) * h / 700);
    }
  }

  /// Porte ou façade de [h] × [w] mm.
  MpPrice door(int h, int w, {required bool handle}) {
    for (final i in doors) {
      if (i.handle == handle && i.h == h && i.w == w) return (price: i.price, exact: true, ref: i.ref);
    }
    MpPrice est(double v) => (price: v, exact: false, ref: '');
    final rows = <int, List<MpItem>>{};
    for (final i in doors.where((i) => i.handle)) {
      (rows[i.h] ??= []).add(i);
    }
    final hs = rows.keys.toList()..sort();
    double withHandle() => _interp([for (final k in hs) (k.toDouble(), _width(rows[k]!, w))], h.toDouble());
    if (handle) return est(withHandle());
    // sans poignée, quatre prix seulement : rapport au prix avec poignée, à la hauteur voisine
    double ratio(int hh, int ww) =>
        doors.firstWhere((i) => !i.handle && i.h == hh && i.w == ww).price / doors.firstWhere((i) => i.handle && i.h == hh && i.w == ww).price;
    final k = _interpClamped([(700, (ratio(700, 350) + ratio(700, 600)) / 2), (1300, ratio(1300, 600)), (2000, ratio(2000, 600))], h.toDouble());
    return est(withHandle() * k);
  }

  static double _interpClamped(List<(double, double)> pts, double x) => x <= pts.first.$1
      ? pts.first.$2
      : x >= pts.last.$1
          ? pts.last.$2
          : _interp(pts, x);

  /// Type de caisson du tarif pour un meuble.
  static String typeOf(CabinetModel m) {
    if (m.kind == CabinetKind.tall || m.kind == CabinetKind.cornerTall) return 'colonne';
    if (m.kind == CabinetKind.cornerBase) return m.id.contains('blind') ? 'bas' : 'angle_bas_l';
    if (m.kind == CabinetKind.cornerWall) return m.id.contains('blind') ? 'haut' : (m.id.contains('diagonal') ? 'angle_haut_c' : 'angle_haut_l');
    if (m.kind.isHigh) return m.isHoodUnit ? 'surhotte' : 'haut';
    if (m.id.contains('sink')) return 'evier';
    if (m.id.contains('oven')) return 'four';
    return 'bas';
  }

  /// Porte à poignée intégrée pour ce projet : le choix du devis, sinon d'après les poignées dessinées.
  static bool integratedHandle(LayoutEngine e, ProjectSpecs s) =>
      s.mpDoor == 'pi' || (s.mpDoor == 'auto' && const {'edge', 'groove', 'chamfer'}.contains(e.project.style.handle));
}

/// Caissons, façades et joues du projet au tarif Media Progetti, prix hors taxes.
List<SupplyLine> mediaProgettiLines(LayoutEngine e, MediaProgetti t, ProjectSpecs specs) {
  final line = t.lines.containsKey(specs.mpCarcass) ? specs.mpCarcass : t.lines.keys.first;
  final handle = MediaProgetti.integratedHandle(e, specs);
  final groups = <String, (String, String, double, double, String)>{}; // clé → (poste, nom, qté, HT, détail)
  void add(String section, String name, double qty, MpPrice p) {
    if (qty <= 0) return;
    final ttc = p.price.toStringAsFixed(2).replaceAll('.', ',');
    final detail = p.exact ? 'Media Progetti ${p.ref} · $ttc TTC' : 'Media Progetti · estimé · $ttc TTC';
    final key = '$section|$name|$detail';
    groups[key] = (section, name, (groups[key]?.$3 ?? 0) + qty, t.ht(p.price), detail);
  }

  for (final c in e.project.items) {
    final m = e.modelOf(c);
    if (m.isFreeHood) continue;
    if (m.kind.isFiller || m.kind == CabinetKind.coverPanel || m.kind == CabinetKind.islandPanel) {
      final w = m.kind == CabinetKind.coverPanel ? c.depth : c.width;
      add('Façades', 'Fileur / joue ${c.height} x $w mm', 1, t.door(c.height, w, handle: false));
      continue;
    }
    if (m.isCarcass) {
      add('Caissons', '${t.lines[line]} ${mpTypeLabels[MediaProgetti.typeOf(m)]} ${c.height} x ${c.width} mm', 1, t.carcass(line, MediaProgetti.typeOf(m), c.width, c.height));
    }
    final cells = openableCells(m, c);
    final scale = cellScale(m, c);
    if (m.kind.isCorner && m.isCarcass) {
      // portes d'angle : cotes du débit
      final gola = e.project.style.handle == 'gola' && m.kind == CabinetKind.cornerBase;
      final cs = e.project.cut;
      for (final (kind, name, a, b, q, _, _) in cornerCutList(m, c, T: cs.carcassThickness, td: cs.doorThickness, gap: cs.frontGap, gola: gola)) {
        if (kind != 'facade') continue;
        final h = math.max(a, b), w = math.min(a, b);
        add('Façades', '$name $h x $w mm · ${handle ? 'poignée intégrée' : 'sans poignée'}', q.toDouble(), t.door(h, w, handle: handle));
      }
    }
    for (final cell in cells) {
      final n = cell.kind == CellKind.door2 ? 2 : 1;
      final h = (cell.h * scale / 5).round() * 5, w = (c.width / n / 5).round() * 5;
      final label = cell.kind == CellKind.drawer ? 'Façade tiroir' : 'Porte';
      add('Façades', '$label $h x $w mm · ${handle ? 'poignée intégrée' : 'sans poignée'}', n.toDouble(), t.door(h, w, handle: handle));
    }
  }
  if (e.project.style.endPanels) {
    for (final j in endPanels(e)) {
      add('Façades', 'Joue ${j.height.round()} x ${j.depth.round()} mm', 1, t.door(j.height.round(), j.depth.round(), handle: false));
    }
  }
  return [for (final (s, n, q, p, d) in groups.values) SupplyLine(s, n, d, q, 'pce', PriceRange(p, p))]..sort((a, b) => a.section.compareTo(b.section));
}

/// Type de caisson affiché.
const mpTypeLabels = {
  'semi_colonne': 'semi-colonne',
  'bas': 'bas',
  'evier': 'bas évier',
  'four': 'bas four',
  'haut': 'haut',
  'surhotte': 'surhotte',
  'colonne': 'colonne',
  'angle_bas_l': 'bas angle en L',
  'angle_haut_l': 'haut angle en L',
  'angle_haut_c': 'haut angle en C',
};

/// Devis moyenne gamme : caissons et façades Media Progetti, le reste (tiroirs, plan de travail, quincaillerie,
/// électroménager) comme d'habitude ; sans poignées quand les portes ont la poignée intégrée.
List<SupplyLine> mediaProgettiQuote(LayoutEngine e, MaterialsDb db, ProjectSpecs specs, CutPlan plan, Bom bom, MediaProgetti t, SupplierTariff? other) {
  final noHandles = <String>{
    if (MediaProgetti.integratedHandle(e, specs)) ...[
      for (final l in handleLines(e, db, plan.parts)) l.name,
      if (db.hardware['handle_standard_screw_on'] != null) db.hardware['handle_standard_screw_on']!.name,
    ],
  };
  return [
    ...mediaProgettiLines(e, t, specs),
    // fonds et arrières de tiroir : pas au tarif Media Progetti
    if (other != null) ...supplierQuote(e, other).lines.where((l) => l.section == 'Tiroirs'),
    ...estimate(e, db, specs, plan, bom)
        .where((l) => l.section != 'Panneaux' && l.section != 'Chants' && !(l.section == 'Quincaillerie' && noHandles.contains(l.name))),
  ];
}
