// Choix parmi plusieurs valeurs, sans jamais couper les mots : sur une ligne tant que ça tient, sinon à la ligne.
// Même écriture que SegmentedButton (segments, selected, onSelectionChanged).
import 'package:flutter/material.dart';

class KxChoices<T> extends StatelessWidget {
  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final bool showSelectedIcon;
  final ButtonStyle? style; // seule la densité est reprise
  const KxChoices({super.key, required this.segments, required this.selected, required this.onSelectionChanged, this.showSelectedIcon = false, this.style});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = style?.visualDensity == VisualDensity.compact;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final s in segments)
          () {
            final on = selected.contains(s.value);
            final active = s.enabled && onSelectionChanged != null;
            return ChoiceChip(
              showCheckmark: false,
              avatar: s.icon == null
                  ? null
                  : IconTheme.merge(data: IconThemeData(size: 18, color: on ? scheme.primary : scheme.onSurfaceVariant), child: s.icon!),
              label: s.label ?? const SizedBox.shrink(),
              tooltip: s.tooltip,
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: compact ? 4 : 8),
              side: BorderSide(color: on ? scheme.primary : scheme.outlineVariant, width: on ? 2 : 1),
              backgroundColor: scheme.surface,
              selectedColor: scheme.primary.withValues(alpha: 0.12),
              labelStyle: TextStyle(fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: !active ? scheme.outline : (on ? scheme.primary : scheme.onSurface)),
              selected: on,
              onSelected: active
                  ? (_) {
                      if (!on) onSelectionChanged!({s.value});
                    }
                  : null,
            );
          }(),
      ],
    );
  }
}
