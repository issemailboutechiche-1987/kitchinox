// Menu « Plafond » : choisir sa lumière avec des miniatures et des mots simples ; le calcul selon les normes
// se met à jour en direct (aperçu du plafond, pièce bien éclairée ou non). Les détails techniques (lumens,
// watts, IRC, UGR, IP, lux) sont dans les info-bulles et dans les Contrôles.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'i18n.dart';
import 'lighting_thumbs.dart';
import 'theme.dart';

String _n(num v, [int d = 0]) => v.toStringAsFixed(d).replaceAll('.', ',');
String _w(double w) => _n(w, w % 1 == 0 ? 0 : 1);
String _t(LightText x) => x.fill(tr);

/// Nom simple d'une température de couleur.
String _cctName(int k) => k <= 2200
    ? 'Ambrée'
    : k <= 2700
        ? 'Chaude'
        : k <= 3000
            ? 'Blanc chaud'
            : k <= 4000
                ? 'Neutre'
                : 'Froide';

/// Nom simple d'un faisceau, selon sa place parmi ceux du luminaire.
String _beamName(List<int> beams, int b) {
  final i = beams.indexOf(b);
  if (beams.length == 1) return 'Large';
  if (i == 0) return 'Concentré';
  if (i == beams.length - 1) return 'Large';
  return 'Moyen';
}

String _tech(LightSource s, String power) =>
    '${s.name}\n${s.lm(power)} lm${s.perM ? '/m' : ''} · ${_w(s.w(power))} W${s.perM ? '/m' : ''} · IRC ${s.cri}${s.ugr == null ? '' : ' · UGR ${s.ugr}'}'
    '${s.beams.isEmpty ? '' : ' · ${s.beams.join('/')}°'} · ${s.ips.join(', ')}';

Future<void> showLightingDialog(BuildContext context, AppState state, void Function(String) onMessage) => showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final plan = planLighting(state.engine);
        final ch = plan.choice;
        final src = ch.generalSource;
        final t = Theme.of(ctx).textTheme;
        final scheme = Theme.of(ctx).colorScheme;
        final kitchen = plan.universe == 'cuisine';
        final cct = src.ccts.contains(ch.cct) ? ch.cct : src.ccts.first;
        final allOk = plan.zones.every((z) => z.lumensNeeded == 0 || z.ok);
        void set(void Function(LightingChoice c) f) {
          state.setLighting(f);
          setD(() {});
        }

        Widget title(String x) => Padding(padding: const EdgeInsets.only(top: Tokens.s3, bottom: 6), child: Text(tr(x), style: t.titleSmall));

        // carte à miniature : choix unique ou interrupteur
        Widget card(String kind, String label, bool on, VoidCallback tap, {String? tip, Key? key, int? light}) => Tooltip(
              message: tip ?? '',
              waitDuration: const Duration(milliseconds: 400),
              child: InkWell(
                key: key,
                borderRadius: BorderRadius.circular(12),
                onTap: tap,
                child: AnimatedContainer(
                  duration: Tokens.fast,
                  width: 120,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: on ? scheme.primary.withValues(alpha: 0.10) : scheme.surface,
                    border: Border.all(color: on ? scheme.primary : scheme.outlineVariant, width: on ? 2 : 1),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    LightThumb(kind: kind, cct: light ?? cct),
                    const SizedBox(height: 4),
                    Text(tr(label),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: t.labelMedium?.copyWith(fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? scheme.primary : scheme.onSurface)),
                  ]),
                ),
              ),
            );
        Widget pill(String label, bool on, VoidCallback tap, {String? tip, Widget? lead}) => Tooltip(
              message: tip ?? '',
              child: ChoiceChip(
                label: Text(tr(label)),
                avatar: lead,
                selected: on,
                showCheckmark: false,
                onSelected: (_) => tap(),
              ),
            );

        final options = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('lighting_auto'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.auto_awesome, size: 20),
                label: Text(tr('Calcul automatique')),
                onPressed: () {
                  final n = state.autoLightingForRoom();
                  setD(() {});
                  onMessage(n < 0 ? tr('Posez d’abord les meubles : la place des lumières dépend de la cuisine.') : trp('{0} points lumineux posés au plafond', [n]));
                },
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: tr('Le calcul choisit les luminaires d’après les normes (lumière nécessaire, confort, rendu des couleurs), pas d’après le style.'),
              child: Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
            ),
          ]),
          title('Au plafond'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in lightSourcesFor('general'))
              card(s.shape, s.label, s.id == ch.general, () => set((c) => c.general = s.id), tip: _tech(s, ch.power), key: ValueKey('light_src_${s.id}')),
          ]),
          title('Intensité'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, l) in const [('min', 'Douce'), ('typical', 'Normale'), ('max', 'Forte')])
              pill(l, ch.power == k, () => set((c) => c.power = k), tip: '${src.lm(k)} lm · ${_w(src.w(k))} W'),
          ]),
          title('Couleur de la lumière'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in src.ccts)
              pill(_cctName(k), cct == k, () => set((c) => c.cct = k), tip: '$k K', lead: CircleAvatar(radius: 8, backgroundColor: Color(0xFF000000 | cctColor(k)))),
          ]),
          if (src.beams.length > 1) ...[
            title('Faisceau'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final b in src.beams)
                pill(_beamName(src.beams, b), (ch.beam ?? src.beams[src.beams.length ~/ 2]) == b, () => set((c) => c.beam = b), tip: '$b°'),
            ]),
          ],
          if (kitchen && state.project.room.island != null) ...[
            title('Au-dessus de l’îlot'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in lightSourcesFor('island')) card(s.shape, s.label, ch.island == s.id, () => set((c) => c.island = s.id), tip: _tech(s, ch.power)),
              card('none', 'Aucune', ch.island == 'none', () => set((c) => c.island = 'none')),
            ]),
          ],
          if (kitchen) ...[
            title('Sous les meubles hauts'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in lightSourcesFor('worktop')) card(s.shape, s.label, ch.worktop == s.id, () => set((c) => c.worktop = s.id), tip: _tech(s, ch.power)),
              card('none', 'Aucun', ch.worktop == 'none', () => set((c) => c.worktop = 'none')),
            ]),
          ],
          title('Ambiances'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            card('cove', 'Lumière indirecte', ch.cove, () => set((c) => c.cove = !c.cove), tip: _tech(lightSourceById('ruban_led_corniche_indirect')!, ch.power)),
            if (kitchen)
              card('plinth', 'Plinthe lumineuse', ch.plinth, () => set((c) => c.plinth = !c.plinth), tip: _tech(lightSourceById('ruban_led_plinthe_sous_lit')!, ch.power)),
            if (kitchen)
              card('puck', 'Vitrines éclairées', ch.cabinet, () => set((c) => c.cabinet = !c.cabinet), tip: _tech(lightSourceById('mini_spot_meuble_vitrine')!, ch.power)),
            if (plan.universe == 'dressing')
              card('dressing', 'Penderies lumineuses', ch.dressing, () => set((c) => c.dressing = !c.dressing), tip: _tech(lightSourceById('barre_penderie_dressing_led')!, ch.power)),
          ]),
          title('Couleur des murs'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, l) in const [('clair', 'Clairs'), ('moyen', 'Moyens'), ('fonce', 'Foncés')])
              pill(l, plan.tone == k, () {
                state.setRoomTone(k);
                setD(() {});
              }, tip: tr(roomTones[k]!.$1)),
          ]),
        ]);

        // ---- résultat : aperçu du plafond, verdict, zones, conseils
        final result = Container(
          padding: const EdgeInsets.all(Tokens.s3),
          decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(14), border: Border.all(color: scheme.outlineVariant)),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: (state.project.room.width / state.project.room.depth).clamp(0.6, 2.2),
              child: CustomPaint(painter: _CeilingPreview(state.project.room, plan)),
            ),
            const SizedBox(height: Tokens.s3),
            Row(children: [
              Icon(allOk ? Icons.check_circle : Icons.warning_amber_rounded, color: allOk ? Colors.green.shade600 : scheme.error),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(tr(allOk ? 'La pièce est bien éclairée' : 'Il manque de la lumière'),
                      style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: allOk ? null : scheme.error))),
            ]),
            const SizedBox(height: Tokens.s2),
            for (final z in plan.zones) _ZoneLine(z),
            if (plan.notes.isNotEmpty) ...[
              const SizedBox(height: Tokens.s2),
              Text(tr('Conseils'), style: t.labelLarge),
              for (final note in plan.notes)
                Tooltip(
                  message: note.detail == null ? '' : _t(note.detail!),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.lightbulb_outline, size: 16, color: scheme.tertiary),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_t(note), style: t.bodySmall)),
                    ]),
                  ),
                ),
            ],
            const Divider(height: Tokens.s4),
            Tooltip(
              message: [
                trp('Total : {0} lm · {1} W', [plan.totalLumens, plan.totalWatts.round()]),
                trp('{0} m² · plafond {1} mm · UF {2} · MF {3} · hauteur ×{4}', [_n(plan.area, 1), plan.ceiling.round(), _n(plan.uf, 2), _n(plan.mf, 2), _n(plan.hk, 2)]),
                tr('Méthode des lumens (EN 12464-1, IES) : lux × surface ÷ (UF × MF).'),
                for (final s in plan.strips) '${tr('Rubans LED')} : ${trp('{0} m · {1} W · transformateur 24 V {2} W', [_n(s.length / 1000, 2), _n(s.watts, 1), s.driverW])}, ${tr(s.feed)}',
              ].join('\n'),
              child: Row(children: [
                Icon(Icons.bolt, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(trp('Consommation : {0} W', [plan.totalWatts.round()]), style: t.bodySmall),
                const Spacer(),
                Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
              ]),
            ),
          ]),
        );

        return AlertDialog(
          key: const ValueKey('lighting_dialog'),
          titlePadding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          title: Row(children: [
            const Icon(Icons.light_outlined),
            const SizedBox(width: 10),
            Text(tr('Lumière de la pièce')),
          ]),
          content: SizedBox(
            width: 940,
            child: LayoutBuilder(builder: (ctx, c) {
              final wide = c.maxWidth >= 720;
              return SingleChildScrollView(
                child: wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: options),
                        const SizedBox(width: Tokens.s4),
                        SizedBox(width: 320, child: result),
                      ])
                    : Column(children: [result, const SizedBox(height: Tokens.s3), options]),
              );
            }),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Fermer'))),
            FilledButton.icon(
              key: const ValueKey('lighting_place'),
              icon: const Icon(Icons.check, size: 18),
              label: Text(tr('Poser au plafond')),
              onPressed: () {
                final n = state.placeLighting();
                onMessage(n < 0 ? tr('Posez d’abord les meubles : la place des lumières dépend de la cuisine.') : trp('{0} points lumineux posés au plafond', [n]));
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      }),
    );

/// Une zone : nom, ce qui est prévu en mots simples, jauge ; le détail technique en info-bulle.
class _ZoneLine extends StatelessWidget {
  final ZoneResult z;
  const _ZoneLine(this.z);
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ok = z.lumensNeeded == 0 || z.ok;
    final k = z.lumensNeeded == 0 ? 1.0 : (z.lumensPlanned / z.lumensNeeded).clamp(0.0, 1.0);
    return Tooltip(
      message: [
        _t(z.setup),
        if (z.lumensNeeded > 0) '${trp('{0} / {1} lm', [z.lumensPlanned, z.lumensNeeded])} · ${trp('{0} lux visés ({1}–{2})', [z.zone.lux, z.zone.luxMin, z.zone.luxMax])}',
        '${z.zone.cct} · ${z.zone.cri} · ${tr(z.zone.ip)}',
        if (z.zone.placement.isNotEmpty) tr(z.zone.placement),
      ].join('\n'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: Tokens.s2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(tr(z.zone.name), style: t.labelLarge)),
            Icon(ok ? Icons.check : Icons.priority_high, size: 16, color: ok ? Colors.green.shade600 : scheme.error),
          ]),
          if (z.lumensNeeded > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: k, minHeight: 5, color: ok ? Colors.green.shade600 : scheme.error, backgroundColor: scheme.surfaceContainerHighest),
              ),
            ),
          Text(_t(z.summary), style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// Aperçu du plafond : la pièce, ses luminaires et leurs taches de lumière (se met à jour à chaque choix).
class _CeilingPreview extends CustomPainter {
  final Room room;
  final LightingPlan plan;
  _CeilingPreview(this.room, this.plan);

  @override
  void paint(Canvas c, Size s) {
    final k = [s.width / room.width, s.height / room.depth].reduce((a, b) => a < b ? a : b) * 0.94;
    final ox = (s.width - room.width * k) / 2, oy = (s.height - room.depth * k) / 2;
    Offset at(double x, double y) => Offset(ox + x * k, oy + y * k);
    final floor = Path()..addPolygon([for (final (x, y) in room.floorPolygon) at(x, y)], true);
    c.drawPath(floor, Paint()..color = const Color(0xFF2E3136));
    c.save();
    c.clipPath(floor);
    final deg = plan.choice.generalSource.beams.isEmpty ? 120 : (plan.choice.beam ?? plan.choice.generalSource.beams[plan.choice.generalSource.beams.length ~/ 2]);
    final reach = ((room.height - 900).clamp(300, 3000)) * _tanHalf(deg).clamp(0.3, 1.6);
    for (final sp in plan.spots) {
      final col = Color(0xFF000000 | cctColor(sp.cct));
      final o = at(sp.x, sp.y);
      final r = reach * k * (sp.kind == 'panel' || sp.kind == 'ceiling' ? 1.4 : 1);
      c.drawCircle(o, r, Paint()..shader = RadialGradient(colors: [col.withValues(alpha: 0.8), col.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: o, radius: r)));
    }
    c.restore();
    c.drawPath(
        floor,
        Paint()
          ..color = const Color(0xFF8A8F96)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    for (final sp in plan.spots) {
      final o = at(sp.x, sp.y);
      final col = Color(0xFF000000 | cctColor(sp.cct));
      if (sp.kind == 'track' || sp.kind == 'magnetic') {
        final axis = sp.alongY ? const Offset(0, 1) : const Offset(1, 0);
        c.drawLine(o - axis * (sp.length / 2 * k), o + axis * (sp.length / 2 * k), Paint()
          ..color = const Color(0xFF111214)
          ..strokeWidth = 4);
        for (var i = 0; i < sp.heads; i++) {
          final t = sp.heads == 1 ? 0.0 : -sp.length / 2 + 150 + (sp.length - 300) * i / (sp.heads - 1);
          c.drawCircle(o + axis * (t * k), 4, Paint()..color = col);
        }
      } else if (sp.kind == 'linear') {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: sp.length * k, height: 5), const Radius.circular(2)), Paint()..color = col);
      } else if (sp.kind == 'panel') {
        c.drawRect(Rect.fromCenter(center: o, width: 600 * k, height: 600 * k), Paint()..color = col);
      } else {
        c.drawCircle(o, sp.kind == 'ceiling' ? 200 * k : 4.5, Paint()..color = col);
        c.drawCircle(o, sp.kind == 'ceiling' ? 200 * k : 4.5, Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
      }
    }
  }

  static double _tanHalf(int deg) => math.tan(math.min(deg, 150) / 2 * math.pi / 180);

  @override
  bool shouldRepaint(covariant _CeilingPreview o) => true;
}
