import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/catalog.dart';
import 'package:kitchen_planner/engine/kitchen_accessories.dart';
import 'package:kitchen_planner/engine/layout_engine.dart';
import 'package:kitchen_planner/engine/project.dart';

void main() {
  setUpAll(() {
    final file = File('assets/data/kitchen_accessories_catalog.json');
    expect(file.existsSync(), isTrue, reason: 'Le catalogue JSON doit être présent dans assets/data/');
    KitchenAccessoriesCatalog.parse(file.readAsStringSync());

    final klausFile = File('assets/data/klaus_ma_catalog.json');
    expect(klausFile.existsSync(), isTrue, reason: 'Le catalogue Klaus doit être présent dans assets/data/');
    KitchenAccessoriesCatalog.parse(klausFile.readAsStringSync(), clear: false);
  });

  test('catalogue : charge les accessoires INOXA, quincaillerie et Klaus Systems', () {
    expect(KitchenAccessoriesCatalog.all.length, 196); // 56 standard + 140 Klaus
    expect(KitchenAccessoriesCatalog.byBrand['INOXA']?.length, 30);
    expect(KitchenAccessoriesCatalog.byBrand['Blum']?.length, 8);
    expect(KitchenAccessoriesCatalog.byBrand['Kesseböhmer']?.length, 3);
    expect(KitchenAccessoriesCatalog.byBrand['Hettich']?.length, 2);
    expect(KitchenAccessoriesCatalog.byBrand['Grass']?.length, 1);
    expect(KitchenAccessoriesCatalog.byBrand['Klaus Systems']?.length, 140);

    // Vérification d'un article Klaus Systems
    final klausSpice = KitchenAccessoriesCatalog.byId['klaus_bas_epice_01'];
    expect(klausSpice, isNotNull);
    expect(klausSpice!.brand, 'Klaus Systems');
    expect(klausSpice.category, 'base');
    expect(klausSpice.price.min, 840);
    expect(klausSpice.price.max, 920);

    final klausGola = KitchenAccessoriesCatalog.byId['klaus_gola_sup_horiz_01'];
    expect(klausGola, isNotNull);
    expect(klausGola!.category, 'gola');
    expect(klausGola.price.min, 350);

    // Vérification d'un article INOXA Hyper avec ses 3 illustrations
    final acc = KitchenAccessoriesCatalog.byId['inoxa_8104Y'];
    expect(acc, isNotNull);
    expect(acc!.code, '8104Y');
    expect(acc.collection, 'Hyper');
    expect(acc.shelvesCount, 2);
    expect(acc.softClose, isTrue);
    expect(acc.supportedWidths, [150, 200]);
    expect(acc.productAsset, 'assets/illustrations/inoxa_hyper/8104Y_product.png');
    expect(acc.lifestyleAsset, 'assets/illustrations/inoxa_hyper/8104Y_lifestyle.jpg');
    expect(acc.blueprintAsset, 'assets/illustrations/inoxa_hyper/8104Y_blueprint.png');

    // Les fichiers d'illustration existent bien sur disque
    expect(File(acc.productAsset!).existsSync(), isTrue);
    expect(File(acc.lifestyleAsset!).existsSync(), isTrue);
    expect(File(acc.blueprintAsset!).existsSync(), isTrue);
  });

  test('compatibilité : filtre selon zone et largeur de caisson', () {
    // Caisson bas étroit 150 mm
    final acc150 = KitchenAccessoriesCatalog.compatibleWith(zone: 'base', width: 150);
    final ids150 = acc150.map((a) => a.id).toList();
    expect(ids150, contains('inoxa_8104Y'));
    expect(ids150, contains('inoxa_8106Y'));
    expect(ids150, contains('inoxa_8124Y'));
    expect(ids150, isNot(contains('inoxa_8102Y')), reason: '8102Y requiert au moins 300 mm');

    // Colonne 400 mm
    final accCol400 = KitchenAccessoriesCatalog.compatibleWith(zone: 'column', width: 400);
    final idsCol = accCol400.map((a) => a.id).toList();
    expect(idsCol, contains('inoxa_818Y'));
    expect(idsCol, contains('inoxa_852Y'));
    expect(idsCol, contains('inoxa_860XY'));
    expect(idsCol, contains('kessebohmer_dispensa'));

    // Meuble d'angle
    final accCorner = KitchenAccessoriesCatalog.compatibleWith(zone: 'corner');
    final idsCorner = accCorner.map((a) => a.id).toList();
    expect(idsCorner, contains('inoxa_803Y'));
    expect(idsCorner, contains('inoxa_846BH'));
    expect(idsCorner, contains('kessebohmer_lemans_ii'));
  });

  test('caisson équipé : sérialisation JSON et intégration au devis', () {
    final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
    final p = Project(room: Room(width: 3000, depth: 3000, height: 2500));
    final e = LayoutEngine(cat, p);
    final c = e.add('base_1_door', 'A', width: 150);

    // Équipement du caisson avec l'accessoire INOXA 8104Y
    c.accessory = 'inoxa_8104Y';

    // Sérialisation JSON / désérialisation
    final json = p.toJson();
    final p2 = Project.fromJson(json);
    expect(p2.items.first.accessory, 'inoxa_8104Y');

    // Lignes de chiffrage devis
    final lines = kitchenCabinetAccessoryLines(p2);
    expect(lines.length, 1);
    expect(lines.first.name, contains('INOXA'));
    expect(lines.first.name, contains('8104Y'));
    expect(lines.first.unitPrice.min, greaterThan(0));
  });
}
