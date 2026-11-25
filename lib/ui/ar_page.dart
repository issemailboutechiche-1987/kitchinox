// Écran du mode AR « Voir dans ma pièce » : projection 1:1 dans la pièce réelle via AR Quick Look (iOS).
// Parcours en 3 temps :
// 1. Quoi projeter (4 cartes illustrées à cocher)
// 2. Préparer (barre d'avancement et résumé technique)
// 3. Ouvrir dans ma pièce (aide illustrée par CustomPainter et bouton d'action)

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ar_mode.dart';
import 'i18n.dart';
import 'theme.dart';

/// Ouvre le dialogue du mode AR.
Future<void> showArPageDialog(BuildContext context, AppState st) {
  return showDialog<void>(
    context: context,
    builder: (_) => ArPage(st: st),
  );
}

class ArPage extends StatefulWidget {
  final AppState st;
  const ArPage({super.key, required this.st});

  @override
  State<ArPage> createState() => _ArPageState();
}

class _ArPageState extends State<ArPage> {
  ArOptions _options = const ArOptions();
  ArStats? _stats;
  bool _busy = false;
  String? _error;
  bool _scan = false; // scan de la pièce possible (app iPad avec LiDAR)

  @override
  void initState() {
    super.initState();
    arScanAvailable().then((v) {
      if (mounted) setState(() => _scan = v);
    });
  }

  void _setOptions(ArOptions next) {
    setState(() {
      _options = next;
      _stats = null;
      _error = null;
    });
  }

  Future<void> _prepare() async {
    setState(() {
      _busy = true;
      _error = null;
      _stats = null;
    });

    final s = await prepareAr(widget.st, _options);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _stats = s;
      if (s == null) {
        _error = tr('Ouvrez la vue 3D pour préparer la réalité augmentée.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final networksAvailable = widget.st.project.networks && widget.st.project.points.isNotEmpty;
    final s = _stats;

    return Dialog(
      key: const ValueKey('ar_sheet'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radius * 1.5)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // En-tête : Titre, bouton d'aide '?' et fermeture
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(Tokens.s2),
                    decoration: BoxDecoration(
                      color: Brand.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(Tokens.radius),
                    ),
                    child: const Icon(Icons.view_in_ar, color: Brand.orange, size: 26),
                  ),
                  const SizedBox(width: Tokens.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Voir dans ma pièce (AR)'),
                          style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tr('Projetez votre cuisine à l’échelle 1:1 dans votre pièce réelle'),
                          style: t.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Guide AR Quick Look'),
                    icon: const Icon(Icons.help_outline),
                    onPressed: () => showArHelpDialog(context),
                  ),
                  IconButton(
                    tooltip: tr('Fermer'),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.s3),
              const Divider(height: 1),
              const SizedBox(height: Tokens.s4),

              // Contenu principal déroulant
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Étape 1 : Quoi projeter
                      Text(
                        tr('1. Quoi projeter dans votre pièce'),
                        style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: Tokens.s3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _ArOptionCard(
                              key: const ValueKey('ar_opt_kitchen'),
                              title: tr('Cuisine'),
                              subtitle: tr('Meubles, plans, crédence, électroménager et objets'),
                              icon: Icons.kitchen_outlined,
                              value: _options.kitchen,
                              onChanged: (v) => _setOptions(_options.copyWith(kitchen: v)),
                            ),
                          ),
                          const SizedBox(width: Tokens.s3),
                          Expanded(
                            child: _ArOptionCard(
                              key: const ValueKey('ar_opt_walls'),
                              title: tr('Murs en transparence'),
                              subtitle: tr('Murs, portes et fenêtres en fantôme translucide'),
                              icon: Icons.border_all_outlined,
                              value: _options.walls,
                              onChanged: (v) => _setOptions(_options.copyWith(walls: v)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Tokens.s3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _ArOptionCard(
                              key: const ValueKey('ar_opt_nets'),
                              title: tr('Réseaux : électricité, eau, gaz'),
                              subtitle: networksAvailable
                                  ? tr('Conduits d’électricité, eau, évacuation, gaz et tableau')
                                  : tr('Aucun point de réseau dans le projet'),
                              icon: Icons.electrical_services_outlined,
                              value: _options.nets && networksAvailable,
                              enabled: networksAvailable,
                              onChanged: networksAvailable ? (v) => _setOptions(_options.copyWith(nets: v)) : null,
                            ),
                          ),
                          const SizedBox(width: Tokens.s3),
                          Expanded(
                            child: _ArOptionCard(
                              key: const ValueKey('ar_opt_marker'),
                              title: tr('Repère du coin (L rouge)'),
                              subtitle: tr('Repère d’alignement au sol sur l’angle des murs A et C'),
                              icon: Icons.flag_outlined,
                              value: _options.marker,
                              onChanged: (v) => _setOptions(_options.copyWith(marker: v)),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: Tokens.s5),

                      // Étape 2 : Préparation et état
                      Text(
                        tr('2. Préparation du paquet 3D'),
                        style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: Tokens.s2),

                      if (_busy) ...[
                        const SizedBox(height: Tokens.s2),
                        const LinearProgressIndicator(color: Brand.orange),
                        const SizedBox(height: Tokens.s2),
                        Center(
                          child: Text(
                            tr('Préparation du modèle AR en cours...'),
                            style: t.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ] else if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(Tokens.s3),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(Tokens.radius),
                            border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: scheme.error),
                              const SizedBox(width: Tokens.s3),
                              Expanded(
                                child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      ] else if (s != null) ...[
                        // Résumé technique propre du paquet prêt
                        Container(
                          padding: const EdgeInsets.all(Tokens.s3),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(Tokens.radius),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                  const SizedBox(width: Tokens.s2),
                                  Text(
                                    tr('Paquet AR prêt'),
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                                  ),
                                  const Spacer(),
                                  Text(
                                    s.sizeText,
                                    style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                trp('{0} pièces • {1} sommets • {2} textures', [s.meshes, s.vertices, s.textures]),
                                style: t.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              if (s.dropped > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        trp('{0} modèles trop lourds omis', [s.dropped]),
                                        style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ] else ...[
                        Text(
                          tr('Cliquez sur « Préparer » pour générer le fichier 3D optimisé à partir de la vue actuelle.'),
                          style: t.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],

                      // Étape 3 : Aide illustrée et ouverture
                      if (s != null) ...[
                        const SizedBox(height: Tokens.s5),
                        Text(
                          tr('3. Placement dans votre pièce'),
                          style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: Tokens.s2),
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(Tokens.radius),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(Tokens.radius),
                            child: CustomPaint(
                              painter: _RoomCornerHelpPainter(
                                wallColor: scheme.onSurface.withValues(alpha: 0.65),
                                labelColor: scheme.onSurface,
                                markerColor: const Color(0xFFE53935),
                                guideColor: Brand.orange,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        const SizedBox(height: Tokens.s2),
                        Text(
                          tr('Posez le repère rouge L sur le coin réel correspondant à l’angle des murs A et C.'),
                          textAlign: TextAlign.center,
                          style: t.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: Tokens.s4),
              const Divider(height: 1),
              const SizedBox(height: Tokens.s3),

              // Barre d'actions en bas
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(tr('Fermer')),
                  ),
                  const SizedBox(width: Tokens.s3),
                  if (s == null)
                    FilledButton(
                      key: const ValueKey('ar_prepare'),
                      onPressed: _busy || _options.isEmpty ? null : _prepare,
                      style: FilledButton.styleFrom(
                        backgroundColor: Brand.orange,
                        padding: const EdgeInsets.symmetric(horizontal: Tokens.s4, vertical: Tokens.s2),
                      ),
                      child: Text(tr('Préparer')),
                    )
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('ar_open'),
                          icon: const Icon(Icons.view_in_ar),
                          // Important : appelé directement sans await pour conformité Safari Quick Look
                          onPressed: () => openArPackage(),
                          style: FilledButton.styleFrom(
                            backgroundColor: Brand.orange,
                            padding: const EdgeInsets.symmetric(horizontal: Tokens.s5, vertical: Tokens.s3),
                          ),
                          label: Text(
                            s.quickLook ? tr('Ouvrir dans ma pièce') : tr('Télécharger le fichier USDZ'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        // app iPad : scan complet de la pièce (LiDAR), calage sur les vrais murs, puis le show
                        if (_scan) const SizedBox(height: 8),
                        if (_scan)
                        FilledButton.icon(
                          key: const ValueKey('ar_scan_app'),
                          icon: const Icon(Icons.document_scanner_outlined),
                          onPressed: () async {
                            final ok = await sendArToApp(widget.st.project.name);
                            if (!ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Le scan de la pièce n’a pas pu s’ouvrir.'))));
                            }
                          },
                          label: Text(tr('Scanner la pièce')),
                        ),
                        if (!s.quickLook) ...[
                          const SizedBox(height: 4),
                          Text(
                            tr('Cet appareil n’ouvre pas la réalité augmentée : le fichier USDZ sera téléchargé (à ouvrir sur iPad ou iPhone).'),
                            style: t.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carte d'option à cocher pour le mode AR.
class _ArOptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  const _ArOptionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final selected = value && enabled;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled && onChanged != null ? () => onChanged!(!value) : null,
        borderRadius: BorderRadius.circular(Tokens.radius),
        child: Container(
          padding: const EdgeInsets.all(Tokens.s3),
          decoration: BoxDecoration(
            color: selected ? Brand.orange.withValues(alpha: 0.08) : scheme.surface,
            borderRadius: BorderRadius.circular(Tokens.radius),
            border: Border.all(
              color: selected
                  ? Brand.orange
                  : scheme.outlineVariant.withValues(alpha: enabled ? 1.0 : 0.4),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                activeColor: Brand.orange,
                onChanged: enabled && onChanged != null ? (v) => onChanged!(v ?? false) : null,
              ),
              const SizedBox(width: Tokens.s2),
              Icon(
                icon,
                color: enabled ? (selected ? Brand.orange : scheme.onSurface) : scheme.onSurface.withValues(alpha: 0.35),
                size: 24,
              ),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: t.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: t.textTheme.bodySmall?.copyWith(
                        color: enabled ? scheme.onSurfaceVariant : scheme.onSurface.withValues(alpha: 0.35),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dessin vectoriel pédagogique de la pièce vue de dessus, du L rouge et de la flèche d'alignement.
class _RoomCornerHelpPainter extends CustomPainter {
  final Color wallColor;
  final Color labelColor;
  final Color markerColor;
  final Color guideColor;

  const _RoomCornerHelpPainter({
    required this.wallColor,
    required this.labelColor,
    required this.markerColor,
    required this.guideColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Rectangle de la pièce schématisée (en plan)
    final rw = math.min(size.width * 0.55, 340.0);
    final rh = math.min(size.height * 0.72, 85.0);
    final roomRect = Rect.fromCenter(center: Offset(cx + 30, cy + 6), width: rw, height: rh);

    // Fond sol quadrillé très léger
    final floorPaint = Paint()..color = labelColor.withValues(alpha: 0.04);
    canvas.drawRect(roomRect, floorPaint);

    // Lignes de murs
    final wallPaint = Paint()
      ..color = wallColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Murs B et D en trait continu plus fin
    final otherWallPaint = Paint()
      ..color = wallColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawLine(roomRect.topRight, roomRect.bottomRight, otherWallPaint);
    canvas.drawLine(roomRect.bottomLeft, roomRect.bottomRight, otherWallPaint);

    // Murs A (haut) et C (gauche) mis en valeur
    canvas.drawLine(roomRect.topLeft, roomRect.topRight, wallPaint);
    canvas.drawLine(roomRect.topLeft, roomRect.bottomLeft, wallPaint);

    // Dessin du L rouge au coin supérieur gauche (Mur A / Mur C)
    final markerPaint = Paint()
      ..color = markerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.square;

    const armLen = 22.0;
    final corner = roomRect.topLeft;
    // Branche le long du mur A
    canvas.drawLine(corner, corner + const Offset(armLen, 0), markerPaint);
    // Branche le long du mur C
    canvas.drawLine(corner, corner + const Offset(0, armLen), markerPaint);

    // Étiquettes textuelles des murs
    _drawText(canvas, tr('Mur A'), corner + Offset(rw * 0.45, -16), labelColor, fontWeight: FontWeight.bold);
    _drawText(canvas, tr('Mur C'), corner + Offset(-24, rh * 0.45), labelColor, fontWeight: FontWeight.bold);

    // Flèche d'instruction pointant le coin L
    final arrowStart = Offset(cx - 160, cy + 8);
    final arrowEnd = corner + const Offset(-6, -6);

    final guidePaint = Paint()
      ..color = guideColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    // Ligne courbe vers le coin
    final path = Path()
      ..moveTo(arrowStart.dx, arrowStart.dy)
      ..quadraticBezierTo(cx - 70, cy + 18, arrowEnd.dx, arrowEnd.dy);
    canvas.drawPath(path, guidePaint);

    // Tête de flèche
    final arrowHeadPaint = Paint()
      ..color = guideColor
      ..style = PaintingStyle.fill;

    final headPath = Path()
      ..moveTo(arrowEnd.dx, arrowEnd.dy)
      ..lineTo(arrowEnd.dx - 8, arrowEnd.dy + 3)
      ..lineTo(arrowEnd.dx - 4, arrowEnd.dy + 8)
      ..close();
    canvas.drawPath(headPath, arrowHeadPaint);

    // Texte guide avec badge
    _drawBadge(canvas, tr('Posez le L sur le vrai coin'), arrowStart + const Offset(-10, -10), guideColor);
  }

  void _drawText(Canvas canvas, String text, Offset pos, Color color, {FontWeight fontWeight = FontWeight.normal}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: fontWeight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawBadge(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos - Offset(tp.width / 2, 0), width: tp.width + 14, height: tp.height + 8),
      const Radius.circular(6),
    );
    canvas.drawRRect(bgRect, Paint()..color = color);
    tp.paint(canvas, pos - Offset(tp.width, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RoomCornerHelpPainter oldDelegate) {
    return oldDelegate.wallColor != wallColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.markerColor != markerColor ||
        oldDelegate.guideColor != guideColor;
  }
}

/// Guide court dans l'application (dialogue d'aide).
Future<void> showArHelpDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.help_outline, color: Brand.orange),
          const SizedBox(width: Tokens.s2),
          Text(tr('Guide AR : Voir dans ma pièce')),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _HelpItem(
                icon: Icons.devices,
                title: tr('Appareils compatibles'),
                body: tr('Fonctionne sur iPad et iPhone récents, directement dans Safari (AR Quick Look, sans installer d’application).'),
              ),
              const SizedBox(height: Tokens.s3),
              _HelpItem(
                icon: Icons.flag_outlined,
                title: tr('Calage du repère L'),
                body: tr('Le repère rouge en L est posé sur l’angle des murs A et C. Visez le sol avec la caméra et faites glisser le L pour le superposer au vrai coin de votre pièce.'),
              ),
              const SizedBox(height: Tokens.s3),
              _HelpItem(
                icon: Icons.straighten,
                title: tr('Échelle réelle 1:1'),
                body: tr('La cuisine apparaît en taille réelle. Le pincement pour zoomer est volontairement bloqué pour conserver des cotes exactes.'),
              ),
              const SizedBox(height: Tokens.s3),
              _HelpItem(
                icon: Icons.wb_sunny_outlined,
                title: tr('Lumière recommandée'),
                body: tr('La pièce doit être bien éclairée et dégagée au sol pour que la caméra détecte la surface.'),
              ),
              const SizedBox(height: Tokens.s3),
              _HelpItem(
                icon: Icons.rule,
                title: tr('Limites de mesure'),
                body: tr('Précision visuelle d’environ ±2 cm selon la détection de sol. La vue AR sert à visualiser et vérifier l’espace, pas à modifier les meubles.'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: FilledButton.styleFrom(backgroundColor: Brand.orange),
          child: Text(tr('Compris')),
        ),
      ],
    ),
  );
}

class _HelpItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _HelpItem({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Brand.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 20, color: Brand.orange),
        ),
        const SizedBox(width: Tokens.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(body, style: t.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
