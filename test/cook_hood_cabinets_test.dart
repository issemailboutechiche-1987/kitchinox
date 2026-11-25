// Nouveaux caissons : plaque seule (porte, tiroir + porte, tiroirs), four seul (0, 1 ou 2 tiroirs),
// caissons de hotte (télescopique, groupe filtrant, cache-conduit) et hottes posées librement.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/scene_export.dart';
import 'package:kitchen_planner/ui/textures.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  test('plaque seule et four seul : posés, compositions valides, appareils reconnus', () {
    for (final (id, rows) in [
      ('base_cooktop_door', 1),
      ('base_cooktop_drawer_door', 2),
      ('base_cooktop_drawers', 3),
      ('base_oven_no_drawer', 1),
      ('base_oven_only', 2),
      ('base_oven_2drawers', 3),
    ]) {
      final e = LayoutEngine(cat, Project(room: Room(width: 3600, depth: 3000, height: 2600)));
      final c = e.add(id, 'A');
      final m = e.modelOf(c);
      expect(m.kind, CabinetKind.base, reason: id);
      final r = rowsOf(m, c) ?? seedRows(m, c);
      expect(r, hasLength(rows), reason: id);
      expect(layoutProblem(m.kind, r, c.height), isNull, reason: id);
      expect(e.isCooking(m), isTrue, reason: '$id : zone de cuisson');
      if (id.contains('cooktop')) expect(m.appliances, contains('cooktop_4_burners_60'));
      if (id.contains('oven')) expect(m.appliances, contains('oven_standard_60'));
    }
  });

  test('caissons de hotte : posés au-dessus de la plaque, comme la hotte intégrée', () {
    for (final id in ['wall_hood_telescopic', 'wall_hood_group']) {
      final e = LayoutEngine(cat, Project(room: Room(width: 3600, depth: 3000, height: 2600)));
      final m = cat[id];
      expect(m.isHoodUnit, isTrue, reason: id);
      final c = e.add(id, 'A');
      expect(c.z, greaterThan(e.std.worktopTop + 400), reason: '$id : au-dessus du plan');
    }
    expect(cat['wall_chimney_box'].isHoodUnit, isFalse);
    expect(cat['wall_integrated_hood'].isHoodUnit, isTrue);
  });

  test('hottes posées librement : 650 au-dessus du plan, cheminée jusqu’au plafond, pas de découpe', () {
    for (final id in ['hood_free_pyramid', 'hood_free_inclined', 'hood_free_box']) {
      final e = LayoutEngine(cat, Project(room: Room(width: 3600, depth: 3000, height: 2600)));
      final m = cat[id];
      expect(m.isFreeHood, isTrue);
      expect(m.isCarcass, isFalse);
      final c = e.add(id, 'A');
      expect(c.z, e.std.worktopTop + 650);
      expect(c.z + c.height, lessThanOrEqualTo(2600 + 0.01));
      expect(cutList(e, e.project.cut, {}), isEmpty, reason: '$id : appareil seul dans la pièce, rien à découper');
    }
  });

  testWidgets('3D réelle : la hotte libre est dessinée avec son style, sans caisson', (t) async {
    final st = AppState(cat, project: Project(room: Room(width: 3600, depth: 3000, height: 2600)));
    final hood = st.engine.add('hood_free_inclined', 'A', s: 1200);
    await t.runAsync(() async {
      await TextureBank.instance.init();
      final scene = await SceneExporter().build(st);
      final fx = [for (final f in scene['kitchenFixtures'] as List? ?? const []) if (f['pick'] == hood.uid) f];
      expect(fx, hasLength(1));
      expect(fx.single['type'], 'kitchen_hood_free');
      expect(fx.single['hoodStyle'], 'inclined');
      expect([for (final s in scene['solids'] as List) if (s['uid'] == hood.uid) s], isEmpty, reason: 'pas de caisson autour de la hotte');
    });
  });

  test('caisson simple avec plaque ou évier en option : compte comme zone de cuisson ou de lavage', () {
    final e = LayoutEngine(cat, Project(room: Room(width: 3600, depth: 3000, height: 2600)));
    final hob = e.add('base_standard_single_door', 'A', s: 0)..appliances = ['cooktop_4_burners_60', 'oven_standard_60'];
    final sink = e.add('base_standard_single_door', 'A', s: 1200)..appliances = ['sink_1_bowl_drainer'];
    expect(e.cooks(hob), isTrue);
    expect(e.hasHob(hob), isTrue);
    expect(e.washes(sink), isTrue);
    final (wash, cook, _) = e.workZones();
    expect(wash?.uid, sink.uid);
    expect(cook?.uid, hob.uid);
  });
}
