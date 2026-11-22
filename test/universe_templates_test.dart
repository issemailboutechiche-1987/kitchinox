// Compositions nommées du dressing, de la salle de bain et du meuble TV, recalculées selon la pièce et les finitions.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';

LayoutEngine room(String id, {double w = 4000, double d = 3000}) {
  final u = FurnitureUniverse.parse(id, File('assets/data/furniture/$id.json').readAsStringSync());
  return LayoutEngine(universeCatalog(u), Project(universe: id, room: Room(width: w, depth: d, height: 2600)));
}

void main() {
  for (final id in ['dressing', 'bain', 'tv']) {
    test('$id : tous les modèles nommés tiennent dans une pièce de 4 m, sans chevauchement', () {
      final e = room(id);
      final all = proposeUniverse(e, withStyle: false);
      final props = [for (final x in all) if (!x.$1.startsWith('Dressing en ')) x];
      for (final x in all) {
        expect(LayoutEngine(e.catalog, x.$2.project).validate().where((i) => i.code == 'overlap' || i.code == 'out_of_wall'), isEmpty, reason: x.$2.name);
      }
      expect(props.length, universeTemplates[id]!.length, reason: [for (final (_, p) in props) p.name].join(', '));
      for (final (family, pr) in props) {
        expect(family, isNotEmpty);
        final pe = LayoutEngine(e.catalog, pr.project);
        expect(pe.validate().where((i) => i.code == 'overlap' || i.code == 'out_of_wall'), isEmpty, reason: pr.name);
        expect(pr.project.items, isNotEmpty);
        for (final c in pr.project.items) {
          expect(c.right, lessThanOrEqualTo(pr.project.room.wall(c.wallId).length + 0.5), reason: pr.name);
        }
      }
      // finitions : celles du modèle, ou celles du projet
      final tp = universeTemplates[id]!.first;
      final collection = proposeUniverse(e);
      final styled = collection.firstWhere((x) => x.$2.name == tp.name).$2;
      expect(styled.project.style.front, tp.signature.style['front']);
      // collection : chaque modèle décliné en 3 palettes
      expect(collection.length, greaterThanOrEqualTo(props.length * 2));
      expect(collection.where((x) => x.$2.name.startsWith('${tp.name} · ')).length, 2);
      final mine = proposeUniverse(e, withStyle: false).first.$2;
      expect(mine.project.style.front, e.project.style.front);
    });
  }

  test('pièce étroite : moins de modules (optionnels retirés), remplissage sur un grand mur', () {
    final small = proposeUniverse(room('dressing', w: 1500, d: 1500));
    final big = proposeUniverse(room('dressing', w: 5000, d: 3000));
    final atlasSmall = small.where((x) => x.$2.name == 'Atlas');
    final atlasBig = big.firstWhere((x) => x.$2.name == 'Atlas').$2;
    if (atlasSmall.isNotEmpty) expect(atlasSmall.first.$2.project.items.length, lessThan(atlasBig.project.items.length));
    expect(small.any((x) => x.$2.name == 'Kénitra'), isTrue);
  });

  test('appliquer un modèle de la collection : meubles et finitions dans le projet', () {
    final e = room('bain');
    final st = AppState(e.catalog, project: e.project);
    final (_, pr) = proposeUniverse(st.engine).first;
    expect(st.applyLayoutProposal(pr, withStyle: true), isNull);
    expect(st.project.items.length, pr.project.items.length);
    expect(st.project.style.front, pr.project.style.front);
  });

  test('dressing Atlas sur un mur de 4 m sous 2,6 m : surmeubles posés sur les colonnes, mur rempli', () {
    final e = room('dressing');
    final atlas = proposeUniverse(e, withStyle: false).firstWhere((x) => x.$2.name == 'Atlas').$2;
    final pe = LayoutEngine(e.catalog, atlas.project);
    final boxes = atlas.project.items.where((c) => c.modelId == 'wardrobe_top_box').toList();
    expect(boxes, isNotEmpty);
    for (final b in boxes) {
      expect(b.top, lessThanOrEqualTo(2600 - 20));
      expect(atlas.project.items.any((c) => c.modelId != 'wardrobe_top_box' && (c.top - b.z).abs() < 1 && (c.s - b.s).abs() < 1), isTrue);
    }
    final ground = atlas.project.items.where((c) => c.modelId != 'wardrobe_top_box');
    final span = ground.map((c) => c.right).reduce((a, b) => a > b ? a : b);
    expect(pe.project.room.wall(ground.first.wallId).length - span, lessThan(300));
  });
}
