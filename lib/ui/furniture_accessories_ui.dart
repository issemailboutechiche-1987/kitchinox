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
