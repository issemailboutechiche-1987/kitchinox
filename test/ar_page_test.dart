// Tests du mode AR « Voir dans ma pièce » (ar_page.dart).
// Vérifie le parcours, la désactivation des options, l'absence de crash hors navigateur et la capture tablette.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/ui/app_state.dart';

import 'ui_test.dart' show pumpApp, sampleKitchen;

Future<void> _loadFonts() async {
  final flutterRoot = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final dir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final file = File('$dir/$f');
      if (file.existsSync()) l.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await l.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('mode AR : ouverture depuis menu, filtres, aide et préparation sécurisée', (t) async {
    const size = Size(1180, 820);
    final st = await pumpApp(t, size: size);
    sampleKitchen(st);
    st.goTo(PlanStep.layout);
    st.setView(ViewMode.view3d);
    await t.pumpAndSettle();

    // 1. L'écran s'ouvre depuis le menu Affichage (view_ar)
    expect(find.byKey(const ValueKey('view_display')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('view_display')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('view_ar')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('view_ar')));
    await t.pumpAndSettle();

    // L'écran AR est affiché
    expect(find.byKey(const ValueKey('ar_sheet')), findsOneWidget);

    // 2. Les réseaux sont désactivés sans points de réseau
    expect(st.project.points.isEmpty, isTrue);
    final netsCard = find.ancestor(
      of: find.text('Réseaux : électricité, eau, gaz'),
      matching: find.byType(Material),
    );
    expect(netsCard, findsWidgets);

    // 3. Ouvrir le guide court '?'
    final helpBtn = find.byTooltip('Guide AR Quick Look');
    expect(helpBtn, findsOneWidget);
    await t.tap(helpBtn);
    await t.pumpAndSettle();

    expect(find.text('Guide AR : Voir dans ma pièce'), findsOneWidget);
    expect(find.text('Appareils compatibles'), findsOneWidget);
    expect(find.text('Calage du repère L'), findsOneWidget);
    expect(find.text('Échelle réelle 1:1'), findsOneWidget);
    expect(find.text('Lumière recommandée'), findsOneWidget);
    expect(find.text('Limites de mesure'), findsOneWidget);

    // Fermer l'aide
    await t.tap(find.text('Compris'));
    await t.pumpAndSettle();

    // Capture d'écran (Golden) de l'écran AR en paysage 1180x820
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tablet/ar_page.png'));

    // 4. « Préparer » est désactivé si rien n'est coché
    // Par défaut, Cuisine et Repère du coin sont cochés
    expect(find.byKey(const ValueKey('ar_prepare')), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('ar_prepare'))).onPressed, isNotNull);

    // Décocher Cuisine
    await t.tap(find.byKey(const ValueKey('ar_opt_kitchen')));
    await t.pumpAndSettle();

    // Décocher Repère du coin
    await t.tap(find.byKey(const ValueKey('ar_opt_marker')));
    await t.pumpAndSettle();

    // Maintenant rien n'est coché (Cuisine=false, Murs=false, Réseaux=false, Marker=false) -> bouton Préparer désactivé
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('ar_prepare'))).onPressed, isNull);

    // Recocher Cuisine
    await t.tap(find.byKey(const ValueKey('ar_opt_kitchen')));
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('ar_prepare'))).onPressed, isNotNull);

    // 5. Hors navigateur, prepareAr renvoie null : l'écran affiche le message sans planter
    await t.tap(find.byKey(const ValueKey('ar_prepare')));
    await t.pumpAndSettle();

    expect(find.text('Ouvrez la vue 3D pour préparer la réalité augmentée.'), findsOneWidget);

    // Fermer l'écran AR
    await t.tap(find.text('Fermer'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ar_sheet')), findsNothing);

    // 6. Test du bouton direct dans la barre 3D
    final directBtn = find.byKey(const ValueKey('view_ar_button'));
    expect(directBtn, findsOneWidget);
    await t.tap(directBtn);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ar_sheet')), findsOneWidget);

    await t.tap(find.text('Fermer'));
    await t.pumpAndSettle();
  });
}
