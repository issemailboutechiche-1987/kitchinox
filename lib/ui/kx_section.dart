// Section repliable des panneaux : titre, choix en cours (et sa vignette) sur la même ligne ; on déplie pour
// changer. Les panneaux restent courts, et on voit d'un coup d'œil tout ce qui est choisi.
import 'package:flutter/material.dart';

class KxSection extends StatefulWidget {
  final String title;
  final String? value; // choix en cours, résumé
  final Widget? leading; // vignette du choix en cours
  final Widget child;
  final bool initiallyOpen;
  const KxSection({super.key, required this.title, this.value, this.leading, required this.child, this.initiallyOpen = false});
  @override
  State<KxSection> createState() => _KxSectionState();
}

class _KxSectionState extends State<KxSection> {
  late bool open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: open ? scheme.surface : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: open ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => open = !open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(children: [
              if (widget.leading != null) ...[ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 44, height: 32, child: widget.leading)), const SizedBox(width: 10)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  if (widget.value != null)
                    Text(widget.value!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ]),
              ),
              AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(Icons.expand_more, color: scheme.onSurfaceVariant)),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open ? Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: widget.child) : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

/// Un libellé discret au-dessus d'un réglage, dans une section.
class KxLabel extends StatelessWidget {
  final String text;
  const KxLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
      );
}

/// Carrousel de cartes à vignette (un seul choix) : défile à l'horizontale, la carte choisie est cerclée.
class KxCarousel<T> extends StatelessWidget {
  final List<(T value, String label, Widget thumb)> items;
  final T selected;
  final ValueChanged<T> onSelected;
  final double width;
  const KxCarousel({super.key, required this.items, required this.selected, required this.onSelected, this.width = 116});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (v, label, thumb) in items)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelected(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: width,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: v == selected ? scheme.primary.withValues(alpha: 0.08) : scheme.surface,
                  border: Border.all(color: v == selected ? scheme.primary : scheme.outlineVariant, width: v == selected ? 2 : 1),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: width - 8, height: (width - 8) * 0.62, child: thumb)),
                  const SizedBox(height: 4),
                  Text(label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: t.labelSmall?.copyWith(fontWeight: v == selected ? FontWeight.w800 : FontWeight.w600, color: v == selected ? scheme.primary : scheme.onSurface)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
