import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/engine/furniture_accessories.dart';
import 'package:kitchen_planner/ui/app_state.dart';

void main() {
  test('colonne d angle', () {
    final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
    final p = Project();
    final e = LayoutEngine(cat, p);
    e.applyShape(RoomShape.lShape);
    for (final id in ['corner_tall_l_shaped', 'corner_tall_blind']) {
      p.items.clear();
      final c = e.add(id, 'A', s: 0);
      final m = e.modelOf(c);
      expect(m.kind, CabinetKind.cornerTall);
      expect(c.height, greaterThanOrEqualTo(2000));
      expect(cutList(e, p.cut, {}), isNotEmpty);
      expect(() => e.add('base_standard_single_door', 'A', s: 0), returnsNormally);
      final b = e.project.items.last;
      expect(b.right <= c.s + 0.5 || b.s >= c.right - 0.5, isTrue, reason: 'pas de chevauchement');
      final h = e.add('wall_standard_single_door', 'A', s: c.s, z: 1500);
      expect(h.right <= c.s + 0.5 || h.s >= c.right - 0.5, isTrue, reason: 'un haut ne se pose pas dans la colonne');
    }
  });

  test('caisson personnalisÃ© : dimensions libres, sans fond, sans porte', () {
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    expect(st.addCustomCabinet(type: 'base', width: 437, height: 655, depth: 480), isNull);
    final c = st.project.items.last;
    expect((c.width, c.height, c.depth), (437, 655, 480));
    final withBack = cutList(st.engine, st.project.cut, {}).length;
    st.project.items.clear();
    expect(st.addCustomCabinet(type: 'tall', width: 500, height: 2350, depth: 560, noBack: true, noDoor: true), isNull);
    final t = st.project.items.last;
    expect(t.noBack, isTrue);
    expect(t.layout!.single.kind, CellKind.niche);
    expect(st.engine.modelOf(t).kind, CabinetKind.tall);
    expect(t.height, 2350);
    expect(cutList(st.engine, st.project.cut, {}).length, lessThan(withBack + 2));
    expect(Project.fromJson(st.project.toJson()).items.last.noBack, isTrue);
  });

  test('accessoires : quantitÃ©s, estimation et sauvegarde', () {
    FurnitureAccessories.parse(File('assets/data/furniture_accessories.json').readAsStringSync());
    expect(FurnitureAccessories.categories.length, greaterThanOrEqualTo(5));
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    st.setAccessory('pan_drawer', 2);
    st.setAccessory('bin_30', 1);
    st.setAccessory('bin_30', 0);
    final lines = furnitureAccessoryLines(st.project.accessories);
    expect(lines.single.total.min, 2500);
    expect(Project.fromJson(st.project.toJson()).accessories, {'pan_drawer': 2});
  });

  test('dressings en L et en U', () {
    final u = FurnitureUniverse.parse('dressing', File('assets/data/furniture/dressing.json').readAsStringSync());
    final p = Project(universe: 'dressing', room: Room(width: 3600, depth: 3000, height: 2600));
    final st = AppState(universeCatalog(u), project: p);
    final all = proposeUniverse(st.engine);
    final l = all.where((x) => x.$1 == 'Dressing en L').toList();
    final uu = all.where((x) => x.$1 == 'Dressing en U').toList();
    expect(l, isNotEmpty);
    expect(uu, isNotEmpty);
    final walls = {for (final c in uu.first.$2.project.items) c.wallId};
    expect(walls.length, 3);
    final e = LayoutEngine(st.engine.catalog, uu.first.$2.project);
    expect(e.validate().where((i) => i.severity == Severity.error), isEmpty);
  });
}
