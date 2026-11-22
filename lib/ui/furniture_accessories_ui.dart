// Accessoires de meubles : choix par catégorie et quantité, ajoutés à l'estimation du projet.
import 'package:flutter/material.dart';

import '../engine/furniture_accessories.dart';
import 'app_state.dart';
import 'i18n.dart';

String _dh(double v) => '${v.round()} DH';

Future<void> showFurnitureAccessoriesDialog(BuildContext context, AppState st) => showDialog<void>(
      context: context,
      builder: (ctx) => AnimatedBuilder(
        animation: st,
        builder: (ctx, _) {
          final cats = FurnitureAccessories.categories;
          var lo = 0.0, hi = 0.0;
          for (final e in st.project.accessories.entries) {
            final a = FurnitureAccessories.byId[e.key];
            if (a == null) continue;
            lo += a.price.min * e.value;
            hi += a.price.max * e.value;
          }
          return AlertDialog(
            title: Text(tr('Accessoires')),
            content: SizedBox(
              width: 560,
              height: 460,
              child: cats.isEmpty
                  ? Center(child: Text(tr('Catalogue d’accessoires indisponible')))
                  : DefaultTabController(
                      length: cats.length,
                      child: Column(children: [
                        TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final c in cats) Tab(text: tr(c.name))]),
                        Expanded(
                          child: TabBarView(children: [
                            for (final c in cats)
                              ListView(children: [
                                for (final a in c.items)
                                  ListTile(
                                    key: ValueKey('acc_${a.id}'),
                                    dense: true,
                                    leading: SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: CustomPaint(key: ValueKey('acc_fig_${a.id}'), painter: AccessoryFigure(a.id, Theme.of(ctx).colorScheme.onSurface)),
                                    ),
                                    title: Text(tr(a.name)),
                                    subtitle: Text(a.price.min == a.price.max ? _dh(a.price.min) : '${_dh(a.price.min)} – ${_dh(a.price.max)}'),
                                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                      IconButton(
                                        key: ValueKey('acc_minus_${a.id}'),
                                        icon: const Icon(Icons.remove_circle_outline),
                                        onPressed: (st.project.accessories[a.id] ?? 0) > 0 ? () => st.setAccessory(a.id, (st.project.accessories[a.id] ?? 0) - 1) : null,
                                      ),
                                      SizedBox(width: 28, child: Text('${st.project.accessories[a.id] ?? 0}', textAlign: TextAlign.center)),
                                      IconButton(
                                        key: ValueKey('acc_plus_${a.id}'),
                                        icon: const Icon(Icons.add_circle_outline),
                                        onPressed: () => st.setAccessory(a.id, (st.project.accessories[a.id] ?? 0) + 1),
                                      ),
                                    ]),
                                  ),
                              ]),
                          ]),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(trp('Total accessoires : {0} à {1} (ajouté à l’estimation)', [_dh(lo), _dh(hi)]),
                              style: Theme.of(ctx).textTheme.titleSmall),
                        ),
                        Text(tr('Prix publics indicatifs relevés au Maroc, à confirmer avec le fournisseur.'), style: Theme.of(ctx).textTheme.bodySmall),
                      ]),
                    ),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Fermer')))],
          );
        },
      ),
    );


/// Petite figure au trait de chaque accessoire (range-épices, casserolier, poubelle, penderie, poignée, pied…).
class AccessoryFigure extends CustomPainter {
  final String id;
  final Color color;
  AccessoryFigure(this.id, this.color);

  @override
  void paint(Canvas c, Size size) {
    final k = size.shortestSide / 40; // dessin sur une grille de 40
    final p = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final accent = Paint()..color = const Color(0xFFF26A1B).withValues(alpha: 0.85);
    Offset o(double x, double y) => Offset(x * k, y * k);
    void line(double x0, double y0, double x1, double y1) => c.drawLine(o(x0, y0), o(x1, y1), p);
    void rect(double x, double y, double w, double h) => c.drawRect(Rect.fromLTWH(x * k, y * k, w * k, h * k), p);
    void dot(double x, double y, double r) => c.drawCircle(o(x, y), r * k, accent);

    switch (id) {
      case 'spice_150' || 'spice_200' || 'spice_300':
        // coulissant étroit à 3 étages, bouteilles
        final w = id == 'spice_150' ? 10.0 : id == 'spice_200' ? 13.0 : 17.0;
        final x = 20 - w / 2;
        rect(x, 4, w, 32);
        for (final y in [13.0, 22.0, 31.0]) {
          line(x, y, x + w, y);
        }
        for (var i = 0; i < 3; i++) {
          dot(x + w * (i + 1) / 4, 10.5, 1.6);
          dot(x + w * (i + 1) / 4, 19.5, 1.6);
        }
        line(x - 3, 36, x + w + 3, 36);
      case 'spice_3':
        rect(8, 6, 24, 28);
        for (final y in [15.0, 24.0]) {
          line(8, y, 32, y);
        }
        for (final y in [12.0, 21.0, 30.0]) {
          for (var i = 0; i < 4; i++) {
            dot(12 + i * 5.5, y, 1.5);
          }
        }
      case 'pan_drawer':
        // tiroir avec casseroles
        rect(4, 18, 32, 16);
        line(4, 22, 36, 22);
        c.drawArc(Rect.fromLTWH(8 * k, 9 * k, 12 * k, 10 * k), 3.14, 3.14, false, p);
        line(8, 14, 20, 14);
        line(20, 13, 25, 11);
        c.drawArc(Rect.fromLTWH(22 * k, 11 * k, 10 * k, 8 * k), 3.14, 3.14, false, p);
        line(22, 15, 32, 15);
      case 'cleaning':
        // panier sous évier + flacon
        rect(6, 20, 28, 14);
        for (var x = 10.0; x < 34; x += 6) {
          line(x, 20, x, 34);
        }
        rect(12, 9, 6, 11);
        line(15, 9, 15, 5);
        line(15, 5, 19, 5);
      case 'multi_basket' || 'pullout_kit':
        // paniers grillagés
        for (final y in id == 'multi_basket' ? [14.0] : [6.0, 17.0, 28.0]) {
          rect(7, y, 26, id == 'multi_basket' ? 14 : 8);
          for (var x = 11.0; x < 33; x += 5) {
            line(x, y, x, y + (id == 'multi_basket' ? 14 : 8));
          }
        }
      case 'tall_pullout':
        // colonne garde-manger coulissante
        rect(12, 3, 16, 34);
        for (final y in [10.0, 17.0, 24.0, 31.0]) {
          line(12, y, 28, y);
          dot(16, y - 2.5, 1.4);
          dot(22, y - 2.5, 1.4);
        }
      case 'corner_pullout':
        // paniers d'angle en haricot
        c.drawPath(
            Path()
              ..moveTo(6 * k, 30 * k)
              ..lineTo(6 * k, 14 * k)
              ..quadraticBezierTo(6 * k, 8 * k, 14 * k, 8 * k)
              ..lineTo(34 * k, 8 * k)
              ..lineTo(34 * k, 18 * k)
              ..lineTo(18 * k, 18 * k)
              ..lineTo(18 * k, 30 * k)
              ..close(),
            p);
        line(6, 34, 18, 34);
      case 'bin_64' || 'bin_30':
        // poubelle avec couvercle (pédale pour la 30 L)
        c.drawPath(
            Path()
              ..moveTo(11 * k, 12 * k)
              ..lineTo(13 * k, 35 * k)
              ..lineTo(27 * k, 35 * k)
              ..lineTo(29 * k, 12 * k),
            p);
        line(9, 12, 31, 12);
        line(17, 8, 23, 8);
        line(17, 8, 17, 12);
        line(23, 8, 23, 12);
        if (id == 'bin_64') {
          line(20, 14, 20, 33);
        } else {
          line(25, 35, 31, 37);
        }
      case 'fold_rail' || 'fold_rail_electric':
        // penderie rabattable : barre + bras
        line(6, 6, 6, 34);
        line(34, 6, 34, 34);
        line(6, 10, 18, 22);
        line(34, 10, 22, 22);
        line(14, 22, 26, 22);
        for (final x in [16.0, 20.0, 24.0]) {
          c.drawPath(
              Path()
                ..moveTo(x * k, 22 * k)
                ..lineTo((x - 3) * k, 27 * k)
                ..lineTo((x + 3) * k, 27 * k)
                ..close(),
              p);
        }
        if (id == 'fold_rail_electric') dot(34, 34, 2.4);
      case 'trouser_rack':
        rect(6, 8, 28, 4);
        for (var x = 9.0; x < 33; x += 4) {
          line(x, 12, x, 32);
        }
      case 'shoe_rack':
        for (final y in [14.0, 26.0]) {
          line(6, y, 34, y - 4);
          c.drawPath(
              Path()
                ..moveTo(10 * k, (y - 1) * k)
                ..quadraticBezierTo(14 * k, (y - 7) * k, 20 * k, (y - 3) * k),
              p);
        }
      case 'tie_rack':
        line(6, 8, 34, 8);
        for (var x = 10.0; x < 34; x += 6) {
          c.drawPath(
              Path()
                ..moveTo(x * k, 8 * k)
                ..lineTo((x - 2) * k, 26 * k)
                ..lineTo(x * k, 30 * k)
                ..lineTo((x + 2) * k, 26 * k)
                ..close(),
              p);
        }
      case 'pull_mirror':
        rect(12, 4, 16, 32);
        line(15, 9, 19, 13);
        line(15, 14, 22, 21);
      case 'handle_basic' || 'handle_mid' || 'handle_design':
        // poignée : barre et ses pieds
        final w = id == 'handle_basic' ? 18.0 : id == 'handle_mid' ? 24.0 : 30.0;
        final x = 20 - w / 2;
        line(x, 16, x + w, 16);
        line(x + 3, 16, x + 3, 24);
        line(x + w - 3, 16, x + w - 3, 24);
        line(4, 26, 36, 26);
        if (id == 'handle_design') dot(20, 16, 1.8);
      case 'leg_steel':
        rect(6, 6, 28, 5);
        line(10, 11, 8, 35);
        line(30, 11, 32, 35);
      case 'leg_square':
        rect(6, 6, 28, 5);
        rect(9, 11, 4, 24);
        rect(27, 11, 4, 24);
      case 'leg_coffee':
        rect(4, 14, 32, 4);
        line(9, 18, 6, 32);
        line(31, 18, 34, 32);
        line(9, 18, 12, 32);
        line(31, 18, 28, 32);
      case 'leg_xxl':
        rect(6, 4, 28, 4);
        c.drawPath(
            Path()
              ..moveTo(12 * k, 8 * k)
              ..lineTo(20 * k, 36 * k)
              ..lineTo(28 * k, 8 * k),
            p);
      default:
        rect(8, 8, 24, 24);
        line(8, 20, 32, 20);
    }
  }

  @override
  bool shouldRepaint(AccessoryFigure old) => old.id != id || old.color != color;
}
