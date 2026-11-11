// Barre d'outils de chaque étape, fenêtre de choix de la forme de pièce,
// sélecteur de vue (en bas au centre) et commandes de zoom (en bas à droite).

import 'dart:convert';
import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'brands_ui.dart';
import 'client_ui.dart';
import 'web_io.dart';
import 'busy.dart';
import 'net_symbols.dart';
import 'openings_ui.dart';
import 'room_shape_editor.dart';
import 'scene3d.dart';
import 'header.dart';
import 'theme.dart';
import 'i18n.dart';

enum StyleSection { fronts, worktop, handles, carcass, room }

class StepToolbar extends StatelessWidget {
  final AppState state;
  final void Function(String) onMessage;
  final StyleSection styleSection;
  final ValueChanged<StyleSection> onStyleSection;
  final VoidCallback onExportCsv, onExportPdf, onCutPdf, onSct, onCutSettings, onSave, onIssues;
  final VoidCallback? onManualCut;

  const StepToolbar({
    super.key,
    required this.state,
    required this.onMessage,
    required this.styleSection,
    required this.onStyleSection,
    required this.onExportCsv,
    required this.onExportPdf,
    required this.onCutPdf,
    required this.onSct,
    this.onManualCut,
    required this.onCutSettings,
    required this.onSave,
    required this.onIssues,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final room = state.project.room;
    final tiles = <Widget>[];
    final trailing = <Widget>[];

    switch (state.step) {
      case PlanStep.space:
        tiles.addAll([
          ToolTile(
              icon: Icons.polyline_outlined,
              label: room.outline == null ? tr('Forme de la pièce') : trp('Forme ({0} murs)', [room.order.length]),
              active: room.outline != null,
              onTap: () => showRoomShapeEditor(context, state, onMessage)),
          if ((SizeCatalog.presets[state.project.universe] ?? const []).isNotEmpty)
            ToolTile(icon: Icons.straighten, label: tr('Dimensions types'), onTap: () => showRoomPresets(context, state, onMessage)),
          _openingMenu(context),
          if (state.needsWater) ...[
            ToolTile(
              icon: Icons.water_drop_outlined,
              label: state.existingCount(false) == 0 ? tr('Point d’eau (obligatoire)') : trp('Point d’eau ({0})', [state.existingCount(false)]),
              active: state.existingCount(false) == 0,
              onTap: () {
                state.addExistingWater(NetKind.waterCold);
                if (state.view != ViewMode.front) state.setView(ViewMode.front);
                onMessage(trp('Arrivée d’eau ajoutée sur {0} : glissez-la à sa place réelle (vous pouvez en mettre plusieurs)', [Room.wallNames[state.wallId]?.toLowerCase()]));
              },
            ),
            ToolTile(
              icon: Icons.south_outlined,
              label: state.existingCount(true) == 0 ? tr('Évacuation') : trp('Évacuation ({0})', [state.existingCount(true)]),
              onTap: () {
                state.addExistingWater(NetKind.drain);
                if (state.view != ViewMode.front) state.setView(ViewMode.front);
                onMessage(trp('Évacuation ajoutée sur {0} : glissez-la à sa place réelle', [Room.wallNames[state.wallId]?.toLowerCase()]));
              },
            ),
          ],
          ToolTile(
            icon: Icons.view_in_ar_outlined,
            label: tr('Voir en 3D'),
            active: state.view == ViewMode.view3d,
            onTap: () => state.setView(state.view == ViewMode.view3d ? ViewMode.plan : ViewMode.view3d),
          ),
        ]);
        trailing.addAll([
          MmField(label: tr('Largeur'), value: room.width, onSubmit: (v) => state.updateRoom(width: v)),
          const SizedBox(width: Tokens.s3),
          MmField(label: tr('Profondeur'), value: room.depth, onSubmit: (v) => state.updateRoom(depth: v)),
          const SizedBox(width: Tokens.s3),
          MmField(
              label: tr('Hauteur sous plafond'), value: room.height, min: 2000, max: 4000, onSubmit: (v) => state.updateRoom(height: v)),
        ]);
      case PlanStep.layout:
        tiles.addAll([
          if (state.engine.kitchen)
            ToolTile(icon: Icons.dashboard_customize_outlined, label: tr('Disposition des meubles'), onTap: () => showShapeDialog(context, state)),
          ToolTile(
            icon: Icons.kitchen_outlined,
            label: tr('Éléments de rangement'),
            active: state.megaMenu || state.browse != null,
            onTap: () => state.toggleMegaMenu(),
          ),
          ToolTile(
            icon: Icons.search,
            label: tr('Rechercher'),
            onTap: () => state.openBrowse(const CatalogBrowse(Shelf.base)),
          ),
          ToolTile(
            icon: Icons.chair_outlined,
            label: tr('Objets'),
            active: state.objectsPanel,
            onTap: () => state.openObjects(!state.objectsPanel),
          ),
          // propositions, îlot et réseaux : propres à la cuisine
          if (state.engine.kitchen)
            _fillMenu(context)
          else if (universeTemplates[state.project.universe]?.isNotEmpty ?? false)
            ToolTile(icon: Icons.auto_awesome_outlined, label: tr('Propositions'), onTap: () => showProposalsDialog(context, state, onMessage)),
          if (state.engine.kitchen)
          ToolTile(
            icon: Icons.table_restaurant_outlined,
            label: state.project.room.island == null ? tr('Ajouter un îlot') : tr('Îlot'),
            active: state.project.room.island != null,
            onTap: () {
              if (state.project.room.island == null) {
                onMessage(state.addIsland() ?? tr('Îlot ajouté : choisissez « Îlot » en vue de face ou glissez-le en vue du dessus'));
              } else {
                showIslandDialog(context, state, onMessage);
              }
            },
          ),
          _networksMenu(context),
          ToolTile(
            icon: Icons.add_box_outlined,
            label: tr('Combler les vides'),
            onTap: () {
              final gaps = state.engine.gaps().where((g) => g.fillable).toList();
              if (gaps.isEmpty) {
                onMessage(tr('Aucun vide à combler'));
                return;
              }
              final err = state.edit(() {
                for (final g in gaps) {
                  state.engine.fillGap(g);
                }
              });
              onMessage(err ?? trp('{0} fileur(s) ajouté(s)', [gaps.length]));
            },
          ),
        ]);
      case PlanStep.style:
        tiles.addAll([
          for (final (s, icon, label) in [
            (StyleSection.fronts, Icons.door_front_door_outlined, 'Façades'),
            if (state.engine.kitchen) (StyleSection.worktop, Icons.countertops_outlined, 'Plan de travail'),
            (StyleSection.handles, Icons.drag_handle, 'Poignées'),
            (StyleSection.carcass, Icons.inventory_2_outlined, 'Caissons'),
            (StyleSection.room, Icons.wallpaper_outlined, 'Sol et murs'),
          ])
            ToolTile(icon: icon, label: label, active: styleSection == s, onTap: () => onStyleSection(s)),
        ]);
      case PlanStep.summary:
        tiles.addAll([
          ToolTile(icon: Icons.picture_as_pdf_outlined, label: tr("Plan d'exécution (PDF)"), active: true, onTap: onExportPdf),
          ToolTile(icon: Icons.grid_on, label: tr('Plan de découpe (PDF)'), active: true, onTap: onCutPdf),
          ToolTile(icon: Icons.content_cut, label: tr('Fichiers SketchCut (.sct)'), onTap: onSct),
          ToolTile(icon: Icons.tune, label: tr('Réglages du débit'), onTap: onCutSettings),
          if (onManualCut != null) ToolTile(icon: Icons.edit_note, label: tr('Débit manuel'), onTap: onManualCut!),
          ToolTile(icon: Icons.table_view_outlined, label: tr('Exporter la liste (CSV)'), onTap: onExportCsv),
          ToolTile(icon: Icons.save_outlined, label: tr('Enregistrer le projet'), onTap: onSave),
          ToolTile(icon: Icons.badge_outlined, label: tr('Fiche client'), onTap: () => showClientDialog(context, state, onMessage)),
          ToolTile(icon: Icons.sell_outlined, label: tr('Marques et prix'), onTap: () => showBrandsDialog(context, state, onMessage)),
          ToolTile(
              icon: Icons.speed,
              label: tr('Diagnostic'),
              onTap: () {
                // journal des temps de calcul (débit, nesting, PDF, contrôles) et de la mémoire, pour le support
                downloadBytes('${state.project.name}_diagnostic_performance.json', utf8.encode(PerformanceProfiler.instance.exportJson()),
                    mime: 'application/json');
                onMessage(tr('Diagnostic de performance téléchargé'));
              }),
          ToolTile(icon: Icons.rule, label: tr('Contrôles'), onTap: onIssues),
        ]);
    }

    return Container(
      width: double.infinity,
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s3, vertical: Tokens.s1),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          ...tiles,
          if (trailing.isNotEmpty) ...[
            Container(width: 1, height: 56, margin: const EdgeInsets.symmetric(horizontal: Tokens.s4), color: scheme.outlineVariant),
            ...trailing,
          ],
          const SizedBox(width: Tokens.s4),
          Text(tr(state.step.hint), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      ),
    );
  }

  Widget _openingMenu(BuildContext context) =>
      ToolTile(icon: Icons.sensor_door_outlined, label: tr('Portes et fenêtres'), onTap: () => showOpeningPicker(context, state, onMessage));

  Widget _networksMenu(BuildContext context) {
    final p = state.project;
    final on = p.networks;
    return PopupMenuButton<String>(
      tooltip: tr('Électricité, eau, évacuations, gaz'),
      onSelected: (v) {
        switch (v) {
          case 'toggle':
            state.setNetworks(!on);
            onMessage(on ? tr('Réseaux masqués') : tr('Réseaux posés d’après l’implantation : ils suivent les meubles (vue de face pour les cotes)'));
          case 'regen':
            state.regenerateNetworks(all: true);
            onMessage(tr('Réseaux recalculés (points manuels remplacés)'));
          case 'gas':
          case 'electric':
            state.setHobEnergy(v);
            onMessage(v == 'gas' ? tr('Plaque gaz : robinet gaz dans le meuble de cuisson') : tr('Plaque électrique : sortie de câble 32 A'));
          case 'exist:water':
          case 'exist:drain':
            state.addExistingWater(v == 'exist:water' ? NetKind.waterCold : NetKind.drain);
            if (state.view != ViewMode.front) state.setView(ViewMode.front);
            onMessage(v == 'exist:water'
                ? tr('Arrivée d’eau existante ajoutée : glissez-la à sa place réelle')
                : tr('Évacuation existante ajoutée : glissez-la à sa place réelle'));
          default:
            if (v.startsWith('add:')) {
              state.addPoint(NetKind.parse(v.substring(4)));
              if (state.view != ViewMode.front) state.setView(ViewMode.front);
              onMessage(trp('Point ajouté sur {0} : glissez-le à sa place', [Room.wallNames[state.selectedPointObj?.wallId] ?? 'le mur']));
            }
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(value: 'toggle', checked: on, child: Text(tr('Afficher les réseaux'))),
        PopupMenuItem(
            value: 'regen',
            child: ListTile(leading: Icon(Icons.refresh), title: Text(tr('Tout recalculer')), subtitle: Text(tr('repart de l’implantation')))),
        const PopupMenuDivider(),
        PopupMenuItem(
            value: 'exist:water',
            child: ListTile(leading: Icon(Icons.water_drop_outlined), title: Text(tr('Arrivée d’eau existante')), subtitle: Text(tr('dans la pièce, avant travaux')))),
        PopupMenuItem(
            value: 'exist:drain',
            child: ListTile(leading: Icon(Icons.south_outlined), title: Text(tr('Évacuation existante')), subtitle: Text(tr('pour vérifier la pente vers l’évier')))),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(value: 'gas', checked: p.specs.hobEnergy == 'gas', child: Text(tr('Plaque au gaz'))),
        CheckedPopupMenuItem(value: 'electric', checked: p.specs.hobEnergy == 'electric', child: Text(tr('Plaque électrique (32 A)'))),
        const PopupMenuDivider(),
        for (final k in NetKind.values)
          PopupMenuItem(
            value: 'add:${k.name}',
            child: ListTile(
              dense: true,
              leading: SizedBox(width: 26, height: 26, child: CustomPaint(painter: _NetIcon(k))),
              title: Text(trp('Ajouter : {0}', [tr(k.label)])),
            ),
          ),
      ],
      child: IgnorePointer(child: ToolTile(icon: Icons.electrical_services_outlined, label: tr('Réseaux'), active: on, onTap: _noop)),
    );
  }

  Widget _fillMenu(BuildContext context) => PopupMenuButton<String>(
        tooltip: trp('Propositions de cuisine ou remplissage du mur {0}', [state.wallId]),
        onSelected: (v) {
          switch (v) {
            case 'proposals':
              showProposalsDialog(context, state, onMessage);
            case 'low':
              onMessage(state.autoFill(Band.low) ?? '');
            case 'high':
              onMessage(state.autoFill(Band.high) ?? '');
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
              value: 'proposals',
              child: ListTile(
                  leading: Icon(Icons.auto_awesome),
                  title: Text(tr('Propositions de cuisine')),
                  subtitle: Text(tr('formes éprouvées (L, U, parallèle, îlot) à choisir sur aperçu')))),
          const PopupMenuDivider(),
          PopupMenuItem(
              value: 'low', child: ListTile(leading: const Icon(Icons.kitchen_outlined), title: Text(trp('Caissons bas · mur {0}', [state.wallId])))),
          PopupMenuItem(
              value: 'high', child: ListTile(leading: const Icon(Icons.shelves), title: Text(trp('Caissons hauts · mur {0}', [state.wallId])))),
        ],
        child: IgnorePointer(child: ToolTile(icon: Icons.auto_awesome_outlined, label: tr('Propositions / remplir'), onTap: _noop)),
      );
}

void _noop() {}

class _NetIcon extends CustomPainter {
  final NetKind k;
  _NetIcon(this.k);
  @override
  void paint(Canvas canvas, Size size) => paintNetSymbol(canvas, size.center(Offset.zero), k, size.shortestSide * 0.42);
  @override
  bool shouldRepaint(covariant _NetIcon o) => o.k != k;
}

// ------------------------------------------------------------------ îlot

Future<void> showIslandDialog(BuildContext context, AppState state, void Function(String) onMessage) async {
  final isl = state.project.room.island!;
  final fields = {
    'Longueur (mm)': TextEditingController(text: '${isl.length.round()}'),
    'Distance au mur du fond (mm)': TextEditingController(text: '${isl.y0.round()}'),
    'Distance au mur gauche (mm)': TextEditingController(text: '${isl.x0.round()}'),
    'Débord repas à l\'arrière (mm)': TextEditingController(text: '${isl.overhang.round()}'),
  };
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Îlot')),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in fields.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s3),
              child: TextField(
                controller: e.value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: e.key, border: const OutlineInputBorder(), isDense: true, suffixText: 'mm'),
              ),
            ),
          Text(tr('Caissons bas uniquement, façades tournées vers le mur du fond. Passages de 1000 mm minimum autour.'),
              style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: Tokens.s3),
          // passages actuels autour de l'îlot
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in state.engine.islandAisles().entries)
              Chip(
                avatar: Icon(e.value < 1000 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                    size: 18, color: e.value < 1000 ? Theme.of(ctx).colorScheme.error : const Color(0xFF2F9E44)),
                label: Text(trp('{0} {1} mm', [e.key, e.value.isFinite ? e.value.round() : '-'])),
                visualDensity: VisualDensity.compact,
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'auto'), child: Text(tr('Replacer automatiquement'))),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, 'delete'),
          child: Text(tr('Supprimer l\'îlot')),
        ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuler'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'ok'), child: Text(tr('Appliquer'))),
      ],
    ),
  );
  if (r == 'delete') {
    state.removeIsland();
    onMessage(tr('Îlot supprimé'));
  } else if (r == 'auto') {
    onMessage(state.replaceIsland() ?? tr('Îlot replacé avec 1 m de passage tout autour'));
  } else if (r == 'ok') {
    double? v(String k) => double.tryParse(fields[k]!.text.replaceAll(',', '.'));
    final err = state.setIsland(
      length: v('Longueur (mm)'),
      y0: v('Distance au mur du fond (mm)'),
      x0: v('Distance au mur gauche (mm)'),
      overhang: v('Débord repas à l\'arrière (mm)'),
    );
    onMessage(err ?? tr('Îlot mis à jour'));
  }
}

// ------------------------------------------------------------------ forme de la pièce

Future<void> showShapeDialog(BuildContext context, AppState state) => showDialog(
      context: context,
      builder: (context) {
        final t = Theme.of(context).textTheme;
        return Dialog(
          insetPadding: const EdgeInsets.all(Tokens.s5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              padding: const EdgeInsets.all(Tokens.s5),
              child: ListenableBuilder(
                listenable: state,
                builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('Disposition des meubles'), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(tr('Choisissez les murs qui reçoivent des caissons (en gras). La pièce elle-même ne change pas.'), style: t.bodyMedium),
                      ]),
                    ),
                    IconButton(tooltip: tr('Fermer'), onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ]),
                  const Divider(height: 32),
                  Wrap(spacing: Tokens.s5, runSpacing: Tokens.s5, children: [
                    for (final s in RoomShape.values)
                      _ShapeCard(
                        shape: s,
                        selected: state.project.shape == s,
                        onTap: () {
                          state.applyShape(s);
                          Navigator.pop(context);
                        },
                      ),
                  ]),
                ]),
              ),
            ),
          ),
        );
      },
    );

class _ShapeCard extends StatelessWidget {
  final RoomShape shape;
  final bool selected;
  final VoidCallback onTap;
  const _ShapeCard({required this.shape, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: trp('Cuisine {0}', [tr(shape.label)]),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radius),
        child: SizedBox(
          width: 136,
          child: Column(children: [
            Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary.withValues(alpha: 0.14) : scheme.surface,
                  border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: CustomPaint(painter: _ShapePainter(shape, scheme.onSurface, scheme.primary)),
              ),
              if (selected)
                Positioned(
                  bottom: -14,
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: scheme.primary,
                    child: Icon(Icons.check, size: 18, color: scheme.onPrimary),
                  ),
                ),
            ]),
            const SizedBox(height: Tokens.s5),
            Text(tr(shape.label), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  final RoomShape shape;
  final Color ink, accent;
  _ShapePainter(this.shape, this.ink, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(18, 18, size.width - 36, size.height - 36);
    final thin = Paint()
      ..color = ink.withValues(alpha: 0.35)
      ..strokeWidth = 1.5;
    final thick = Paint()
      ..color = accent
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.square;
    final walls = {
      'A': (r.topLeft, r.topRight),
      'B': (r.topRight, r.bottomRight),
      'D': (r.bottomRight, r.bottomLeft),
      'C': (r.bottomLeft, r.topLeft),
    };
    walls.forEach((id, seg) => canvas.drawLine(seg.$1, seg.$2, thin));
    for (final id in shape.walls) {
      final (a, b) = walls[id]!;
      // caissons dessinés à l'intérieur du mur
      final n = switch (id) { 'A' => const Offset(0, 5), 'B' => const Offset(-5, 0), 'D' => const Offset(0, -5), _ => const Offset(5, 0) };
      canvas.drawLine(a + n, b + n, thick);
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePainter o) => o.shape != shape || o.accent != accent;
}

// ------------------------------------------------------------------ vue et zoom

class ViewSwitcher extends StatelessWidget {
  final AppState state;
  const ViewSwitcher({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 700;
    Widget seg(ViewMode v, IconData icon, String label) {
      final on = state.view == v;
      return Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => state.setView(v),
          child: AnimatedContainer(
            duration: Tokens.fast,
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: on ? scheme.primary.withValues(alpha: 0.14) : null, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: on ? scheme.primary : scheme.onSurfaceVariant),
              if (!narrow) ...[
                const SizedBox(width: 6),
                Text(label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: on ? scheme.primary : scheme.onSurface, fontWeight: on ? FontWeight.w800 : FontWeight.w600)),
              ],
            ]),
          ),
        ),
      );
    }

    final walls = [...state.project.room.walls, if (state.project.room.island != null) state.project.room.wall('I')];
    return Material(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          seg(ViewMode.plan, Icons.grid_view, 'Vue du dessus'),
          seg(ViewMode.front, Icons.crop_portrait, 'Vue de face'),
          seg(ViewMode.view3d, Icons.view_in_ar_outlined, '3D'),
          if (state.view == ViewMode.front) ...[
            Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 6), color: scheme.outlineVariant),
            for (final w in walls)
              Tooltip(
                message: trp('{0} · {1} mm', [Room.wallNames[w.id], w.length.round()]),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => state.setWall(w.id),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: state.wallId == w.id ? scheme.primary : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(w.id,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: state.wallId == w.id
                                ? scheme.onPrimary
                                : w.enabled
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant.withValues(alpha: 0.5))),
                  ),
                ),
              ),
          ],
          if (state.view == ViewMode.view3d) ...[
            Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 6), color: scheme.outlineVariant),
            IconButton(tooltip: tr('Tourner à gauche'), onPressed: () => state.rotate3d(-0.35), icon: const Icon(Icons.rotate_left)),
            IconButton(tooltip: tr('Tourner à droite'), onPressed: () => state.rotate3d(0.35), icon: const Icon(Icons.rotate_right)),
            IconButton(
              tooltip: state.anyOpen ? tr('Fermer tous les meubles') : tr('Ouvrir tous les meubles'),
              isSelected: state.anyOpen,
              onPressed: () => state.openAll(!state.anyOpen),
              icon: const Icon(Icons.door_front_door_outlined),
              selectedIcon: const Icon(Icons.door_sliding_outlined),
            ),
          ],
        ]),
      ),
    );
  }
}

class ZoomControls extends StatelessWidget {
  final AppState state;
  const ZoomControls({super.key, required this.state});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: tr('Zoom avant'), onPressed: () => state.setZoom(state.zoom * 1.25), icon: const Icon(Icons.add)),
        IconButton(tooltip: tr('Zoom arrière'), onPressed: () => state.setZoom(state.zoom / 1.25), icon: const Icon(Icons.remove)),
        IconButton(tooltip: tr('Tout afficher'), onPressed: state.resetZoom, icon: const Icon(Icons.fit_screen_outlined)),
      ]),
    );
  }
}

// ------------------------------------------------------------------ propositions d'implantation

const _universeTitles = {'dressing': 'du dressing', 'bain': 'de salle de bain', 'tv': 'de meuble TV', 'interieur': 'd’intérieur'};

Future<void> showProposalsDialog(BuildContext context, AppState state, void Function(String) onMessage) async {
  final kitchen = state.engine.kitchen;
  // cuisine : formes (L, U, îlot...) + collection ; autres univers : compositions adaptées au mur, avec vos
  // finitions ou celles du modèle
  final props = await runBusy(context, tr('Composition des propositions pour votre pièce…'),
      () => kitchen ? proposeLayouts(state.engine) : [for (final (_, pr) in proposeUniverse(state.engine, withStyle: false)) pr]);
  if (!context.mounted) return;
  if (props.isEmpty) {
    onMessage(kitchen
        ? tr('Aucune implantation complète possible dans cette pièce (évier, plaque et frigo)')
        : tr('Aucune composition ne tient dans cette pièce : agrandissez un mur ou retirez une porte'));
    return;
  }
  final chosen = await showDialog<(LayoutProposal, bool)>(
    context: context,
    builder: (ctx) => kitchen
        ? _ProposalsDialog(state: state, props: props)
        : _ProposalsDialog(
            state: state,
            props: props,
            title: 'Propositions ${_universeTitles[state.project.universe] ?? ''}',
            firstTab: 'Selon votre pièce',
            firstText: 'Compositions recalculées pour le mur le plus adapté de votre pièce (largeurs ajustées, modules ajoutés ou retirés). '
                'Les éléments posés seront remplacés, vos finitions sont conservées.',
            collectionText: 'La collection kitchinox : chaque modèle avec ses façades, poignées, caissons, sol et murs, recalculé pour votre pièce.',
            collection: () => proposeUniverse(state.engine, withStyle: true),
          ),
  );
  if (chosen == null) return;
  final (pr, withStyle) = chosen;
  final err = state.applyLayoutProposal(pr, withStyle: withStyle);
  onMessage(err ?? trp('{0}{1} : {2} éléments posés', [withStyle ? 'Modèle ' : '', tr(pr.name), pr.project.items.length]));
}

class _ProposalsDialog extends StatefulWidget {
  final AppState state;
  final List<LayoutProposal> props;
  final String title, firstTab, firstText, collectionText;
  final List<(String, LayoutProposal)> Function()? collection; // (famille, proposition) ; null = collection de cuisine
  const _ProposalsDialog({
    required this.state,
    required this.props,
    this.title = 'Propositions de cuisine',
    this.firstTab = 'Formes',
    this.firstText = 'Implantations composées selon les règles des cuisinistes : froid, préparation, lavage, préparation, cuisson ; '
        'évier sous la fenêtre, colonnes groupées, triangle d’activité entre 4 et 7,9 m. Les éléments posés seront '
        'remplacés, le style reste le vôtre.',
    this.collectionText = 'La collection kitchinox : des cuisines complètes (forme, composition, façades, plan, poignées, sol, murs, '
        'crédence), recalculées pour votre pièce.',
    this.collection,
  });
  @override
  State<_ProposalsDialog> createState() => _ProposalsDialogState();
}

class _ProposalsDialogState extends State<_ProposalsDialog> {
  List<(String, LayoutProposal)>? _collection;
  bool _loading = false;
  String _family = 'Toutes';

  void _loadCollection() {
    if (_collection != null || _loading) return;
    _loading = true;
    // calcul un peu long (24 modèles) : après l'affichage de l'onglet
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      final c = widget.collection?.call() ?? [for (final (tp, pr) in buildTemplates(widget.state.engine)) (tp.family, pr)];
      if (mounted) setState(() => _collection = c);
    });
  }

  Widget _card(BuildContext ctx, LayoutProposal pr, {bool recommended = false, String? family, required bool withStyle}) {
    final t = Theme.of(ctx).textTheme;
    final scheme = Theme.of(ctx).colorScheme;
    return SizedBox(
      width: 310,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radius),
          side: BorderSide(color: recommended ? scheme.primary : scheme.outlineVariant, width: recommended ? 2 : 1),
        ),
        child: InkWell(
          onTap: () => Navigator.pop(ctx, (pr, withStyle)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 190,
              width: double.infinity,
              child: ColoredBox(color: const Color(0xFFF6F5F2), child: CustomPaint(painter: _ProposalPainter(widget.state, pr))),
            ),
            Padding(
              padding: const EdgeInsets.all(Tokens.s3),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(tr(pr.name), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                  if (recommended)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(10)),
                      child: Text(tr('Recommandée'), style: t.labelSmall?.copyWith(color: scheme.onPrimary)),
                    ),
                  if (family != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(10)),
                      child: Text(family, style: t.labelSmall),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(tr(pr.description), style: t.bodySmall),
                const SizedBox(height: 6),
                for (final s in pr.strengths)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.check, size: 14, color: scheme.primary),
                    const SizedBox(width: 4),
                    Expanded(child: Text(s, style: t.bodySmall)),
                  ]),
                for (final w in pr.warnings.take(2))
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline, size: 14, color: Color(0xFFE8590C)),
                    const SizedBox(width: 4),
                    Expanded(child: Text(w, style: t.bodySmall)),
                  ]),
                const SizedBox(height: 6),
                Text(proposalSummary(widget.state.engine, pr), style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 1000,
          height: 640,
          child: Column(children: [
            TabBar(
              onTap: (i) {
                if (i == 1) _loadCollection();
              },
              tabs: [Tab(text: widget.firstTab), const Tab(text: 'Collection kitchinox')],
            ),
            const SizedBox(height: Tokens.s3),
            Expanded(
              child: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
                SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.firstText, style: t.bodySmall),
                    const SizedBox(height: Tokens.s4),
                    Wrap(spacing: Tokens.s4, runSpacing: Tokens.s4, children: [
                      for (var i = 0; i < widget.props.length; i++) _card(context, widget.props[i], recommended: i == 0, withStyle: false),
                    ]),
                  ]),
                ),
                Builder(builder: (context) {
                  final col = _collection;
                  if (col == null) {
                    _loadCollection();
                    return Center(child: LogoLoader(size: 130, label: tr('Composition des modèles pour votre pièce…')));
                  }
                  final families = ['Toutes', ...{for (final (f, _) in col) f}];
                  final shown = [for (final x in col) if (_family == 'Toutes' || x.$1 == _family) x];
                  return SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(trp('{0} {1} modèles possibles ici.', [widget.collectionText, col.length]), style: t.bodySmall),
                      const SizedBox(height: Tokens.s3),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final f in families)
                          ChoiceChip(label: Text(f), selected: _family == f, onSelected: (_) => setState(() => _family = f)),
                      ]),
                      const SizedBox(height: Tokens.s4),
                      Wrap(spacing: Tokens.s4, runSpacing: Tokens.s4, children: [
                        for (final (f, pr) in shown) _card(context, pr, family: f, withStyle: true),
                      ]),
                    ]),
                  );
                }),
              ]),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler')))],
      ),
    );
  }
}

class _ProposalPainter extends CustomPainter {
  final AppState state;
  final LayoutProposal pr;
  _ProposalPainter(this.state, this.pr);

  @override
  void paint(Canvas canvas, Size size) {
    final e = LayoutEngine(state.catalog, pr.project);
    final cam = Camera3d.fit(pr.project.room, -0.6, size, zoom: 1.75);
    Scene3dPainter(e, cam, selectColor: Colors.orange, background: const Color(0xFFF6F5F2), handles: state.db?.handles).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _ProposalPainter o) => o.pr != pr;
}
