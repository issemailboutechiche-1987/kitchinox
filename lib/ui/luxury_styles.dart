// « Luxury Kitchen » : ambiances complètes en un toucher. Chacune règle façades (hauts, bas, îlot), modèle,
// plan de travail et crédence, îlot en cascade, poignées, robinetterie, électroménager, sol, murs, lumière
// (luminaires du plafond, îlot, LED) et décor. Compositions tirées de l'analyse de cuisines haut de gamme
// (matières, couleurs, éclairages) : rien n'est copié, seulement les principes.
import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'app_settings.dart';
import 'app_state.dart';
import 'finishes.dart';
import 'i18n.dart';
import 'theme.dart';

class LuxuryStyle {
  final String id, name, mood;
  final String front; // façades (toutes)
  final String? upper, lower, island; // façades des hauts, des bas, de l'îlot (null : [front])
  final String profile; // modèle de façade
  final String? upperProfile; // modèle propre aux hauts
  final String worktop;
  final String? islandTop;
  final bool waterfall;
  final String? splash; // null : comme les murs ; 'plan' : comme le plan ; sinon une finition de crédence
  final String handle; // rendu : gola, bar, knob, edge…
  final String handleFinish;
  final String tap; // finition robinetterie
  final String lever;
  final String sink; // finition évier
  final String oven, ovenHandle, sockets;
  final String floor, wall;
  final String lightGeneral, lightIsland; // luminaires (catalogue de l'éclairage)
  final bool cove, plinthLight;
  final int cct;
  final String hdri;
  final Set<String> decor;
  const LuxuryStyle(this.id, this.name, this.mood,
      {required this.front,
      this.upper,
      this.lower,
      this.island,
      this.profile = 'lisse',
      this.upperProfile,
      required this.worktop,
      this.islandTop,
      this.waterfall = true,
      this.splash = 'plan',
      this.handle = 'gola',
      this.handleFinish = 'Noir mat',
      this.tap = 'noir_mat',
      this.lever = 'side_pin',
      this.sink = 'noir_quartz',
      this.oven = 'full_black',
      this.ovenHandle = 'integrated',
      this.sockets = 'noir_mat',
      required this.floor,
      required this.wall,
      this.lightGeneral = 'spot_led_cob_darklight',
      this.lightIsland = 'suspension_ilot_focale',
      this.cove = false,
      this.plinthLight = true,
      this.cct = 3000,
      this.hdri = 'studio_loft',
      this.decor = const {'plante', 'fruits', 'vase', 'bouteilles', 'vaisselle'}});
}

const luxuryStyles = <LuxuryStyle>[
  LuxuryStyle('nuit_laiton', 'Nuit & laiton', 'Façades noires sans poignée, marbre noir veiné, touches de laiton',
      front: 'noir_mat', upper: 'anthracite', worktop: 'marbre_noir', handleFinish: 'Doré / Laiton brossé', tap: 'or_brosse', oven: 'black_gold',
      sockets: 'or_brosse', sink: 'noir_quartz', floor: 'parquet_fume', wall: 'gris_perle', cct: 2700),
  LuxuryStyle('blanc_calacatta', 'Blanc Calacatta', 'Blanc mat lisse, marbre Calacatta du plan à la crédence, liseré doré',
      front: 'blanc_mat', worktop: 'marbre_calacatta', handleFinish: 'Or brossé', tap: 'or_brosse', sink: 'blanc_ceramique', oven: 'black_inox',
      sockets: 'or_brosse', floor: 'carrelage_gris', wall: 'blanc_pur', cove: true),
  LuxuryStyle('noyer_marbre', 'Noyer & marbre', 'Noyer chaleureux, îlot monolithe en marbre blanc, lumière d’ambiance',
      front: 'noyer', worktop: 'marbre', tap: 'noir_mat', floor: 'carrelage_marbre', wall: 'blanc_casse', lightIsland: 'suspension_lineaire_ilot'),
  LuxuryStyle('foret_cannele', 'Forêt & noyer cannelé', 'Vert forêt mat, hauts en noyer cannelé, plan effet béton',
      front: 'vert_foret', upper: 'noyer', upperProfile: 'cannelee', worktop: 'beton', waterfall: false, handle: 'edge',
      floor: 'parquet_chene', wall: 'blanc_casse', lightGeneral: 'rail_magnetique_48v'),
  LuxuryStyle('lavande', 'Lavande classique', 'Façades à cadre lavande, marbre blanc, laiton et globes de verre',
      front: 'lavande', profile: 'shaker', worktop: 'marbre', waterfall: false, handle: 'bar', handleFinish: 'Doré / Laiton brossé', tap: 'or_brosse', lever: 'top_lever',
      sink: 'blanc_ceramique', oven: 'blanc', ovenHandle: 'bar', sockets: 'blanc', floor: 'parquet_clair', wall: 'blanc_pur', plinthLight: false),
  LuxuryStyle('fume_pierre', 'Chêne fumé & pierre', 'Chêne fumé, granit cuir sombre, îlot massif, spots architecturaux',
      front: 'chene_fume', worktop: 'granit_cuir', floor: 'parquet_fume', wall: 'greige_moderne', cct: 2700, hdri: 'studio_hall'),
  LuxuryStyle('bois_onyx', 'Bois & onyx', 'Noyer profond, onyx miel en plan et en crédence, reflets dorés',
      front: 'noyer', worktop: 'onyx_miel', tap: 'or_brosse', oven: 'black_gold', handleFinish: 'Or brossé', sockets: 'or_brosse',
      floor: 'beton_cire', wall: 'beige_sable', cove: true, cct: 2700),
  LuxuryStyle('travertin', 'Travertin minéral', 'Chêne clair, pierre crème monolithe, lumière indirecte au plafond',
      front: 'chene_clair', worktop: 'marbre_creme', tap: 'inox_brosse', sink: 'blanc_ceramique', floor: 'carrelage_travertin', wall: 'blanc_casse', cove: true,
      lightIsland: 'suspension_lineaire_ilot', hdri: 'ciel_verger'),
  LuxuryStyle('gris_cristal', 'Gris classique', 'Façades moulurées gris galet, marbre blanc, crédence marbre, chrome',
      front: 'gris_galet', profile: 'mouluree', worktop: 'marbre', waterfall: false, splash: 'marbre_cred', handle: 'bar', handleFinish: 'Chrome poli', tap: 'chrome',
      lever: 'retro_cross', sink: 'inox', oven: 'inox_brosse', ovenHandle: 'retro', sockets: 'blanc', floor: 'parquet_chene', wall: 'blanc_pur', plinthLight: false),
  LuxuryStyle('rouge_cendre', 'Rouge & bois cendré', 'Hauts rouge carmin, bas en bois cendré, plan granit noir',
      front: 'chene_fume', upper: 'rouge_carmin', worktop: 'granit_noir', waterfall: false, splash: null, handle: 'bar', handleFinish: 'Inox brossé',
      tap: 'chrome', sink: 'inox', oven: 'inox_brosse', ovenHandle: 'bar', sockets: 'blanc', floor: 'carrelage_gris', wall: 'blanc_casse', plinthLight: false),
  LuxuryStyle('creme_patine', 'Crème & patine', 'Moulures crème, îlot vert patiné, marbre crème, laiton vieilli',
      front: 'cachemire', island: 'vert_jade', profile: 'mouluree', worktop: 'marbre_creme', waterfall: false, splash: 'zellige_blanc', handle: 'knob',
      handleFinish: 'Bronze vieilli', tap: 'or_brosse', lever: 'retro_cross', sink: 'blanc_ceramique', oven: 'blanc', ovenHandle: 'retro', sockets: 'or_brosse',
      floor: 'carrelage_travertin', wall: 'blanc_casse', plinthLight: false, lightIsland: 'suspension_ilot_focale', cct: 2700),
  LuxuryStyle('greige_vitrines', 'Greige & vitrines', 'Greige mat, vitrines éclairées, quartz sable, LED sous les hauts',
      front: 'sable', upper: 'champignon', worktop: 'quartz_beige', handle: 'edge', tap: 'inox_brosse', sink: 'inox', oven: 'black_inox',
      floor: 'carrelage_blanc', wall: 'blanc_casse', lightGeneral: 'spot_led_gu10_std'),
];

/// Applique une ambiance à tout le projet (une seule étape d'annulation).
void applyLuxury(AppState state, LuxuryStyle l) {
  final p = state.project;
  state.edit(() {
    final st = p.style;
    st
      ..front = l.lower ?? l.front
      ..frontUpper = l.upper
      ..frontLower = l.upper != null ? (l.lower ?? l.front) : null
      ..frontProfile = l.profile
      ..islandFront = l.island
      ..worktop = l.worktop
      ..islandTop = l.islandTop
      ..islandWaterfall = l.waterfall
      ..splash = l.splash
      ..handle = l.handle
      ..handleId = null
      ..handleFinish = l.handleFinish
      ..plinth = null
      ..lighting = l.plinthLight ? 'led_hauts_plinthes' : 'led_hauts'
      ..floor = l.floor
      ..wall = l.wall
      ..faucetFinish = l.tap
      ..faucetLever = l.lever
      ..sinkMount = 'undermount'
      ..sinkFinish = l.sink
      ..hobType = 'induction'
      ..ovenFinish = l.oven
      ..ovenHandle = l.ovenHandle
      ..socketFinish = l.sockets
      ..showDecor = true;
    st.profileByZone
      ..clear()
      ..addAll({if (l.upperProfile != null) 'haut': l.upperProfile!});
    st.decor
      ..clear()
      ..addAll(l.decor);
    syncWorktop(p);
    // lumière : luminaires du plafond, îlot, ambiances
    final lc = p.specs.lighting;
    lc
      ..general = l.lightGeneral
      ..power = 'typical'
      ..cct = l.cct
      ..island = l.lightIsland
      ..worktop = 'ruban_led_cob_plan_travail'
      ..cove = l.cove
      ..plinth = l.plinthLight
      ..cabinet = true;
  });
  AppSettings.instance
    ..hdri = l.hdri
    ..save();
  state.refresh();
}

/// Galerie « Luxury Kitchen » : une vignette dessinée par ambiance ; un toucher l'applique à tout le projet.
Future<void> showLuxuryGallery(BuildContext context, AppState state, void Function(String) onMessage) => showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final t = Theme.of(ctx).textTheme;
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          key: const ValueKey('luxury_dialog'),
          titlePadding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          title: Row(children: [
            Icon(Icons.diamond_outlined, color: scheme.primary),
            const SizedBox(width: 10),
            Text(tr('Luxury Kitchen')),
          ]),
          content: SizedBox(
            width: 900,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(tr('Une ambiance complète en un toucher : façades, plan et crédence, îlot, poignées, robinetterie, sol, murs et lumière. Tout reste modifiable ensuite.'),
                    style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: Tokens.s3),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final l in luxuryStyles)
                    InkWell(
                      key: ValueKey('luxury_${l.id}'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        applyLuxury(state, l);
                        setD(() {});
                        onMessage(trp('Ambiance « {0} » appliquée (Annuler pour revenir)', [tr(l.name)]));
                      },
                      child: Container(
                        width: 206,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: scheme.outlineVariant),
                          color: scheme.surface,
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(width: 194, height: 120, child: CustomPaint(painter: LuxuryPreview(l))),
                          ),
                          const SizedBox(height: 6),
                          Text(tr(l.name), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          Text(tr(l.mood), maxLines: 3, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ]),
                      ),
                    ),
                ]),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Fermer')))],
        );
      }),
    );

/// Vignette d'une ambiance : élévation simplifiée (hauts, crédence, plan, bas, îlot, suspensions, LED).
class LuxuryPreview extends CustomPainter {
  final LuxuryStyle l;
  LuxuryPreview(this.l);

  Color _f(List<Finish> list, String? id, Color fallback) => id == null ? fallback : (list.where((f) => f.id == id).firstOrNull?.color ?? fallback);

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final wall = _f(walls, l.wall, const Color(0xFFF1EFEA));
    final floor = _f(floors, l.floor, const Color(0xFFE2C9A4));
    final front = _f(fronts, l.lower ?? l.front, Colors.white);
    final upper = _f(fronts, l.upper ?? l.front, front);
    final island = _f(fronts, l.island ?? l.lower ?? l.front, front);
    final top = _f(worktops, l.worktop, Colors.white);
    final splash = l.splash == 'plan' ? top : (l.splash == null ? wall : _f(splashes, l.splash, wall));
    final light = l.cct <= 2700 ? const Color(0xFFFFD2A1) : const Color(0xFFFFE4C4);
    c.drawRect(Rect.fromLTWH(0, 0, w, h * 0.78), Paint()..color = wall);
    c.drawRect(Rect.fromLTWH(0, h * 0.78, w, h * 0.22), Paint()..color = floor);
    if (l.cove) c.drawRect(Rect.fromLTWH(0, 0, w, h * 0.06), Paint()..color = light.withValues(alpha: 0.8));
    // hauts, crédence, plan, bas (mur du fond)
    final x0 = w * 0.06, x1 = w * 0.94;
    c.drawRect(Rect.fromLTRB(x0, h * 0.1, x1, h * 0.34), Paint()..color = upper);
    c.drawRect(Rect.fromLTRB(x0, h * 0.34, x1, h * 0.5), Paint()..color = splash);
    c.drawRect(Rect.fromLTRB(x0, h * 0.34, x1, h * 0.37), Paint()..color = light.withValues(alpha: 0.9)); // LED sous les hauts
    c.drawRect(Rect.fromLTRB(x0, h * 0.5, x1, h * 0.53), Paint()..color = top);
    c.drawRect(Rect.fromLTRB(x0, h * 0.53, x1, h * 0.74), Paint()..color = front);
    final line = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 6; i++) {
      final x = x0 + (x1 - x0) * i / 6;
      c.drawLine(Offset(x, h * 0.1), Offset(x, h * 0.34), line);
      c.drawLine(Offset(x, h * 0.53), Offset(x, h * 0.74), line);
    }
    if (l.upperProfile == 'cannelee') {
      for (var x = x0; x < x1; x += 3) {
        c.drawLine(Offset(x, h * 0.1), Offset(x, h * 0.34), Paint()
          ..color = Colors.black.withValues(alpha: 0.12)
          ..strokeWidth = 0.6);
      }
    }
    // îlot au premier plan (cascade : plan jusqu'au sol)
    final iL = w * 0.22, iR = w * 0.78;
    c.drawRect(Rect.fromLTRB(iL, h * 0.66, iR, h * 0.92), Paint()..color = l.waterfall ? top : island);
    if (!l.waterfall) c.drawRect(Rect.fromLTRB(iL, h * 0.64, iR, h * 0.67), Paint()..color = top);
    if (l.waterfall) c.drawRect(Rect.fromLTRB(iL + 6, h * 0.69, iR - 6, h * 0.92), Paint()..color = island.withValues(alpha: 0.0));
    if (l.plinthLight) c.drawRect(Rect.fromLTRB(iL, h * 0.92, iR, h * 0.94), Paint()..color = light);
    // suspensions au-dessus de l'îlot
    final pend = Paint()..color = l.tap == 'or_brosse' ? const Color(0xFFC9A247) : const Color(0xFF1D1F22);
    if (l.lightIsland == 'suspension_lineaire_ilot') {
      c.drawLine(Offset(w * 0.32, 0), Offset(w * 0.32, h * 0.44), Paint()..color = Colors.black38);
      c.drawLine(Offset(w * 0.68, 0), Offset(w * 0.68, h * 0.44), Paint()..color = Colors.black38);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.3, h * 0.44, w * 0.7, h * 0.47), const Radius.circular(2)), pend);
      c.drawRect(Rect.fromLTRB(w * 0.31, h * 0.47, w * 0.69, h * 0.49), Paint()..color = light);
    } else {
      for (final x in [w * 0.36, w * 0.5, w * 0.64]) {
        c.drawLine(Offset(x, 0), Offset(x, h * 0.4), Paint()..color = Colors.black38);
        c.drawPath(
            Path()
              ..moveTo(x - 3, h * 0.4)
              ..lineTo(x + 3, h * 0.4)
              ..lineTo(x + 9, h * 0.48)
              ..lineTo(x - 9, h * 0.48)
              ..close(),
            pend);
        c.drawCircle(Offset(x, h * 0.5), 3, Paint()..color = light);
      }
    }
  }

  @override
  bool shouldRepaint(covariant LuxuryPreview o) => o.l.id != l.id;
}

