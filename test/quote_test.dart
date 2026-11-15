// Devis final : prix unique par ligne selon la gamme du poste, prix saisi, ligne hors devis, remise, TVA,
// validation qui fige le devis, réouverture, sauvegarde et PDF.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/main.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/quote_pdf.dart';

MaterialsDb db() {
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  return MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'), handles: f('handles'));
}

AppState kitchen() {
  final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()), db: db());
  st.engine.applyShape(RoomShape.linear);
  st.engine.add('base_sink', 'A', s: 0, width: 800);
  st.engine.add('base_cooktop_oven', 'A', s: 800, width: 600);
  st.engine.add('base_drawers_multi', 'A', s: 1400, width: 600);
  return st;
}

void main() {
  setUpAll(() {
    PublicPrices.parse(File('assets/data/public_prices.json').readAsStringSync());
    BrandCatalog.parse(File('assets/data/brands.json').readAsStringSync());
  });

  test('prix unique dans la fourchette selon la gamme : bas, milieu, haut', () {
    const r = PriceRange(1000, 3000);
    expect([for (var i = 0; i < 3; i++) priceAtLevel(r, i)], [1000, 2000, 3000]);
    expect(priceAtLevel(const PriceRange(850, 850), 2), 850);
    final lines = [
      const SupplyLine('Électroménager', 'Four', '', 1, 'pce', PriceRange(2000, 4000)),
      const SupplyLine('Panneaux', 'Découpe', '', 3, 'feuille', PriceRange(53, 53)),
      const SupplyLine('Panneaux', 'Découpe', '', 2, 'feuille', PriceRange(53, 53)),
    ];
    final s = QuoteSettings();
    var q = buildQuote(lines, s);
    expect(q.lines.map((l) => l.key), ['Électroménager|Four', 'Panneaux|Découpe', 'Panneaux|Découpe#2']);
    expect(q.subtotal, 3000 + 5 * 53);
    s.levels['Électroménager'] = 2;
    expect(buildQuote(lines, s).lines.first.unitPrice, 4000);
    s.prices['Électroménager|Four'] = 3500;
    s.excluded.add('Panneaux|Découpe#2');
    s.discount = 10;
    q = buildQuote(lines, s);
    expect(q.subtotal, 3500 + 3 * 53);
    expect(q.net, closeTo(3659 * 0.9, 0.01));
    expect(q.total, closeTo(3659 * 0.9 * 1.2, 0.01));
    expect(q.lines.first.edited, isTrue);
  });

  test('projet : gamme et type de produit changent le devis ; la validation le fige ; réouverture', () {
    final st = kitchen();
    final q0 = st.quote;
    expect(q0.sections, containsAll(['Panneaux', 'Chants', 'Plan de travail', 'Quincaillerie', 'Électroménager']));
    expect(q0.total, closeTo(q0.subtotal * 1.2, 0.01));
    // gamme d'un poste
    st.setQuoteLevel('Électroménager', 2);
    final up = st.quote.sectionTotal('Électroménager');
    expect(up, greaterThan(q0.sectionTotal('Électroménager')));
    // type de produit : gamme d'électroménager, panneau du tarif public
    st.setApplianceTier(2);
    expect(st.quote.sectionTotal('Électroménager'), greaterThan(up));
    st.applyPublicPanel(PublicPrices.byId('mdf_noyer_18')!);
    expect(st.quote.of('Panneaux').first.unitPrice, 950);
    // ligne hors devis, prix saisi
    final oven = st.quote.of('Électroménager').first;
    st.setQuoteIncluded(oven.key, false);
    expect(st.quote.of('Électroménager').first.total, 0);
    st.setQuoteIncluded(oven.key, true);
    st.setQuotePrice(oven.key, 1234);
    expect(st.quote.of('Électroménager').first.unitPrice, 1234);

    st.validateQuote('DV-2026-0001', DateTime(2026, 11, 14));
    final frozen = st.quote.total;
    expect(st.quoteValidated, isTrue);
    expect(st.quoteStale, isFalse);
    st.setApplianceTier(0); // le projet change : le devis validé ne bouge pas, mais il est signalé périmé
    expect(st.quote.total, frozen);
    expect(st.quoteStale, isTrue);
    // sauvegarde et relecture
    final back = Project.fromJson(jsonDecode(jsonEncode(st.project.toJson())) as Map<String, dynamic>);
    expect(back.quote.validated!.number, 'DV-2026-0001');
    expect(back.quote.validated!.date, '2026-11-14');
    expect(back.quote.validated!.quote.total, frozen);
    expect(back.quote.prices[oven.key], 1234);
    st.reopenQuote();
    expect(st.quoteValidated, isFalse);
    expect(st.quote.total, isNot(frozen));
  });

  test('PDF du devis : provisoire puis validé', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final st = kitchen();
    st.project.client
      ..company = 'Atlas Bois'
      ..ice = '001234567000089';
    st.setQuoteTerms(discount: 5);
    final a = await buildQuotePdf(st.project, st.quote, date: '2026-11-14');
    expect(utf8.decode(a.sublist(0, 5)), '%PDF-');
    st.validateQuote('DV-2026-0002', DateTime(2026, 11, 14));
    final b = await buildQuotePdf(st.project, st.quote, number: 'DV-2026-0002', date: '2026-11-14', validated: true);
    expect(b.length, greaterThan(2000));
    expect(money(1234567.5), '1 234 567,50');
  });

  testWidgets('Récapitulatif → Devis final : changer la gamme, saisir un prix, valider, rouvrir', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = kitchen();
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
    await t.pumpAndSettle();
    st.goTo(PlanStep.summary);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Devis final'));
    await t.pumpAndSettle();
    await t.tap(find.text('Devis final'));
    await t.pumpAndSettle();
    expect(find.text('Provisoire, modifiable'), findsOneWidget);
    expect(find.text('Total TTC'), findsOneWidget);
    final before = st.quote.total;
    // gamme premium sur l'électroménager
    final level = find.descendant(of: find.byKey(const ValueKey('quote_level_Électroménager')), matching: find.text('Premium'));
    await t.ensureVisible(level);
    await t.pumpAndSettle();
    await t.tap(level);
    await t.pumpAndSettle();
    expect(st.project.quote.levels['Électroménager'], 2);
    expect(st.quote.total, greaterThan(before));
    // prix saisi sur la première ligne
    final line = st.quote.lines.first;
    final price = find.byKey(ValueKey('quote_price_${line.key}'));
    await t.ensureVisible(price);
    await t.pumpAndSettle();
    await t.tap(price);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('quote_price_field')), '777');
    await t.tap(find.text('Appliquer'));
    await t.pumpAndSettle();
    expect(st.quote.lines.first.unitPrice, 777);
    // validation
    await t.ensureVisible(find.byKey(const ValueKey('quote_validate')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('quote_validate')));
    await t.pumpAndSettle();
    expect(st.quoteValidated, isTrue);
    expect(find.byKey(const ValueKey('quote_reopen')), findsOneWidget);
    expect(find.byKey(ValueKey('quote_level_Électroménager')), findsNothing, reason: 'devis figé : plus de choix');
    await t.ensureVisible(find.byKey(const ValueKey('quote_reopen')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('quote_reopen')));
    await t.pumpAndSettle();
    expect(st.quoteValidated, isFalse);
    expect(t.takeException(), isNull);
  });
}
