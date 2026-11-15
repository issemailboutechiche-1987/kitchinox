/// Devis final : toutes les lignes chiffrées du projet (panneaux, chants, plan de travail, quincaillerie,
/// électroménager, sanitaires) ramenées à un prix unique, modifiables poste par poste (niveau de gamme, prix
/// saisi, ligne hors devis), puis figées à la validation avec remise et TVA.
library;

import 'materials.dart';

/// Niveaux de gamme d'un poste : position dans la fourchette de prix.
const quoteLevels = ['Économique', 'Standard', 'Premium'];

/// Ligne du devis : un prix unitaire unique.
class QuoteLine {
  final String key; // identifiant stable de la ligne dans le projet
  final String section, name, detail, unit;
  final double qty;
  final double unitPrice;
  final double min, max; // fourchette d'origine (égales si prix ferme)
  final bool included; // false : hors devis (fourni par le client)
  final bool edited; // prix saisi à la main
  const QuoteLine(this.key, this.section, this.name, this.detail, this.qty, this.unit, this.unitPrice,
      {this.min = 0, this.max = 0, this.included = true, this.edited = false});

  double get total => included ? unitPrice * qty : 0;
  bool get ranged => max > min;

  /// Ligne sans prix connu : à chiffrer avant de valider.
  bool get unpriced => included && unitPrice == 0;

  Map<String, dynamic> toJson() => {
        'key': key,
        'section': section,
        'name': name,
        if (detail.isNotEmpty) 'detail': detail,
        'qty': qty,
        'unit': unit,
        'price': unitPrice,
        if (!included) 'included': false,
      };

  factory QuoteLine.fromJson(Map<String, dynamic> j) {
    final p = (j['price'] as num?)?.toDouble() ?? 0;
    return QuoteLine('${j['key'] ?? ''}', '${j['section'] ?? ''}', '${j['name'] ?? ''}', '${j['detail'] ?? ''}', (j['qty'] as num?)?.toDouble() ?? 0,
        '${j['unit'] ?? ''}', p,
        min: p, max: p, included: j['included'] != false);
  }
}

/// Devis calculé : lignes, sous-totaux par poste, remise, TVA.
class Quote {
  final List<QuoteLine> lines;
  final double discount; // remise en %
  final double vat; // TVA en %
  const Quote(this.lines, {this.discount = 0, this.vat = 20});

  List<String> get sections => {for (final l in lines) l.section}.toList();
  List<QuoteLine> of(String section) => [for (final l in lines) if (l.section == section) l];
  double sectionTotal(String section) => of(section).fold(0, (a, l) => a + l.total);

  /// Total des lignes, hors taxes, avant remise.
  double get subtotal => lines.fold(0, (a, l) => a + l.total);
  double get discountAmount => _r2(subtotal * discount / 100);

  /// Total hors taxes après remise.
  double get net => _r2(subtotal - discountAmount);
  double get vatAmount => _r2(net * vat / 100);

  /// Total toutes taxes comprises.
  double get total => _r2(net + vatAmount);

  int get unpriced => lines.where((l) => l.unpriced).length;

  Map<String, dynamic> toJson() => {
        'lines': [for (final l in lines) l.toJson()],
        'discount': discount,
        'vat': vat,
      };

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
        [for (final l in (j['lines'] as List? ?? const [])) QuoteLine.fromJson((l as Map).cast<String, dynamic>())],
        discount: (j['discount'] as num?)?.toDouble() ?? 0,
        vat: (j['vat'] as num?)?.toDouble() ?? 20,
      );
}

double _r2(double v) => (v * 100).roundToDouble() / 100;

/// Devis validé : figé à une date, avec son numéro.
class ValidatedQuote {
  final String? number;
  final String date; // AAAA-MM-JJ
  final Quote quote;
  const ValidatedQuote(this.number, this.date, this.quote);

  Map<String, dynamic> toJson() => {if (number != null) 'number': number, 'date': date, ...quote.toJson()};

  factory ValidatedQuote.fromJson(Map<String, dynamic> j) => ValidatedQuote(j['number'] as String?, '${j['date'] ?? ''}', Quote.fromJson(j));
}

/// Choix du devis enregistrés dans le projet.
class QuoteSettings {
  final Map<String, int> levels; // poste → 0 économique, 1 standard, 2 premium
  final Map<String, double> prices; // ligne → prix unitaire saisi
  final Set<String> excluded; // lignes hors devis
  double discount; // %
  double vat; // %
  ValidatedQuote? validated;

  QuoteSettings({Map<String, int>? levels, Map<String, double>? prices, Set<String>? excluded, this.discount = 0, this.vat = 20, this.validated})
      : levels = levels ?? {},
        prices = prices ?? {},
        excluded = excluded ?? {};

  int levelOf(String section) => (levels[section] ?? 1).clamp(0, 2);

  bool get isDefault => levels.isEmpty && prices.isEmpty && excluded.isEmpty && discount == 0 && vat == 20 && validated == null;

  Map<String, dynamic> toJson() => {
        if (levels.isNotEmpty) 'levels': levels,
        if (prices.isNotEmpty) 'prices': prices,
        if (excluded.isNotEmpty) 'excluded': excluded.toList(),
        if (discount != 0) 'discount': discount,
        if (vat != 20) 'vat': vat,
        if (validated != null) 'validated': validated!.toJson(),
      };

  factory QuoteSettings.fromJson(Map<String, dynamic> j) => QuoteSettings(
        levels: {for (final e in ((j['levels'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
        prices: {for (final e in ((j['prices'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toDouble()},
        excluded: {for (final e in (j['excluded'] as List? ?? const [])) '$e'},
        discount: (j['discount'] as num?)?.toDouble() ?? 0,
        vat: (j['vat'] as num?)?.toDouble() ?? 20,
        validated: j['validated'] is Map ? ValidatedQuote.fromJson((j['validated'] as Map).cast<String, dynamic>()) : null,
      );
}

/// Prix retenu dans une fourchette selon le niveau de gamme (0 bas, 1 milieu, 2 haut), arrondi au dirham.
double priceAtLevel(PriceRange p, int level) {
  if (p.max <= p.min) return p.min;
  final v = p.min + (p.max - p.min) * level.clamp(0, 2) / 2;
  return v.roundToDouble();
}

/// Devis du projet : les lignes de l'estimation, chacune à un prix unique selon les choix [s].
Quote buildQuote(List<SupplyLine> lines, QuoteSettings s) {
  final seen = <String, int>{};
  final out = <QuoteLine>[];
  for (final l in lines) {
    final base = '${l.section}|${l.name}';
    final n = seen[base] = (seen[base] ?? 0) + 1;
    final key = n == 1 ? base : '$base#$n';
    final typed = s.prices[key];
    out.add(QuoteLine(key, l.section, l.name, l.detail, l.qty, l.unit, typed ?? priceAtLevel(l.unitPrice, s.levelOf(l.section)),
        min: l.unitPrice.min, max: l.unitPrice.max, included: !s.excluded.contains(key), edited: typed != null));
  }
  return Quote(out, discount: s.discount, vat: s.vat);
}
