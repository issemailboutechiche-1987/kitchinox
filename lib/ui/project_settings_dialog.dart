// Dialogue unifié des Paramètres du Projet Kitchinox :
// 1. Fiche client (nom, société, ICE, contact)
// 2. Paramètres de débit & optimisation des panneaux (Caissons, Façades, Fonds, formats, épaisseurs, machine)
// 3. Hauteurs et standards architecturaux (plans de travail, plinthes, caissons hauts, casquettes)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/cutting.dart';
import '../engine/standards.dart';
import 'app_state.dart';
import 'i18n.dart';
import 'kx_choices.dart';
import 'theme.dart';

Future<void> showProjectSettingsDialog(BuildContext context, AppState state, void Function(String) onMessage) {
  final p = state.project;
  final c = p.client;
  final cs = p.cut;
  final std = p.standards;

  // Contrôleurs Client
  final nameCtrl = TextEditingController(text: c.name);
  final companyCtrl = TextEditingController(text: c.company);
  final iceCtrl = TextEditingController(text: c.ice);

  // Contrôleurs Débit - Caissons
  String carcassMat = cs.carcassMaterial;
  final sheetLCtrl = TextEditingController(text: '${cs.sheetLength}');
  final sheetWCtrl = TextEditingController(text: '${cs.sheetWidth}');
  final carcassThickCtrl = TextEditingController(text: '${cs.carcassThickness}');

  // Contrôleurs Débit - Façades
  String frontMat = cs.frontMaterial;
  final (fL, fW) = cs.sheetDimensionsFor(cs.frontMaterial);
  final frontSheetLCtrl = TextEditingController(text: '${cs.frontSheetLength ?? fL}');
  final frontSheetWCtrl = TextEditingController(text: '${cs.frontSheetWidth ?? fW}');
  final doorThickCtrl = TextEditingController(text: '${cs.doorThickness}');

  // Contrôleurs Débit - Fonds
  String backMat = cs.backMaterial;
  final (bL, bW) = cs.sheetDimensionsFor(cs.backMaterial);
  final backSheetLCtrl = TextEditingController(text: '${cs.backSheetLength ?? bL}');
  final backSheetWCtrl = TextEditingController(text: '${cs.backSheetWidth ?? bW}');
  final backThickCtrl = TextEditingController(text: '${cs.backThickness}');

  // Prix d'une feuille, par type de panneau (vide : tarif des caissons / prix public)
  final sp = state.project.specs;
  final sheetPriceCtrl = TextEditingController(text: sp.sheetPrice?.round().toString() ?? '');
  final frontPriceCtrl = TextEditingController(text: sp.frontSheetPrice?.round().toString() ?? '');
  final backPriceCtrl = TextEditingController(text: sp.backSheetPrice?.round().toString() ?? '');

  // Paramètres généraux
  final kerfCtrl = TextEditingController(text: '${cs.kerf}');
  final trimCtrl = TextEditingController(text: '${cs.trim}');
  final frontGapCtrl = TextEditingController(text: '${cs.frontGap}');
  final gapHCtrl = TextEditingController(text: '${cs.gapH}');
  String machine = cs.machine;
  int method = cs.method;

  // Contrôleurs Standards
  int baseH = std.baseCarcassHeight;
  int plinthH = std.plinthHeight;
  int topThick = std.worktopThickness;
  int splashH = std.credenceHeight;
  int wallH = std.wallHeightDefault;

  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        final t = Theme.of(ctx).textTheme;
        final scheme = Theme.of(ctx).colorScheme;

        Widget buildSectionCard({
          required IconData icon,
          required String title,
          required String subtitle,
          required Widget child,
        }) {
          return Container(
            margin: const EdgeInsets.only(bottom: Tokens.s3),
            padding: const EdgeInsets.all(Tokens.s3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: const Color(0xFFF26522)),
                    const SizedBox(width: Tokens.s2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                          Text(subtitle, style: t.bodySmall?.copyWith(color: scheme.outline, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.s2),
                child,
              ],
            ),
          );
        }

        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.tune, color: Color(0xFFF26522)),
              const SizedBox(width: Tokens.s2),
              Text(tr('Paramètres du projet')),
            ],
          ),
          content: SizedBox(
            width: 660,
            height: 540,
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    labelColor: scheme.primary,
                    indicatorColor: scheme.primary,
                    tabs: [
                      Tab(icon: const Icon(Icons.badge_outlined), text: tr('Fiche client')),
                      Tab(icon: const Icon(Icons.content_cut), text: tr('Débit & Panneaux')),
                      Tab(icon: const Icon(Icons.straighten), text: tr('Hauteurs & Cotes')),
                    ],
                  ),
                  const SizedBox(height: Tokens.s3),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // TAB 1: FICHE CLIENT
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(Tokens.s2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(tr('Informations client imprimées sur les plans, devis et fiches de fabrication.'), style: t.bodySmall),
                              const SizedBox(height: Tokens.s3),
                              TextField(
                                controller: nameCtrl,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: tr('Nom du client'),
                                  prefixIcon: const Icon(Icons.person_outline),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: Tokens.s3),
                              TextField(
                                controller: companyCtrl,
                                decoration: InputDecoration(
                                  labelText: tr('Société / Entreprise'),
                                  prefixIcon: const Icon(Icons.business_outlined),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: Tokens.s3),
                              TextField(
                                controller: iceCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(19)],
                                decoration: InputDecoration(
                                  labelText: tr('Identifiant Commun de l’Entreprise (ICE)'),
                                  prefixIcon: const Icon(Icons.pin_outlined),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: Tokens.s3),
                              Text(trp('Univers : {0} · Projet : {1}', [tr(p.universe.toUpperCase()), p.name]), style: t.bodySmall?.copyWith(color: scheme.outline)),
                            ],
                          ),
                        ),

                        // TAB 2: DÉBIT & PANNEAUX (3 CATÉGORIES : CAISSONS, FAÇADES, FONDS)
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(Tokens.s2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                tr('Formats de feuilles, épaisseurs et paramètres de débit pour les caissons, façades et fonds.'),
                                style: t.bodySmall,
                              ),
                              const SizedBox(height: Tokens.s3),

                              // 1. CAISSONS (Latté / MDF / Stratifié)
                              buildSectionCard(
                                icon: Icons.kitchen,
                                title: tr('1. Panneaux Caissons (Corps de meuble)'),
                                subtitle: tr('Latté blockboard, mélaminé ou stratifié - Mesures de feuille configurables'),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      initialValue: carcassMat, // matière du projet, même hors de la liste type
                                      decoration: InputDecoration(labelText: tr('Matériau des caissons'), border: const OutlineInputBorder(), isDense: true),
                                      items: [for (final m in {carcassMat, ...carcassMaterialChoices}) DropdownMenuItem(value: m, child: Text(tr(m), overflow: TextOverflow.ellipsis))],
                                      onChanged: (v) {
                                        if (v == null) return;
                                        setD(() {
                                          carcassMat = v;
                                          final cat = v.contains('Latté') ? 'Latté (Blockboard)' : v.contains('Stratifié') ? 'Stratifié / Mélaminé' : 'MDF';
                                          final p0 = woodSheetPresets[cat]?.first;
                                          if (p0 != null) {
                                            sheetLCtrl.text = '${p0.length}';
                                            sheetWCtrl.text = '${p0.width}';
                                          }
                                        });
                                      },
                                    ),
                                    const SizedBox(height: Tokens.s2),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Text('${tr('Presets')} :', style: t.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                                        for (final pr in [
                                          const SheetPreset('2100 × 2020 mm (Latté atelier)', 2100, 2020),
                                          const SheetPreset('2440 × 1220 mm (8×4)', 2440, 1220),
                                          const SheetPreset('2800 × 2070 mm', 2800, 2070),
                                          const SheetPreset('2800 × 2100 mm', 2800, 2100),
                                        ])
                                          ActionChip(
                                            visualDensity: VisualDensity.compact,
                                            label: Text(pr.label, style: const TextStyle(fontSize: 11)),
                                            onPressed: () {
                                              setD(() {
                                                sheetLCtrl.text = '${pr.length}';
                                                sheetWCtrl.text = '${pr.width}';
                                              });
                                            },
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: Tokens.s2),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: sheetLCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Longueur feuille (mm)'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                        const SizedBox(width: Tokens.s2),
                                        Expanded(
                                          child: TextField(
                                            controller: sheetWCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Largeur feuille (mm)'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                        const SizedBox(width: Tokens.s2),
                                        Expanded(
                                          child: TextField(
                                            controller: carcassThickCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Épaisseur (mm)'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                        const SizedBox(width: Tokens.s2),
                                        Expanded(
                                          child: TextField(
                                            key: const ValueKey('price_sheetPriceCtrl'),
                                            controller: sheetPriceCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Prix feuille (MAD)'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // 2. FAÇADES & PORTES (MDF / High Gloss / Acrylique)
                              buildSectionCard(
                                icon: Icons.door_front_door_outlined,
                                title: tr('2. Panneaux Façades (Portes & faces tiroirs)'),
                                subtitle: tr('MDF brut, High Gloss brillant ou Acrylique - Format standard 2800×1220 ou atelier'),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      initialValue: frontMat, // matière du projet, même hors de la liste type
                                      decoration: InputDecoration(labelText: tr('Matériau des façades'), border: const OutlineInputBorder(), isDense: true),
                                      items: [for (final m in {frontMat, ...frontMaterialChoices}) DropdownMenuItem(value: m, child: Text(tr(m), overflow: TextOverflow.ellipsis))],
                                      onChanged: (v) {
                                        if (v == null) return;
                                        setD(() {
                                          frontMat = v;
                                          final cat = v.contains('High Gloss') || v.contains('Acrylique') || v.contains('PET')
                                              ? 'High Gloss / Acrylique'
                                              : 'MDF';
                                          final p0 = woodSheetPresets[cat]?.first;
                                          if (p0 != null) {
                                            frontSheetLCtrl.text = '${p0.length}';
                                            frontSheetWCtrl.text = '${p0.width}';
                                          }
                                        });
                                      },
                                    ),
                                    const SizedBox(height: Tokens.s2),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Text('${tr('Presets')} :', style: t.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                                        for (final pr in [
                                          const SheetPreset('2800 × 1220 mm (High Gloss standard)', 2800, 1220),
                                          const SheetPreset('2440 × 1220 mm (8×4)', 2440, 1220),
                                          const SheetPreset('2750 × 1220 mm', 2750, 1220),
                                          const SheetPreset('2800 × 2100 mm (Grand format)', 2800, 2100),
                                        ])
                                          ActionChip(
                                            visualDensity: VisualDensity.compact,
                                            label: Text(pr.label, style: const TextStyle(fontSize: 11)),
                                            onPressed: () {
                                              setD(() {
                                                frontSheetLCtrl.text = '${pr.length}';
                                                frontSheetWCtrl.text = '${pr.width}';
                                              });
                                            },
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: Tokens.s2),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: frontSheetLCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Longueur feuille (mm)'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                        const SizedBox(width: Tokens.s2),
                                        Expanded(
                                          child: TextField(
                                            controller: frontSheetWCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Largeur feuille (mm)'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                        const SizedBox(width: Tokens.s2),
                                        Expanded(
                                          child: TextField(
                                            controller: doorThickCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Épaisseur (mm)'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                        const SizedBox(width: Tokens.s2),
                                        Expanded(
                                          child: TextField(
                                            key: const ValueKey('price_frontPriceCtrl'),
                                            controller: frontPriceCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Prix feuille (MAD)'), hintText: tr('Vide : prix des caissons'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // 3. FONDS ARRIÈRE (HDF / Panneaux minces rainurés)
                              buildSectionCard(
                                icon: Icons.flip_to_back,
                                title: tr('3. Panneaux Fonds arrière (Dos rainurés)'),
                                subtitle: tr('HDF 6 mm ou 3 mm - Mesures et épaisseur prises en compte pour découpe et devis'),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      initialValue: backMat, // matière du projet, même hors de la liste type
                                      decoration: InputDecoration(labelText: tr('Matériau des fonds'), border: const OutlineInputBorder(), isDense: true),
                                      items: [for (final m in {backMat, ...backMaterialChoices}) DropdownMenuItem(value: m, child: Text(tr(m), overflow: TextOverflow.ellipsis))],
                                      onChanged: (v) {
                                        if (v == null) return;
                                        setD(() {
                                          backMat = v;
                                          final thMatch = RegExp(r'(\d+)\s*mm').firstMatch(v);
                                          if (thMatch != null) {
                                            backThickCtrl.text = thMatch.group(1)!;
                                          }
                                        });
                                      },
                                    ),
                                    const SizedBox(height: Tokens.s2),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Text('${tr('Presets')} :', style: t.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                                        for (final pr in [
                                          const SheetPreset('2800 × 2100 mm (Grand format)', 2800, 2100),
                                          const SheetPreset('2440 × 1220 mm (Standard 8×4)', 2440, 1220),
                                          const SheetPreset('2070 × 2800 mm', 2070, 2800),
                                        ])
                                          ActionChip(
                                            visualDensity: VisualDensity.compact,
                                            label: Text(pr.label, style: const TextStyle(fontSize: 11)),
                                            onPressed: () {
                                              setD(() {
                                                backSheetLCtrl.text = '${pr.length}';
                                                backSheetWCtrl.text = '${pr.width}';
                                              });
                                            },
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: Tokens.s2),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: backSheetLCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Longueur feuille (mm)'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                        const SizedBox(width: Tokens.s2),
                                        Expanded(
                                          child: TextField(
                                            controller: backSheetWCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Largeur feuille (mm)'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                        const SizedBox(width: Tokens.s2),
                                        Expanded(
                                          child: TextField(
                                            controller: backThickCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Épaisseur (mm)'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                        const SizedBox(width: Tokens.s2),
                                        Expanded(
                                          child: TextField(
                                            key: const ValueKey('price_backPriceCtrl'),
                                            controller: backPriceCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Prix feuille (MAD)'), hintText: tr('Vide : prix public'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // 4. PARAMÈTRES DE COUPE & MACHINE
                              buildSectionCard(
                                icon: Icons.precision_manufacturing_outlined,
                                title: tr('4. Paramètres de coupe & Machine'),
                                subtitle: tr('Trait de lame, recoupes périphériques et jeux de fonctionnement'),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: kerfCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Trait de scie (mm)'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                        const SizedBox(width: Tokens.s2),
                                        Expanded(
                                          child: TextField(
                                            controller: trimCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Recoupe des bords (mm)'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: Tokens.s2),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: frontGapCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Jeu vertical (mm)'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                        const SizedBox(width: Tokens.s2),
                                        Expanded(
                                          child: TextField(
                                            controller: gapHCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(labelText: tr('Jeu horizontal (mm)'), border: const OutlineInputBorder(), isDense: true),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: Tokens.s3),
                                    Text(tr('Type de machine de découpe'), style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: Tokens.s1),
                                    KxChoices<String>(
                                      showSelectedIcon: false,
                                      segments: [
                                        ButtonSegment(value: 'scie', label: Text(tr('Scie à panneaux (bandes)'))),
                                        ButtonSegment(value: 'cnc', label: Text(tr('Centre d’usinage CNC (libre)'))),
                                      ],
                                      selected: {machine},
                                      onSelectionChanged: (v) => setD(() => machine = v.first),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // TAB 3: HAUTEURS & STANDARDS
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(Tokens.s2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(tr('Hauteurs ergonomiques et standards Kitchinox.'), style: t.bodySmall),
                              const SizedBox(height: Tokens.s3),
                              Text(tr('Hauteur caisson bas'), style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: Tokens.s1),
                              KxChoices<int>(
                                showSelectedIcon: false,
                                segments: [
                                  ButtonSegment(value: 700, label: Text('700 mm')),
                                  ButtonSegment(value: 720, label: Text(tr('720 mm (Std)'))),
                                  ButtonSegment(value: 750, label: Text('750 mm')),
                                  ButtonSegment(value: 800, label: Text(tr('800 mm (Maxi)'))),
                                ],
                                selected: {baseH},
                                onSelectionChanged: (v) => setD(() => baseH = v.first),
                              ),
                              const SizedBox(height: Tokens.s3),
                              Text(tr('Hauteur de plinthe'), style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: Tokens.s1),
                              KxChoices<int>(
                                showSelectedIcon: false,
                                segments: [
                                  ButtonSegment(value: 80, label: Text('80 mm')),
                                  ButtonSegment(value: 100, label: Text(tr('100 mm (Std)'))),
                                  ButtonSegment(value: 120, label: Text('120 mm')),
                                  ButtonSegment(value: 150, label: Text('150 mm')),
                                ],
                                selected: {plinthH},
                                onSelectionChanged: (v) => setD(() => plinthH = v.first),
                              ),
                              const SizedBox(height: Tokens.s3),
                              Text(tr('Hauteur des caissons hauts'), style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: Tokens.s1),
                              KxChoices<int>(
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(value: 600, label: Text('600 mm')),
                                  ButtonSegment(value: 720, label: Text('720 mm')),
                                  ButtonSegment(value: 800, label: Text('800 mm')),
                                  ButtonSegment(value: 1000, label: Text('1000 mm')),
                                ],
                                selected: {wallH},
                                onSelectionChanged: (v) => setD(() => wallH = v.first),
                              ),
                              const SizedBox(height: Tokens.s3),
                              Text(tr('Hauteur de crédence (sous hauts)'), style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: Tokens.s1),
                              KxChoices<int>(
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(value: 500, label: Text('500 mm')),
                                  ButtonSegment(value: 550, label: Text('550 mm')),
                                  ButtonSegment(value: 600, label: Text('600 mm')),
                                ],
                                selected: {splashH},
                                onSelectionChanged: (v) => setD(() => splashH = v.first),
                              ),
                              const SizedBox(height: Tokens.s2),
                              Text(
                                trp('Plan de travail fini : {0} mm du sol', [plinthH + baseH + topThick]),
                                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFFF26522)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(tr('Annuler')),
            ),
            FilledButton(
              onPressed: () {
                // une cote vide ou impossible garde l'ancienne valeur
                int mm(TextEditingController t, int old, int min) {
                  final x = int.tryParse(t.text.trim());
                  return x == null || x < min ? old : x;
                }

                state.edit(() {
                  // Sauvegarde Client
                  c.name = nameCtrl.text.trim();
                  c.company = companyCtrl.text.trim();
                  c.ice = iceCtrl.text.trim();

                  // Sauvegarde Débit - Caissons
                  cs.carcassMaterial = carcassMat;
                  cs.sheetLength = mm(sheetLCtrl, cs.sheetLength, 300);
                  cs.sheetWidth = mm(sheetWCtrl, cs.sheetWidth, 300);
                  cs.carcassThickness = mm(carcassThickCtrl, cs.carcassThickness, 2);

                  // Sauvegarde Débit - Façades
                  cs.frontMaterial = frontMat;
                  cs.frontSheetLength = mm(frontSheetLCtrl, cs.frontSheetLength ?? cs.sheetLength, 300);
                  cs.frontSheetWidth = mm(frontSheetWCtrl, cs.frontSheetWidth ?? cs.sheetWidth, 300);
                  cs.doorThickness = mm(doorThickCtrl, cs.doorThickness, 2);

                  // Sauvegarde Débit - Fonds
                  cs.backSheetLength = mm(backSheetLCtrl, cs.backSheetLength ?? cs.sheetLength, 300);
                  cs.backSheetWidth = mm(backSheetWCtrl, cs.backSheetWidth ?? cs.sheetWidth, 300);
                  cs.backThickness = mm(backThickCtrl, cs.backThickness, 2);

                  cs.backMaterial = backMaterialName(backMat, cs.backThickness); // le nom suit l'épaisseur saisie

                  // Prix par type de panneau
                  double? price(TextEditingController t) {
                    final x = double.tryParse(t.text.trim().replaceAll(',', '.'));
                    return x == null || x <= 0 ? null : x;
                  }

                  sp
                    ..sheetPrice = price(sheetPriceCtrl)
                    ..frontSheetPrice = price(frontPriceCtrl)
                    ..backSheetPrice = price(backPriceCtrl);

                  // Sauvegarde Débit - Général
                  cs.kerf = int.tryParse(kerfCtrl.text) ?? cs.kerf;
                  cs.trim = int.tryParse(trimCtrl.text) ?? cs.trim;
                  cs.frontGap = int.tryParse(frontGapCtrl.text) ?? cs.frontGap;
                  cs.gapH = int.tryParse(gapHCtrl.text) ?? cs.gapH;
                  cs.machine = machine;
                  cs.method = method;

                  // Sauvegarde Standards
                  state.project.standards = KitchenStandards(
                    baseCarcassHeight: baseH,
                    plinthHeight: plinthH,
                    worktopThickness: topThick,
                    wallHeightDefault: wallH,
                    wallBottomDefault: baseH + plinthH + topThick + splashH,
                  );
                });
                Navigator.of(ctx).pop();
                onMessage(tr('Paramètres du projet mis à jour'));
              },
              child: Text(tr('Enregistrer')),
            ),
          ],
        );
      },
    ),
  );
}
