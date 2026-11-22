// Aperçu à l'écran des planches du plan d'exécution (3D, dessus, une face par mur),
// dessinées exactement comme dans le PDF.

import 'i18n.dart';
import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'tech_drawings.dart';
import 'kx_choices.dart';
import 'theme.dart';

class TechPreview extends StatefulWidget {
  final AppState state;
  final Widget? real3dView;
  const TechPreview({super.key, required this.state, this.real3dView});
  @override
  State<TechPreview> createState() => _TechPreviewState();
}

class _TechPreviewState extends State<TechPreview> {
  String sheet = '3d';

  @override
  Widget build(BuildContext context) {
    final e = widget.state.engine;
    final walls = wallsToDraw(e);
    final sheets = <(String, String)>[
      ('3d', 'Vue 3D'),
      ('plan', 'Plan du dessus'),
      for (final w in walls) ('wall:$w', 'Face mur $w'),
    ];
    if (!sheets.any((s) => s.$1 == sheet)) sheet = '3d';
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: context.pc.canvas,
      padding: const EdgeInsets.all(Tokens.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: KxChoices<String>(
            showSelectedIcon: false,
            segments: [for (final (id, label) in sheets) ButtonSegment(value: id, label: Text(label))],
            selected: {sheet},
            onSelectionChanged: (v) {
              setState(() => sheet = v.first);
              if (v.first == '3d' && widget.state.view != ViewMode.view3d) {
                widget.state.setView(ViewMode.view3d);
              }
            },
          ),
        ),
        const SizedBox(height: Tokens.s3),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: (sheet == '3d' && widget.real3dView != null)
                ? widget.real3dView!
                : Semantics(
                    label: trp('Aperçu de la planche {0}', [sheets.firstWhere((s) => s.$1 == sheet).$2]),
                    child: CustomPaint(painter: _SheetPainter(e, sheet, widget.state.yaw), size: Size.infinite),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _SheetPainter extends CustomPainter {
  final LayoutEngine e;
  final String sheet;
  final double yaw;
  _SheetPainter(this.e, this.sheet, this.yaw);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final d = TechDrawer(e);
    if (sheet == 'plan') {
      d.paintPlan(canvas, size);
    } else if (sheet.startsWith('wall:')) {
      d.paintElevation(canvas, size, sheet.substring(5));
    } else {
      d.paint3d(canvas, size, yaw);
    }
  }

  @override
  bool shouldRepaint(covariant _SheetPainter old) => true;
}
