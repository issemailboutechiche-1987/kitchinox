// Marques et prix (marché marocain) : comparatif chiffré sur le projet, choix de la marque du devis ;
// dimensions types des pièces (cuisine, salle de bain, dressing) selon les normes.
import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'theme.dart';
import 'i18n.dart';

String _mad(PriceRange p) => p.min == p.max ? '${p.min.round()} MAD' : '${p.min.round()} – ${p.max.round()} MAD';

/// Quantités de quincaillerie du projet, par article (d'après le devis).
Map<String, double> projectHardwareQty(AppState st) {
  final db = st.db;
  if (db == null) return const {};
  final out = <String, double>{};
  final ids = {for (final it in db.hardware.values) it.name: it.id};
  for (final l in hardwareList(st.engine, db, st.project.specs, st.cutPlan.parts, st.bom.plinthLength)) {
    final id = ids[l.name];
    if (id != null) out[id] = (out[id] ?? 0) + l.qty;
  }
  return out;
}

Future<void> showBrandsDialog(BuildContext context, AppState st, void Function(String) onMessage) {
  final t = Theme.of(context).textTheme;
  final cats = BrandCatalog.categories;
  if (cats.isEmpty) {
    onMessage(tr('Catalogue des marques non chargé'));
    return Future.value();
  }
  final qty = projectHardwareQty(st);
  final estimate = BrandCatalog.hardwareEstimate(qty);
  final sheets = st.cutPlan.sheets.where((s) => !s.material.startsWith('HDF')).length;
  return showDialog<void>(
    context: context,
    builder: (ctx) => DefaultTabController(
      length: cats.length,
      child: Dialog(
        insetPadding: const EdgeInsets.all(Tokens.s5),
        child: SizedBox(
          width: 980,
          height: 680,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s3, 0),
              child: Row(children: [
                Expanded(child: Text(tr('Marques et prix (Maroc)'), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                IconButton(tooltip: tr('Fermer'), onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ]),
            ),
            TabBar(isScrollable: true, tabs: [for (final c in cats) Tab(text: c.label)]),
            Expanded(
              child: TabBarView(children: [
                for (final c in cats)
                  ListView(padding: const EdgeInsets.all(Tokens.s4), children: [
                    Text(tr(c.description), style: t.bodySmall),
                    if (c.distributors.isNotEmpty) Text(trp('Distributeurs au Maroc : {0}', [c.distributors.join(', ')]), style: t.bodySmall),
                    // ---- quincaillerie : estimation sur le projet, choix de la marque du devis
                    if (c.id == 'furniture_hardware' && estimate.isNotEmpty) ...[
                      const SizedBox(height: Tokens.s3),
                      Text(tr('Votre projet : charnières, tiroirs, relevables, suspentes'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      for (final (b, total, _) in estimate)
                        Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            dense: true,
                            title: Text(tr(b.name), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                            subtitle: Text('${b.tier} · ${b.origin}'),
                            trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, children: [
                              Text(_mad(total), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                              st.project.specs.hardwareBrand == b.name
                                  ? Chip(label: Text(tr('Dans le devis')))
                                  : OutlinedButton(
                                      onPressed: () {
                                        st.setHardwareBrand(b.name);
                                        Navigator.pop(ctx);
                                        onMessage(trp('Quincaillerie {0} : devis mis à jour', [tr(b.name)]));
                                      },
                                      child: Text(tr('Choisir'))),
                            ]),
                          ),
                        ),
                    ],
                    // ---- panneaux : tarif public (prix par feuille), applicable au projet d'un clic
                    if (c.id == 'mdf_and_wood_panels' && PublicPrices.panels.isNotEmpty) ...[
                      const SizedBox(height: Tokens.s3),
                      Text(tr('Prix publics des panneaux'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text(trp('Tarif public relevé en {0}, par feuille. À confirmer avec le fournisseur.', [PublicPrices.updated]), style: t.bodySmall),
                      for (final fam in PublicPrices.families) ...[
                        const SizedBox(height: Tokens.s2),
                        Text(tr(fam), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                        for (final p in PublicPrices.panels.where((p) => p.family == fam))
                          Card(
                            margin: const EdgeInsets.only(top: 4),
                            child: ListTile(
                              dense: true,
                              title: Text(tr(p.name), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                              subtitle: Text([
                                '${p.length ~/ 10} x ${p.width ~/ 10} cm · ${p.thickness} mm${p.thicknessAssumed ? ' ?' : ''}',
                                trp('{0} MAD/m²', [p.perM2.round()]),
                                if (p.note.isNotEmpty) tr(p.note),
                              ].join(' · ')),
                              trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, children: [
                                Text(_mad(PriceRange(p.price, p.price)), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                if (p.thickness >= 16)
                                  st.project.specs.sheetPrice == p.price && st.project.cut.sheetLength == p.length && st.project.cut.sheetWidth == p.width
                                      ? Chip(label: Text(tr('Dans le devis')))
                                      : OutlinedButton(
                                          key: ValueKey('pub_${p.id}'),
                                          onPressed: () {
                                            st.applyPublicPanel(p);
                                            Navigator.pop(ctx);
                                            onMessage(trp('{0} : {1} MAD la feuille, devis et débit mis à jour', [tr(p.name), p.price.round()]));
                                          },
                                          child: Text(tr('Choisir'))),
                              ]),
                            ),
                          ),
                      ],
                      const SizedBox(height: Tokens.s2),
                      Text(
                          [for (final (n, pr) in PublicPrices.edges) trp('{0} : {1} MAD/m', [tr(n), pr.toStringAsFixed(pr == pr.roundToDouble() ? 0 : 1)])].join(' · '),
                          style: t.bodySmall),
                      const Divider(height: Tokens.s5),
                    ],
                    // ---- panneaux : nombre de feuilles du débit × prix de la marque
                    if (c.id == 'mdf_and_wood_panels' && sheets > 0) ...[
                      const SizedBox(height: Tokens.s3),
                      Text(trp('Votre projet : {0} feuille(s) de panneau au débit', [sheets]), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                    const SizedBox(height: Tokens.s3),
                    for (final b in c.brands)
                      Card(
                        margin: const EdgeInsets.only(bottom: Tokens.s2),
                        child: Padding(
                          padding: const EdgeInsets.all(Tokens.s3),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(tr(b.name), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                              Text('${b.tier} · ${b.origin}', style: t.labelSmall),
                            ]),
                            if (b.specialties.isNotEmpty) Text(b.specialties.join(' · '), style: t.bodySmall),
                            const SizedBox(height: 6),
                            for (final pr in b.prices)
                              Row(children: [
                                Expanded(child: Text(pr.label, style: t.bodySmall)),
                                Text(_mad(pr.price), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                                if (c.id == 'mdf_and_wood_panels' && sheets > 0)
                                  SizedBox(width: 170, child: Text(trp('  × {0} = {1}', [sheets, _mad(pr.price * sheets)]), textAlign: TextAlign.right, style: t.labelSmall)),
                              ]),
                          ]),
                        ),
                      ),
                    const SizedBox(height: Tokens.s2),
                    Text(tr('Prix indicatifs du marché marocain (2026), à confirmer avec le fournisseur.'), style: t.labelSmall),
                  ]),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
}

/// Dimensions types de la pièce (cuisine, salle de bain, dressing) : un clic les applique.
Future<void> showRoomPresets(BuildContext context, AppState st, void Function(String) onMessage) {
  final t = Theme.of(context).textTheme;
  final list = SizeCatalog.presets[st.project.universe] ?? const <RoomPreset>[];
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Dimensions types')),
      content: SizedBox(
        width: 620,
        child: ListView(shrinkWrap: true, children: [
          Text(trp('Les pièces les plus répandues, aux normes ({0}).', [SizeCatalog.references.take(2).join(', ')]), style: t.bodySmall),
          const SizedBox(height: Tokens.s3),
          for (final pr in list)
            Card(
              margin: const EdgeInsets.only(bottom: Tokens.s2),
              child: ListTile(
                title: Text(tr(pr.name), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  trp('{0} x {1} mm · {2} m²', [pr.width.round(), pr.depth.round(), pr.area.toStringAsFixed(1).replaceAll('.', ',')]),
                  if (pr.minWidth != null) trp('minimum {0} x {1}', [pr.minWidth!.round(), pr.minDepth!.round()]),
                  if (pr.kitchenShape != null) trp('disposition {0}', [pr.kitchenShape!.label.toLowerCase()]),
                  if (pr.note.isNotEmpty) pr.note,
                ].join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  onMessage(st.applyRoomPreset(pr));
                },
              ),
            ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Fermer')))],
    ),
  );
}
