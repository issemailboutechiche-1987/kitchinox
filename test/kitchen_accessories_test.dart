import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/catalog.dart';
import 'package:kitchen_planner/engine/kitchen_accessories.dart';
import 'package:kitchen_planner/engine/layout_engine.dart';
import 'package:kitchen_planner/engine/materials.dart';
import 'package:kitchen_planner/engine/project.dart';

void main() {
  setUpAll(() {
    final file = File('assets/data/kitchen_accessories_catalog.json');
    expect(file.existsSync(), isTrue, reason: 'Le catalogue JSON doit être présent dans assets/data/');
    KitchenAccessoriesCatalog.parse(file.readAsStringSync());
  });

  test('catalogue : charge les 56 accessoires et leurs marques', () {
    expect(KitchenAccessoriesCatalog.all.length, 56);
    expect(KitchenAccessoriesCatalog.byBrand['INOXA']?.length, 30);
    expect(KitchenAccessoriesCatalog.byBrand['Blum']?.length, 8);
    expect(KitchenAccessoriesCatalog.byBrand['Kesseböhmer']?.length, 3);
    expect(KitchenAccessoriesCatalog.byBrand['Hettich']?.length, 2);
    expect(KitchenAccessoriesCatalog.byBrand['Grass']?.length, 1);

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
