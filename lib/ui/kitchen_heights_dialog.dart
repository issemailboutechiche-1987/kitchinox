// Dialogue de réglage des hauteurs de cuisine : caissons bas, crédence,
// caissons hauts et caissons casquette (sur-meubles pleine hauteur jusqu'au plafond).
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'theme.dart';
import 'i18n.dart';

Future<void> showKitchenHeightsDialog(
  BuildContext context,
  AppState st,
  void Function(String) onMessage,
) {
  final t = Theme.of(context).textTheme;
  final scheme = Theme.of(context).colorScheme;
  final std = st.project.standards;
  final roomH = st.project.room.height;

  int baseH = std.baseCarcassHeight;
  int plinthH = std.plinthHeight;
  int worktopH = std.worktopThickness;
  int credenceH = std.credenceHeight;
  int wallH = std.wallHeightDefault;
  bool casquette = std.casquetteEnabled;
  int casquetteH = std.casquetteHeight;
  int casquetteD = std.casquetteDepth;

  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        final worktopTop = plinthH + baseH + worktopH;
        final wallBottom = worktopTop + credenceH;
        final wallTop = wallBottom + wallH;
        final ceilingDist = roomH - wallTop;

        void applyToExisting() {
          st.edit(() {
            st.project.standards = st.project.standards.copyWith(
              baseCarcassHeight: baseH,
              plinthHeight: plinthH,
              worktopThickness: worktopH,
              wallBottomDefault: wallBottom,
              wallHeightDefault: wallH,
              casquetteEnabled: casquette,
              casquetteHeight: casquetteH,
              casquetteDepth: casquetteD,
            );

            // Met à jour les meubles existants
            for (final c in st.project.items) {
              final m = st.engine.modelOf(c);
              if (m.kind.isLow) {
                c.height = baseH;
              } else if (m.kind == CabinetKind.wall || m.kind == CabinetKind.cornerWall) {
                if (c.z < wallTop) {
                  c.z = wallBottom.toDouble();
                  c.height = wallH;
                }
              }
            }
          });
          st.refresh();
          onMessage(tr('Hauteurs appliquées à tous les meubles du projet'));
          Navigator.pop(ctx);
        }

        void generateCasquettes() {
          var count = 0;
          st.edit(() {
            final wallsWithHauts = <String, List<PlacedCabinet>>{};
            for (final c in st.project.items) {
              final m = st.engine.modelOf(c);
              if (m.kind == CabinetKind.wall) {
                (wallsWithHauts[c.wallId] ??= []).add(c);
              }
            }

            final actualCasquetteH = casquetteH > 0 && casquetteH <= ceilingDist
                ? casquetteH
                : math.max(250, ceilingDist);

            for (final entry in wallsWithHauts.entries) {
              final wId = entry.key;
              final list = entry.value;
              for (final c in list) {
                // Vérifier s'il y a déjà un caisson au-dessus
                final alreadyHasAbove = st.project.items.any(
                  (other) => other.wallId == wId && other.z >= c.top - 10 && (other.s - c.s).abs() < 50,
                );
                if (!alreadyHasAbove && actualCasquetteH >= 200) {
                  final modelId = c.width >= 700 ? 'wall_lift_up' : 'wall_standard_single_door';
                  try {
                    final newCab = st.engine.add(
                      modelId,
                      wId,
                      s: c.s,
                      z: c.top,
                      width: c.width,
                      height: actualCasquetteH.toInt(),
                    );
                    newCab.depth = casquetteD;
                    count++;
                  } catch (_) {}
                }
              }
            }
          });
          st.refresh();
          Navigator.pop(ctx);
          onMessage(trp('{0} caisson(s) casquette posé(s) au-dessus des hauts', [count]));
        }

        Widget chipGroup<T>({
          required String title,
          required T current,
          required List<(T, String)> options,
          required ValueChanged<T> onSelect,
          String? subtitle,
        }) =>
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(title), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(tr(subtitle), style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final (val, label) in options)
                  ChoiceChip(
                    label: Text(label),
                    selected: current == val,
                    onSelected: (_) => setD(() => onSelect(val)),
                  ),
              ]),
              const SizedBox(height: Tokens.s3),
            ]);

        return AlertDialog(
          title: Row(children: [
            const Icon(Icons.height, size: 28),
            const SizedBox(width: Tokens.s2),
            Expanded(child: Text(tr('Hauteurs des caissons & Crédence'))),
          ]),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Résumé visuel en direct
                Container(
                  padding: const EdgeInsets.all(Tokens.s3),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(tr('Plan de travail'), style: t.labelMedium),
                      Text(trp('{0} mm du sol', [worktopTop]), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ]),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(tr('Crédence (dégagement)'), style: t.labelMedium),
                      Text(trp('{0} mm', [credenceH]), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ]),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(tr('Haut des meubles hauts'), style: t.labelMedium),
                      Text(trp('{0} mm du sol', [wallTop]), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ]),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(tr('Espace restant sous plafond'), style: t.labelMedium),
                      Text(
                        trp('{0} mm', [ceilingDist]),
                        style: t.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ceilingDist < 0 ? scheme.error : scheme.primary,
                        ),
                      ),
                    ]),
                  ]),
                ),
                const SizedBox(height: Tokens.s4),

                // 1. Caissons bas
                chipGroup<int>(
                  title: 'Hauteur des caissons bas',
                  subtitle: 'Hauteur du meuble hors pieds et plan',
                  current: baseH,
                  options: const [
                    (720, '720 mm (Standard)'),
                    (750, '750 mm (Kitchinox)'),
                    (780, '780 mm (Maxi)'),
                    (820, '820 mm (Grand)'),
                  ],
                  onSelect: (v) => baseH = v,
                ),

                // Plinthe & Plan
                Row(children: [
                  Expanded(
                    child: chipGroup<int>(
                      title: 'Plinthe',
                      current: plinthH,
                      options: const [
                        (100, '100 mm'),
                        (120, '120 mm'),
                        (150, '150 mm'),
                      ],
                      onSelect: (v) => plinthH = v,
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  Expanded(
                    child: chipGroup<int>(
                      title: 'Plan de travail',
                      current: worktopH,
                      options: const [
                        (20, '20 mm'),
                        (38, '38 mm'),
                        (50, '50 mm'),
                      ],
                      onSelect: (v) => worktopH = v,
                    ),
                  ),
                ]),

                // 2. Crédence
                chipGroup<int>(
                  title: 'Hauteur de la crédence',
                  subtitle: 'Espace libre entre le plan de travail et le dessous des hauts',
                  current: credenceH,
                  options: const [
                    (500, '500 mm (Basse)'),
                    (550, '550 mm (Standard)'),
                    (600, '600 mm (Confort)'),
                    (650, '650 mm (Haute)'),
                  ],
                  onSelect: (v) => credenceH = v,
                ),

                // 3. Caissons hauts
                chipGroup<int>(
                  title: 'Hauteur des caissons hauts',
                  subtitle: 'Hauteur standard de la première rangée de meubles hauts',
                  current: wallH,
                  options: const [
                    (360, '360 mm (Court)'),
                    (600, '600 mm (Médium)'),
                    (720, '720 mm (Standard)'),
                    (800, '800 mm'),
                    (900, '900 mm (Haut)'),
                    (1000, '1000 mm (Maxi)'),
                  ],
                  onSelect: (v) => wallH = v,
                ),

                const Divider(),

                // 4. Caissons casquette
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Caissons casquette (sur-meubles)'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    tr('Remplissage toute hauteur jusqu’au plafond au-dessus des meubles hauts'),
                    style: t.labelSmall,
                  ),
                  value: casquette,
                  onChanged: (v) => setD(() => casquette = v),
                ),

                if (casquette) ...[
                  const SizedBox(height: Tokens.s2),
                  chipGroup<int>(
                    title: 'Profondeur de la casquette',
                    current: casquetteD,
                    options: const [
                      (370, '370 mm (Alignée sur les hauts)'),
                      (600, '600 mm (Alignée sur colonnes / Moderne)'),
                    ],
                    onSelect: (v) => casquetteD = v,
                  ),
                  chipGroup<int>(
                    title: 'Hauteur de la casquette',
                    current: casquetteH,
                    options: [
                      (360, '360 mm'),
                      (400, '400 mm'),
                      if (ceilingDist > 0) (ceilingDist.toInt(), trp('{0} mm (Jusqu’au plafond)', [ceilingDist.toInt()])),
                    ],
                    onSelect: (v) => casquetteH = v,
                  ),
                  FilledButton.tonalIcon(
                    onPressed: generateCasquettes,
                    icon: const Icon(Icons.vertical_align_top),
                    label: Text(tr('Poser les caissons casquette sur les hauts existants')),
                  ),
                  const SizedBox(height: Tokens.s2),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuler'))),
            FilledButton(
              onPressed: applyToExisting,
              child: Text(tr('Appliquer au projet')),
            ),
          ],
        );
      },
    ),
  );
}
