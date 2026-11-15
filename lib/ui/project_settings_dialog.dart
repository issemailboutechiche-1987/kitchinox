// Dialogue unifié des Paramètres du Projet Kitchinox :
// 1. Fiche client (nom, société, ICE, contact)
// 2. Paramètres de débit & optimisation des panneaux (dimensions, trait de scie, recoupe, épaisseurs, jeux)
// 3. Hauteurs et standards architecturaux (plans de travail, plinthes, caissons hauts, casquettes)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/standards.dart';
import 'app_state.dart';
import 'i18n.dart';
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

  // Contrôleurs Débit
  final sheetLCtrl = TextEditingController(text: '${cs.sheetLength}');
  final sheetWCtrl = TextEditingController(text: '${cs.sheetWidth}');
  final kerfCtrl = TextEditingController(text: '${cs.kerf}');
  final trimCtrl = TextEditingController(text: '${cs.trim}');
  final carcassThickCtrl = TextEditingController(text: '${cs.carcassThickness}');
  final doorThickCtrl = TextEditingController(text: '${cs.doorThickness}');
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

        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.tune, color: Color(0xFFF26522)),
              const SizedBox(width: Tokens.s2),
              Text(tr('Paramètres du projet')),
            ],
          ),
          content: SizedBox(
            width: 580,
            height: 480,
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

                        // TAB 2: DÉBIT & PANNEAUX
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(Tokens.s2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(tr('Paramètres pour le nesting, débit des panneaux et fiches SketchCut.'), style: t.bodySmall),
                              const SizedBox(height: Tokens.s3),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: sheetLCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(labelText: tr('Longueur panneau (mm)'), border: const OutlineInputBorder(), isDense: true),
                                    ),
                                  ),
                                  const SizedBox(width: Tokens.s2),
                                  Expanded(
                                    child: TextField(
                                      controller: sheetWCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(labelText: tr('Largeur panneau (mm)'), border: const OutlineInputBorder(), isDense: true),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: Tokens.s3),
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
                              const SizedBox(height: Tokens.s3),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: carcassThickCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(labelText: tr('Épaisseur caisson (mm)'), border: const OutlineInputBorder(), isDense: true),
                                    ),
                                  ),
                                  const SizedBox(width: Tokens.s2),
                                  Expanded(
                                    child: TextField(
                                      controller: doorThickCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(labelText: tr('Épaisseur façade (mm)'), border: const OutlineInputBorder(), isDense: true),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: Tokens.s3),
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
                              SegmentedButton<String>(
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
                              SegmentedButton<int>(
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(value: 700, label: Text('700 mm')),
                                  ButtonSegment(value: 720, label: Text('720 mm (Std)')),
                                  ButtonSegment(value: 750, label: Text('750 mm')),
                                  ButtonSegment(value: 800, label: Text('800 mm (Maxi)')),
                                ],
                                selected: {baseH},
                                onSelectionChanged: (v) => setD(() => baseH = v.first),
                              ),
                              const SizedBox(height: Tokens.s3),
                              Text(tr('Hauteur de plinthe'), style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: Tokens.s1),
                              SegmentedButton<int>(
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(value: 80, label: Text('80 mm')),
                                  ButtonSegment(value: 100, label: Text('100 mm (Std)')),
                                  ButtonSegment(value: 120, label: Text('120 mm')),
                                  ButtonSegment(value: 150, label: Text('150 mm')),
                                ],
                                selected: {plinthH},
                                onSelectionChanged: (v) => setD(() => plinthH = v.first),
                              ),
                              const SizedBox(height: Tokens.s3),
                              Text(tr('Hauteur des caissons hauts'), style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: Tokens.s1),
                              SegmentedButton<int>(
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
                              SegmentedButton<int>(
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
                state.edit(() {
                  // Sauvegarde Client
                  c.name = nameCtrl.text.trim();
                  c.company = companyCtrl.text.trim();
                  c.ice = iceCtrl.text.trim();

                  // Sauvegarde Débit
                  cs.sheetLength = int.tryParse(sheetLCtrl.text) ?? cs.sheetLength;
                  cs.sheetWidth = int.tryParse(sheetWCtrl.text) ?? cs.sheetWidth;
                  cs.kerf = int.tryParse(kerfCtrl.text) ?? cs.kerf;
                  cs.trim = int.tryParse(trimCtrl.text) ?? cs.trim;
                  cs.carcassThickness = int.tryParse(carcassThickCtrl.text) ?? cs.carcassThickness;
                  cs.doorThickness = int.tryParse(doorThickCtrl.text) ?? cs.doorThickness;
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
