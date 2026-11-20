// Barre d'outils CAO et bandeau contextuel pour le Mode Art :
// 1. Outils de dessin 2D : Ligne, Rectangle, Rectangle orienté, Polygone, Cercle, Arc, Main levée
// 2. Outils de transformation : Déplacer, Pivoter, Échelle, Symétrie
// 3. Outils de mesure : Mètre ruban, Cotation
// 4. Outil Pousser / Tirer (Extrusion SketchUp)
// 5. Outils de menuiserie : Bande de chant, Rainure

import 'package:flutter/material.dart';

import '../engine/art.dart';
import '../engine/art_cad.dart';
import 'i18n.dart';

const _brandOrange = Color(0xFFF26A1B);

/// Barre d'outils flottante CAO (façon SketchUp / CAO pro)
class ArtCadToolbar extends StatelessWidget {
  final CadTool activeTool;
  final ValueChanged<CadTool> onToolSelected;
  final VoidCallback onClearSketches;
  final int sketchCount;
  final int dimensionCount;
  final bool isMachiningMode;
  final VoidCallback onToggleMachiningMode;
  final CadWorkPlane workPlane;
  final ValueChanged<CadWorkPlane> onWorkPlaneChanged;
  final bool orthoLock;
  final ValueChanged<bool> onToggleOrtho;
  final bool autoExtrude;
  final ValueChanged<bool> onToggleAutoExtrude;

  const ArtCadToolbar({
    super.key,
    required this.activeTool,
    required this.onToolSelected,
    required this.onClearSketches,
    this.sketchCount = 0,
    this.dimensionCount = 0,
    this.isMachiningMode = false,
    required this.onToggleMachiningMode,
    this.workPlane = CadWorkPlane.ground,
    required this.onWorkPlaneChanged,
    this.orthoLock = true,
    required this.onToggleOrtho,
    this.autoExtrude = true,
    required this.onToggleAutoExtrude,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xE622262E) : const Color(0xF5FFFFFF);
    final border = isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000);

    return Material(
      color: bg,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bascule Mode Usinage (Trous, Tourillons, Vis, Chants)
              Tooltip(
                message: isMachiningMode
                    ? tr('Mode Usinage actif (Tourillons, Vis, Perçages). Cliquer pour revenir à la CAO.')
                    : tr('Activer le Mode Usinage (Tourillons, Vis, Perçages 32mm, Chants)'),
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: isMachiningMode ? const Color(0xFFD97706) : null,
                    foregroundColor: isMachiningMode ? Colors.white : null,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: Icon(isMachiningMode ? Icons.precision_manufacturing : Icons.precision_manufacturing_outlined, size: 18),
                  label: Text(tr('Mode Usinage'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: onToggleMachiningMode,
                ),
              ),
              _divider(border),

              // Plan 2D actif (Sol XZ / Façade XY / Côté YZ)
              Tooltip(
                message: tr('Plan 2D de travail : ') + tr(workPlane.label),
                child: PopupMenuButton<CadWorkPlane>(
                  initialValue: workPlane,
                  onSelected: onWorkPlaneChanged,
                  tooltip: tr('Changer le plan 2D'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: _brandOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.layers, size: 16, color: _brandOrange),
                        const SizedBox(width: 5),
                        Text(
                          workPlane.label,
                          style: const TextStyle(color: _brandOrange, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 16, color: _brandOrange),
                      ],
                    ),
                  ),
                  itemBuilder: (ctx) => [
                    for (final wp in CadWorkPlane.values)
                      PopupMenuItem(
                        value: wp,
                        child: Row(
                          children: [
                            Icon(
                              wp == workPlane ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                              size: 16,
                              color: wp == workPlane ? _brandOrange : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(wp.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text(wp.description, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),

              // Verrouillage 90° (Ortho)
              Tooltip(
                message: orthoLock
                    ? tr('Verrouillage orthogonal 90° ACTIF (X / Y à angle droit)')
                    : tr('Verrouillage orthogonal 90° INACTIF (angles libres)'),
                child: IconButton(
                  icon: Icon(
                    Icons.square_foot,
                    size: 20,
                    color: orthoLock ? _brandOrange : Colors.grey,
                  ),
                  onPressed: () => onToggleOrtho(!orthoLock),
                  visualDensity: VisualDensity.compact,
                ),
              ),

              // Création directe feuille 3D
              Tooltip(
                message: autoExtrude
                    ? tr('Feuille 3D auto ACTIVE : les formes 2D fermées créent directement un panneau 3D')
                    : tr('Feuille 3D auto INACTIVE : conserve sous forme d’esquisse 2D filaire'),
                child: IconButton(
                  icon: Icon(
                    autoExtrude ? Icons.view_in_ar : Icons.crop_free,
                    size: 20,
                    color: autoExtrude ? _brandOrange : Colors.grey,
                  ),
                  onPressed: () => onToggleAutoExtrude(!autoExtrude),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              _divider(border),

              // Sélection
              _btn(CadTool.select, Icons.near_me_outlined, 'Sélectionner'),
              _divider(border),

              // Groupe 1 : Dessin 2D (Image 1)
              _btn(CadTool.line, Icons.edit_outlined, 'Ligne / Crayon (Orthogonal 90°)'),
              _btn(CadTool.freehand, Icons.gesture, 'Main levée'),
              _btn(CadTool.rectangle, Icons.crop_square_outlined, 'Rectangle'),
              _btn(CadTool.rotatedRectangle, Icons.crop_rotate, 'Rectangle orienté'),
              _btn(CadTool.circle, Icons.radio_button_unchecked, 'Cercle'),
              _btn(CadTool.polygon, Icons.hexagon_outlined, 'Polygone régulier'),
              _btn(CadTool.arc, Icons.architecture, 'Arc de cercle'),
              _divider(border),

              // Groupe 2 : Modification 3D (Image 2)
              _btn(CadTool.move, Icons.open_with, 'Déplacer'),
              _btn(CadTool.rotate, Icons.autorenew, 'Pivoter'),
              _btn(CadTool.scale, Icons.aspect_ratio, 'Échelle'),
              _btn(CadTool.symmetry, Icons.flip, 'Symétrie / Miroir'),
              _divider(border),

              // Groupe 3 : Mesure (Image 3)
              _btn(CadTool.tape, Icons.straighten, 'Mètre ruban'),
              _btn(CadTool.dimension, Icons.linear_scale, 'Cotation permanente'),
              _divider(border),

              // Groupe 4 : Pousser / Tirer (Image 4)
              _btn(CadTool.pushPull, Icons.vertical_align_top, 'Pousser / Tirer (Extrusion 3D)'),
              _btn(CadTool.cut, Icons.content_cut, 'Couper la feuille (X / Y)'),
              _btn(CadTool.link, Icons.link, 'Lier deux chants (le 1er passe dessous)'),
              _divider(border),

              // Groupe 5 : Menuiserie (Chants & Rainures)
              _btn(CadTool.edgeBand, Icons.border_all, 'Bande de chant'),
              _btn(CadTool.groove, Icons.line_style, 'Rainure'),

              if (sketchCount > 0 || dimensionCount > 0) ...[
                _divider(border),
                IconButton(
                  tooltip: tr('Effacer les esquisses 2D'),
                  icon: const Icon(Icons.layers_clear_outlined, size: 20, color: Colors.redAccent),
                  onPressed: onClearSketches,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static const _keys = {
    CadTool.select: 'Espace',
    CadTool.line: 'L',
    CadTool.rectangle: 'R',
    CadTool.circle: 'C',
    CadTool.move: 'M',
    CadTool.rotate: 'Q',
    CadTool.tape: 'T',
    CadTool.dimension: 'D',
    CadTool.pushPull: 'P',
    CadTool.edgeBand: 'B',
    CadTool.groove: 'G',
    CadTool.cut: 'X',
    CadTool.link: 'K',
  };

  Widget _btn(CadTool tool, IconData icon, String tooltip) {
    final active = activeTool == tool;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        // raccourci clavier façon SketchUp
        message: _keys[tool] == null ? tr(tooltip) : '${tr(tooltip)} (${tr(_keys[tool]!)})',
        child: Material(
          color: active ? _brandOrange : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onToolSelected(tool),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 20,
                color: active ? Colors.white : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider(Color border) => Container(
        height: 24,
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: border,
      );
}

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
  final TextEditingController? measureController;
  final FocusNode? measureFocus;
  final String measureHint;
  final ValueChanged<String>? onMeasure;
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
    this.measureController,
    this.measureFocus,
    this.measureHint = '',
    this.onMeasure,
    this.onSetRole,
    this.onToggleHinge,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xF01E222A) : const Color(0xF5FFFFFF);
    final border = isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000);
    final t = Theme.of(context).textTheme;

    return Material(
      color: bg,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 880),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _brandOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tr(activeTool.label),
                    style: const TextStyle(
                      color: _brandOrange,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(statusText),
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (measureController != null && measureHint.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  // boîte des cotes : on peut aussi taper directement au clavier, puis Entrée
                  SizedBox(
                    width: 170,
                    child: TextField(
                      key: const ValueKey('cad_measure'),
                      controller: measureController,
                      focusNode: measureFocus,
                      textInputAction: TextInputAction.done,
                      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.straighten, size: 16),
                        prefixIconConstraints: const BoxConstraints(minWidth: 28),
                        hintText: measureHint,
                        hintStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      onSubmitted: (v) {
                        onMeasure?.call(v);
                        measureFocus?.unfocus();
                      },
                    ),
                  ),
                ],
                IconButton(
                  tooltip: tr('Fermer / Revenir à la sélection'),
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onCancel,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
            // réglages propres à l'outil, sur leur propre ligne (défilable si l'écran est étroit)
            if (extra != null) ...[
              const SizedBox(height: 8),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: extra!),
            ],
            const SizedBox(height: 8),

            // Panneau contextuel selon l'outil (scrollable horizontalement pour éviter tout débordement)
            SingleChildScrollView(
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
    return Row(
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
          label: const Text('+90° (Sens horaire)'),
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
          tr('Cliquez sur le plancher ou une face pour poser les points. Vous pourrez extruder en 3D avec Pousser/Tirer.'),
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
