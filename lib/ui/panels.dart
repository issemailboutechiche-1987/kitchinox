// Panneaux : menu du catalogue en colonnes, liste de produits, finitions, fiche de l'élément
// sélectionné (caisson ou ouverture), contrôles et récapitulatif.

import 'quote_ui.dart';
import 'quote_pdf.dart' show money;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'custom_cabinet_ui.dart';
import 'favorites.dart';
import 'furniture_accessories_ui.dart';
import 'finishes.dart';
import 'fronts.dart';
import 'net_symbols.dart';
import 'openings_ui.dart';
import 'brands_ui.dart';
import 'kx_choices.dart';
import 'presentation_bar.dart';
import 'theme.dart';
import 'textures.dart';
import 'toolbar.dart';
import 'web_io.dart';
import 'i18n.dart';
import 'app_settings.dart';

part 'cabinet_tools.dart';

// ================================================================== menu du catalogue

class MegaMenu extends StatelessWidget {
  final AppState state;
  final void Function(String)? onMessage;
  const MegaMenu({super.key, required this.state, this.onMessage});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Material(
      color: scheme.surface,
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(Tokens.radius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Tokens.s5),
          child: Wrap(
            spacing: Tokens.s6,
            runSpacing: Tokens.s5,
            children: [
              for (final shelf in Shelf.values)
                SizedBox(
                  width: 220,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => state.openBrowse(CatalogBrowse(shelf)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(tr(shelf.label), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const Divider(height: Tokens.s4),
                      for (final cat in state.categoriesOf(shelf)) ...[
                        if (state.categoriesOf(shelf).length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: Tokens.s2, bottom: 2),
                            child: Text(tr(cat.name).toUpperCase(), style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.6)),
                          ),
                        for (final m in cat.items)
                          InkWell(
                            // l'article se pose directement sur le mur, le menu se referme
                            onTap: () {
                              final err = state.addModel(m.id);
                              state.toggleMegaMenu(false);
                              onMessage?.call(err ?? trp('{0} posé sur le mur {1}', [tr(m.name), state.wallId]));
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(width: 26, height: 30, child: ExcludeSemantics(child: _thumbOf(state, m))),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(tr(m.name), style: t.bodyMedium)),
                                ],
                              ),
                            ),
                          ),
                      ],
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

// ================================================================== liste de produits

class CatalogPanel extends StatefulWidget {
  final AppState state;
  final void Function(String) onMessage;
  const CatalogPanel({super.key, required this.state, required this.onMessage});
  @override
  State<CatalogPanel> createState() => _CatalogPanelState();
}

class _CatalogPanelState extends State<CatalogPanel> {
  late final search = TextEditingController(text: widget.state.search);

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final b = st.browse!;
    final fav = Favorites.instance;
    final all = fav.sorted(st.browseModels(), (m) => '${st.project.universe}:${m.id}');
    final models = st.favoritesOnly ? all.where((m) => fav.has('${st.project.universe}:${m.id}')).toList() : all;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final cat = b.categoryId == null ? null : st.catalog.categories.firstWhere((c) => c.id == b.categoryId);
    final armed = st.armedModel == null ? null : st.catalog.tryGet(st.armedModel!);
    return _PanelFrame(
      title: tr('Ajouter des meubles'),
      onClose: () => st.openBrowse(null),
      action: IconButton(
        key: const ValueKey('catalog_pin'),
        isSelected: st.browsePinned,
        tooltip: st.browsePinned ? tr('Désépingler : le panneau se ferme quand on touche un meuble') : tr('Épingler : le panneau reste toujours visible'),
        icon: const Icon(Icons.push_pin_outlined),
        selectedIcon: Icon(Icons.push_pin, color: scheme.primary),
        onPressed: () {
          st.browsePinned = !st.browsePinned;
          st.refresh();
        },
      ),
      // l'en-tête défile avec la liste : rien ne déborde sur un écran bas (iPad paysage)
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // pose en cours : on touche le mur, autant de fois qu'on veut
                if (armed != null)
                  Container(
                    key: const ValueKey('armed_banner'),
                    margin: const EdgeInsets.only(bottom: Tokens.s3),
                    padding: const EdgeInsets.fromLTRB(Tokens.s3, Tokens.s2, Tokens.s1, Tokens.s2),
                    decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(Icons.touch_app_outlined, color: scheme.onPrimary),
                        const SizedBox(width: Tokens.s2),
                        Expanded(
                          child: Text(
                            trp('Touchez le plan pour poser « {0} » (L {1}). Répétez pour en poser d’autres.', [
                              tr(armed.name),
                              st.armedWidth ?? armed.defaultWidth,
                            ]),
                            style: t.bodySmall?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: tr('Arrêter la pose (Échap)'),
                          icon: Icon(Icons.close, color: scheme.onPrimary),
                          onPressed: () => st.arm(null),
                        ),
                      ],
                    ),
                  ),
                // fil d'Ariane
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    InkWell(
                      onTap: () => st.toggleMegaMenu(true),
                      child: Text(tr('Catalogue'), style: t.bodySmall?.copyWith(decoration: TextDecoration.underline)),
                    ),
                    Text('  /  ', style: t.bodySmall),
                    InkWell(
                      onTap: () => st.openBrowse(CatalogBrowse(b.shelf)),
                      child: Text(tr(b.shelf.label), style: t.bodySmall?.copyWith(decoration: cat == null ? null : TextDecoration.underline)),
                    ),
                    if (cat != null) ...[Text('  /  ', style: t.bodySmall), Text(tr(cat.name), style: t.bodySmall)],
                  ],
                ),
                const SizedBox(height: Tokens.s3),
                TextField(
                  controller: search,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: tr('Rechercher (évier, tiroirs, angle…)'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: tr('Effacer'),
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              search.clear();
                              st.setSearch('');
                            },
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    isDense: true,
                  ),
                  onChanged: st.setSearch,
                ),
                const SizedBox(height: Tokens.s3),
                // filtres rapides par rayon
                Wrap(
                  spacing: Tokens.s2,
                  runSpacing: Tokens.s2,
                  children: [
                    for (final s in Shelf.values)
                      ChoiceChip(
                        label: Text(tr(s.label)),
                        selected: st.search.isEmpty && b.shelf == s,
                        onSelected: (_) {
                          search.clear();
                          st.openBrowse(CatalogBrowse(s));
                        },
                      ),
                    // caissons libres : seulement si le catalogue de l'univers les contient (cuisine)
                    if (st.catalog.tryGet('custom_base') != null)
                      ActionChip(
                        key: const ValueKey('tile_custom_cabinet'),
                        avatar: const Icon(Icons.dashboard_customize_outlined, size: 16),
                        label: Text(tr('Personnalisé')),
                        onPressed: () => showCustomCabinetDialog(context, st, widget.onMessage),
                      ),
                    FilterChip(
                      key: const ValueKey('fav_only'),
                      avatar: Icon(st.favoritesOnly ? Icons.star_rounded : Icons.star_outline_rounded, size: 16, color: const Color(0xFFF5A524)),
                      showCheckmark: false,
                      label: Text(tr('Favoris')),
                      selected: st.favoritesOnly,
                      onSelected: (v) {
                        st.favoritesOnly = v;
                        st.refresh();
                      },
                    ),
                    ActionChip(
                      key: const ValueKey('tile_accessories'),
                      avatar: const Icon(Icons.inventory_2_outlined, size: 16),
                      label: Text(trp('Accessoires ({0})', [st.project.accessories.values.fold<int>(0, (a, b) => a + b)])),
                      onPressed: () => showFurnitureAccessoriesDialog(context, st),
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.s3),
                Text(
                  trp('{0} produit(s) · touchez une carte puis le plan, ou glissez-la', [models.length]),
                  style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: Tokens.s2),
                // mur où « + » pose les meubles (aussi : toucher un mur sur le plan)
                Row(
                  children: [
                    Text(tr('« + » pose sur le mur'), style: t.bodySmall),
                    const SizedBox(width: Tokens.s2),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: KxChoices<String>(
                          key: const ValueKey('add_wall'),
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: [
                            for (final w in [...st.project.room.walls]..sort((a, b) => a.id.compareTo(b.id)))
                              ButtonSegment(value: w.id, label: Text(w.id), enabled: w.enabled),
                          ],
                          selected: {st.wallId},
                          onSelectionChanged: (v) => st.setWall(v.first),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.s2),
              ],
            ),
          ),
          SliverList.separated(
            itemCount: models.length,
            separatorBuilder: (_, _) => const SizedBox(height: Tokens.s2),
            itemBuilder: (_, i) => _ProductCard(model: models[i], state: st, onMessage: widget.onMessage),
          ),
        ],
      ),
    );
  }
}

String shortSizes(SizeOptions o) {
  if (o.isRange) return '${o.min} à ${o.max}';
  final v = o.values;
  if (v.length > 2) return '${v.first} à ${v.last}';
  return v.join(' / ');
}

/// Vignette d'un modèle dans les façades du projet (face avant dessinée).
Widget _thumbOf(AppState state, CabinetModel model) {
  final f = frontFinish(
    state.project.style,
    model.kind.isHigh ? (state.project.style.frontUpper ?? state.project.style.front) : (state.project.style.frontLower ?? state.project.style.front),
  );
  return FrontThumb(model: model, fill: f.color, stroke: shade(f.color, -0.35), line: lineOn(f.color));
}

class _ProductCard extends StatelessWidget {
  final CabinetModel model;
  final AppState state;
  final void Function(String) onMessage;
  const _ProductCard({required this.model, required this.state, required this.onMessage});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final w = model.shape == CabinetShape.lShape || model.shape == CabinetShape.diagonal
        ? '${shortSizes(model.widths)} × ${model.widthRight}'
        : shortSizes(model.widths);
    final armed = state.armedModel == model.id;
    final chosen = armed ? (state.armedWidth ?? model.defaultWidth) : model.defaultWidth;
    // largeurs proposées en puces (liste courte du catalogue) ; une plage se règle ensuite dans la fiche
    final widths = model.widths.isRange || model.widths.values.length > 8 ? const <int>[] : model.widths.values;
    final thumb = SizedBox(width: 84, height: 92, child: _thumbOf(state, model));
    void addNow() =>
        onMessage(state.addModel(model.id, width: armed ? state.armedWidth : null) ?? trp('{0} ajouté sur le mur {1}', [tr(model.name), state.wallId]));
    void toggleArm() => state.arm(armed ? null : model.id, width: armed ? null : chosen);

    final card = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: armed ? scheme.primary : scheme.outlineVariant, width: armed ? 2.5 : 1),
      ),
      // la carte défile avec la liste : seuls la vignette (glisser ou toucher) et « + » agissent
      child: KeyedSubtree(
        key: ValueKey('card_${model.id}'),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Draggable<CabinetModel>(
                data: model,
                feedback: Material(color: Colors.transparent, child: Opacity(opacity: 0.9, child: thumb)),
                childWhenDragging: Opacity(opacity: 0.4, child: _thumbBox(scheme, thumb)),
                child: InkWell(
                  key: ValueKey('thumb_${model.id}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: toggleArm,
                  child: _thumbBox(scheme, thumb),
                ),
              ),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(model.name), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(tr(model.categoryName), style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: Tokens.s2),
                    if (widths.length > 1)
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final v in widths)
                            ChoiceChip(
                              key: ValueKey('w_${model.id}_$v'),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                              label: Text('$v', style: t.labelSmall),
                              selected: armed && chosen == v,
                              onSelected: (_) => state.arm(model.id, width: v),
                            ),
                        ],
                      )
                    else
                      Text(trp('L {0} mm', [w]), style: t.bodySmall),
                    const SizedBox(height: 4),
                    Text(trp('H {0} · P {1} mm', [shortSizes(model.heights), model.depth]), style: t.bodySmall),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(tooltip: trp('Ajouter {0}', [tr(model.name)]), onPressed: addNow, icon: const Icon(Icons.add)),
                  FavoriteStar(id: '${state.project.universe}:${model.id}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(label: trp('Ajouter {0}', [tr(model.name)]), child: card);
  }

  Widget _thumbBox(ColorScheme scheme, Widget thumb) => Container(
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.all(4),
        child: ExcludeSemantics(child: thumb),
      );
}

// ================================================================== cadre commun

class _PanelFrame extends StatelessWidget {
  final String title;
  final VoidCallback? onClose;
  final Widget child;
  final Widget? action;
  const _PanelFrame({required this.title, required this.child, this.onClose, this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s3, Tokens.s4, Tokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                ?action,
                if (onClose != null) IconButton(tooltip: tr('Fermer'), onPressed: onClose, icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: Tokens.s2),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

// ================================================================== finitions

class StylePanel extends StatelessWidget {
  final AppState state;
  final StyleSection section;
  const StylePanel({super.key, required this.state, required this.section});

  @override
  Widget build(BuildContext context) {
    final st = state.project.style;
    final t = Theme.of(context).textTheme;
    Widget swatches(List<Finish> list, String current, void Function(String) on) => Wrap(
      spacing: Tokens.s3,
      runSpacing: Tokens.s3,
      children: [for (final f in list) _Swatch(finish: f, selected: f.id == current, onTap: () => on(f.id))],
    );
    final split = st.frontUpper != null || st.frontLower != null;
    final hasHigh = state.project.items.any((c) => state.engine.modelOf(c).kind.isHigh);
    final perItem = state.project.items.where((c) => c.front != null).length;
    Widget frontsBody() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Modèle de façade'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: Tokens.s2),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final e in frontProfiles.entries)
            () {
              final on = st.frontProfile == e.key;
              final f = frontFinish(st, st.frontLower ?? st.front);
              return InkWell(
                key: ValueKey('profile_${e.key}'),
                borderRadius: BorderRadius.circular(Tokens.radius),
                onTap: () => state.edit(() => st.frontProfile = e.key),
                child: SizedBox(
                  width: 78,
                  child: Column(children: [
                    Container(
                      width: 70,
                      height: 88,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant, width: on ? 3 : 1)),
                      child: CustomPaint(painter: _ProfilePainter(state.catalog, f, e.key)),
                    ),
                    const SizedBox(height: 4),
                    Text(tr(e.value.$1), textAlign: TextAlign.center, style: t.labelSmall?.copyWith(fontWeight: on ? FontWeight.w800 : null)),
                  ]),
                ),
              );
            }(),
        ]),
        const SizedBox(height: Tokens.s4),
        Text(tr('Couleur'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: Tokens.s2),
        if (state.engine.kitchen || hasHigh)
        KxChoices<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: false, label: Text(tr(state.engine.kitchen ? 'Toute la cuisine' : 'Tout le projet')), icon: Icon(state.engine.kitchen ? Icons.kitchen_outlined : Icons.select_all)),
            ButtonSegment(value: true, label: Text(tr('Hauts / bas')), icon: Icon(Icons.vertical_split_outlined)),
          ],
          selected: {split},
          onSelectionChanged: (v) => v.first ? state.setFrontScope(upper: st.front, lower: st.front) : state.setFrontScope(clearUpper: true, clearLower: true),
        ),
        const SizedBox(height: Tokens.s4),
        if (!split)
          swatches(frontFinishes(st), st.front, (v) => state.setStyle(front: v))
        else if (!state.engine.kitchen && !hasHigh)
          // un seul type de meuble : une seule façade
          swatches(frontFinishes(st), st.frontLower ?? st.front, (v) => state.edit(() => st
            ..front = v
            ..frontLower = null
            ..frontUpper = null))
        else ...[
          Text(tr('Éléments hauts'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: Tokens.s2),
          swatches(frontFinishes(st), st.frontUpper ?? st.front, (v) => state.setFrontScope(upper: v)),
          const SizedBox(height: Tokens.s4),
          Text(tr('Éléments bas et colonnes'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: Tokens.s2),
          swatches(frontFinishes(st), st.frontLower ?? st.front, (v) => state.setFrontScope(lower: v)),
        ],
        if (state.project.room.island != null) ...[
          const SizedBox(height: Tokens.s4),
          Text(tr('Îlot'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: Tokens.s2),
          KxChoices<bool>(
            key: const ValueKey('island_front_mode'),
            segments: [ButtonSegment(value: false, label: Text(tr('Comme les bas'))), ButtonSegment(value: true, label: Text(tr('Sa propre couleur')))],
            selected: {st.islandFront != null},
            onSelectionChanged: (v) => state.edit(() => st.islandFront = v.first ? (st.frontLower ?? st.front) : null),
          ),
          if (st.islandFront != null) ...[const SizedBox(height: Tokens.s2), swatches(frontFinishes(st), st.islandFront!, (v) => state.edit(() => st.islandFront = v))],
        ],
        const SizedBox(height: Tokens.s3),
        Text(
          perItem == 0
              ? tr('Astuce : cliquez un meuble pour lui donner sa propre façade (fiche de l’élément).')
              : trp('{0} élément(s) ont leur propre façade.', [perItem]),
          style: t.bodySmall,
        ),
        if (perItem > 0) TextButton.icon(onPressed: state.clearItemFronts, icon: const Icon(Icons.restart_alt), label: Text(tr('Tout aligner sur le style'))),
        const SizedBox(height: Tokens.s4),
        _TextureLibrary(state: state, target: 'front'),
      ],
    );
    final (title, body) = switch (section) {
      StyleSection.fronts => ('Façades', frontsBody()),
      StyleSection.worktop => (
        'Plan de travail',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.db == null) swatches(worktopFinishes(st), st.worktop, (v) => state.setStyle(worktop: v)) else _WorktopMaterialForm(state: state),
            const SizedBox(height: Tokens.s4),
            _TextureLibrary(state: state, target: 'worktop'),
            if (KitchenFixtures.sinks.isNotEmpty) ...[
              const SizedBox(height: Tokens.s4),
              Text(tr('Évier'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: Tokens.s2),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in KitchenFixtures.sinks)
                    ChoiceChip(
                      label: Text(trp('{0} · {1}×{2}', [tr(s.name), s.length, s.depth])),
                      selected: KitchenFixtures.sink(st.sink).id == s.id,
                      onSelected: (_) => state.edit(() => st.sink = s.id),
                    ),
                ],
              ),
              const SizedBox(height: Tokens.s2),
              KxChoices<String>(
                showSelectedIcon: false,
                segments: [
                  if (KitchenFixtures.sink(st.sink).mounting.contains('inset')) ButtonSegment(value: 'inset', label: Text(tr('À encastrer'))),
                  if (KitchenFixtures.sink(st.sink).mounting.contains('undermount')) ButtonSegment(value: 'undermount', label: Text(tr('Sous plan'))),
                ],
                selected: {KitchenFixtures.sink(st.sink).mounting.contains(st.sinkMount) ? st.sinkMount : KitchenFixtures.sink(st.sink).mounting.first},
                onSelectionChanged: (v) => state.edit(() => st.sinkMount = v.first),
              ),
              const SizedBox(height: Tokens.s3),
              Text(tr('Finition de l’évier'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: Tokens.s2),
              KxChoices<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'inox', label: Text(tr('Inox brossé'))),
                  ButtonSegment(value: 'noir_quartz', label: Text(tr('Noir quartz'))),
                  ButtonSegment(value: 'blanc_ceramique', label: Text(tr('Blanc céramique'))),
                ],
                selected: {st.sinkFinish},
                onSelectionChanged: (v) => state.edit(() => st.sinkFinish = v.first),
              ),
              const SizedBox(height: Tokens.s4),
              Text(tr('Mitigeur'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: Tokens.s2),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in KitchenFixtures.faucets)
                    ChoiceChip(
                      label: Text(trp('{0} · H {1}', [tr(f.name), f.height])),
                      selected: KitchenFixtures.faucet(st.faucet).id == f.id,
                      onSelected: (_) => state.edit(() => st.faucet = f.id),
                    ),
                ],
              ),
              const SizedBox(height: Tokens.s3),
              Text(tr('Finition de la robinetterie'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: Tokens.s2),
              KxChoices<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'chrome', label: Text(tr('Chrome poli'))),
                  ButtonSegment(value: 'noir_mat', label: Text(tr('Noir mat'))),
                  ButtonSegment(value: 'or_brosse', label: Text(tr('Laiton doré'))),
                  ButtonSegment(value: 'inox_brosse', label: Text(tr('Inox brossé'))),
                ],
                selected: {st.faucetFinish},
                onSelectionChanged: (v) => state.edit(() => st.faucetFinish = v.first),
              ),
              const SizedBox(height: Tokens.s3),
              Text(tr('Style de levier du mitigeur'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: Tokens.s2),
              KxChoices<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'side_pin', label: Text(tr('Manette fine'))),
                  ButtonSegment(value: 'side_flat', label: Text(tr('Palette plate'))),
                  ButtonSegment(value: 'top_lever', label: Text(tr('Levier haut'))),
                  ButtonSegment(value: 'retro_cross', label: Text(tr('Croisillons'))),
                ],
                selected: {st.faucetLever},
                onSelectionChanged: (v) => state.edit(() => st.faucetLever = v.first),
              ),
              if (state.engine.kitchen) ...[
              const SizedBox(height: Tokens.s4),
              Text(tr('Plaque de cuisson'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: Tokens.s2),
              KxChoices<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'induction', label: Text(tr('Induction'))),
                  ButtonSegment(value: 'gaz', label: Text(tr('Gaz (grilles fonte)'))),
                  ButtonSegment(value: 'vitro', label: Text(tr('Vitrocéramique'))),
                ],
                selected: {st.hobType},
                onSelectionChanged: (v) => state.edit(() => st.hobType = v.first),
              ),
              const SizedBox(height: Tokens.s3),
              Text(tr('Largeur de la plaque'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: Tokens.s2),
              KxChoices<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 0, label: Text(tr('Auto'))),
                  ButtonSegment(value: 60, label: Text('60 cm')),
                  ButtonSegment(value: 80, label: Text('80 cm')),
                  ButtonSegment(value: 90, label: Text('90 cm')),
                ],
                selected: {st.hobWidth},
                onSelectionChanged: (v) => state.edit(() => st.hobWidth = v.first),
              ),
              const SizedBox(height: Tokens.s4),
              Text(tr('Four encastrable'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: Tokens.s2),
              Text(tr('Finition'), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: Tokens.s1),
              KxChoices<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'black_inox', label: Text(tr('Inox & Verre noir'))),
                  ButtonSegment(value: 'inox_brosse', label: Text(tr('Inox brossé'))),
                  ButtonSegment(value: 'full_black', label: Text(tr('Full Black'))),
                  ButtonSegment(value: 'blanc', label: Text(tr('Blanc'))),
                  ButtonSegment(value: 'black_gold', label: Text(tr('Noir & Or'))),
                ],
                selected: {st.ovenFinish},
                onSelectionChanged: (v) => state.edit(() => st.ovenFinish = v.first),
              ),
              const SizedBox(height: Tokens.s3),
              Text(tr('Poignée / Levier de four'), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: Tokens.s1),
              KxChoices<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'bar', label: Text(tr('Barre ronde'))),
                  ButtonSegment(value: 'square', label: Text(tr('Profilé carré'))),
                  ButtonSegment(value: 'retro', label: Text(tr('Cintrée classique'))),
                  ButtonSegment(value: 'integrated', label: Text(tr('Intégrée'))),
                ],
                selected: {st.ovenHandle},
                onSelectionChanged: (v) => state.edit(() => st.ovenHandle = v.first),
              ),
              ],
            ],
          ],
        ),
      ),
      StyleSection.carcass => (
        'Caissons, joues et éclairage',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Couleur du caisson et de l’intérieur'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: Tokens.s2),
            swatches(carcasses, st.carcass, (v) => state.setStyle(carcass: v)),
            const SizedBox(height: Tokens.s5),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: st.endPanels,
              onChanged: (v) => state.setFinishOptions(endPanels: v),
              title: Text(tr('Joues de finition automatiques')),
              subtitle: Text(
                trp('{0} extrémité(s) visible(s) habillée(s) dans la finition des façades. Ajoutées au débit et à la liste.', [endPanels(state.engine, auto: true).where((j) => j.item == null).length]),
              ),
            ),
            Text(tr('Joues (costados) sur les caissons'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              trp('{0} joue(s) ajoutée(s). Pour un seul caisson : touchez-le, puis « Joues (costados) ».', [endPanels(state.engine, auto: false).length]),
              style: t.bodySmall,
            ),
            const SizedBox(height: Tokens.s2),
            Wrap(spacing: Tokens.s2, runSpacing: Tokens.s2, children: [
              OutlinedButton.icon(
                key: const ValueKey('cheeks_visible'),
                onPressed: state.engine.cheekCandidates().isEmpty ? null : () => _cheekMsg(context, state.addCheeks()),
                icon: const Icon(Icons.add, size: 18),
                label: Text(trp('Sur tous les côtés visibles ({0})', [state.engine.cheekCandidates().length])),
              ),
              OutlinedButton.icon(
                key: const ValueKey('cheeks_all'),
                onPressed: () => _cheekMsg(context, state.addCheeks(visibleOnly: false)),
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('Sur tous les caissons')),
              ),
              if (state.project.items.any((c) => c.cheekL != null || c.cheekR != null))
                TextButton.icon(
                  key: const ValueKey('cheeks_clear'),
                  onPressed: state.clearCheeks,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: Text(tr('Tout remettre en automatique')),
                ),
            ]),
            if (endPanels(state.engine).isNotEmpty || st.endPanels) ...[
              const SizedBox(height: Tokens.s3),
              Text(tr('Finition des joues et côtés visibles'), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: Tokens.s1),
              Text(
                tr('Quand les hauts et les bas sont différents, choisissez la matière appliquée sur les côtés exposés :'),
                style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: Tokens.s2),
              KxChoices<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'auto', label: Text(tr('Automatique'))),
                  if (hasHigh) ButtonSegment(value: 'lower', label: Text(tr('Comme les bas / colonnes'))),
                  if (hasHigh) ButtonSegment(value: 'upper', label: Text(tr('Comme les hauts'))),
                  ButtonSegment(value: 'custom', label: Text(tr('Personnalisée'))),
                ],
                selected: {
                  st.endPanelFinish == null
                      ? 'auto'
                      : hasHigh && st.endPanelFinish == (st.frontLower ?? st.front)
                          ? 'lower'
                          : (hasHigh && st.endPanelFinish == (st.frontUpper ?? st.front) ? 'upper' : 'custom')
                },
                onSelectionChanged: (v) {
                  final sel = v.first;
                  if (sel == 'auto') {
                    state.setFinishOptions(clearEndPanelFinish: true);
                  } else if (sel == 'lower') {
                    state.setFinishOptions(endPanelFinish: st.frontLower ?? st.front);
                  } else if (sel == 'upper') {
                    state.setFinishOptions(endPanelFinish: st.frontUpper ?? st.front);
                  } else {
                    // une finition différente des deux autres, à changer ensuite dans la palette
                    final taken = {st.frontLower ?? st.front, st.frontUpper ?? st.front};
                    final other = frontFinishes(st).where((f) => !taken.contains(f.id)).firstOrNull;
                    if (other != null) state.setFinishOptions(endPanelFinish: other.id);
                  }
                },
              ),
              if (st.endPanelFinish != null &&
                  st.endPanelFinish != (st.frontLower ?? st.front) &&
                  st.endPanelFinish != (st.frontUpper ?? st.front)) ...[
                const SizedBox(height: Tokens.s3),
                swatches(frontFinishes(st), st.endPanelFinish ?? st.front, (v) => state.setFinishOptions(endPanelFinish: v)),
              ],
            ],
            const SizedBox(height: Tokens.s4),
            Text(tr('Éclairage'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: Tokens.s2),
            for (final (id, name, icon) in const [
              ('aucun', 'Aucun éclairage', Icons.lightbulb_outline),
              ('led_hauts', 'LED sous les éléments hauts', Icons.light_outlined),
              ('led_hauts_plinthes', 'LED sous les hauts et dans les plinthes', Icons.highlight_outlined),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.s2),
                child: _ChoiceRow(
                  icon: icon,
                  label: name,
                  selected: st.lighting == id,
                  onTap: () => state.setFinishOptions(lighting: id),
                ),
              ),
            Text(tr('L’alimentation 24 V et les rubans sont ajoutés à la liste ; une prise ou une boîte de connexion est à prévoir.'), style: t.bodySmall),
          ],
        ),
      ),
      StyleSection.room => (
        state.engine.kitchen ? 'Sol, murs et crédence' : 'Sol et murs',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Sol'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: Tokens.s2),
            swatches(floorFinishes(st), st.floor, (v) => state.setRoomFinish(floor: v)),
            const SizedBox(height: Tokens.s3),
            _TextureLibrary(state: state, target: 'floor'),
            const SizedBox(height: Tokens.s5),
            Text(tr('Murs'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: Tokens.s2),
            swatches(wallFinishes(st), st.wall, (v) => state.setRoomFinish(wall: v)),
            const SizedBox(height: Tokens.s5),
            if (state.engine.kitchen) ...[
            Text(tr('Crédence (entre le plan de travail et les hauts)'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: Tokens.s2),
            _SplashChoices(state: state),
            const SizedBox(height: Tokens.s2),
            swatches(splashFinishes(st), st.splash ?? '', (v) => state.setRoomFinish(splash: v)),
            const SizedBox(height: Tokens.s3),
            ],
            _TextureLibrary(state: state, target: 'wall'),
            const SizedBox(height: Tokens.s5),
            Text(tr('Appareillage électrique (Prises & Interrupteurs)'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: Tokens.s1),
            Text(tr('Finition des plaques et mécanismes'), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: Tokens.s2),
            KxChoices<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'blanc', label: Text(tr('Blanc'))),
                ButtonSegment(value: 'noir_mat', label: Text(tr('Noir mat'))),
                ButtonSegment(value: 'anthracite', label: Text(tr('Anthracite'))),
                ButtonSegment(value: 'alu_brosse', label: Text(tr('Alu'))),
                ButtonSegment(value: 'or_brosse', label: Text(tr('Laiton/Or'))),
              ],
              selected: {st.socketFinish},
              onSelectionChanged: (v) => state.edit(() => st.socketFinish = v.first),
            ),
          ],
        ),
      ),
      StyleSection.decor => ('Décor', DecorPanel(state: state)),
      StyleSection.handles when state.db != null && state.db!.handles.items.isNotEmpty => ('Poignées', _HandlePicker(state: state, cat: state.db!.handles)),
      StyleSection.handles => (
        'Poignées',
        Column(
          children: [
            for (final (id, name, icon) in handles)
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.s2),
                child: _ChoiceRow(
                  icon: icon,
                  label: name,
                  selected: st.handle == id,
                  onTap: () => state.setStyle(handle: id),
                ),
              ),
          ],
        ),
      ),
    };
    return _PanelFrame(
      title: tr(title),
      child: ListView(
        children: [
          Text(tr('Le rendu est appliqué en vue de face et en 3D.'), style: t.bodySmall),
          const SizedBox(height: Tokens.s4),
          body,
        ],
      ),
    );
  }
}

void _cheekMsg(BuildContext context, (int, int) r) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(trp(r.$2 == 0 ? '{0} joue(s) ajoutée(s)' : '{0} joue(s) ajoutée(s), {1} sans place', [r.$1, r.$2]))));

/// Une porte et un tiroir dans le modèle de façade.
class _ProfilePainter extends CustomPainter {
  final Catalog catalog;
  final Finish finish;
  final String profile;
  _ProfilePainter(this.catalog, this.finish, this.profile);
  @override
  void paint(Canvas canvas, Size size) {
    final m = catalog.models.where((m) => m.isCarcass && m.kind == CabinetKind.base).firstOrNull ?? catalog.models.where((m) => m.isCarcass).firstOrNull;
    if (m == null) return;
    void face(Rect r, double wMm, CellKind kind) {
      final k = r.width / wMm;
      canvas.save();
      canvas.translate(r.left, r.top);
      canvas.scale(k);
      final hMm = r.height / k;
      paintFront(canvas, Rect.fromLTWH(0, 0, wMm, hMm), m,
          fill: finish.color,
          stroke: shade(finish.color, -0.3),
          line: lineOn(finish.color),
          fillPaint: finish.paint(vertical: true),
          cells: [FrontCell(kind, 0, hMm, 'left', -1)],
          handle: 'push',
          profile: profile,
          realistic: true,
          pxPerMm: 1,
          opening: 'hinged_left',
          gloss: finish.gloss);
      canvas.restore();
    }

    final dh = size.height * 0.3;
    face(Rect.fromLTWH(0, 0, size.width, dh), 450, CellKind.drawer);
    face(Rect.fromLTWH(0, dh + 1, size.width, size.height - dh - 1), 450, CellKind.door);
  }

  @override
  bool shouldRepaint(_ProfilePainter o) => o.profile != profile || o.finish.id != finish.id;
}

class _Swatch extends StatelessWidget {
  final Finish finish;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch({super.key, required this.finish, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: tr(finish.name),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radius),
        child: SizedBox(
          width: 96,
          child: Column(
            children: [
              AnimatedContainer(
                duration: Tokens.fast,
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Tokens.radius),
                  border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 3 : 1),
                ),
                padding: const EdgeInsets.all(3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: CustomPaint(painter: _GrainPainter(finish)),
                ),
              ),
              const SizedBox(height: 6),
              Text(tr(finish.name), textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  final Finish f;
  _GrainPainter(this.f);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = f.color);
    if (f.textured) {
      // vignette : un échantillon d'environ 300 mm de la vraie texture
      canvas.save();
      final k = size.width / 300;
      canvas.scale(k);
      canvas.drawRect(Rect.fromLTWH(0, 0, 300, size.height / k), f.paint(vertical: f.id.startsWith('chene') || f.id == 'noyer'));
      canvas.restore();
      if (f.gloss) {
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)],
            ).createShader(Offset.zero & size),
        );
      }
      return;
    }
    final g = f.grain;
    if (g == null) return;
    final p = Paint()
      ..color = g
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 9; i++) {
      final y = size.height * (i + 0.5) / 9;
      final path = Path()..moveTo(0, y);
      path.cubicTo(size.width * 0.3, y - 4 + (i % 3) * 2, size.width * 0.6, y + 5 - (i % 2) * 3, size.width, y + 1);
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _GrainPainter o) => o.f != f || o.f.textured != f.textured;
}

class _ChoiceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceRow({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tokens.radius),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Tokens.radius),
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: Tokens.s3),
            Expanded(child: Text(label)),
            if (selected) Icon(Icons.check_circle, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

// ================================================================== fiche de l'élément sélectionné

class InspectorCard extends StatelessWidget {
  final AppState state;
  final void Function(String) onMessage;
  const InspectorCard({super.key, required this.state, required this.onMessage});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = state.selectedPointObj != null
        ? _PointForm(state: state, x: state.selectedPointObj!)
        : state.selectedOpeningObj != null
        ? _OpeningForm(state: state, o: state.selectedOpeningObj!)
        : _CabinetForm(state: state, item: state.selectedItem!, onMessage: onMessage);
    return Material(
      color: scheme.surface,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(Tokens.radius),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 380,
        child: SingleChildScrollView(padding: const EdgeInsets.all(Tokens.s4), child: child),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section(this.title, this.children);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Tokens.s4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr(title), style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: Tokens.s2),
        ...children,
      ],
    ),
  );
}

Widget _header(BuildContext context, String title, String sub, VoidCallback onClose) {
  final t = Theme.of(context).textTheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          IconButton(tooltip: tr('Fermer (Échap)'), icon: const Icon(Icons.close), onPressed: onClose),
        ],
      ),
      Text(sub, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: Tokens.s4),
    ],
  );
}

Widget _wallPicker(AppState state, String current, void Function(String) on, {bool onlyEnabled = true}) => KxChoices<String>(
  showSelectedIcon: false,
  segments: [
    for (final w in [
      ...[...state.project.room.walls]..sort((a, b) => a.id.compareTo(b.id)),
      if (state.project.room.island != null) state.project.room.wall('I'),
    ])
      ButtonSegment(
        value: w.id,
        label: Text(w.id == 'I' ? tr('Îlot') : w.id),
        tooltip: Room.wallNames[w.id],
        enabled: (!onlyEnabled || w.enabled) && (w.id == 'I' || w.orthogonal),
      ),
  ],
  selected: {current},
  onSelectionChanged: (v) => on(v.first),
);

class _CabinetForm extends StatelessWidget {
  final AppState state;
  final PlacedCabinet item;
  final void Function(String) onMessage;
  const _CabinetForm({required this.state, required this.item, required this.onMessage});

  void _resize({int? w, int? h}) {
    String? reason;
    state.edit(() {
      final r = state.engine.resize(item.uid, width: w, height: h);
      if (!r.moved) reason = r.reason;
      // lave-vaisselle / évier : l'appareil par défaut suit la nouvelle largeur
      final id = state.engine.modelOf(item).id;
      if (r.moved && w != null && (id == 'base_integrated_dishwasher_door' || id == 'base_sink')) item.appliances = null;
    });
    if (reason != null) onMessage(reason!);
  }

  @override
  Widget build(BuildContext context) {
    final m = state.engine.modelOf(item);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final canZ = state.engine.canMoveVertically(m);
    final corner = m.shape == CabinetShape.lShape || m.shape == CabinetShape.diagonal;
    final editable = state.step == PlanStep.layout;

    Widget chips(List<int> values, int current, void Function(int) on) => Wrap(
      spacing: Tokens.s2,
      runSpacing: Tokens.s2,
      children: [for (final v in values) ChoiceChip(label: Text('$v'), selected: v == current, onSelected: editable ? (_) => on(v) : null)],
    );

    Widget nudge(IconData icon, String tip, double ds, double dz) => IconButton.outlined(
      tooltip: tip,
      icon: Icon(icon),
      onPressed: () {
        final r = state.nudge(ds, dz);
        if (r != null) onMessage(r);
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, m.name, '${m.categoryName} · ${Room.wallNames[item.wallId]}', () => state.select(null)),
        if (editable)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s4),
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, Tokens.minTarget)),
              onPressed: () => showReplaceDialog(context, state, item, onMessage),
              icon: const Icon(Icons.swap_horiz),
              label: Text(tr('Remplacer par un autre article')),
            ),
          ),
        if (m.isCarcass || m.id == 'base_integrated_dishwasher_door')
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s4),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, Tokens.minTarget)),
              onPressed: () {
                if (state.view != ViewMode.view3d) state.setView(ViewMode.view3d);
                state.toggleOpen(item.uid);
              },
              icon: Icon(state.isOpen(item.uid) ? Icons.door_sliding_outlined : Icons.door_front_door_outlined),
              label: Text(state.isOpen(item.uid) ? tr('Fermer (3D)') : tr('Ouvrir en 3D')),
            ),
          ),
        if (machineSlots(item).isNotEmpty) _MachineSection(state: state, item: item, editable: editable || state.step == PlanStep.style),
        _Section('Largeur (mm)', [
          if (m.widths.isRange)
            _NumberField(
              value: item.width,
              min: m.widths.min!,
              max: m.widths.max!,
              onSubmit: (v) => _resize(w: v),
            )
          else
            chips(m.widths.values, item.width, (v) => _resize(w: v)),
          if (corner)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s2),
              child: Text(trp('Bras sur le mur {0} : {1} mm', [state.project.room.nextOf(item.wallId), item.widthRight]), style: t.bodySmall),
            ),
        ]),
        if (corner && (cornerSizes[m.id] ?? const []).isNotEmpty)
          _Section(m.shape == CabinetShape.blind ? 'Format d’angle (encombrement / retour)' : 'Format d’angle (mur 1 / mur 2)', [
            Wrap(
              spacing: Tokens.s2,
              runSpacing: Tokens.s2,
              children: [
                for (final sz in cornerSizes[m.id]!)
                  ChoiceChip(
                    label: Text('${sz.code}${sz.carcass != null ? ' · caisson ${sz.carcass}' : ''}'),
                    selected: sz.carcass != null ? item.width == sz.carcass : (item.width == sz.w1 && item.widthRight == sz.w2),
                    onSelected: editable
                        ? (_) {
                            final err = state.setCornerSize(item.uid, sz);
                            if (err != null) onMessage(err);
                          }
                        : null,
                  ),
              ],
            ),
          ]),
        if (m.heights.values.length > 1) _Section('Hauteur (mm)', [chips(m.heights.values, item.height, (v) => _resize(h: v))]),
        if (m.hasDoors || m.openingOptions.isNotEmpty || (m.isCarcass && !m.kind.isCorner && item.width <= 700))
          _Section('Sens d’ouverture', [
            KxChoices<String>(
              segments: [
                ButtonSegment(value: 'hinged_left', label: Text(tr('Charnières à gauche')), icon: const Icon(Icons.arrow_back, size: 16)),
                ButtonSegment(value: 'hinged_right', label: Text(tr('Charnières à droite')), icon: const Icon(Icons.arrow_forward, size: 16)),
              ],
              selected: {item.opening == 'hinged_right' ? 'hinged_right' : 'hinged_left'},
              onSelectionChanged: editable ? (s) => state.edit(() => item.opening = s.first) : null,
            ),
          ]),
        if (state.engine.canHaveCheeks(m))
          _Section('Joues (costados)', [
            for (final left in [true, false])
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.s2),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(left ? 'Côté gauche' : 'Côté droit'), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  KxChoices<String>(
                    key: ValueKey('cheek_${left ? 'l' : 'r'}'),
                    segments: [
                      ButtonSegment(value: 'auto', label: Text(tr('Automatique'))),
                      ButtonSegment(value: 'oui', label: Text(tr('Avec joue'))),
                      ButtonSegment(value: 'non', label: Text(tr('Sans joue'))),
                    ],
                    selected: {item.hasCheek(left) ? 'oui' : (item.cheek(left) ?? 'auto')},
                    onSelectionChanged: editable
                        ? (v) {
                            final msg = state.setCheek(item.uid, left, v.first == 'auto' ? null : v.first == 'oui');
                            if (msg != null) onMessage(msg);
                          }
                        : null,
                  ),
                ]),
              ),
            Text(tr('Panneau de 18 mm dans la finition des façades, au débit et au devis. Automatique : posée si le côté finit un linéaire.'), style: t.bodySmall),
          ]),
        if (m.variants.length > 1)
          _Section('Variante', [
            Wrap(
              spacing: Tokens.s2,
              runSpacing: Tokens.s2,
              children: [
                for (final o in m.variants)
                  ChoiceChip(label: Text(optionLabel(o)), selected: item.variant == o, onSelected: editable ? (_) => state.edit(() => item.variant = o) : null),
              ],
            ),
          ]),
        if (m.kind.isLow && m.isCarcass && !m.kind.isCorner && state.engine.kitchen)
          _Section('Équipement du plan', [
            Wrap(
              spacing: Tokens.s2,
              runSpacing: Tokens.s2,
              children: [
                FilterChip(
                  avatar: const Icon(Icons.water_drop_outlined, size: 16),
                  label: Text(tr('Évier & Robinet')),
                  selected: item.appliances?.any((a) => a.contains('sink')) ?? (m.id.contains('sink') || state.engine.isWashing(m)),
                  onSelected: editable
                      ? (active) {
                          state.edit(() {
                            final current = [...(item.appliances ?? defaultAppliances(m, item))];
                            current.removeWhere((a) => a.contains('sink'));
                            if (active) current.add('sink_1_bowl_drainer');
                            item.appliances = current;
                          });
                        }
                      : null,
                ),
                FilterChip(
                  avatar: const Icon(Icons.microwave_outlined, size: 16),
                  label: Text(tr('Plaque de cuisson')),
                  selected: item.appliances?.any((a) => a.contains('cooktop')) ?? (m.id.contains('cooktop') || state.engine.isCooking(m)),
                  onSelected: editable
                      ? (active) {
                          state.edit(() {
                            final current = [...(item.appliances ?? defaultAppliances(m, item))];
                            current.removeWhere((a) => a.contains('cooktop'));
                            if (active) current.add('cooktop_4_burners_60');
                            item.appliances = current;
                          });
                        }
                      : null,
                ),
              ],
            ),
          ]),
        if (state.db != null && appliancesOf(m, item).isNotEmpty)
          _ApplianceSection(state: state, item: item, model: m, editable: editable, onMessage: onMessage),
        if (m.isCarcass && !m.kind.isCorner && (m.kind.isLow || m.kind.isHigh || m.kind == CabinetKind.tall) && (editable || state.step == PlanStep.style))
          _FrontLayoutEditor(state: state, item: item, model: m),
        _ItemFrontSection(state: state, item: item),
        if (editable) ...[
          _Section('Mur', [
            _wallPicker(state, item.wallId, (w) {
              String? reason;
              state.edit(() {
                final r = state.engine.move(item.uid, wallId: w, s: item.s);
                if (!r.moved) reason = r.reason;
              });
              if (reason != null) {
                onMessage(reason!);
              } else {
                state.setWall(w);
              }
            }),
          ]),
          _Section('Position (mm)', [
            if (!corner)
              Builder(
                builder: (_) {
                  final (gl, gr) = state.engine.neighbourGaps(item.uid);
                  void apply(double v, bool right) {
                    String? reason;
                    state.edit(() {
                      final r = state.engine.setNeighbourGap(item.uid, v, fromRight: right);
                      if (!r.moved) reason = r.reason;
                    });
                    if (reason != null) onMessage(reason!);
                  }

                  return Wrap(
                    spacing: Tokens.s3,
                    runSpacing: Tokens.s3,
                    children: [
                      _MmBox(label: tr('Écart à gauche'), value: gl, min: 0, max: 20000, onSubmit: (v) => apply(v, false)),
                      _MmBox(label: tr('Écart à droite'), value: gr, min: 0, max: 20000, onSubmit: (v) => apply(v, true)),
                      if (canZ)
                        _MmBox(
                          label: tr('Hauteur du bas'),
                          value: item.z,
                          min: 0,
                          max: state.project.room.height,
                          onSubmit: (v) => state.edit(() => state.engine.move(item.uid, z: v)),
                        ),
                    ],
                  );
                },
              ),
            const SizedBox(height: Tokens.s2),
            Text(trp('{0} mm depuis la gauche du mur · bas à {1} mm', [item.s.round(), item.z.round()]), style: t.bodySmall),
            const SizedBox(height: Tokens.s2),
            if (!corner)
              Wrap(
                spacing: Tokens.s2,
                runSpacing: Tokens.s2,
                children: [
                  nudge(Icons.keyboard_double_arrow_left, 'Gauche 100 mm (Maj + ←)', -100, 0),
                  nudge(Icons.chevron_left, 'Gauche 10 mm (←)', -10, 0),
                  nudge(Icons.chevron_right, 'Droite 10 mm (→)', 10, 0),
                  nudge(Icons.keyboard_double_arrow_right, 'Droite 100 mm (Maj + →)', 100, 0),
                  if (canZ) ...[nudge(Icons.expand_less, 'Monter 10 mm (↑)', 0, 10), nudge(Icons.expand_more, 'Descendre 10 mm (↓)', 0, -10)],
                ],
              ),
          ]),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, Tokens.minTarget)),
            onPressed: () {
              final err = state.duplicateSelected();
              onMessage(err ?? tr('Élément dupliqué'));
            },
            icon: const Icon(Icons.copy_all_outlined),
            label: Text(tr('Dupliquer (Ctrl+D)')),
          ),
          const SizedBox(height: Tokens.s2),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(foregroundColor: scheme.error, minimumSize: const Size(double.infinity, Tokens.minTarget)),
            onPressed: state.deleteSelected,
            icon: const Icon(Icons.delete_outline),
            label: Text(tr('Supprimer (Suppr)')),
          ),
        ] else
          Text(tr('Modifiable à l\'étape « Implantation ».'), style: t.bodySmall),
      ],
    );
  }
}

class _OpeningForm extends StatelessWidget {
  final AppState state;
  final Opening o;
  const _OpeningForm({required this.state, required this.o});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wallLen = state.project.room.wall(o.wallId).length;
    void move({String? wall, double? s, double? width, double? height, double? z}) =>
        state.edit(() => state.engine.moveOpening(o.uid, wallId: wall, s: s, width: width, height: height, z: z));
    final m = openingModelOf(o);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, openingName(o), Room.wallNames[o.wallId]!, () => state.selectOpening(null)),
        Row(
          children: [
            SizedBox(width: 64, height: 84, child: m == null ? null : CustomPaint(painter: OpeningThumb(m))),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (m != null) Text('${m.mechanismLabel} · ${m.style}', style: t.bodySmall),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: () => showOpeningPicker(context, state, (_) {}, replace: o),
                    icon: Icon(Icons.swap_horiz),
                    label: Text(tr('Changer de modèle')),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (m != null && m.widths.isNotEmpty)
          _Section('Largeurs standard', [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final w in m.widths)
                  ChoiceChip(
                    label: Text('$w'),
                    selected: o.width.round() == w,
                    onSelected: (_) => move(width: w.toDouble()),
                  ),
              ],
            ),
          ]),
        if (m != null && m.heights.length > 1)
          _Section('Hauteurs standard', [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final h in m.heights)
                  ChoiceChip(
                    label: Text('$h'),
                    selected: o.height.round() == h,
                    onSelected: (_) => move(height: h.toDouble()),
                  ),
              ],
            ),
          ]),
        if (m == null || m.hinged && !m.twoLeaves || m.sliding || m.pivot)
          _Section(m != null && m.sliding ? 'Coulisse vers' : 'Charnières', [
            KxChoices<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'left', label: Text(tr('Gauche'))),
                ButtonSegment(value: 'right', label: Text(tr('Droite'))),
              ],
              selected: {o.hinge},
              onSelectionChanged: (v) => state.setOpeningHinge(o.uid, v.first),
            ),
          ]),
        _Section('Mur', [_wallPicker(state, o.wallId, (w) => move(wall: w), onlyEnabled: false)]),
        _Section('Dimensions et position (mm)', [
          Wrap(
            spacing: Tokens.s3,
            runSpacing: Tokens.s3,
            children: [
              _MmBox(
                label: tr('Largeur'),
                value: o.width,
                min: 300,
                max: wallLen,
                onSubmit: (v) => move(width: v),
              ),
              _MmBox(
                label: tr('Hauteur'),
                value: o.height,
                min: 300,
                max: state.project.room.height,
                onSubmit: (v) => move(height: v),
              ),
              _MmBox(
                label: tr('Depuis la gauche'),
                value: o.s,
                min: 0,
                max: wallLen,
                onSubmit: (v) => move(s: v),
              ),
              if (!o.isDoor)
                _MmBox(
                  label: tr('Allège'),
                  value: o.z,
                  min: 0,
                  max: 2000,
                  onSubmit: (v) => move(z: v),
                ),
            ],
          ),
        ]),
        if (m != null && (m.composition.isNotEmpty || m.hardware.isNotEmpty))
          _Section('Composition et quincaillerie', [
            for (final e in m.composition.entries)
              Text(
                '${const {'frame': 'Cadre', 'core': 'Âme', 'finish': 'Finition', 'profile': 'Profilé', 'glazing': 'Vitrage'}[e.key] ?? e.key} : ${e.value}',
                style: t.bodySmall,
              ),
            if (m.hardware.isNotEmpty) Text(trp('Quincaillerie : {0}', [m.hardware.join(', ')]), style: t.bodySmall),
          ]),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(foregroundColor: scheme.error, minimumSize: const Size(double.infinity, Tokens.minTarget)),
          onPressed: state.deleteSelected,
          icon: const Icon(Icons.delete_outline),
          label: Text(tr('Supprimer (Suppr)')),
        ),
      ],
    );
  }
}

class _MmBox extends StatefulWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onSubmit;
  const _MmBox({required this.label, required this.value, required this.min, required this.max, required this.onSubmit});
  @override
  State<_MmBox> createState() => _MmBoxState();
}

class _MmBoxState extends State<_MmBox> {
  late final c = TextEditingController(text: lenValue(widget.value));
  String? error;
  @override
  void didUpdateWidget(covariant _MmBox old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) c.text = lenValue(widget.value);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 140,
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.allow(lenInputPattern)],
      decoration: InputDecoration(labelText: widget.label, suffixText: lenSuffix, isDense: true, border: const OutlineInputBorder(), errorText: error),
      onSubmitted: (s) {
        final v = editedLen(s, widget.value)?.roundToDouble();
        if (v == null || v < widget.min || v > widget.max) {
          setState(() => error = lenRange(widget.min, widget.max));
          return;
        }
        setState(() => error = null);
        widget.onSubmit(v);
      },
    ),
  );
}

class _NumberField extends StatefulWidget {
  final int value, min, max;
  final void Function(int) onSubmit;
  const _NumberField({required this.value, required this.min, required this.max, required this.onSubmit});
  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final c = TextEditingController(text: lenValue(widget.value));
  String? error;

  @override
  void didUpdateWidget(covariant _NumberField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) c.text = lenValue(widget.value);
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: c,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.allow(lenInputPattern)],
    decoration: InputDecoration(
      border: const OutlineInputBorder(),
      isDense: true,
      suffixText: lenSuffix,
      helperText: trf('{plage}, Entrée pour valider', {'plage': lenRange(widget.min, widget.max)}),
      errorText: error,
    ),
    onSubmitted: (s) {
      final v = editedLen(s, widget.value)?.round();
      if (v == null || v < widget.min || v > widget.max) {
        setState(() => error = lenRange(widget.min, widget.max));
        return;
      }
      setState(() => error = null);
      widget.onSubmit(v);
    },
  );
}

// ================================================================== contrôles

class IssuesList extends StatelessWidget {
  final AppState state;
  final VoidCallback? onPick;
  const IssuesList({super.key, required this.state, this.onPick});

  @override
  Widget build(BuildContext context) {
    final issues = state.issues..sort((a, b) => a.severity.index.compareTo(b.severity.index));
    final scheme = Theme.of(context).colorScheme;
    (IconData, Color, String) look(Severity s) => switch (s) {
      Severity.error => (Icons.error_outline, scheme.error, 'Erreur'),
      Severity.warning => (Icons.warning_amber_rounded, scheme.tertiary, 'À vérifier'),
      Severity.info => (Icons.info_outline, scheme.primary, 'Info'),
    };
    if (issues.isEmpty) {
      return ListTile(
        leading: Icon(Icons.check_circle_outline, color: scheme.primary),
        title: Text(tr('Aucun problème détecté')),
      );
    }
    final fixable = issues.where((i) => i.severity != Severity.info && fixFor(state.engine, i, db: state.db).apply != null).length;
    void say(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));
    return Column(
      children: [
        if (fixable > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s3),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, Tokens.minTarget)),
              onPressed: () {
                final n = state.fixAll();
                say(n == 0 ? tr('Aucune correction automatique possible') : trp('{0} correction(s) appliquée(s)', [n]));
              },
              icon: const Icon(Icons.auto_fix_high),
              label: Text(trp('Tout corriger ({0})', [fixable])),
            ),
          ),
        for (final i in issues)
          Builder(
            builder: (context) {
              final (icon, color, word) = look(i.severity);
              final fix = fixFor(state.engine, i, db: state.db);
              return ListTile(
                dense: true,
                leading: Icon(icon, color: color, semanticLabel: word),
                title: Text(i.message),
                subtitle: i.severity == Severity.info && fix.apply == null ? null : Text(fix.hint, style: Theme.of(context).textTheme.bodySmall),
                trailing: fix.apply == null ? null : TextButton(onPressed: () => say(state.applyFix(i)), child: Text(tr(fix.label ?? tr('Corriger')))),
                onTap: i.uids.isEmpty
                    ? null
                    : () {
                        final u = i.uids.first;
                        if (state.project.byUid(u) != null) {
                          if (state.step != PlanStep.layout) state.goTo(PlanStep.layout);
                          state.select(u);
                        } else {
                          state.goTo(PlanStep.space);
                          state.selectOpening(u);
                        }
                        onPick?.call();
                      },
              );
            },
          ),
      ],
    );
  }
}

// ================================================================== récapitulatif

class SummaryPanel extends StatelessWidget {
  final AppState state;
  const SummaryPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final bom = state.bom;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = state.project;
    final style = p.style;
    String m(double mm) => '${(mm / 1000).toStringAsFixed(2).replaceAll('.', ',')} m';

    final sections = <String, List<BomLine>>{};
    for (final l in bom.lines) {
      sections.putIfAbsent(l.section, () => []).add(l);
    }

    Widget stat(String value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(Tokens.s3),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(Tokens.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(tr(label), style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );

    return _PanelFrame(
      title: 'Récapitulatif · ${p.name}',
      child: ListView(
        children: [
          // cartes d'une même rangée : toujours la même hauteur
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              stat('${bom.cabinetCount}', 'caissons'),
              const SizedBox(width: Tokens.s2),
              stat(m(bom.worktopLength), 'plan de travail'),
              const SizedBox(width: Tokens.s2),
              stat(m(bom.plinthLength), 'plinthes'),
            ]),
          ),
          const SizedBox(height: Tokens.s2),
          Builder(
            builder: (_) {
              final plan = state.cutPlan; // en cache, calculé en arrière-plan
              final pct = plan.sheets.isEmpty
                  ? 0
                  : 100 * plan.sheets.fold<int>(0, (a, s) => a + s.partsArea) / plan.sheets.fold<int>(0, (a, s) => a + s.length * s.width);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      stat('${plan.partCount}', 'pièces à débiter'),
                      const SizedBox(width: Tokens.s2),
                      stat('${plan.newSheets().length}', trp('panneaux {0}', [{for (final s in plan.newSheets()) '${s.length.round()}×${s.width.round()}'}.join(' · ')])),
                      const SizedBox(width: Tokens.s2),
                      stat('${pct.toStringAsFixed(0)} %', 'utilisation'),
                    ]),
                  ),
                  if (plan.stockSheets().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.recycling, size: 18, color: scheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            trp('+ {0} chute(s) du stock : {1}', [plan.stockSheets().length, plan.stockSheets().map((s) => s.stockId).join(', ')]),
                            style: t.bodySmall),
                      ),
                    ]),
                  ],
                  if (p.cut.stockFrozen != null) ...[
                    const SizedBox(height: 6),
                    Text(tr('Découpe validée : le plan est figé.'), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                  // optimisation en arrière-plan : l'écran reste utilisable, les chiffres se mettent à jour à la fin
                  if (state.cutPending) ...[
                    const SizedBox(height: 6),
                    const LinearProgressIndicator(minHeight: 3),
                    const SizedBox(height: 4),
                    Text(tr('Optimisation du débit en cours…'), style: t.labelSmall),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: Tokens.s3),
          if (state.engine.kitchen) Text(trp('Cuisine {0} · {1}', [state.engine.layoutShape(), _triangleText(state.engine)]), style: t.bodySmall),
          Text(
            trp('Pièce {0} × {1} × {2} mm · {3} · {4} ouverture(s)', [
              p.room.width.round(),
              p.room.depth.round(),
              p.room.height.round(),
              p.shape?.label ?? 'forme libre',
              p.openings.length,
            ]),
            style: t.bodySmall,
          ),
          Text(
            trp('Façades {0} · plan {1} · {2}', [
              tr(frontFinish(style, style.front).name),
              tr(worktopFinish(style, style.worktop).name),
              handleName(style, state.db?.handles),
            ]),
            style: t.bodySmall,
          ),
          const SizedBox(height: Tokens.s4),
          if (bom.lines.isEmpty) Text(tr('Aucun élément posé pour l\'instant.'), style: t.bodyMedium),
          for (final e in sections.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s3, bottom: Tokens.s1),
              child: Text(
                e.key,
                style: t.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800),
              ),
            ),
            for (final l in e.value)
              Container(
                padding: const EdgeInsets.symmetric(vertical: Tokens.s2),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(l.unit == 'pce' ? trp('{0}×', [l.qty]) : '', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(l.name), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          Text([l.dims, if (l.details.isNotEmpty) l.details].join(' · '), style: t.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (state.db != null && state.supplier != null) ...[
            SizedBox(height: Tokens.s4),
            KxChoices<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'standard', label: Text(tr('Standard · MDF')), icon: Icon(Icons.view_module_outlined)),
                if (MediaProgetti.instance != null) ButtonSegment(value: 'moyen', label: Text(tr('Moyenne · Alvic')), icon: const Icon(Icons.kitchen_outlined)),
                ButtonSegment(value: 'luxe', label: Text(tr('Luxe · latté')), icon: Icon(Icons.diamond_outlined)),
              ],
              selected: {state.project.specs.gamme},
              onSelectionChanged: (v) => state.setGamme(v.first),
            ),
            const SizedBox(height: Tokens.s1),
            Text(
              state.project.specs.gamme == 'luxe'
                  ? tr('Caissons en contreplaqué latté et façades MDF facturés à l’article (caisson, porte, joue, tiroir).')
                  : state.project.specs.gamme == 'moyen'
                  ? tr('Caissons blancs Alvic et portes MDF 19 super mat, facturés à l’article.')
                  : tr('Caissons et façades en MDF, chiffrés à la feuille : panneaux, chants et découpe au tarif de l’atelier.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (state.project.specs.gamme == 'moyen') ...[const SizedBox(height: Tokens.s2), MediaProgettiChoices(state: state)],
          ],
          if (state.db != null) _SupplySections(state: state),
          if (state.db != null) ...[
            const SizedBox(height: Tokens.s3),
            FilledButton.icon(
              key: const ValueKey('open_quote'),
              onPressed: () => showQuoteDialog(context, state, (m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)))),
              icon: const Icon(Icons.request_quote_outlined),
              label: Text(
                state.quoteValidated
                    ? trp('Devis validé · {0} MAD TTC', [money(state.quote.total)])
                    : trp('Devis final · {0} MAD TTC', [money(state.quote.total)]),
              ),
            ),
          ],
          if (state.supplierEstimate != null && state.project.specs.gamme == 'standard') _SupplierCompare(state: state),
          const SizedBox(height: Tokens.s5),
          Text(tr('Contrôles'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          IssuesList(state: state),
        ],
      ),
    );
  }
}

String _triangleText(LayoutEngine e) {
  final legs = e.triangleLegs();
  if (legs == null) return 'triangle d\'activité incomplet (évier, plaque, froid)';
  final (a, b, c) = legs;
  return 'triangle ${a.round()} + ${b.round()} + ${c.round()} = ${(a + b + c).round()} mm';
}

// ================================================================== matériaux (bases du catalogue)

String _mad(PriceRange p) => p.min == p.max ? '${p.min.round()} MAD' : '${p.min.round()} – ${p.max.round()} MAD';

/// Crédence : comme les murs, dans la matière du plan (toute la hauteur ou relevé de 10 cm).
class _SplashChoices extends StatelessWidget {
  final AppState state;
  const _SplashChoices({required this.state});
  @override
  Widget build(BuildContext context) {
    final cur = state.project.style.splash;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      ChoiceChip(label: Text(tr('Comme les murs')), selected: cur == null, onSelected: (_) => state.setRoomFinish(clearSplash: true)),
      ChoiceChip(
          key: const ValueKey('splash_plan'),
          avatar: const Icon(Icons.countertops_outlined, size: 18),
          label: Text(tr('Comme le plan de travail')),
          selected: cur == splashLikeTop,
          onSelected: (_) => state.setRoomFinish(splash: splashLikeTop)),
      ChoiceChip(key: const ValueKey('splash_plan_10'), label: Text(tr('Relevé 10 cm, comme le plan')), selected: cur == splashUpstand, onSelected: (_) => state.setRoomFinish(splash: splashUpstand)),
    ]);
  }
}

/// Plan de travail : matière, puis ses coloris (rendu et prix ensemble), puis son épaisseur.
class _WorktopMaterialForm extends StatelessWidget {
  final AppState state;
  const _WorktopMaterialForm({required this.state});

  @override
  Widget build(BuildContext context) {
    final db = state.db!;
    final p = state.project;
    final sp = p.specs, st = p.style;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final (matId, variant) = worktopOf(p);
    final mat = db.worktop(matId) ?? db.worktops.first;
    final custom = worktopFinishes(st).where((f) => f.id.startsWith('tex:')).toList();
    final own = !worktopLooks.containsKey(st.worktop); // photo importée
    final v = mat.variants.isEmpty ? null : mat.variants[variant.clamp(0, mat.variants.length - 1)];
    final th = mat.thicknesses.isEmpty || mat.thicknesses.contains(sp.worktopThickness) ? sp.worktopThickness : mat.thicknesses.last;
    Widget title(String s) => Padding(
        padding: const EdgeInsets.only(top: Tokens.s3, bottom: Tokens.s2), child: Text(tr(s), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)));
    // « Chaleur : Moyenne… » : les deux moitiés se traduisent séparément
    String note(String n) {
      final k = n.indexOf(' : ');
      return k < 0 ? tr(n) : '${tr(n.substring(0, k))} : ${tr(n.substring(k + 3))}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      title('1. Matière'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final w in db.worktops)
          ChoiceChip(
            key: ValueKey('wt_${w.id}'),
            label: Text(tr(_short(w.name))),
            selected: w.id == mat.id,
            onSelected: (_) => state.setWorktopMaterial(w.id),
          ),
      ]),
      title('2. Coloris'),
      Wrap(spacing: Tokens.s3, runSpacing: Tokens.s3, children: [
        for (final id in looksOf(mat.id))
          _Swatch(key: ValueKey('look_$id'), finish: finishById(worktops, id), selected: st.worktop == id, onTap: () => state.setStyle(worktop: id)),
      ]),
      if (custom.isNotEmpty) ...[
        title('Vos photos'),
        Wrap(spacing: Tokens.s3, runSpacing: Tokens.s3, children: [for (final f in custom) _Swatch(finish: f, selected: st.worktop == f.id, onTap: () => state.setStyle(worktop: f.id))]),
        if (own) Text(tr('Photo importée : le prix est celui de la matière choisie ci-dessus.'), style: t.bodySmall),
      ],
      if (mat.thicknesses.isNotEmpty) ...[
        title('3. Épaisseur'),
        Wrap(spacing: Tokens.s2, children: [
          for (final x in mat.thicknesses)
            ChoiceChip(label: Text(trp('{0} mm', [x])), selected: th == x, onSelected: (_) => state.edit(() => sp.worktopThickness = x)),
        ]),
      ],
      title('Plinthes'),
      KxChoices<String>(
        key: const ValueKey('plinth_mode'),
        segments: [
          ButtonSegment(value: 'facade', label: Text(tr('Comme les façades'))),
          ButtonSegment(value: 'plan', label: Text(tr('Comme le plan de travail'))),
          ButtonSegment(value: 'autre', label: Text(tr('Autre matière'))),
        ],
        selected: {st.plinth == null ? 'facade' : (st.plinth == 'plan' ? 'plan' : 'autre')},
        onSelectionChanged: (v) => state.edit(() => st.plinth = switch (v.first) { 'facade' => null, 'plan' => 'plan', _ => st.plinth != null && st.plinth != 'plan' ? st.plinth : 'alu' }),
      ),
      if (st.plinth != null && st.plinth != 'plan') ...[
        const SizedBox(height: Tokens.s2),
        Wrap(spacing: Tokens.s3, runSpacing: Tokens.s3, children: [
          for (final f in plinthPlain) _Swatch(key: ValueKey('plinth_${f.id}'), finish: f, selected: st.plinth == f.id, onTap: () => state.edit(() => st.plinth = f.id)),
          for (final f in frontFinishes(st)) _Swatch(key: ValueKey('plinth_f_${f.id}'), finish: f, selected: st.plinth == 'f:${f.id}', onTap: () => state.edit(() => st.plinth = 'f:${f.id}')),
        ]),
      ],
      if (p.room.island != null) ...[
        title('Plan de l’îlot'),
        KxChoices<bool>(
          key: const ValueKey('island_top_mode'),
          segments: [ButtonSegment(value: false, label: Text(tr('Comme les autres'))), ButtonSegment(value: true, label: Text(tr('Son propre plan')))],
          selected: {st.islandTop != null},
          onSelectionChanged: (v) => state.edit(() => st.islandTop = v.first ? (worktopLooks.containsKey(st.worktop) ? st.worktop : 'marbre') : null),
        ),
        if (st.islandTop != null) ...[
          const SizedBox(height: Tokens.s2),
          Wrap(spacing: Tokens.s3, runSpacing: Tokens.s3, children: [for (final f in worktops) _Swatch(key: ValueKey('isl_${f.id}'), finish: f, selected: f.id == st.islandTop, onTap: () => state.edit(() => st.islandTop = f.id))]),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(tr('Plan en cascade (jambages jusqu’au sol)')),
          value: st.islandWaterfall,
          onChanged: (v) => state.edit(() => st.islandWaterfall = v),
        ),
      ],
      if (state.engine.kitchen) ...[
        title('4. Crédence'),
        _SplashChoices(state: state),
        if (!splashMatchesTop(st)) Text(tr('Autres crédences (carreaux, zellige…) : « Sol et murs ».'), style: t.bodySmall),
      ],
      const SizedBox(height: Tokens.s3),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Tokens.s3),
        decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(Tokens.radius)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${tr(worktopFinish(st, st.worktop).name)} · ${trp('{0} mm', [th])}', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          if (v != null) Text(tr(v.label), style: t.bodySmall),
          if (splashMatchesTop(st)) Text(trp(st.splash == splashUpstand ? 'Relevé de 10 cm assorti : {0} m²' : 'Crédence assortie : {0} m²', [splashArea(state.engine).toStringAsFixed(2)]), style: t.bodySmall),
          const SizedBox(height: 4),
          Text(v == null || v.price.isZero ? tr('Prix à demander') : trp('{0} le mètre linéaire', [_mad(v.price)]), style: t.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800)),
        ]),
      ),
      const SizedBox(height: Tokens.s2),
      for (final n in mat.notes) Text(note(n), style: t.bodySmall),
      if (mat.edgeProfiles.isNotEmpty) Text(trp('Chants : {0}', [mat.edgeProfiles.map(tr).join(', ')]), style: t.bodySmall),
      Text(trp('La hauteur du plan reste à {0} mm (norme).', [p.standards.worktopTop]), style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
    ]);
  }

  /// « Granit Naturel (Zellijj Granit) » → « Granit Naturel ».
  static String _short(String name) => name.split(' (').first.split(' & ').first;
}

/// Machines logées dans un meuble de buanderie : type et capacité de chacune.
class _MachineSection extends StatelessWidget {
  final AppState state;
  final PlacedCabinet item;
  final bool editable;
  const _MachineSection({required this.state, required this.item, required this.editable});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final slots = machineSlots(item);
    final now = [for (var i = 0; i < slots.length; i++) item.machines != null && i < item.machines!.length ? item.machines![i] : slots[i].def];
    void set(int i, String key) => state.edit(() {
          final l = [...now];
          l[i] = key;
          item.machines = l;
        });
    return _Section('Machines', [
      for (var i = 0; i < slots.length; i++)
        () {
          final (f, v) = machineOf(now[i]) ?? machineOf(slots[i].def)!;
          final all = machinesFor(slots[i]);
          final caps = all.where((x) => x.$1.id == f.id).firstOrNull?.$2 ?? [v];
          return Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<String>(
                key: ValueKey('${item.uid}-machine$i-${f.id}'),
                isExpanded: true,
                initialValue: f.id,
                decoration: InputDecoration(border: const OutlineInputBorder(), isDense: true, labelText: tr(slots[i].name)),
                items: [
                  if (!all.any((x) => x.$1.id == f.id)) DropdownMenuItem(value: f.id, child: Text(tr(f.name))),
                  for (final (q, _) in all) DropdownMenuItem(value: q.id, child: Text(tr(q.name))),
                ],
                onChanged: editable
                    ? (id) {
                        final ok = all.firstWhere((x) => x.$1.id == id).$2;
                        final keep = ok.where((x) => x.label == v.label).firstOrNull ?? (ok.contains(fixtureById(id!)!.defaultVariant) ? fixtureById(id)!.defaultVariant! : ok.last);
                        set(i, '$id|${keep.label}');
                      }
                    : null,
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final q in caps)
                  ChoiceChip(
                    key: ValueKey('machine$i-${q.label}'),
                    label: Text(tr(q.label)),
                    selected: q.label == v.label,
                    onSelected: editable ? (_) => set(i, '${f.id}|${q.label}') : null,
                  ),
              ]),
              const SizedBox(height: 4),
              Text(trp('{0} × {1} × H{2} mm', [v.w, v.d, v.h]), style: t.bodySmall),
            ]),
          );
        }(),
    ]);
  }
}

class _ApplianceSection extends StatelessWidget {
  final AppState state;
  final PlacedCabinet item;
  final CabinetModel model;
  final bool editable;
  final void Function(String) onMessage;
  const _ApplianceSection({required this.state, required this.item, required this.model, required this.editable, required this.onMessage});

  @override
  Widget build(BuildContext context) {
    final db = state.db!;
    final t = Theme.of(context).textTheme;
    final ids = appliancesOf(model, item);
    final hasSink = ids.any((a) => a.contains('sink')) || (item.appliances?.any((a) => a.contains('sink')) ?? false) || model.id.contains('sink');
    final hasOven = ids.any((a) => a.contains('oven')) || (item.appliances?.any((a) => a.contains('oven')) ?? false) || model.id.contains('oven');
    final st = state.project.style;
    final styleEditable = editable || state.step == PlanStep.style;

    return _Section('Électroménager', [
      for (var i = 0; i < ids.length; i++)
        if (db.appliances[ids[i]] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey('${item.uid}-app$i-${ids[i]}'),
                  isExpanded: true,
                  itemHeight: null, // noms entiers, sur deux lignes si besoin
                  initialValue: ids[i],
                  selectedItemBuilder: (_) => [for (final a in db.ofCategory(db.appliances[ids[i]]!.category)) Text(tr(a.name), maxLines: 2, overflow: TextOverflow.ellipsis)],
                  decoration: InputDecoration(border: const OutlineInputBorder(), isDense: true, labelText: tr(db.appliances[ids[i]]!.categoryName)),
                  items: [
                    for (final a in db.ofCategory(db.appliances[ids[i]]!.category))
                      DropdownMenuItem(
                        value: a.id,
                        child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(tr(a.name))),
                      ),
                  ],
                  onChanged: editable
                      ? (v) {
                          final msg = state.setAppliance(item.uid, i, v!);
                          if (msg != null) onMessage(msg);
                        }
                      : null,
                ),
                const SizedBox(height: 4),
                Text(db.appliances[ids[i]]!.dimsText, style: t.bodySmall),
                if (db.appliances[ids[i]]!.ventilationGap != null)
                  Text(trp('Ventilation arrière : {0} mm', [db.appliances[ids[i]]!.ventilationGap]), style: t.bodySmall),
                if (db.appliances[ids[i]]!.cutoutNote != null) Text(db.appliances[ids[i]]!.cutoutNote!, style: t.bodySmall),
              ],
            ),
          ),
      if (hasSink) ...[
        const Divider(height: Tokens.s4),
        Text(tr('Style Évier & Robinetterie'), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: Tokens.s2),
        Text(tr('Finition de l’évier'), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: Tokens.s1),
        KxChoices<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'inox', label: Text(tr('Inox'))),
            ButtonSegment(value: 'noir_quartz', label: Text(tr('Noir quartz'))),
            ButtonSegment(value: 'blanc_ceramique', label: Text(tr('Blanc'))),
          ],
          selected: {st.sinkFinish},
          onSelectionChanged: styleEditable ? (v) => state.edit(() => st.sinkFinish = v.first) : null,
        ),
        const SizedBox(height: Tokens.s3),
        Text(tr('Finition de la robinetterie'), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: Tokens.s1),
        KxChoices<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'chrome', label: Text(tr('Chrome'))),
            ButtonSegment(value: 'noir_mat', label: Text(tr('Noir mat'))),
            ButtonSegment(value: 'or_brosse', label: Text(tr('Laiton'))),
            ButtonSegment(value: 'inox_brosse', label: Text(tr('Inox'))),
          ],
          selected: {st.faucetFinish},
          onSelectionChanged: styleEditable ? (v) => state.edit(() => st.faucetFinish = v.first) : null,
        ),
        const SizedBox(height: Tokens.s3),
        Text(tr('Style de levier du mitigeur'), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: Tokens.s1),
        KxChoices<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'side_pin', label: Text(tr('Manette fine'))),
            ButtonSegment(value: 'side_flat', label: Text(tr('Palette plate'))),
            ButtonSegment(value: 'top_lever', label: Text(tr('Levier haut'))),
            ButtonSegment(value: 'retro_cross', label: Text(tr('Croisillons'))),
          ],
          selected: {st.faucetLever},
          onSelectionChanged: styleEditable ? (v) => state.edit(() => st.faucetLever = v.first) : null,
        ),
      ],
      if (hasOven) ...[
        const Divider(height: Tokens.s4),
        Text(tr('Style Four encastrable'), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: Tokens.s2),
        Text(tr('Finition de façade'), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: Tokens.s1),
        KxChoices<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'black_inox', label: Text(tr('Inox/Verre'))),
            ButtonSegment(value: 'inox_brosse', label: Text(tr('Inox pro'))),
            ButtonSegment(value: 'full_black', label: Text(tr('Full Black'))),
            ButtonSegment(value: 'blanc', label: Text(tr('Blanc'))),
            ButtonSegment(value: 'black_gold', label: Text(tr('Noir & Or'))),
          ],
          selected: {st.ovenFinish},
          onSelectionChanged: styleEditable ? (v) => state.edit(() => st.ovenFinish = v.first) : null,
        ),
        const SizedBox(height: Tokens.s3),
        Text(tr('Poignée / Levier de four'), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: Tokens.s1),
        KxChoices<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'bar', label: Text(tr('Barre ronde'))),
            ButtonSegment(value: 'square', label: Text(tr('Profilé carré'))),
            ButtonSegment(value: 'retro', label: Text(tr('Cintrée classique'))),
            ButtonSegment(value: 'integrated', label: Text(tr('Intégrée'))),
          ],
          selected: {st.ovenHandle},
          onSelectionChanged: styleEditable ? (v) => state.edit(() => st.ovenHandle = v.first) : null,
        ),
      ],
    ]);
  }
}

class _SupplySections extends StatelessWidget {
  final AppState state;
  const _SupplySections({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final lines = state.estimateLines;
    final bySection = <String, List<SupplyLine>>{};
    for (final l in lines) {
      bySection.putIfAbsent(l.section, () => []).add(l);
    }
    String q(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2).replaceAll('.', ',');
    final total = totalOf(lines);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in bySection.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: Tokens.s4, bottom: Tokens.s1),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    e.key,
                    style: t.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(totalOf(e.value).isZero ? '' : _mad(totalOf(e.value)), style: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          for (final l in e.value)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 64,
                    child: Text('${q(l.qty)} ${l.unit}', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(l.name), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                        if (l.detail.isNotEmpty) Text(trParts(l.detail), style: t.bodySmall),
                      ],
                    ),
                  ),
                  Text(l.unitPrice.isZero ? tr('à chiffrer') : _mad(l.total), style: t.bodySmall),
                ],
              ),
            ),
        ],
        const SizedBox(height: Tokens.s3),
        Container(
          padding: const EdgeInsets.all(Tokens.s3),
          decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Tokens.radius)),
          child: Row(
            children: [
              Expanded(
                child: Text(tr('Estimation totale'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              Text(
                _mad(total),
                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary),
              ),
            ],
          ),
        ),
        Text(
          state.project.specs.gamme == 'luxe'
              ? tr('Caissons, façades, joues et tiroirs à l\'article (gamme luxe) ; le reste selon les fourchettes du marché marocain.')
              : state.project.specs.gamme == 'moyen'
              ? tr('Caissons, façades et joues à l’article au tarif moyenne gamme, hors taxes ; le reste selon les fourchettes du marché marocain.')
              : tr('Panneaux, chant et découpe au tarif de l\'atelier ; le reste selon les fourchettes du marché marocain.'),
          style: t.bodySmall,
        ),
      ],
    );
  }
}

/// Comparaison : caissons et façades achetés usinés chez le fournisseur / fabriqués à l'atelier.
class _SupplierCompare extends StatelessWidget {
  final AppState state;
  const _SupplierCompare({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final q = state.supplierEstimate!;
    // atelier : panneaux, chants et découpe (mêmes postes que le fournisseur)
    final shop = totalOf(state.estimateLines.where((l) => l.section == 'Panneaux' || l.section == 'Chants').toList());
    // même matière que le fournisseur : caissons en latté (prix marché au m²) au lieu du MDF de l'atelier
    final plan = state.cutPlan;
    final cs = plan.settings;
    final carcParts = plan.parts.where((x) => x.material == cs.carcassMaterial && !RegExp('Porte|Façade|Joue|Fileur').hasMatch(x.name));
    final allCarcMat = plan.parts.where((x) => x.material == cs.carcassMaterial).fold<double>(0, (a, x) => a + x.area * x.qty);
    final carcShare = allCarcMat <= 0 ? 0.0 : carcParts.fold<double>(0, (a, x) => a + x.area * x.qty) / allCarcMat;
    final carcSheetM2 = plan.sheetsArea(cs.carcassMaterial) * carcShare; // chutes comprises
    final sheetM2 = cs.sheetLength * cs.sheetWidth / 1e6;
    final mdfM2 = (state.project.specs.sheetPrice ?? 850) / sheetM2;
    final latte = state.db?.panel('latte_melamine_ou_plaque')?.sheetPrice(2440, 1220);
    final latteM2 = latte == null ? null : latte * (1 / (2.44 * 1.22));
    final shopLatte = latteM2 == null ? null : shop + PriceRange((latteM2.min - mdfM2) * carcSheetM2, (latteM2.max - mdfM2) * carcSheetM2);
    final bySection = <String, List<SupplyLine>>{};
    for (final l in q.lines) {
      bySection.putIfAbsent(l.section, () => []).add(l);
    }
    String n(double v) => v.toStringAsFixed(0);
    Widget row(String a, String b, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(a, style: t.bodySmall?.copyWith(fontWeight: bold ? FontWeight.w800 : null)),
          ),
          Text(
            b,
            style: t.bodySmall?.copyWith(fontWeight: bold ? FontWeight.w800 : null, color: color),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: Tokens.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Acheter usiné ou fabriquer ?'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: Tokens.s1),
          Text(
            trp(
              'Fournisseur : caissons en contreplaqué latté blanc 18 mm et façades MDF, au tarif relevé sur un devis fournisseur (remise {0} % comprise). Plan de travail, électroménager et quincaillerie à part.',
              [state.supplier!.discountPct.round()],
            ),
            style: t.bodySmall,
          ),
          const SizedBox(height: Tokens.s2),
          for (final e in bySection.entries)
            ExpansionTile(
              key: ValueKey('sup-${e.key}'),
              tilePadding: EdgeInsets.zero,
              dense: true,
              title: Text(e.key, style: t.labelLarge),
              trailing: Text(_mad(totalOf(e.value)), style: t.labelMedium),
              children: [for (final l in e.value) row('${l.qty.round()} × ${l.name}', '${n(l.unitPrice.min)} MAD')],
            ),
          const Divider(),
          row('Fournisseur : brut TTC', '${n(q.gross)} MAD'),
          row('Fournisseur : net TTC (${n(q.netHt)} HT)', '${n(q.net)} MAD', bold: true),
          row('Atelier, caissons en MDF (${n(mdfM2)} MAD/m²)', _mad(shop), color: scheme.onSurfaceVariant),
          if (shopLatte != null) ...[
            row(
              'Atelier, caissons en latté comme le fournisseur (${n(latteM2!.min)}–${n(latteM2.max)} MAD/m²)',
              _mad(shopLatte),
              bold: true,
              color: scheme.primary,
            ),
            row('Écart à matière égale (montage non compté)', '${n(q.net - shopLatte.max)} à ${n(q.net - shopLatte.min)} MAD'),
            Text(
              trp(
                'Panneaux, chants et découpe seulement. Prix du latté : fourchette du marché (feuille 2440 × 1220 à {0}–{1} MAD), à remplacer par votre prix réel.',
                [n(latte!.min), n(latte.max)],
              ),
              style: t.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
