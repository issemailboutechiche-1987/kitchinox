// Aménagements intérieurs en 3D : chaque article du catalogue a une famille connue,
// et un caisson équipé envoie son volume utile et sa description à la vue 3D.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/scene_export.dart';
import 'package:kitchen_planner/ui/textures.dart';

const families = {
  'none', 'basket_pullout', 'drawer_box', 'tall_pantry', 'carousel', 'corner_pullout', 'lift', 'pulldown_shelf', 'bins', 'organizer', 'rack', 'rod', //
};

void main() {
  setUpAll(() {
    KitchenAccessoriesCatalog.parse(File('assets/data/kitchen_accessories_catalog.json').readAsStringSync());
    KitchenAccessoriesCatalog.parse(File('assets/data/klaus_ma_catalog.json').readAsStringSync(), clear: false);
  });

  test('chaque article des deux catalogues a une famille du contrat', () {
    expect(KitchenAccessoriesCatalog.all.length, greaterThan(150));
    final unknown = [
      for (final a in KitchenAccessoriesCatalog.all)
        if (!families.contains(model3dOf(a)['family'])) '${a.id} → ${model3dOf(a)['family']}',
    ];
    expect(unknown, isEmpty);
  });

  test('déduction depuis le type quand le catalogue ne dit rien', () {
    String fam(String type, {String cat = 'base'}) => model3dOf(KitchenAccessory(
          id: 'x', code: 'x', brand: 'INOXA', collection: '', category: cat, type: type, nameFr: '', price: PriceRange.zero)).values.first as String;
    expect(fam('carousel_3_4', cat: 'corner'), 'carousel');
    expect(fam('lemans_kidney_corner', cat: 'corner'), 'corner_pullout');
    expect(fam('pantry_column_pullout_120kg', cat: 'column'), 'tall_pantry');
    expect(fam('u_shaped_under_sink_drawer', cat: 'under_sink'), 'drawer_box');
    expect(fam('pull_out_waste_sorting_bin', cat: 'under_sink'), 'bins');
    expect(fam('hinge_35mm_soft_close', cat: 'hardware'), 'none');
    expect(fam('pull_out_base_3_tier'), 'basket_pullout');
    final m = model3dOf(KitchenAccessory(id: 'x', code: 'x', brand: 'INOXA', collection: '', category: 'base', type: 'pull_out_base_3_tier', nameFr: '', price: PriceRange.zero));
    expect(m['tiers'], 3);
  });

  test('le catalogue l’emporte quand il a un model3d', () {
    final a = KitchenAccessory(
        id: 'y', code: 'y', brand: 'INOXA', collection: '', category: 'base', type: 'pull_out_base_2_tier', nameFr: '', price: PriceRange.zero,
        model3d: const {'family': 'rack', 'type': 'bottle', 'tiers': 3});
    expect(model3dOf(a), {'family': 'rack', 'type': 'bottle', 'tiers': 3});
  });

  testWidgets('caisson équipé : la 3D reçoit son volume utile et son aménagement', (t) async {
    final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
    final st = AppState(cat, project: Project(room: Room(width: 3600, depth: 3000, height: 2600)));
    final c = st.engine.add('base_standard_single_door', 'A', s: 600, width: 600);
    final acc = KitchenAccessoriesCatalog.all.firstWhere((a) => model3dOf(a)['family'] == 'basket_pullout');
    st.setCabinetAccessory(c.uid, acc.id);
    await t.runAsync(() async {
      await TextureBank.instance.init();
      final scene = await SceneExporter().build(st);
      final fits = [for (final f in scene['fittings'] as List) if (f['uid'] == c.uid) f];
      expect(fits, hasLength(1));
      final f = fits.single;
      expect(f['spec']['family'], 'basket_pullout');
      expect(f['w'], closeTo(c.width - 36, 1), reason: 'entre les deux côtés de 18 mm');
      expect(f['h'], greaterThan(500));
      expect(f['d'], greaterThan(400));
      expect(f['z'], closeTo(c.z + 18, 1), reason: 'posé sur le dessous du caisson');
    });
  });

  testWidgets('tiroir en haut, porte en bas : le panier suit la porte et reste sous le tiroir', (t) async {
    final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
    final st = AppState(cat, project: Project(room: Room(width: 3600, depth: 3000, height: 2600)));
    final c = st.engine.add('base_door_drawer', 'A', s: 600, width: 600);
    st.setCabinetAccessory(c.uid, KitchenAccessoriesCatalog.all.firstWhere((a) => model3dOf(a)['family'] == 'basket_pullout').id);
    await t.runAsync(() async {
      await TextureBank.instance.init();
      final scene = await SceneExporter().build(st);
      final fit = [for (final f in scene['fittings'] as List) if (f['uid'] == c.uid) f].single;
      final parts = [for (final f in scene['fronts'] as List) if (f['uid'] == c.uid) ...(f['parts'] as List)];
      final door = parts.firstWhere((p) => p['kind'] == 'door');
      final drawer = parts.firstWhere((p) => p['kind'] == 'drawer');
      expect(fit['k'], door['k'], reason: 'il suit la porte, pas le tiroir');
      expect(fit['k'], isNot(drawer['k']));
      final top = (fit['z'] as num) + (fit['h'] as num);
      expect(top, lessThanOrEqualTo((door['z1'] as num) + 0.5), reason: 'il reste dans la case de la porte');
      expect(top, lessThan((drawer['z0'] as num) + 0.5), reason: 'sous le tiroir');
    });
  });
}
