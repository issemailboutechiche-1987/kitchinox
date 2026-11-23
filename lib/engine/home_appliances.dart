/// Buanderie : lave-linge, sèche-linge et chauffe-eau, par forme et par capacité (cotes courantes du marché,
/// prix indicatifs). Posés dans la pièce, ou logés dans un meuble de buanderie pour les machines.
library;

import 'project.dart';
import 'room_objects.dart';

const washCategory = 'Lave-linge et sèche-linge';
const heaterCategory = 'Chauffe-eau';

const _washWater = [('froide', 0.25, 750), ('evac', 0.75, 600)];
const _dryWater = [('evac', 0.75, 600)]; // condensats
const _heaterWater = [('froide', 0.4, 1000), ('chaude', 0.6, 1000), ('evac', 0.5, 900)];

/// Les anciens projets ont « chauffe_eau » sans capacité : ils gardent leurs cotes.
const homeAppliances = <FixtureType>[
  // ---- chauffe-eau
  FixtureType('chauffe_eau', 'Chauffe-eau vertical', heaterCategory, [(450, 450)], 1000, 1100, 600, _heaterWater, 'Mural, cylindrique. Groupe de sécurité raccordé à l’évacuation.',
      def: 3,
      variants: [
        FixtureVariant('30 L', 350, 370, 620, 1100, 1700, z: 1300),
        FixtureVariant('50 L', 450, 450, 580, 1200, 2200, z: 1300),
        FixtureVariant('80 L', 450, 450, 780, 1500, 2800, z: 1200),
        FixtureVariant('100 L', 450, 450, 1000, 1800, 3500),
        FixtureVariant('150 L', 505, 520, 1240, 2800, 4800),
        FixtureVariant('200 L', 505, 520, 1570, 3800, 6500, z: 900),
      ]),
  FixtureType('chauffe_eau_h', 'Chauffe-eau horizontal', heaterCategory, [(780, 470)], 450, 1800, 600, _heaterWater, 'Mural, couché : au-dessus d’un plan ou d’une porte. Piquages à gauche, dessous.',
      def: 1,
      variants: [
        FixtureVariant('50 L', 580, 470, 450, 1300, 2300),
        FixtureVariant('80 L', 780, 470, 450, 1600, 3000),
        FixtureVariant('100 L', 1000, 470, 450, 1900, 3700),
        FixtureVariant('150 L', 1240, 525, 505, 3000, 5200, z: 1700),
      ]),
  FixtureType('chauffe_eau_plat', 'Chauffe-eau extra-plat', heaterCategory, [(490, 290)], 1300, 1000, 600, _heaterWater, 'Peu profond : 29 cm, il tient dans un placard ou entre deux meubles hauts.',
      def: 2,
      variants: [
        FixtureVariant('40 L', 490, 290, 765, 2200, 3800, z: 1300),
        FixtureVariant('65 L', 490, 290, 1090, 2700, 4600),
        FixtureVariant('80 L', 490, 290, 1300, 3200, 5500),
        FixtureVariant('100 L', 560, 340, 1250, 3800, 6500),
      ]),
  FixtureType('chauffe_eau_plat_h', 'Chauffe-eau extra-plat horizontal', heaterCategory, [(1090, 290)], 490, 1800, 600, _heaterWater, 'Extra-plat couché, au-dessus des meubles ou d’une porte.',
      def: 1,
      variants: [
        FixtureVariant('40 L', 765, 290, 490, 2200, 3800),
        FixtureVariant('65 L', 1090, 290, 490, 2700, 4600),
        FixtureVariant('80 L', 1300, 290, 490, 3200, 5500),
      ]),
  FixtureType('chauffe_eau_carre', 'Petit chauffe-eau carré', heaterCategory, [(360, 350)], 360, 1400, 300, _heaterWater, 'Au-dessus ou au-dessous d’un évier (bac à laver, lave-mains).',
      def: 1,
      variants: [
        FixtureVariant('10 L', 340, 300, 340, 700, 1200),
        FixtureVariant('15 L', 360, 350, 360, 800, 1400),
        FixtureVariant('30 L', 447, 410, 447, 1100, 1800),
        FixtureVariant('50 L', 560, 480, 560, 1500, 2400, z: 1200),
      ]),
  FixtureType('chauffe_eau_sol', 'Chauffe-eau au sol', heaterCategory, [(575, 600)], 1250, 0, 600, [('froide', 0.35, 250), ('chaude', 0.65, 250), ('evac', 0.5, 100)],
      'Posé sur trois pieds : grande famille. Groupe de sécurité raccordé à l’évacuation.',
      variants: [
        FixtureVariant('200 L', 575, 600, 1250, 4500, 7500),
        FixtureVariant('250 L', 575, 600, 1500, 5200, 8500),
        FixtureVariant('300 L', 575, 600, 1770, 6000, 10000),
      ]),
  FixtureType('chauffe_eau_thermo', 'Chauffe-eau thermodynamique', heaterCategory, [(620, 640)], 1620, 0, 600, [('froide', 0.35, 300), ('chaude', 0.65, 300), ('evac', 0.5, 100)],
      'Pompe à chaleur sur la cuve : environ trois fois moins d’électricité. Prévoir 20 m³ d’air ou deux gaines de 160 mm.',
      def: 1,
      variants: [
        FixtureVariant('100 L mural', 525, 540, 1300, 9000, 15000, z: 900),
        FixtureVariant('200 L', 620, 640, 1620, 12000, 20000),
        FixtureVariant('270 L', 620, 640, 1960, 14000, 24000),
      ]),
  FixtureType('chauffe_eau_gaz', 'Chauffe-eau à gaz', heaterCategory, [(340, 230)], 590, 1300, 600, [('froide', 0.75, 1200), ('chaude', 0.25, 1200)],
      'Instantané, gaz butane, propane ou naturel. Évacuation des fumées et aération obligatoires.',
      def: 1,
      variants: [
        FixtureVariant('6 L/min', 290, 210, 500, 900, 1700),
        FixtureVariant('11 L/min', 340, 230, 590, 1500, 2900),
        FixtureVariant('14 L/min', 360, 240, 650, 2300, 4300),
        FixtureVariant('17 L/min', 400, 250, 680, 3000, 5500),
      ]),
  FixtureType('chauffe_eau_inst', 'Chauffe-eau électrique instantané', heaterCategory, [(240, 110)], 400, 1300, 300, [('froide', 0.65, 1200), ('chaude', 0.35, 1200)],
      'Sans cuve, très compact. Ligne électrique dédiée (puissance élevée).',
      variants: [
        FixtureVariant('5 kW', 200, 80, 300, 700, 1500),
        FixtureVariant('9 kW', 240, 110, 400, 1500, 3000),
        FixtureVariant('18 kW', 240, 110, 480, 2500, 4800),
        FixtureVariant('24 kW', 240, 110, 480, 3000, 5500),
      ]),
  // ---- lave-linge
  FixtureType('ll_hublot', 'Lave-linge hublot', washCategory, [(600, 550)], 850, 0, 900, _washWater, 'Chargement frontal. Robinet machine, évacuation et prise 20 A.',
      def: 2,
      variants: [
        FixtureVariant('6 kg (étroit)', 600, 400, 850, 2200, 3800),
        FixtureVariant('7 kg', 600, 500, 850, 2500, 4300),
        FixtureVariant('8 kg', 600, 550, 850, 2900, 5000),
        FixtureVariant('9 kg', 600, 570, 850, 3400, 6000),
        FixtureVariant('10 kg', 600, 600, 850, 3900, 7000),
        FixtureVariant('12 kg', 600, 660, 850, 4800, 8500),
        FixtureVariant('17 kg', 700, 770, 990, 9000, 16000),
      ]),
  FixtureType('ll_top', 'Lave-linge chargement par le dessus', washCategory, [(400, 600)], 890, 0, 700, _washWater, 'Étroit : 40 cm. Laisser le dessus libre pour ouvrir le couvercle.',
      def: 1,
      variants: [
        FixtureVariant('6 kg', 400, 600, 890, 2500, 4200),
        FixtureVariant('7 kg', 400, 600, 890, 2800, 4800),
        FixtureVariant('8 kg', 400, 610, 900, 3200, 5500),
      ]),
  FixtureType('ll_cuve', 'Lave-linge grande cuve (dessus)', washCategory, [(590, 600)], 1010, 0, 700, _washWater, 'Automatique à cuve verticale. Laisser le dessus libre pour ouvrir le couvercle.',
      variants: [
        FixtureVariant('10 kg', 560, 580, 970, 2800, 4800),
        FixtureVariant('13 kg', 590, 610, 1010, 3500, 6000),
        FixtureVariant('16 kg', 630, 680, 1040, 4500, 8000),
        FixtureVariant('20 kg', 690, 720, 1080, 6500, 11000),
      ]),
  FixtureType('ll_semi', 'Lave-linge semi-automatique (2 cuves)', washCategory, [(800, 470)], 930, 0, 700, _washWater, 'Une cuve de lavage, une cuve d’essorage.',
      variants: [
        FixtureVariant('7 kg', 750, 440, 900, 1300, 2200),
        FixtureVariant('10 kg', 800, 470, 930, 1600, 2800),
        FixtureVariant('13 kg', 880, 520, 1000, 2000, 3500),
      ]),
  FixtureType('ll_mini', 'Mini lave-linge', washCategory, [(510, 440)], 680, 0, 700, _washWater, 'Petit linge ou studio.',
      variants: [
        FixtureVariant('3 kg', 510, 440, 680, 1500, 2600),
        FixtureVariant('4 kg', 510, 460, 700, 1800, 3000),
      ]),
  FixtureType('ll_encastrable', 'Lave-linge encastrable', washCategory, [(595, 540)], 820, 0, 900, _washWater, 'Se cache derrière une façade de meuble, sous un plan continu.',
      variants: [
        FixtureVariant('7 kg', 595, 540, 820, 4500, 7500),
        FixtureVariant('8 kg', 595, 560, 820, 5200, 9000),
      ]),
  FixtureType('ll_sechant', 'Lave-linge séchant', washCategory, [(600, 580)], 850, 0, 900, _washWater, 'Lave et sèche dans la même machine (lavage / séchage).',
      def: 1,
      variants: [
        FixtureVariant('8/5 kg', 600, 550, 850, 4500, 7500),
        FixtureVariant('9/6 kg', 600, 580, 850, 5200, 9000),
        FixtureVariant('10/7 kg', 600, 600, 850, 6000, 11000),
        FixtureVariant('12/8 kg', 600, 660, 850, 7500, 13000),
      ]),
  // ---- sèche-linge
  FixtureType('sl_evac', 'Sèche-linge à évacuation', washCategory, [(600, 560)], 850, 0, 900, [], 'Gaine d’évacuation de l’air humide vers l’extérieur (100 mm).',
      variants: [
        FixtureVariant('7 kg', 600, 560, 850, 2500, 4200),
        FixtureVariant('8 kg', 600, 590, 850, 2900, 4800),
      ]),
  FixtureType('sl_cond', 'Sèche-linge à condensation', washCategory, [(600, 590)], 850, 0, 900, _dryWater, 'Bac à vider ou condensats raccordés à l’évacuation.',
      def: 1,
      variants: [
        FixtureVariant('7 kg', 600, 560, 850, 3200, 5500),
        FixtureVariant('8 kg', 600, 590, 850, 3600, 6200),
        FixtureVariant('9 kg', 600, 600, 850, 4200, 7000),
      ]),
  FixtureType('sl_pac', 'Sèche-linge pompe à chaleur', washCategory, [(600, 600)], 850, 0, 900, _dryWater, 'Le plus économe. Condensats raccordés à l’évacuation.',
      def: 1,
      variants: [
        FixtureVariant('7 kg (étroit)', 600, 480, 850, 4800, 8000),
        FixtureVariant('8 kg', 600, 600, 850, 5200, 9000),
        FixtureVariant('9 kg', 600, 620, 850, 5800, 10000),
        FixtureVariant('10 kg', 600, 660, 850, 7000, 12000),
        FixtureVariant('17 kg', 700, 770, 990, 11000, 19000),
      ]),
  FixtureType('sl_mural', 'Mini sèche-linge mural', washCategory, [(600, 420)], 600, 1300, 600, [], 'Fixé au mur, au-dessus d’un lave-linge ou d’un plan.',
      variants: [
        FixtureVariant('3 kg', 500, 420, 600, 1800, 3000),
        FixtureVariant('4 kg', 600, 440, 680, 2200, 3600),
      ]),
  // ---- tours
  FixtureType('tour_lavage', 'Tour lave-linge et sèche-linge', washCategory, [(600, 600)], 1720, 0, 900, _washWater, 'Deux machines superposées, kit de superposition compris.',
      def: 1,
      variants: [
        FixtureVariant('7 + 7 kg', 600, 560, 1720, 6000, 10500),
        FixtureVariant('8 + 8 kg', 600, 600, 1720, 7200, 12500),
        FixtureVariant('9 + 9 kg', 600, 620, 1720, 8500, 15000),
        FixtureVariant('17 + 17 kg', 700, 770, 1890, 20000, 34000),
      ]),
];

/// Appareil à laver ou à sécher (prise 20 A, robinet machine).
bool isWashAppliance(FixtureType? f) => f?.category == washCategory;
bool isHeater(FixtureType? f) => f?.category == heaterCategory;

/// Machine choisie dans un meuble : « type|capacité ».
(FixtureType, FixtureVariant)? machineOf(String key) {
  final k = key.split('|');
  final f = fixtureById(k.first);
  if (f == null || f.variants.isEmpty) return null;
  return (f, f.variants.where((v) => v.label == k.last).firstOrNull ?? f.defaultVariant!);
}

/// Places de machines d'un meuble de buanderie : (nom, machine par défaut, largeur, hauteur, profondeur disponibles).
List<({String name, String def, double w, double h, double d})> machineSlots(PlacedCabinet c) => switch (c.modelId) {
      'laundry_washer_dryer_side_by_side' => [
          (name: 'Machine de gauche', def: 'll_hublot|8 kg', w: (c.width - 36) / 2, h: c.height + 5.0, // dessus retiré sous le plan
            d: c.depth + 20.0),
          (name: 'Machine de droite', def: 'sl_cond|8 kg', w: (c.width - 36) / 2, h: c.height + 5.0, // dessus retiré sous le plan
            d: c.depth + 20.0),
        ],
      'laundry_washer_dryer_column' => [
          (name: 'Machine du bas', def: 'll_hublot|8 kg', w: c.width - 40.0, h: 860, d: c.depth + 20.0),
          (name: 'Machine du haut', def: 'sl_pac|8 kg', w: c.width - 40.0, h: 860, d: c.depth + 20.0),
        ],
      _ => const [],
    };

/// Machines qui tiennent dans une place : largeur, hauteur, profondeur ; pas de chargement par le dessus sous un plan.
List<(FixtureType, List<FixtureVariant>)> machinesFor(({String name, String def, double w, double h, double d}) slot) => [
      for (final f in homeAppliances)
        if (isWashAppliance(f) && !const {'ll_top', 'll_cuve', 'll_semi', 'tour_lavage', 'sl_mural', 'll_mini'}.contains(f.id))
          if ([for (final v in f.variants) if (v.w <= slot.w && v.h <= slot.h && v.d <= slot.d) v] case final ok when ok.isNotEmpty) (f, ok),
    ];
