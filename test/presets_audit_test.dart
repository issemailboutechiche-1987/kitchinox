// Toutes les compositions proposées, dans des pièces variées : une porte, des façades accessibles, l'eau dans les salles de bain.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';

void main() {
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  SizeCatalog.parse(f('sizes'));
  const rooms = [(3600.0, 3000.0), (4200.0, 3600.0), (2400.0, 2000.0), (3000.0, 2500.0), (5000.0, 4000.0), (2000.0, 3000.0)];

  List<String> audit(LayoutEngine e) => [for (final i in essentialChecks(e)) '${i.code} ${i.message}'];

  for (final u in ['dressing', 'bain', 'tv', 'interieur', 'buanderie']) {
    test('compositions $u : porte, accès, eau', () {
      final cat = universeCatalog(FurnitureUniverse.parse(u, f('furniture/$u')));
      var n = 0;
      final families = <String>{};
      for (final (w, d) in rooms) {
        final st = AppState(cat, project: Project(universe: u, room: Room(width: w, depth: d, height: 2600)));
        for (final (fam, pr) in proposeUniverse(st.engine)) {
          n++;
          families.add(fam);
          final e = LayoutEngine(cat, pr.project);
          expect(audit(e), isEmpty, reason: '$u ${pr.id} ${w}x$d');
          expect(pr.project.openings.where((o) => o.isDoor), isNotEmpty);
          if (u == 'bain') {
            expect(pr.project.networks, isTrue);
            for (final k in [NetKind.waterCold, NetKind.waterHot, NetKind.drain]) {
              expect(pr.project.points.any((x) => x.kind == k), isTrue, reason: '${pr.id} $k');
            }
            // chaque sanitaire qui en a besoin est raccordé
            for (final o in pr.project.objects.where(needsWaterPoint)) {
              expect(pr.project.points.any((x) => x.forUid == o.uid), isTrue, reason: '${pr.id} ${o.ref}');
            }
          }
          // une fois choisie, la composition apporte sa porte (et son eau)
          if (n % 7 == 0) {
            final st2 = AppState(cat, project: Project(universe: u, room: Room(width: w, depth: d, height: 2600)));
            st2.applyLayoutProposal(pr, withStyle: true);
            expect(st2.project.openings.where((o) => o.isDoor), isNotEmpty);
            expect(st2.issues.where((i) => {'no_door', 'no_water', 'front_hidden'}.contains(i.code)), isEmpty);
          }
        }
      }
      if (u != 'interieur') expect(n, greaterThan(0));
      if (u == 'dressing') expect(families, containsAll(['Dressing en L', 'Dressing en U']));
    });
  }

  test('dressing en U : deux meubles d’angle en L, aucun meuble caché', () {
    final cat = universeCatalog(FurnitureUniverse.parse('dressing', f('furniture/dressing')));
    final st = AppState(cat, project: Project(universe: 'dressing', room: Room(width: 3600, depth: 3000, height: 2600)));
    final us = proposeUniverse(st.engine).where((x) => x.$1 == 'Dressing en U').toList();
    expect(us, isNotEmpty);
    for (final (_, pr) in us) {
      final e = LayoutEngine(cat, pr.project);
      expect(pr.project.items.where((c) => c.modelId == 'wardrobe_corner_L_90'), hasLength(2));
      for (final c in pr.project.items) {
        expect(accessibleFront(e, c), greaterThanOrEqualTo(c.width * 0.6), reason: '${pr.id} ${c.modelId}');
      }
      expect(e.validate().where((i) => i.severity == Severity.error), isEmpty);
    }
    // l'ancien angle (400 mm cachés par le meuble du mur voisin) est refusé
    final bad = AppState(cat, project: Project(universe: 'dressing', room: Room(width: 3600, depth: 3000, height: 2600)));
    bad.engine.add('wardrobe_shelves_column', 'A', s: 0, width: 400);
    bad.engine.add('wardrobe_shelves_column', 'C', s: bad.project.room.wall('C').length - 600 - 600, width: 600);
    expect(essentialChecks(bad.engine).map((i) => i.code), contains('no_door'));
  });

  test('pièces types et nouvelle pièce : porte posée, eau en salle de bain', () {
    for (final u in SizeCatalog.presets.keys) {
      final cat = u == 'cuisine' ? Catalog.parse(File('assets/catalog.json').readAsStringSync()) : universeCatalog(FurnitureUniverse.parse(u, f('furniture/$u')));
      for (final pr in SizeCatalog.presets[u]!) {
        final st = AppState(cat, project: Project(universe: u));
        st.applyRoomPreset(pr);
        expect(st.project.openings.where((o) => o.isDoor), hasLength(1), reason: '$u ${pr.id}');
        final o = st.project.openings.first;
        expect(o.s >= 0 && o.right <= st.project.room.wall(o.wallId).length, isTrue);
        if (u == 'bain') expect(st.project.points.where((x) => x.kind == NetKind.drain), isNotEmpty);
      }
    }
  });

  test('cuisines : propositions et collection avec une porte, façades accessibles', () {
    final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'), handles: f('handles'));
    final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
    for (final (w, d) in [(3600.0, 3000.0), (4200.0, 3400.0)]) {
      final st = AppState(cat, db: db, project: Project(room: Room(width: w, depth: d, height: 2600)));
      final all = [...proposeLayouts(st.engine), for (final (_, pr) in buildTemplates(st.engine)) pr];
      expect(all, isNotEmpty);
      for (final pr in all) {
        expect(audit(LayoutEngine(cat, pr.project)), isEmpty, reason: '${pr.id} ${w}x$d');
      }
    }
  });

  test('hotte : le choix change vraiment de hotte', () {
    final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'), handles: f('handles'));
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()), db: db);
    st.engine.applyShape(RoomShape.linear);
    final c = st.engine.add('wall_integrated_hood', 'A', s: 600, width: 600);
    st.setAppliance(c.uid, 0, 'hood_wall_inclined');
    var now = st.project.byUid(c.uid)!;
    expect((now.modelId, now.s), ('hood_free_inclined', 600));
    expect(now.z, st.project.standards.worktopTop + 650);
    expect(appliancesOf(st.engine.modelOf(now), now), ['hood_wall_inclined']);
    st.setAppliance(now.uid, 0, 'hood_wall_decorative');
    now = st.project.byUid(c.uid)!;
    expect(now.modelId, 'hood_free_pyramid');
    st.setAppliance(now.uid, 0, 'hood_telescopic_or_builtin');
    now = st.project.byUid(c.uid)!;
    expect(now.modelId, 'wall_integrated_hood');
  });
}
