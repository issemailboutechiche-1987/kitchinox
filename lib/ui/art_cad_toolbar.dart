// Bandeau contextuel des outils du Mode Art :
// 1. Outils de dessin 2D : Ligne, Rectangle, Rectangle orienté, Polygone, Cercle, Arc, Main levée
// 2. Outils de transformation : Déplacer, Pivoter, Échelle, Symétrie
// 3. Outils de mesure : Mètre ruban, Cotation
// 4. Outil Pousser / Tirer (Extrusion SketchUp)
// 5. Outils de menuiserie : Bande de chant, Rainure

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../engine/art.dart';
import '../engine/art_cad.dart';
import 'i18n.dart';

const _brandOrange = Color(0xFFF26A1B);

/// Bandeau d'action contextuel en bas de l'écran lorsqu'un outil CAO est sélectionné
class ArtCadContextHud extends StatelessWidget {
  final CadTool activeTool;
  final String statusText;
  final ArtPanel? selectedPanel;
  final CadShape? selectedShape;
  final double pushPullThickness;
  final ValueChanged<double> onPushPullThicknessChanged;
  final VoidCallback? onExecutePushPull;
  final ValueChanged<double> onApplyEdgeBanding;
  final void Function(double offset, double depth, double width) onApplyGroove;
  final void Function(String axis) onApplyMirror;
  final void Function(double dx, double dy, double dz) onApplyTranslate;
  final void Function(double angleDeg) onApplyRotate;
  final VoidCallback onCancel;
  final int linePointsCount;
  final VoidCallback? onCloseLoop;
  final VoidCallback? onInspectPanel;
  final VoidCallback? onDeleteSelected;
  final VoidCallback? onDuplicateSelected;
  final ValueChanged<ArtRole>? onSetRole;
  final VoidCallback? onToggleHinge;
  final Widget? extra; // réglage propre à l'outil (ex. matière des panneaux dessinés)

  const ArtCadContextHud({
    super.key,
    required this.activeTool,
    required this.statusText,
    this.selectedPanel,
    this.selectedShape,
    required this.pushPullThickness,
    required this.onPushPullThicknessChanged,
    this.onExecutePushPull,
    required this.onApplyEdgeBanding,
    required this.onApplyGroove,
    required this.onApplyMirror,
    required this.onApplyTranslate,
    required this.onApplyRotate,
    required this.onCancel,
    this.linePointsCount = 0,
    this.onCloseLoop,
    this.onInspectPanel,
    this.onDeleteSelected,
    this.onDuplicateSelected,
    this.onSetRole,
    this.onToggleHinge,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xF01E222A) : const Color(0xF5FFFFFF);
    final border = isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000);
    const rows = {CadTool.line, CadTool.pushPull, CadTool.edgeBand, CadTool.groove, CadTool.symmetry, CadTool.move, CadTool.rotate};

    return Material(
      color: bg,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: BoxConstraints(maxWidth: math.min(880.0, MediaQuery.of(context).size.width - 32)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // réglages propres à l'outil, sur leur propre ligne (défilable si l'écran est étroit)
            if (extra != null) ...[
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: extra!),
            ],
            if (extra != null && rows.contains(activeTool)) const SizedBox(height: 8),

            // Panneau contextuel selon l'outil (scrollable horizontalement pour éviter tout débordement)
            // (découpe, liaison, dessin : leurs réglages suffisent)
            if (rows.contains(activeTool)) SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: activeTool == CadTool.line
                  ? _buildLineRow(context)
                  : activeTool == CadTool.select
                      ? _buildSelectRow(context)
                      : activeTool == CadTool.pushPull
                          ? _buildPushPullRow(context)
                          : activeTool == CadTool.edgeBand
                              ? _buildEdgeBandRow(context)
                              : activeTool == CadTool.groove
                                  ? _buildGrooveRow(context)
                                  : activeTool == CadTool.symmetry
                                      ? _buildSymmetryRow(context)
                                      : activeTool == CadTool.move
                                          ? _buildMoveRow(context)
                                          : activeTool == CadTool.rotate
                                              ? _buildRotateRow(context)
                                              : _buildDrawingRow(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineRow(BuildContext context) {
    final presets = [18.0, 16.0, 19.0, 12.0, 6.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            linePointsCount == 0
                ? tr('Posez le 1er point')
                : trp('Sommets : {0}', [linePointsCount]),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue),
          ),
        ),
        const SizedBox(width: 8),
        Text(tr('Épaisseur future :'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(width: 6),
        for (final th in presets)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('${th.toInt()} mm'),
              selected: (pushPullThickness - th).abs() < 0.1,
              onSelected: (_) => onPushPullThicknessChanged(th),
              visualDensity: VisualDensity.compact,
            ),
          ),
        if (linePointsCount >= 3 && onCloseLoop != null) ...[
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.check_circle, size: 16),
            label: Text(tr('Fermer & Créer feuille 3D')),
            onPressed: onCloseLoop,
          ),
        ],
      ],
    );
  }

  Widget _buildSelectRow(BuildContext context) {
    final p = selectedPanel;
    if (p == null) {
      return Row(
        children: [
          const Icon(Icons.touch_app, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Text(
            tr('Cliquez sur un panneau 3D ou une esquisse pour modifier ses caractéristiques.'),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _brandOrange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${tr(p.role.label)} · ${p.w.round()} × ${p.h.round()} × ${p.d.round()} mm',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _brandOrange),
          ),
        ),
        const SizedBox(width: 8),
        if (onSetRole != null)
          PopupMenuButton<ArtRole>(
            tooltip: tr('Rôle du panneau'),
            onSelected: onSetRole,
            itemBuilder: (_) => [
              for (final r in ArtRole.values) CheckedPopupMenuItem(value: r, checked: r == p.role, child: Text(tr(r.label))),
            ],
            child: Chip(
              avatar: const Icon(Icons.category_outlined, size: 14),
              label: Text(tr('Rôle')),
              visualDensity: VisualDensity.compact,
            ),
          ),
        if (onToggleHinge != null && p.role == ArtRole.porte) ...[
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.swap_horiz, size: 14),
            label: Text(p.hinge == 'right' ? tr('Charnières à droite') : tr('Charnières à gauche')),
            onPressed: onToggleHinge,
            visualDensity: VisualDensity.compact,
          ),
        ],
        const SizedBox(width: 8),
        if (onInspectPanel != null)
          FilledButton.tonalIcon(
            icon: const Icon(Icons.tune, size: 16),
            label: Text(tr('Modifier caractéristiques (Taille, Chants, Rainures)')),
            onPressed: onInspectPanel,
          ),
        const SizedBox(width: 6),
        if (onDuplicateSelected != null)
          ActionChip(
            avatar: const Icon(Icons.copy, size: 14),
            label: Text(tr('Dupliquer')),
            onPressed: onDuplicateSelected,
            visualDensity: VisualDensity.compact,
          ),
        const SizedBox(width: 6),
        if (onDeleteSelected != null)
          ActionChip(
            avatar: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
            label: Text(tr('Supprimer'), style: const TextStyle(color: Colors.red)),
            onPressed: onDeleteSelected,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _buildPushPullRow(BuildContext context) {
    final presets = [18.0, 16.0, 19.0, 12.0, 6.0, 36.0, 50.0];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('Épaisseur :'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 8),
          for (final th in presets)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${th.toInt()} mm'),
                selected: (pushPullThickness - th).abs() < 0.1,
                onSelected: (_) => onPushPullThicknessChanged(th),
                visualDensity: VisualDensity.compact,
              ),
            ),
          const SizedBox(width: 10),
          if (onExecutePushPull != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _brandOrange,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.check, size: 16),
              label: Text(tr('Extruder')),
              onPressed: onExecutePushPull,
            ),
        ],
      ),
    );
  }

  Widget _buildEdgeBandRow(BuildContext context) {
    final p = selectedPanel;
    final chantPresets = [0.4, 1.0, 2.0];
    return Row(
      children: [
        if (p != null) ...[
          Text('${tr(p.role.label)} (${p.w.round()}×${p.h.round()} mm) : ',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 6),
        ],
        Text(tr('Appliquer chant :'), style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 6),
        for (final th in chantPresets)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              avatar: const Icon(Icons.line_weight, size: 14),
              label: Text('$th mm'),
              onPressed: () => onApplyEdgeBanding(th),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.clear, size: 14),
          label: Text(tr('Sans chant')),
          onPressed: () => onApplyEdgeBanding(0),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildGrooveRow(BuildContext context) {
    return Row(
      children: [
        Text(tr('Presets rainure fond :'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        ActionChip(
          label: Text(tr('Standard (10x8 mm - fond 6mm)')),
          onPressed: () => onApplyGroove(10, 8, 6),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 6),
        ActionChip(
          label: Text(tr('Profonde (15x10 mm - fond 8mm)')),
          onPressed: () => onApplyGroove(15, 10, 8),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 6),
        ActionChip(
          label: Text(tr('Supprimer rainure')),
          onPressed: () => onApplyGroove(0, 0, 0),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildSymmetryRow(BuildContext context) {
    return Row(
      children: [
        Text(tr('Axe du miroir :'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: () => onApplyMirror('X'),
          child: Text(tr('Axe X (Gauche / Droite)')),
        ),
        const SizedBox(width: 6),
        FilledButton.tonal(
          onPressed: () => onApplyMirror('Y'),
          child: Text(tr('Axe Y (Haut / Bas)')),
        ),
        const SizedBox(width: 6),
        FilledButton.tonal(
          onPressed: () => onApplyMirror('Z'),
          child: Text(tr('Axe Z (Avant / Arrière)')),
        ),
      ],
    );
  }

  Widget _buildMoveRow(BuildContext context) {
    return Row(
      children: [
        Text(tr('Déplacements rapides :'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        ActionChip(
          label: const Text('+100 mm X'),
          onPressed: () => onApplyTranslate(100, 0, 0),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 4),
        ActionChip(
          label: const Text('-100 mm X'),
          onPressed: () => onApplyTranslate(-100, 0, 0),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 6),
        ActionChip(
          label: const Text('+100 mm Y'),
          onPressed: () => onApplyTranslate(0, 100, 0),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 4),
        ActionChip(
          label: const Text('-100 mm Y'),
          onPressed: () => onApplyTranslate(0, -100, 0),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 6),
        ActionChip(
          label: const Text('+50 mm Z'),
          onPressed: () => onApplyTranslate(0, 0, 50),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildRotateRow(BuildContext context) {
    return Row(
      children: [
        Text(tr('Rotation 90° :'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.rotate_right, size: 16),
          label: Text(tr('+90° (Sens horaire)')),
          onPressed: () => onApplyRotate(90),
        ),
        const SizedBox(width: 6),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.rotate_left, size: 16),
          label: const Text('-90°'),
          onPressed: () => onApplyRotate(-90),
        ),
        const SizedBox(width: 6),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.screen_rotation, size: 16),
          label: const Text('180°'),
          onPressed: () => onApplyRotate(180),
        ),
      ],
    );
  }

  Widget _buildDrawingRow(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 16, color: _brandOrange),
        const SizedBox(width: 6),
        Text(
          activeTool == CadTool.cut
              ? tr('PC : un clic coupe. Tablette : placez la ligne puis « Couper », ou tapez la cote puis Entrée. La ligne s’accroche aux bords et au milieu des pièces.')
              : tr('Cliquez sur le plancher ou une face pour poser les points. Vous pourrez extruder en 3D avec Pousser/Tirer.'),
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
