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
  final sheets = st.cutPlan.newSheets().where((s) => !s.material.startsWith('HDF')).length;
  final extra = <(String, Widget Function(BuildContext))>[
    if (MediaProgetti.instance != null) ('Media Progetti', (c) => _MediaProgettiTab(state: st, tariff: MediaProgetti.instance!, onMessage: onMessage)),
    if (Market.articles.isNotEmpty) ('Prix indicatifs', (c) => const _MarketArticles()),
    if (Market.panels.isNotEmpty) ('Panneaux par gamme', (c) => _MarketPanelsTab(state: st, onMessage: onMessage)),
    if (Market.brands.isNotEmpty) ('Marques mondiales', (c) => _MarketBrands(state: st, onMessage: onMessage)),
    if (Market.makers.isNotEmpty) ('Fabricants', (c) => const _MarketMakers()),
  ];
  return showDialog<void>(
    context: context,
    builder: (ctx) => DefaultTabController(
      length: cats.length + extra.length,
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
            TabBar(isScrollable: true, tabs: [for (final c in cats) Tab(text: tr(c.label)), for (final (l, _) in extra) Tab(text: tr(l))]),
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
                for (final (_, w) in extra) w(ctx),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
}

/// Choix de la moyenne gamme : caissons Alvic standard ou hydrofuges, portes avec ou sans poignée intégrée.
class MediaProgettiChoices extends StatelessWidget {
  final AppState state;
  const MediaProgettiChoices({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final sp = state.project.specs;
    return Wrap(spacing: Tokens.s2, runSpacing: Tokens.s2, children: [
      for (final (k, label) in [('alvic', tr('Caisson Alvic antibactérien')), ('alvic_hydro', tr('Caisson Alvic hydrofuge'))])
        ChoiceChip(key: ValueKey('mp_$k'), label: Text(label), selected: sp.mpCarcass == k, onSelected: (_) => state.edit(() => sp.mpCarcass = k)),
      for (final (k, label) in [('auto', tr('Portes selon les poignées')), ('pi', tr('Poignée intégrée')), ('plain', tr('Sans poignée intégrée'))])
        ChoiceChip(key: ValueKey('mp_$k'), label: Text(label), selected: sp.mpDoor == k, onSelected: (_) => state.edit(() => sp.mpDoor = k)),
    ]);
  }
}

/// Tarif Media Progetti : coordonnées, choix pour le devis, caissons et portes.
class _MediaProgettiTab extends StatelessWidget {
  final AppState state;
  final MediaProgetti tariff;
  final void Function(String) onMessage;
  const _MediaProgettiTab({required this.state, required this.tariff, required this.onMessage});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    String dh(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} MAD';
    Widget row(MpItem i, String name) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 120, child: Text(i.ref, style: t.labelSmall)),
            Expanded(child: Text(name, style: t.bodySmall)),
            Text(dh(i.price), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        );
    final used = state.project.specs.gamme == 'moyen';
    return ListView(padding: const EdgeInsets.all(Tokens.s4), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${tariff.supplier} · ${tr(tariff.tier)}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text('${tr(tariff.activity)} · ${tariff.city}', style: t.bodySmall),
            Text(trp('Prix TTC (TVA {0} %) du {1}, à confirmer avec le fournisseur. Le devis les compte hors taxes.', [tariff.vat.round(), tariff.date.split('-').reversed.join('/')]),
                style: t.bodySmall),
          ]),
        ),
        used
            ? Chip(label: Text(tr('Dans le devis')))
            : FilledButton(
                key: const ValueKey('mp_use'),
                onPressed: () {
                  state.setGamme('moyen');
                  Navigator.pop(context);
                  onMessage(tr('Moyenne gamme Media Progetti : devis mis à jour'));
                },
                child: Text(tr('Utiliser dans le devis'))),
      ]),
      for (final l in tariff.lines.entries)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: l.key == 'alvic',
          title: Text(tr(l.value), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          children: [
            for (final i in tariff.carcasses.where((i) => i.line == l.key))
              row(i, '${tr(mpTypeLabels[i.type] ?? i.type)} ${i.h} x ${i.w} x ${i.d}'),
          ],
        ),
      for (final handle in [true, false])
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(tr(handle ? tariff.doorHandle : tariff.doorPlain), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          children: [for (final i in tariff.doors.where((i) => i.handle == handle)) row(i, '${i.h} x ${i.w} mm')],
        ),
    ]);
  }
}

/// Prix indicatifs, de la vis à la feuille, en dirhams et en euros.
class _MarketArticles extends StatelessWidget {
  const _MarketArticles();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    String n(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toString().replaceAll('.', ',');
    return ListView(padding: const EdgeInsets.all(Tokens.s4), children: [
      Text(tr(Market.note), style: t.bodySmall),
      for (final c in Market.categories) ...[
        const SizedBox(height: Tokens.s3),
        Text(tr(c), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        for (final a in Market.articles.where((a) => a.category == c))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(tr(a.name), style: t.bodySmall)),
              SizedBox(width: 150, child: Text(_mad(a.mad), textAlign: TextAlign.end, style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
              SizedBox(width: 110, child: Text('${n(a.eur.min)} – ${n(a.eur.max)} EUR', textAlign: TextAlign.end, style: t.labelSmall)),
            ]),
          ),
      ],
    ]);
  }
}

/// Panneaux par gamme : marques, formats, épaisseurs, prix ; applicable au projet.
class _MarketPanelsTab extends StatelessWidget {
  final AppState state;
  final void Function(String) onMessage;
  const _MarketPanelsTab({required this.state, required this.onMessage});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.all(Tokens.s4), children: [
      Text(tr('Choisir un format met le prix moyen de la gamme et ce format dans le devis et le débit (18 mm).'), style: t.bodySmall),
      for (final p in Market.panels)
        Card(
          margin: const EdgeInsets.only(top: Tokens.s3),
          child: Padding(
            padding: const EdgeInsets.all(Tokens.s3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(tr(p.tier), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                Text('${_mad(p.mad)} · ${p.eur.min.round()} – ${p.eur.max.round()} EUR', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ]),
              Text(p.brands.join(' · '), style: t.bodyMedium),
              Text(p.types.map(tr).join(' · '), style: t.bodySmall),
              Text(trp('Épaisseurs : {0} mm', [p.thicknesses.join(', ')]), style: t.bodySmall),
              Text(tr(p.usage), style: t.bodySmall),
              const SizedBox(height: Tokens.s2),
              Wrap(spacing: Tokens.s2, runSpacing: Tokens.s2, children: [
                for (final (l, w) in p.sizes)
                  () {
                    final price = ((p.mad.min + p.mad.max) / 2).roundToDouble();
                    final on = state.project.specs.sheetPrice == price && state.project.cut.sheetLength == l && state.project.cut.sheetWidth == w;
                    return ActionChip(
                      key: ValueKey('mk_${p.tier}_${l}_$w'),
                      avatar: on ? const Icon(Icons.check, size: 16) : null,
                      label: Text('$l x $w'),
                      onPressed: () {
                        state.applyPublicPanel(PublicPanel('market', p.tier, 'market', l, w, 18, price));
                        Navigator.pop(context);
                        onMessage(trp('{0} : {1} MAD la feuille, devis et débit mis à jour', [tr(p.tier), price.round()]));
                      },
                    );
                  }(),
              ]),
            ]),
          ),
        ),
    ]);
  }
}

/// Marques mondiales de quincaillerie ; celles qui ont un prix au Maroc peuvent servir au devis.
class _MarketBrands extends StatelessWidget {
  final AppState state;
  final void Function(String) onMessage;
  const _MarketBrands({required this.state, required this.onMessage});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.all(Tokens.s4), children: [
      for (final b in Market.brands)
        () {
          final priced = BrandCatalog.hardwareBrand(b.name.split(' (').first);
          return Card(
            margin: const EdgeInsets.only(bottom: Tokens.s2),
            child: ListTile(
              title: Text('${b.name} · ${tr(b.country)}', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              subtitle: Text([
                b.specialties.map(tr).join(' · '),
                if (b.test.isNotEmpty) trp('Essais : {0}', [tr(b.test)]),
                b.site,
              ].join('\n')),
              isThreeLine: true,
              trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: Tokens.s2, children: [
                Text(tr(b.tier), style: t.labelSmall),
                if (priced != null)
                  state.project.specs.hardwareBrand == priced.name
                      ? Chip(label: Text(tr('Dans le devis')))
                      : OutlinedButton(
                          onPressed: () {
                            state.setHardwareBrand(priced.name);
                            Navigator.pop(context);
                            onMessage(trp('Quincaillerie {0} : devis mis à jour', [tr(priced.name)]));
                          },
                          child: Text(tr('Choisir'))),
              ]),
            ),
          );
        }(),
    ]);
  }
}

/// Fabricants exportateurs : présentation, contact, catalogue.
class _MarketMakers extends StatelessWidget {
  const _MarketMakers();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.all(Tokens.s4), children: [
      Text(tr('Coordonnées à vérifier sur le site du fabricant avant de commander.'), style: t.bodySmall),
      for (final m in Market.makers)
        Card(
          margin: const EdgeInsets.only(top: Tokens.s2),
          child: Padding(
            padding: const EdgeInsets.all(Tokens.s3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(m.name, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                Text('${tr(m.sector)} · ${tr(m.country)}', style: t.labelSmall),
              ]),
              Text(tr(m.about), style: t.bodySmall),
              const SizedBox(height: 4),
              SelectableText('${m.address}\n${m.phone} · ${m.email}\n${m.site} · ${m.catalog}', style: t.bodySmall),
            ]),
          ),
        ),
    ]);
  }
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
