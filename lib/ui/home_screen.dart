// Accueil : le logo se dessine au pochoir, se remplit, puis se réduit en haut ; dessous, les univers
// (Cuisine, Dressing, Meuble WC, Meuble TV, Art) et le mode Débitage (débit manuel, fichiers .sct / kitchinox).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'art_page.dart';
import 'furniture_page.dart';
import 'logo.dart';
import 'manual_cut_page.dart';
import 'theme.dart';
import 'i18n.dart';

class HomeScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onKitchen;
  final void Function(String universe)? onUniverse; // dressing, bain, tv, interieur : même planificateur
  const HomeScreen({super.key, required this.state, required this.onKitchen, this.onUniverse});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  // sur le web, la page de chargement a déjà dessiné le logo au pochoir : on part du logo plein
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))
    ..forward(from: kIsWeb ? 0.5 : 0);
  LogoShape? _logo;

  @override
  void initState() {
    super.initState();
    LogoShape.load().then((l) {
      if (mounted) setState(() => _logo = l);
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  double _seg(double t, double a, double b) => Curves.easeInOut.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final tiles = <(IconData, String, String, VoidCallback?)>[
      (Icons.kitchen_outlined, 'Cuisine', 'Plan, 3D, débit et devis', widget.onKitchen),
      (Icons.checkroom_outlined, 'Dressing', 'Penderies, lingères, angles, portes battantes ou coulissantes', () => widget.onUniverse != null ? widget.onUniverse!('dressing') : openFurniture(context, widget.state, 'dressing')),
      (Icons.wc_outlined, 'Salle de bain et WC', 'Meubles vasque, colonnes, armoires miroir, dessus WC', () => widget.onUniverse != null ? widget.onUniverse!('bain') : openFurniture(context, widget.state, 'bain')),
      (Icons.tv_outlined, 'Meuble TV', 'Bancs TV, colonnes, ponts, panneaux muraux, cheminée', () => widget.onUniverse != null ? widget.onUniverse!('tv') : openFurniture(context, widget.state, 'tv')),
      (Icons.weekend_outlined, 'Intérieur', 'Entrée, bibliothèque, bureau, chambre, claustras', () => widget.onUniverse != null ? widget.onUniverse!('interieur') : openFurniture(context, widget.state, 'interieur')),
      (Icons.palette_outlined, 'Art', 'Création libre : dessinez vos meubles, 3D et débit', () => openArt(context, widget.state)),
      (Icons.content_cut, 'Débitage', 'Débit manuel, fichiers SketchCut (.sct) ou kitchinox', () => openManualCut(context, widget.state, offerOpen: true)),
    ];
    return Scaffold(
      backgroundColor: scheme.surface,
      body: LayoutBuilder(builder: (context, box) {
        return AnimatedBuilder(
          animation: _a,
          builder: (context, _) {
            final v = _a.value;
            final draw = _seg(v, 0.0, 0.45), fill = _seg(v, 0.38, 0.6), shrink = _seg(v, 0.6, 0.82), show = _seg(v, 0.72, 1.0);
            final big = (box.biggest.shortestSide * 0.55).clamp(160.0, 440.0);
            final small = (box.maxHeight * 0.2).clamp(110.0, 180.0);
            final size = big + (small - big) * shrink;
            final top = (box.maxHeight - big) / 2 + ((box.maxHeight * 0.06) - (box.maxHeight - big) / 2) * shrink;
            return Stack(children: [
              Positioned(
                left: (box.maxWidth - size) / 2,
                top: top,
                width: size,
                height: size * 228.1 / 276.7,
                child: _logo == null ? const SizedBox() : CustomPaint(painter: LogoPainter(_logo!, draw: draw, fill: fill)),
              ),
              if (show > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  top: box.maxHeight * 0.06 + small * 228.1 / 276.7 + Tokens.s5 + (1 - show) * 30,
                  bottom: 0,
                  child: Opacity(
                    opacity: show,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: Tokens.s5, vertical: Tokens.s3),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 980),
                          child: Wrap(alignment: WrapAlignment.center, spacing: Tokens.s4, runSpacing: Tokens.s4, children: [
                            for (final (icon, title, sub, on) in tiles) _Tile(icon: icon, title: title, subtitle: sub, onTap: on),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              if (show > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: Tokens.s3,
                  child: Opacity(
                    opacity: show,
                    child: Text(tr('kitchinox · conception et fabrication de meubles'), textAlign: TextAlign.center, style: t.bodySmall),
                  ),
                ),
            ]);
          },
        );
      }),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  const _Tile({required this.icon, required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final soon = onTap == null;
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 2 * Tokens.s5).clamp(200.0, 300.0),
      height: 132,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        elevation: soon ? 0 : 1,
        color: soon ? scheme.surfaceContainerHighest.withValues(alpha: 0.5) : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radius * 1.4),
          side: BorderSide(color: soon ? scheme.outlineVariant : logoOrange.withValues(alpha: 0.6)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Tokens.s4),
            child: Row(children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: (soon ? scheme.outline : logoOrange).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 32, color: soon ? scheme.outline : logoOrange),
              ),
              const SizedBox(width: Tokens.s4),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: soon ? scheme.outline : null))),
                    if (soon) ...[
                      const SizedBox(width: Tokens.s2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(10)),
                        child: Text(tr('Bientôt'), style: t.labelSmall),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Text(subtitle, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}


/// L'app reste en paysage. Écran tenu droit (navigateur, qui ne peut pas verrouiller l'orientation) :
/// tout l'affichage tourne d'un quart de tour, sans message ; le toucher suit la rotation.
class LandscapeLock extends StatelessWidget {
  final Widget child;
  const LandscapeLock({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final s = mq.size;
    if (s.height <= s.width) return child;
    return RotatedBox(
      quarterTurns: 1,
      child: MediaQuery(
        data: mq.copyWith(
          size: Size(s.height, s.width),
          padding: EdgeInsets.fromLTRB(mq.padding.top, mq.padding.right, mq.padding.bottom, mq.padding.left),
          viewPadding: EdgeInsets.fromLTRB(mq.viewPadding.top, mq.viewPadding.right, mq.viewPadding.bottom, mq.viewPadding.left),
        ),
        child: child,
      ),
    );
  }
}
