// Attente des tâches longues : arrière-plan flouté et logo kitchinox qui se dessine en boucle, jusqu'à la
// fin de la tâche (propositions, plans PDF, débit, ouverture d'un univers...).
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'logo.dart';

/// Logo animé (pochoir qui se trace puis se remplit, en boucle).
class LogoLoader extends StatefulWidget {
  final double size;
  final String? label;
  const LogoLoader({super.key, this.size = 160, this.label});
  @override
  State<LogoLoader> createState() => _LogoLoaderState();
}

class _LogoLoaderState extends State<LogoLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _a;
  LogoShape? _logo;

  @override
  void initState() {
    super.initState();
    _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
    LogoShape.load().then((l) {
      if (mounted) setState(() => _logo = l);
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: widget.size,
        height: widget.size * 228.1 / 276.7,
        child: _logo == null
            ? const SizedBox()
            : AnimatedBuilder(
                animation: _a,
                builder: (_, _) {
                  final v = _a.value;
                  // trace (0 → 0,6), remplissage (0,5 → 0,8), puis s'efface (0,85 → 1)
                  final draw = Curves.easeInOut.transform((v / 0.6).clamp(0.0, 1.0));
                  final fill = Curves.easeIn.transform(((v - 0.5) / 0.3).clamp(0.0, 1.0)) * (1 - ((v - 0.85) / 0.15).clamp(0.0, 1.0));
                  return CustomPaint(painter: LogoPainter(_logo!, draw: v > 0.85 ? 1 : draw, fill: fill));
                },
              ),
      ),
      if (widget.label != null) ...[
        const SizedBox(height: 16),
        Text(widget.label!, textAlign: TextAlign.center, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    ]);
  }
}

/// Avancement d'une tâche longue : fraction (0 à 1) et étape en cours.
class BusyProgress extends ValueNotifier<(double, String)> {
  BusyProgress() : super((0, ''));
  void set(double f, String step) => value = (f.clamp(0.0, 1.0), step);
}

/// Barre de progression centrée sous le logo : pourcentage et étape en cours.
class _ProgressBar extends StatelessWidget {
  final BusyProgress progress;
  const _ProgressBar(this.progress);
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<(double, String)>(
      valueListenable: progress,
      builder: (_, v, _) => SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              key: const Key('busy-progress'),
              value: v.$1,
              minHeight: 10,
              backgroundColor: scheme.primary.withValues(alpha: 0.15),
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(v.$2, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text('${(v.$1 * 100).round()} %', style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary)),
          ]),
        ]),
      ),
    );
  }
}

/// Lance [task] derrière un voile flouté avec le logo animé ; le voile reste jusqu'à la fin de la tâche.
/// Surcouche (pas une page) : elle bloque les gestes sans toucher à la navigation.
/// Avec [progress], une barre de progression s'affiche au centre, sous le logo.
Future<T> runBusy<T>(BuildContext context, String label, FutureOr<T> Function() task, {BusyProgress? progress}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return await task();
  final surface = Theme.of(context).colorScheme.surface;
  final entry = OverlayEntry(
    builder: (_) => Stack(children: [
      const ModalBarrier(dismissible: false),
      Positioned.fill(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
          child: Container(
            color: surface.withValues(alpha: 0.45),
            alignment: Alignment.center,
            child: Material(
              type: MaterialType.transparency,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                LogoLoader(label: label),
                if (progress != null) _ProgressBar(progress),
              ]),
            ),
          ),
        ),
      ),
    ]),
  );
  overlay.insert(entry);
  // laisse le voile s'afficher avant de lancer un calcul qui occupe le processeur
  await SchedulerBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 40));
  try {
    return await task();
  } finally {
    entry.remove();
  }
}
