// Exporte une cuisine complète pour la vue WebGL (web/dev/scene.json) : sert à contrôler la
// visionneuse three.js hors de l'application (tool/web3d/test3d.html, à copier dans build/web/dev).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/scene_export.dart';
import 'package:kitchen_planner/ui/textures.dart';

void main() {
  testWidgets('porte vitrée : cadre et vitre transparente exportés', (t) async {
    await t.runAsync(() async {
      final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
      st.engine.applyShape(RoomShape.linear);
      final c = st.engine.add('wall_glass_door', 'A', s: 0, width: 600, z: 1500);
      final sc = await SceneExporter().build(st);
      final parts = [for (final f in sc['fronts'] as List) if (f['uid'] == c.uid) ...(f['parts'] as List)];
      expect(parts.where((q) => q['glass'] == 60.0), isNotEmpty);
    });
  });

  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  testWidgets('export de la scène 3D', (t) async {
    final e0 = LayoutEngine(cat, Project(room: Room(width: 4200, depth: 3400, height: 2600)));
    e0.addOpening('window', 'A', s: 2100);
    e0.addOpening('door', 'D', s: 3100);
    final pr = proposeLayouts(e0).first;
    final st = AppState(cat, project: Project.fromJson(pr.project.toJson()));
    st.project.style
      ..front = 'chene'
      ..frontUpper = 'blanc_mat'
      ..worktop = 'marbre'
      ..floor = 'carrelage_gris'
      ..splash = 'zellige_vert';
    st.openTargets.add(st.project.items.firstWhere((c) => c.modelId == 'base_integrated_dishwasher_door').uid);
    await t.runAsync(() async {
      await TextureBank.instance.init();
      final ex = SceneExporter();
      final scene = await ex.build(st);
      final images = <Map<String, dynamic>>[];
      for (final img in ex.takeNewImages()) {
        final c = await _png(img);
        images.add({'key': img.key, 'w': img.width, 'h': img.height, 'png': base64Encode(c)});
      }
      File('test/out/scene3d.json').writeAsStringSync(jsonEncode({'scene': scene, 'images': images}));
      expect(scene['fronts'], isNotEmpty);
      expect(images, isNotEmpty);
    });
  });

  testWidgets('export 3D de toutes les formes (angles en L, pan coupé, borgne, ouverts)', (t) async {
    final e0 = LayoutEngine(cat, Project(room: Room(width: 4200, depth: 3400, height: 2600)));
    e0.addOpening('door', 'D', s: 3100);
    final props = proposeLayouts(e0, distinct: false, max: 40);
    await t.runAsync(() async {
      await TextureBank.instance.init();
      for (final pr in props) {
        final st = AppState(cat, project: Project.fromJson(pr.project.toJson()));
        st.openAll(true);
        final scene = await SceneExporter().build(st);
        expect(scene['solids'], isNotEmpty, reason: pr.name);
      }
      // chaque modèle d'angle, seul dans un angle, ouvert
      for (final id in ['corner_base_l_shaped', 'corner_base_diagonal', 'corner_base_blind', 'corner_wall_l_shaped', 'corner_wall_diagonal', 'corner_wall_blind']) {
        final st = AppState(cat, project: Project(room: Room(width: 4000, depth: 3000, height: 2600)));
        st.engine.applyShape(RoomShape.lShape);
        st.engine.add(id, 'A');
        st.openAll(true);
        final scene = await SceneExporter().build(st);
        expect((scene['fronts'] as List).expand((f) => f['parts'] as List).any((p) => p['kind'] == 'door'), isTrue, reason: id);
      }
    });
  });

  testWidgets('profil Gola : gorge en aluminium dans le caisson, façades arrêtées dessous, rien sur les portes', (t) async {
    final st = AppState(cat, project: Project(room: Room(width: 4000, depth: 3000, height: 2600)));
    st.project.style.handle = 'gola';
    final door = st.engine.add('base_standard_single_door', 'A', s: 0);
    final drawers = st.engine.add('base_drawers_multi', 'A', s: 600);
    st.openAll(true);
    await t.runAsync(() async {
      await TextureBank.instance.init();
      final scene = await SceneExporter().build(st);
      final top = st.engine.boxesOf(door).first.box.z1;
      final parts = [for (final f in scene['fronts'] as List) if (f['uid'] == door.uid) ...(f['parts'] as List)];
      expect(parts, isNotEmpty);
      expect((parts.first['z1'] as num).toDouble(), closeTo(top - 30, 0.01), reason: 'la porte s’arrête sous la gorge');
      // gorge : pièces métal du caisson, dans les 33 mm sous le haut du caisson
      final metal = [
        for (final sld in scene['solids'] as List)
          if (sld['uid'] == door.uid && ((sld['mat'] as Map)['metal'] as num? ?? 0) > 0.5) sld
      ];
      expect(metal, hasLength(3), reason: 'fond, lèvre basse, rebord haut');
      expect(metal.every((b) => (b['z0'] as num) >= top - 33.01 && (b['z1'] as num) <= top + 0.01), isTrue);
      // caisson à tiroirs : une gorge de plus entre deux tiroirs
      final dMetal = [
        for (final sld in scene['solids'] as List)
          if (sld['uid'] == drawers.uid && ((sld['mat'] as Map)['metal'] as num? ?? 0) > 0.5) sld
      ];
      expect(dMetal.length, greaterThan(3));
      // meuble haut : gorge en bas, façade relevée de 30 ; colonne à deux portes : gorge entre les portes
      for (final (id, s0) in [('wall_standard_single_door', 1800.0), ('tall_pantry', 2600.0)]) {
        final c = st.engine.add(id, 'A', s: s0);
        final sc = await SceneExporter().build(st);
        final n = (sc['solids'] as List).where((x) => x['uid'] == c.uid && ((x['mat'] as Map)['metal'] as num? ?? 0) > 0.5).length;
        final pieces = [for (final f in sc['fronts'] as List) if (f['uid'] == c.uid) ...(f['parts'] as List)];
        if (id.startsWith('wall')) {
          expect(n, 3, reason: id);
          expect((pieces.first['z0'] as num).toDouble(), closeTo(c.z + 30, 0.01));
        } else {
          expect(n % 3, 0, reason: id);
        }
      }
    });
  });

  testWidgets('export de la scène 3D : salle de bain proposée (sanitaires)', (t) async {
    final u = FurnitureUniverse.parse('bain', File('assets/data/furniture/bain.json').readAsStringSync());
    final p = Project(universe: 'bain', room: Room(width: 3600, depth: 3000, height: 2600));
    p.openings.add(Opening(uid: 'door', type: 'door', wallId: 'D', s: 300, width: 800, z: 0, height: 2040));
    final st = AppState(universeCatalog(u), project: p);
    final pr = proposeUniverse(st.engine).firstWhere((x) => x.$2.name == 'Fès').$2;
    st.applyLayoutProposal(pr, withStyle: true);
    await t.runAsync(() async {
      await TextureBank.instance.init();
      final ex = SceneExporter();
      final scene = await ex.build(st);
      final images = <Map<String, dynamic>>[];
      for (final img in ex.takeNewImages()) {
        images.add({'key': img.key, 'w': img.width, 'h': img.height, 'png': base64Encode(await _png(img))});
      }
      File('test/out/bain_scene.json').writeAsStringSync(jsonEncode({'scene': scene, 'images': images}));
      expect((scene['objects'] as List).length, 4);
    });
  });

  testWidgets('export de la scène 3D : salon TV proposé (mobilier réaliste)', (t) async {
    final u = FurnitureUniverse.parse('tv', File('assets/data/furniture/tv.json').readAsStringSync());
    final p = Project(universe: 'tv', room: Room(width: 4800, depth: 4200, height: 2700));
    p.openings.add(Opening(uid: 'door', type: 'door', wallId: 'D', s: 300, width: 900, z: 0, height: 2040));
    final st = AppState(universeCatalog(u), project: p)..objectCatalog = CatalogObject.parse(File('assets/data/objects.json').readAsStringSync());
    st.applyLayoutProposal(proposeUniverse(st.engine).first.$2, withStyle: true);
    st.addObject('ph_ArmChair_01');
    await t.runAsync(() async {
      await TextureBank.instance.init();
      final ex = SceneExporter();
      final scene = await ex.build(st);
      final images = <Map<String, dynamic>>[];
      for (final img in ex.takeNewImages()) {
        images.add({'key': img.key, 'w': img.width, 'h': img.height, 'png': base64Encode(await _png(img))});
      }
      File('test/out/tv_scene.json').writeAsStringSync(jsonEncode({'scene': scene, 'images': images}));
      expect((scene['objects'] as List).where((o) => '${o['file']}'.contains('polyhaven')), isNotEmpty);
    });
  });

  testWidgets('export de la scène 3D : pièce à contour libre (pan coupé, mur arrondi)', (t) async {
    final st = AppState(cat);
    st.setRoomOutline([RoomVertex(0, 0), RoomVertex(4200, 0), RoomVertex(4200, 1900), RoomVertex(3200, 2900, 600), RoomVertex(0, 2900)]);
    st.engine.add('base_drawers_multi', 'A', s: 0, width: 800);
    st.engine.add('base_sink', 'A', s: 800, width: 1000);
    st.engine.add('base_drawers_multi', 'E', s: 0, width: 600);
    await t.runAsync(() async {
      await TextureBank.instance.init();
      final ex = SceneExporter();
      final scene = await ex.build(st);
      final images = <Map<String, dynamic>>[];
      for (final img in ex.takeNewImages()) {
        images.add({'key': img.key, 'w': img.width, 'h': img.height, 'png': base64Encode(await _png(img))});
      }
      File('test/out/forme_scene.json').writeAsStringSync(jsonEncode({'scene': scene, 'images': images}));
    });
  });

  testWidgets("export de la scène 3D : prises, interrupteurs et arrivées d'eau", (t) async {
    final e0 = LayoutEngine(cat, Project(room: Room(width: 3600, depth: 3000, height: 2600)));
    e0.addOpening('door', 'D', s: 2600);
    final st = AppState(cat, project: Project.fromJson(proposeLayouts(e0).first.project.toJson()));
    st.setNetworks(true);
    st.placeLighting(); // les points lumineux du plafond se posent depuis le menu Lumière
    for (final k in [NetKind.switchDouble, NetKind.usb, NetKind.tvSat]) {
      st.addPoint(k);
    }
    await t.runAsync(() async {
      await TextureBank.instance.init();
      final scene = await SceneExporter().build(st);
      final pts = scene['netPoints'] as List;
      expect(pts.where((x) => x['kind'] == 'socketDouble'), isNotEmpty);
      expect(pts.where((x) => x['kind'] == 'switch_'), isNotEmpty);
      expect(pts.where((x) => x['ceiling'] == true), isNotEmpty); // point lumineux
      File('test/out/reseaux_scene.json').writeAsStringSync(jsonEncode({'scene': scene, 'images': []}));
    });
  });
}


Future<List<int>> _png(SceneImage img) async {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(img.rgba, img.width, img.height, ui.PixelFormat.rgba8888, c.complete);
  final im = await c.future;
  final d = await im.toByteData(format: ui.ImageByteFormat.png);
  return d!.buffer.asUint8List();
}
