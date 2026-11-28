// Choix parmi plusieurs valeurs : sélecteur segmenté compact (un bloc, la pastille du choix animée) ;
// tout reste visible : s'il manque de place, le bloc passe à la ligne sans couper les mots. Même écriture que SegmentedButton
// (segments, selected, onSelectionChanged).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final t = Theme.of(context).textTheme;
    final compact = style?.visualDensity == VisualDensity.compact;
    final track = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(12)),
      child: Wrap(spacing: 2, runSpacing: 2, children: [
        for (final s in segments)
          () {
            final on = selected.contains(s.value);
            final active = s.enabled && onSelectionChanged != null;
            final child = AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              constraints: BoxConstraints(minHeight: compact ? 32 : 38),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 4 : 6),
              decoration: BoxDecoration(
                color: on ? scheme.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                border: on ? Border.all(color: scheme.primary, width: 1.5) : null,
                boxShadow: on ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))] : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (s.icon != null) ...[
                  IconTheme.merge(data: IconThemeData(size: 16, color: on ? scheme.primary : scheme.onSurfaceVariant), child: s.icon!),
                  if (s.label != null) const SizedBox(width: 6),
                ],
                if (s.label != null)
                  DefaultTextStyle(
                    style: (t.labelLarge ?? const TextStyle()).copyWith(
                        fontSize: 13, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: !active ? scheme.outline : (on ? scheme.primary : scheme.onSurface)),
                    child: s.label!,
                  ),
              ]),
            );
            final tap = InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: active && !on
                  ? () {
                      HapticFeedback.selectionClick();
                      onSelectionChanged!({s.value});
                    }
                  : null,
              child: child,
            );
            return Semantics(
              selected: on,
              button: true,
              child: s.tooltip == null ? tap : Tooltip(message: s.tooltip!, child: tap),
            );
          }(),
      ]),
    );
    return track;
  }
}
