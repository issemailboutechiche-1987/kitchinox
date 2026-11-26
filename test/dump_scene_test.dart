// Outil de diagnostic (seulement avec KX_DUMP=dossier) : exporte la scène 3D d'une vraie cuisine
// (JSON + images brutes RGBA) pour la recharger telle quelle dans le moteur du navigateur
// (window.kitchen3d.mount / addImage / setScene) et comparer rendu habituel et lancer de rayons.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/scene_export.dart';
import 'package:kitchen_planner/ui/textures.dart';

void main() {
  final out = Platform.environment['KX_DUMP'];
  testWidgets('scène de diagnostic', (t) async {
    final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
    KitchenAccessoriesCatalog.parse(File('assets/data/kitchen_accessories_catalog.json').readAsStringSync());
    final st = AppState(cat, project: Project(room: Room(width: 3600, depth: 3200, height: 2600)));
    final e = st.engine;
    e.applyShape(RoomShape.lShape);
    e.addOpening('window', 'A', s: 1400);
    e.addOpening('door', 'D', s: 2400);
    for (final w in ['A', 'B']) {
      e.autoFillWall(w, Band.low);
      e.autoFillWall(w, Band.high);
    }
    st.project.style.frontProfile = 'cannelee';
    // un caisson équipé
    final base = st.project.items.firstWhere((c) => e.modelOf(c).kind == CabinetKind.base && c.width >= 400);
    base.accessory = KitchenAccessoriesCatalog.all.firstWhere((a) => model3dOf(a)['family'] == 'basket_pullout').id;
    await t.runAsync(() async {
      await TextureBank.instance.init();
      final ex = SceneExporter();
      final scene = await ex.build(st);
      final dir = Directory(out!)..createSync(recursive: true);
      final imgs = ex.takeNewImages();
      File('${dir.path}/scene.json').writeAsStringSync(jsonEncode(scene));
      File('${dir.path}/images.json').writeAsStringSync(jsonEncode([for (final i in imgs) {'key': i.key, 'w': i.width, 'h': i.height, 'file': 'img${imgs.indexOf(i)}.rgba'}]));
      for (var i = 0; i < imgs.length; i++) {
        File('${dir.path}/img$i.rgba').writeAsBytesSync(imgs[i].rgba);
      }
    });
  }, skip: out == null);
}
