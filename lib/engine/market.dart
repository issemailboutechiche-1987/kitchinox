/// Repères de marché : marques mondiales de quincaillerie, prix indicatifs (EUR et MAD) de la vis à la feuille,
/// panneaux par gamme et fabricants exportateurs. Source : assets/data/market.json (liste fournie par l'atelier).
library;

import 'dart:convert';

import 'materials.dart';

class MarketBrand {
  final String name, country, tier, test, site;
  final List<String> specialties;
  const MarketBrand(this.name, this.country, this.tier, this.specialties, this.test, this.site);
}

class MarketArticle {
  final String category, name;
  final PriceRange eur, mad;
  const MarketArticle(this.category, this.name, this.eur, this.mad);
}

class MarketPanels {
  final String tier, usage;
  final List<String> brands, types;
  final List<(int, int)> sizes;
  final List<int> thicknesses;
  final PriceRange eur, mad;
  const MarketPanels(this.tier, this.brands, this.types, this.sizes, this.thicknesses, this.eur, this.mad, this.usage);
}

class MarketMaker {
  final String name, sector, country, about, address, phone, email, site, catalog;
  const MarketMaker(this.name, this.sector, this.country, this.about, this.address, this.phone, this.email, this.site, this.catalog);
}

class Market {
  static final List<MarketBrand> brands = [];
  static final List<MarketArticle> articles = [];
  static final List<MarketPanels> panels = [];
  static final List<MarketMaker> makers = [];
  static String note = '';

  static void parse(String src) {
    final j = jsonDecode(src) as Map<String, dynamic>;
    List<String> strs(Object? v) => [for (final x in v as List) '$x'];
    PriceRange range(Object? a, Object? b) => PriceRange((a as num).toDouble(), (b as num).toDouble());
    note = '${j['note']}';
    brands
      ..clear()
      ..addAll([for (final b in j['brands'] as List) MarketBrand('${b[0]}', '${b[1]}', '${b[2]}', strs(b[3]), '${b[4]}', '${b[5]}')]);
    articles
      ..clear()
      ..addAll([for (final a in j['articles'] as List) MarketArticle('${a[0]}', '${a[1]}', range(a[2], a[3]), range(a[4], a[5]))]);
    panels
      ..clear()
      ..addAll([
        for (final p in j['panels'] as List)
          MarketPanels(
              '${p['tier']}',
              strs(p['brands']),
              strs(p['types']),
              [for (final s in p['sizes'] as List) ((s[0] as num).toInt(), (s[1] as num).toInt())],
              [for (final t in p['thicknesses'] as List) (t as num).toInt()],
              range(p['eur'][0], p['eur'][1]),
              range(p['mad'][0], p['mad'][1]),
              '${p['usage']}'),
      ]);
    makers
      ..clear()
      ..addAll([
        for (final m in j['makers'] as List) MarketMaker('${m[0]}', '${m[1]}', '${m[2]}', '${m[3]}', '${m[4]}', '${m[5]}', '${m[6]}', '${m[7]}', '${m[8]}'),
      ]);
  }

  static List<String> get categories => {for (final a in articles) a.category}.toList();
}
