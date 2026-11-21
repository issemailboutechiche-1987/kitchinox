// Bibliothèque de l'atelier : un meuble enregistré se réinsère dans l'atelier et se pose comme objet
// dans les autres modes, dessiné en 3D panneau par panneau ; vue éclatée avec tourillons et vis.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/art_blueprint_pdf.dart';
import 'package:kitchen_planner/ui/art_library.dart';
import 'package:kitchen_planner/ui/art_page.dart';
import 'package:kitchen_planner/ui/scene_export.dart';
import 'package:kitchen_planner/ui/theme.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  test('enregistrer, retrouver dans le catalogue d’objets, poser dans la cuisine, exporter la 3D', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final shared = <CatalogObject>[const CatalogObject('chaise', 'Chaise', 'Repas', 'x.glb', 't.png', 450, 900, 500, false)];
    ArtLibrary.instance
      ..load()
      ..attach(shared);
    final art = ArtProject()..addBox(300, 100, 800, 720, depth: 560, doors: 2);
    final item = ArtLibrary.instance.add('Buffet 800', art.panels);
    expect((item.w, item.h, item.d), (800, 720, 578), reason: 'ramené à l’origine ; portes de 18 mm devant le caisson');
    expect(shared.where((o) => o.id == 'lib:${item.id}'), hasLength(1), reason: 'visible dans le panneau Objets de tous les modes');
    expect(shared.firstWhere((o) => o.id.startsWith('lib:')).category, libraryCategory);

    // pose dans la cuisine (même catalogue partagé)
    final st = AppState(cat)..objectCatalog = shared;
    st.addObject('lib:${item.id}');
    final o = st.project.objects.single;
    expect((o.w, o.h, o.d), (800, 720, 578));
    final scene = await SceneExporter().build(st);
    final obj = (scene['objects'] as List).single as Map;
    final panels = obj['panels'] as List;
    expect(panels, hasLength(item.panels.length));
    // repère de l'objet : centré en largeur, dos en z = 0
    for (final q in panels.cast<Map>()) {
      expect(q['x0'] as double, greaterThanOrEqualTo(-400.5));
      expect(q['x1'] as double, lessThanOrEqualTo(400.5));
      expect(q['z0'] as double, greaterThanOrEqualTo(-0.5));
    }
    // réinsertion : nouveaux identifiants
    final again = item.placedAt(2000, 0, 0, art.newId);
    expect(again.map((p) => p.id).toSet().intersection(art.panels.map((p) => p.id).toSet()), isEmpty);
    // retrait
    ArtLibrary.instance.remove(item.id);
    expect(shared.where((o) => o.id.startsWith('lib:')), isEmpty);
  });

  test('plan de fabrication : PDF complet (vues, nomenclature, fiches, assemblage)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final art = ArtProject()..addBox(0, 100, 800, 720, depth: 560, doors: 2);
    art.addDrawn(19, 460, 762, 18, depth: 540, role: ArtRole.tablette);
    final bytes = await buildArtBlueprint(art, CutSettings(), projectName: 'Essai');
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(20000));
    File('test/out/plan_de_fabrication.pdf')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  });

  testWidgets('vue éclatée : les panneaux s’écartent, tourillons et vis sortent du bois', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(cat);
    st.project.art.addBox(0, 100, 800, 720, depth: 560, doors: 0);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, googleFonts: false), home: ArtPage(state: st)));
    await t.pumpAndSettle();
    await closeArtWelcome(t);
    await expectLater(find.byKey(const Key('art-viewport')), matchesGoldenFile('goldens/art_vis_assemble.png'));
    await t.ensureVisible(find.text('Éclaté'));
    await t.pumpAndSettle();
    await t.tap(find.text('Éclaté'));
    await t.pumpAndSettle();
    await expectLater(find.byKey(const Key('art-viewport')), matchesGoldenFile('goldens/art_vis_eclate.png'));
    expect(t.takeException(), isNull);
  });

}

/// Ferme l'accueil du mode Art (Nouveau / Ouvrir / Bibliothèque) quand la scène est vide.
Future<void> closeArtWelcome(WidgetTester t) async {
  final f = find.byKey(const ValueKey('welcome_close'));
  if (f.evaluate().isNotEmpty) {
    await t.tap(f);
    await t.pumpAndSettle();
  }
}
