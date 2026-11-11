// L'app vise les tablettes et les grands écrans : chaque étape est parcourue aux tailles courantes
// (en paysage : le portrait affiche « tournez votre tablette ») sans débordement, avec une capture par taille dans test/goldens/tablet.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/home_screen.dart';

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

const sizes = {
  'ipad_paysage_1180x820': Size(1180, 820),
  'tablette_paysage_1024x768': Size(1024, 768),
  'ipad_pro_1366x1024': Size(1366, 1024),
  'ecran_1920x1080': Size(1920, 1080),
};

void main() {
  setUpAll(_loadFonts);

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('tablette / grand écran : $name', (t) async {
      final st = await pumpApp(t, size: size);
      sampleKitchen(st);
      final problems = <String>[];
      Future<void> step(String label, void Function() action) async {
        action();
        await t.pumpAndSettle();
        final ex = t.takeException();
        if (ex != null) problems.add('$label : $ex');
      }

      await step('espace', () => st.goTo(PlanStep.space));
      await step('implantation + fiche', () {
        st.goTo(PlanStep.layout);
        st.setView(ViewMode.plan);
        st.select(st.project.items[2].uid);
      });
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tablet/${name}_implantation.png'));
      await step('vue de face', () => st.setView(ViewMode.front));
      await step('catalogue', () {
        st.select(null);
        st.toggleMegaMenu(true);
      });
      await step('style', () {
        st.toggleMegaMenu(false);
        st.goTo(PlanStep.style);
      });
      await step('récapitulatif', () => st.goTo(PlanStep.summary));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tablet/${name}_recap.png'));
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }

  testWidgets("tablette tenue droite : pas de message, l'app reste en paysage (affichage tourné)", (t) async {
    t.view.physicalSize = const Size(820, 1180);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(builder: (c, child) => LandscapeLock(child: child!), home: Builder(builder: (c) => Text('${MediaQuery.sizeOf(c).width.round()}x${MediaQuery.sizeOf(c).height.round()}'))));
    await t.pump();
    expect(find.text('1180x820'), findsOneWidget, reason: "l'app se voit en paysage");
    expect(find.byType(RotatedBox), findsOneWidget);
    expect(find.text('Tournez votre tablette'), findsNothing);
    t.view.physicalSize = const Size(1180, 820);
    await t.pump();
    expect(find.text('1180x820'), findsOneWidget);
    expect(find.byType(RotatedBox), findsNothing, reason: 'en paysage, rien ne tourne');
  });


}
