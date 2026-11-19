// Prix publics des panneaux : tarif lu, appliqué au projet (prix, format, épaisseur, chants), fond arrière chiffré.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/main.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/brands_ui.dart';

MaterialsDb db() {
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  return MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'), handles: f('handles'));
}

AppState kitchen() {
  final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()), db: db());
  st.engine.applyShape(RoomShape.linear);
  st.engine.add('base_sink', 'A', s: 0, width: 800);
  st.engine.add('base_drawers_multi', 'A', s: 800, width: 600);
  return st;
}

void main() {
  setUpAll(() {
    PublicPrices.parse(File('assets/data/public_prices.json').readAsStringSync());
    BrandCatalog.parse(File('assets/data/brands.json').readAsStringSync());
  });

  test('tarif public : 22 panneaux, prix du relevé, chants 9 à 10 MAD/m', () {
    expect(PublicPrices.panels, hasLength(22));
    double price(String id) => PublicPrices.byId(id)!.price;
    expect((price('mdf_blanc_18'), price('mdf_sonoma_18'), price('mdf_noyer_18'), price('mdf_chene_18')), (850, 850, 950, 900));
    expect((price('latte_blanc_bois_rouge_cp'), price('latte_blanc_bois_rouge_hydro'), price('latte_chene_bois_rouge'), price('latte_chene_normal')),
        (750, 800, 850, 750));
    expect((price('strati_blanc_16'), price('strati_blanc_18'), price('strati_decor_16'), price('strati_decor_18')), (600, 700, 650, 750));
    expect((price('mdf_blanc_8'), price('medlack_blanc_1f_8'), price('mdf_blanc_5'), price('mdf_noyer_8'), price('mdf_noyer_5')), (650, 600, 400, 750, 800));
    final strati = PublicPrices.byId('strati_blanc_18')!;
    expect((strati.length, strati.width, strati.thickness), (2550, 1830, 18));
    expect(PublicPrices.edgeRange, (9, 10));
    expect(PublicPrices.families, ['MDF', 'Latté', 'Stratifié', 'Panneaux minces', 'High Gloss']);
    // fond arrière : le panneau mince blanc le plus proche en épaisseur
    expect(PublicPrices.back(6)!.id, 'mdf_blanc_5');
    expect(PublicPrices.back(8)!.id, 'mdf_blanc_8');
  });

  test('appliquer un panneau du tarif : prix, format de feuille, épaisseur et chants du projet ; annulable', () {
    final st = kitchen();
    st.applyPublicPanel(PublicPrices.byId('strati_decor_16')!);
    expect(st.project.specs.sheetPrice, 650);
    expect((st.project.cut.sheetLength, st.project.cut.sheetWidth, st.project.cut.carcassThickness), (2550, 1830, 16));
    expect((st.project.specs.edgePriceMin, st.project.specs.edgePriceMax), (9, 10));
    final panels = st.estimateLines.where((l) => l.section == 'Panneaux' && l.unit == 'feuille' && l.detail.contains('tarif atelier'));
    expect(panels, isNotEmpty);
    expect(panels.first.unitPrice.min, 650);
    expect(panels.first.detail, contains('2550 x 1830 x 16'));
    st.undo();
    expect(st.project.specs.sheetPrice, 850);
    expect(st.project.cut.sheetLength, 2800);
  });

  test('devis : le fond arrière est chiffré au prix public du MDF mince (avant : prix à demander)', () {
    final st = kitchen();
    final back = st.estimateLines.firstWhere((l) => l.section == 'Panneaux' && l.name.startsWith('HDF'));
    expect(back.unitPrice.min, 400, reason: 'fond de 6 mm → MDF blanc 5 mm à 400 MAD');
    expect(back.detail, contains('prix public'));
    st.edit(() => st.project.cut
      ..backThickness = 8
      ..backMaterial = 'HDF 8 mm');
    final back8 = st.estimateLines.firstWhere((l) => l.section == 'Panneaux' && l.name.startsWith('HDF'));
    expect(back8.unitPrice.min, 650);
  });

  testWidgets('Marques et prix : le tarif public s\'affiche, « Choisir » l\'applique au projet', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = kitchen();
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
    await t.pumpAndSettle();
    st.goTo(PlanStep.summary);
    await t.pumpAndSettle();
    // « Marques et tarifs » s'ouvre depuis l'accueil : même fenêtre
    showBrandsDialog(t.element(find.byType(Scaffold).first), st, (_) {});
    await t.pumpAndSettle();
    expect(find.text('Prix publics des panneaux'), findsOneWidget);
    expect(find.text('MDF noyer'), findsOneWidget);
    final btn = find.byKey(const ValueKey('pub_mdf_noyer_18'));
    await t.ensureVisible(btn);
    await t.pumpAndSettle();
    await t.tap(btn);
    await t.pumpAndSettle();
    expect(st.project.specs.sheetPrice, 950);
    expect(t.takeException(), isNull);
  });
}
