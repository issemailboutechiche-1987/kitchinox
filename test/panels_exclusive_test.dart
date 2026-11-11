// Tablette : un article touché dans le menu se pose directement ; un seul panneau ouvert à la fois.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/main.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/panels.dart';

void main() {
  testWidgets('menu Éléments de rangement : clic = article posé, menu refermé ; catalogue et fiche jamais ensemble', (t) async {
    t.view.physicalSize = const Size(1180, 820);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
    await t.pumpAndSettle();
    st.goTo(PlanStep.layout);
    st.toggleMegaMenu(true);
    await t.pumpAndSettle();
    final name = st.catalog['base_drawers_multi'].name;
    await t.tap(find.text(name).first);
    await t.pumpAndSettle();
    expect(st.project.items.single.modelId, 'base_drawers_multi');
    expect(st.megaMenu, isFalse);
    expect(st.browse, isNull);

    // catalogue ouvert : l'élément ajouté reste choisi mais la fiche ne s'ouvre pas par-dessus
    st.openBrowse(const CatalogBrowse(Shelf.base));
    await t.pumpAndSettle();
    expect(find.byType(CatalogPanel), findsOneWidget);
    expect(find.byType(InspectorCard), findsNothing);
    // toucher l'élément dans le plan : la fiche s'ouvre, le catalogue se ferme
    st.select(st.project.items.single.uid);
    await t.pumpAndSettle();
    expect(find.byType(CatalogPanel), findsNothing);
    expect(find.byType(InspectorCard), findsOneWidget);
    // ouvrir le menu ferme le catalogue
    st.openBrowse(const CatalogBrowse(Shelf.base));
    st.toggleMegaMenu(true);
    expect(st.browse, isNull);
    expect(t.takeException(), isNull);
  });
}
