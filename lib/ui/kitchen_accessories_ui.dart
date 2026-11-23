// Interface utilisateur du catalogue d'accessoires d'équipement (INOXA, Blum, Kesseböhmer, etc.)
// - Dialogue de consultation avec filtres (marques, catégories, recherche textuelle, compatibilité caisson).
// - Fiche produit avec carrousel des 3 illustrations : Produit, Lifestyle en situation, et Blueprint coté.
// - Sélection et équipement direct sur les caissons bas, hauts et colonnes.

import 'package:flutter/material.dart';

import '../engine/catalog.dart';
import '../engine/kitchen_accessories.dart';
import '../engine/project.dart';
import 'app_state.dart';
import 'i18n.dart';
import 'theme.dart';

const _brandOrange = Color(0xFFF26A1B);

/// Détermine la zone Kitchinox ('base', 'column', 'corner', 'overhead', 'under_sink') d'un caisson.
String cabinetZoneOf(CabinetModel m, PlacedCabinet c) {
  if (m.kind == CabinetKind.tall) return 'column';
  if (m.kind.isCorner) return 'corner';
  if (m.kind.isHigh) return 'overhead';
  if (m.id.contains('sink') || (c.appliances?.any((a) => a.contains('sink')) ?? false)) return 'under_sink';
  return 'base';
}

/// Ouvre le catalogue complet des accessoires ou filtré pour un caisson.
Future<void> showKitchenAccessoriesDialog(
  BuildContext context,
  AppState state, {
  PlacedCabinet? forCabinet,
  void Function(String)? onMessage,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _KitchenAccessoriesDialog(
      state: state,
      forCabinet: forCabinet,
      onMessage: onMessage,
    ),
  );
}

class _KitchenAccessoriesDialog extends StatefulWidget {
  final AppState state;
  final PlacedCabinet? forCabinet;
  final void Function(String)? onMessage;

  const _KitchenAccessoriesDialog({
    required this.state,
    this.forCabinet,
    this.onMessage,
  });

  @override
  State<_KitchenAccessoriesDialog> createState() => _KitchenAccessoriesDialogState();
}

class _KitchenAccessoriesDialogState extends State<_KitchenAccessoriesDialog> {
  String? _selectedBrand;
  String? _selectedCategory;
  String _searchQuery = '';
  late bool _filterForCabinet;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filterForCabinet = widget.forCabinet != null;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = widget.forCabinet;
    final m = c == null ? null : widget.state.engine.modelOf(c);
    final zone = (c != null && m != null) ? cabinetZoneOf(m, c) : null;
    final cabWidth = c?.width;

    // Filtrage
    final items = KitchenAccessoriesCatalog.all.where((a) {
      if (_filterForCabinet && zone != null && cabWidth != null) {
        if (!a.isCompatibleWith(zone: zone, width: cabWidth)) return false;
      }
      if (_selectedBrand != null && _selectedBrand!.isNotEmpty && a.brand != _selectedBrand) {
        return false;
      }
      if (_selectedCategory != null && _selectedCategory!.isNotEmpty && a.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final match = a.nameFr.toLowerCase().contains(q) ||
            a.code.toLowerCase().contains(q) ||
            a.brand.toLowerCase().contains(q) ||
            a.type.toLowerCase().contains(q);
        if (!match) return false;
      }
      return true;
    }).toList();

    final brands = ['Toutes', ...KitchenAccessoriesCatalog.byBrand.keys];
    final categories = [
      ('Toutes', ''),
      ('Coulissants étroits', 'base_and_overhead'),
      ('Coulissants bas', 'base'),
      ('Colonnes & Garde-manger', 'column'),
      ('Angles & Carrousels', 'corner'),
      ('Sous-évier & Tri', 'under_sink'),
      ('Tiroirs & Casseroliers', 'drawer'),
      ('Meubles hauts & Relevables', 'overhead'),
      ('Dressing & Penderies', 'dressing'),
      ('Profils Gola', 'gola'),
      ('Poignées & Boutons', 'poignee'),
      ('Accessoires d’atelier', 'finish_and_opening'),
      ('Éclairage & Prises', 'lighting_and_power'),
    ];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 860),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // En-tête
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _brandOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.kitchen_outlined, color: _brandOrange, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Accessoires d’équipement & Quincaillerie'),
                          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          tr('Catalogue officiel INOXA (Collection Hyper), Blum, Kesseböhmer, Hettich, Grass, DTC...'),
                          style: t.bodySmall?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: tr('Fermer'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Bandeau d'association avec un caisson spécifique (si ouvert depuis un caisson)
            if (c != null && m != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                color: _brandOrange.withValues(alpha: 0.08),
                child: Row(
                  children: [
                    const Icon(Icons.tune, size: 18, color: _brandOrange),
                    const SizedBox(width: 8),
                    Text(
                      '${tr('Pour caisson')} : ${m.name} · ${tr('Largeur')} ${c.width} mm',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _brandOrange),
                    ),
                    const Spacer(),
                    FilterChip(
                      avatar: Icon(_filterForCabinet ? Icons.filter_alt : Icons.filter_alt_off, size: 16),
                      label: Text(
                        _filterForCabinet
                            ? tr('Filtrer compatibles ({0} articles)').replaceFirst('{0}', '${items.length}')
                            : tr('Voir tout le catalogue ({0} articles)').replaceFirst('{0}', '${KitchenAccessoriesCatalog.all.length}'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: _filterForCabinet,
                      onSelected: (val) => setState(() => _filterForCabinet = val),
                    ),
                  ],
                ),
              ),

            // Barre de recherche et filtres marques / catégories
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        hintText: tr('Rechercher un modèle, code article (ex: 8104Y, LeMans, épices...)'),
                        hintStyle: const TextStyle(fontSize: 13),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Sélecteur de marque
                  DropdownButton<String>(
                    value: _selectedBrand ?? 'Toutes',
                    underline: const SizedBox(),
                    items: [
                      for (final b in brands)
                        DropdownMenuItem(
                          value: b,
                          child: Text(
                            b == 'Toutes' ? tr('Toutes les marques') : b,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                    onChanged: (val) => setState(() => _selectedBrand = (val == 'Toutes' || val == null) ? null : val),
                  ),
                ],
              ),
            ),

            // Chips des catégories
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  for (final (label, catKey) in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(tr(label), style: const TextStyle(fontSize: 12)),
                        selected: (_selectedCategory == null && catKey.isEmpty) || _selectedCategory == catKey,
                        onSelected: (_) => setState(() => _selectedCategory = catKey.isEmpty ? null : catKey),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),

            const Divider(height: 12),

            // Grille des articles
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 10),
                          Text(tr('Aucun accessoire ne correspond à vos filtres.'), style: t.bodyMedium?.copyWith(color: Colors.grey[600])),
                          if (_filterForCabinet) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              icon: const Icon(Icons.all_inclusive, size: 16),
                              label: Text(tr('Afficher tous les accessoires sans filtre de dimensions')),
                              onPressed: () => setState(() => _filterForCabinet = false),
                            ),
                          ],
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(20),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 340,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: items.length,
                      itemBuilder: (ctx, i) {
                        final acc = items[i];
                        final isEquipped = widget.forCabinet != null && widget.forCabinet!.accessory == acc.id;
                        return _AccessoryCard(
                          accessory: acc,
                          isEquipped: isEquipped,
                          forCabinet: widget.forCabinet,
                          onEquip: widget.forCabinet == null
                              ? null
                              : () {
                                  widget.state.setCabinetAccessory(
                                    widget.forCabinet!.uid,
                                    isEquipped ? null : acc.id,
                                  );
                                  setState(() {});
                                  widget.onMessage?.call(
                                    isEquipped
                                        ? tr('Accessoire retiré du caisson.')
                                        : trp('Caisson équipé de : {0}', ['${acc.brand} ${acc.code}']),
                                  );
                                },
                          onOpenDetails: () => showAccessoryDetailSheet(
                            context,
                            acc,
                            forCabinet: widget.forCabinet,
                            onEquip: widget.forCabinet == null
                                ? null
                                : () {
                                    widget.state.setCabinetAccessory(
                                      widget.forCabinet!.uid,
                                      isEquipped ? null : acc.id,
                                    );
                                    setState(() {});
                                    Navigator.of(context).pop();
                                  },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte d'un accessoire dans la grille
class _AccessoryCard extends StatelessWidget {
  final KitchenAccessory accessory;
  final bool isEquipped;
  final PlacedCabinet? forCabinet;
  final VoidCallback? onEquip;
  final VoidCallback onOpenDetails;

  const _AccessoryCard({
    required this.accessory,
    required this.isEquipped,
    this.forCabinet,
    this.onEquip,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final imgPath = accessory.productAsset ?? accessory.lifestyleAsset;

    return Card(
      elevation: isEquipped ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isEquipped ? _brandOrange : Theme.of(context).dividerColor.withValues(alpha: 0.5),
          width: isEquipped ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenDetails,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image avec badge de marque et bouton de zoom
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    child: imgPath != null
                        ? Image.asset(
                            imgPath,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.kitchen_outlined, size: 48, color: Colors.grey),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.kitchen_outlined, size: 48, color: Colors.grey),
                          ),
                  ),
                  // Badge marque
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: accessory.brand == 'INOXA' ? const Color(0xFF0D47A1) : (accessory.brand == 'Blum' ? const Color(0xFFE65100) : const Color(0xFF37474F)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        accessory.brand,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ),
                  ),
                  // Badge code article
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        accessory.code,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10),
                      ),
                    ),
                  ),
                  if (isEquipped)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _brandOrange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check, size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(tr('Équipé'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Détails et spécifications
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accessory.nameFr,
                      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Largeurs compatibles
                    if (accessory.supportedWidths.isNotEmpty)
                      Text(
                        '${tr('Pour caisson')} L : ${accessory.supportedWidths.map((w) => '$w').join(' · ')} mm',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blueGrey[700]),
                      ),
                    const Spacer(),
                    // Prix indicatif
                    Text(
                      '${accessory.price.min.round()} – ${accessory.price.max.round()} MAD',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _brandOrange),
                    ),
                    const SizedBox(height: 8),
                    // Bouton d'action
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: onOpenDetails,
                            child: Text(tr('Fiche & Plans'), style: const TextStyle(fontSize: 11)),
                          ),
                        ),
                        if (onEquip != null) ...[
                          const SizedBox(width: 6),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: isEquipped ? Colors.grey[700] : _brandOrange,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            onPressed: onEquip,
                            child: Text(isEquipped ? tr('Retirer') : tr('Équiper'), style: const TextStyle(fontSize: 11)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fiche détaillée complète d'un accessoire avec ses 3 visuels : Produit, Lifestyle et Blueprint coté.
Future<void> showAccessoryDetailSheet(
  BuildContext context,
  KitchenAccessory acc, {
  PlacedCabinet? forCabinet,
  VoidCallback? onEquip,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _AccessoryDetailDialog(
      accessory: acc,
      forCabinet: forCabinet,
      onEquip: onEquip,
    ),
  );
}

class _AccessoryDetailDialog extends StatefulWidget {
  final KitchenAccessory accessory;
  final PlacedCabinet? forCabinet;
  final VoidCallback? onEquip;

  const _AccessoryDetailDialog({
    required this.accessory,
    this.forCabinet,
    this.onEquip,
  });

  @override
  State<_AccessoryDetailDialog> createState() => _AccessoryDetailDialogState();
}

class _AccessoryDetailDialogState extends State<_AccessoryDetailDialog> {
  int _activeTab = 0; // 0 = Produit, 1 = Ambiance (Lifestyle), 2 = Schéma technique (Blueprint)

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final acc = widget.accessory;

    final tabs = <(String, String?, IconData)>[
      ('Photo produit', acc.productAsset, Icons.photo_outlined),
      ('En situation', acc.lifestyleAsset, Icons.weekend_outlined),
      ('Schéma coté (Blueprint)', acc.blueprintAsset, Icons.architecture_outlined),
    ].where((tab) => tab.$2 != null).toList();

    final activeImg = tabs.isNotEmpty ? tabs[_activeTab.clamp(0, tabs.length - 1)].$2 : null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _brandOrange,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      acc.brand,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${acc.code} · ${acc.collection.isNotEmpty ? acc.collection : acc.category}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: tr('Fermer'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Contenu en 2 colonnes : Vue image à gauche / Caractéristiques à droite
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Colonne visuelle
                  Expanded(
                    flex: 6,
                    child: Column(
                      children: [
                        // Onglets des illustrations
                        if (tabs.length > 1)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Row(
                              children: [
                                for (var i = 0; i < tabs.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      avatar: Icon(tabs[i].$3, size: 16),
                                      label: Text(tr(tabs[i].$1)),
                                      selected: _activeTab == i,
                                      onSelected: (_) => setState(() => _activeTab = i),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        // Affichage de l'image agrandie avec fond blanc
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: activeImg != null
                                ? InteractiveViewer(
                                    child: Center(
                                      child: Image.asset(
                                        activeImg,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, _, _) => const Center(
                                          child: Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.grey),
                                        ),
                                      ),
                                    ),
                                  )
                                : const Center(child: Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.grey)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const VerticalDivider(width: 1),

                  // Colonne spécifications techniques
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(acc.nameFr, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          if (acc.nameIt != null) ...[
                            const SizedBox(height: 4),
                            Text(acc.nameIt!, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12, color: Colors.grey)),
                          ],
                          const SizedBox(height: 14),

                          // Prix indicatif
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _brandOrange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.payments_outlined, color: _brandOrange),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(tr('Tarif indicatif public (Maroc)'), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    Text(
                                      '${acc.price.min.round()} – ${acc.price.max.round()} MAD',
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: _brandOrange),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Caractéristiques techniques
                          _specRow(tr('Marque & Collection'), '${acc.brand} ${acc.collection.isNotEmpty ? "· ${acc.collection}" : ""}'),
                          if (acc.slides != null) _specRow(tr('Coulisses'), acc.slides!),
                          if (acc.softClose) _specRow(tr('Fermeture'), tr('Amortie (Soft-Close)')),
                          if (acc.antiSlipMat) _specRow(tr('Tapis'), tr('Antidérapant inclus')),
                          if (acc.loadCapacityKg != null) _specRow(tr('Charge maximale'), '${acc.loadCapacityKg} kg'),
                          if (acc.shelvesCount != null) _specRow(tr('Niveaux / Paniers'), '${acc.shelvesCount}'),
                          if (acc.finishes.isNotEmpty) _specRow(tr('Finitions'), acc.finishes.join(', ')),
                          if (acc.sourcePdfPage != null) _specRow(tr('Catalogue officiel'), 'Page ${acc.sourcePdfPage}'),

                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 12),

                          Text(tr('Largeurs de caissons compatibles :'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final w in acc.supportedWidths)
                                Chip(
                                  label: Text('$w mm'),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                ),
                            ],
                          ),

                          if (widget.onEquip != null) ...[
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _brandOrange,
                                minimumSize: const Size(double.infinity, 44),
                              ),
                              icon: const Icon(Icons.check),
                              label: Text(tr('Équiper sur ce caisson')),
                              onPressed: widget.onEquip,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _specRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

/// Section dans le formulaire de propriétés du caisson (`_CabinetForm`)
class CabinetAccessorySection extends StatelessWidget {
  final AppState state;
  final PlacedCabinet item;
  final CabinetModel model;
  final bool editable;
  final void Function(String)? onMessage;

  const CabinetAccessorySection({
    super.key,
    required this.state,
    required this.item,
    required this.model,
    required this.editable,
    this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final zone = cabinetZoneOf(model, item);
    final currentAcc = item.accessory != null ? KitchenAccessoriesCatalog.byId[item.accessory!] : null;

    // Accessoires rapides compatibles avec ce caisson
    final compatibles = KitchenAccessoriesCatalog.compatibleWith(zone: zone, width: item.width).take(3).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(tr('Équipement intérieur & Accessoires'), maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.menu_book, size: 15, color: _brandOrange),
                label: Text(tr('Tout voir'), style: const TextStyle(fontSize: 12, color: _brandOrange, fontWeight: FontWeight.bold)),
                onPressed: () => showKitchenAccessoriesDialog(
                  context,
                  state,
                  forCabinet: item,
                  onMessage: onMessage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          if (currentAcc != null) ...[
            // Carte de l'accessoire actuellement équipé
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: _brandOrange, width: 1.5),
              ),
              color: _brandOrange.withValues(alpha: 0.05),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    if (currentAcc.productAsset != null)
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(currentAcc.productAsset!, fit: BoxFit.contain),
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: currentAcc.brand == 'INOXA' ? const Color(0xFF0D47A1) : const Color(0xFFE65100),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(currentAcc.brand, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 6),
                              Text(currentAcc.code, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            currentAcc.nameFr,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${currentAcc.price.min.round()} – ${currentAcc.price.max.round()} MAD',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: _brandOrange),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      tooltip: tr('Retirer cet accessoire'),
                      onPressed: editable
                          ? () {
                              state.setCabinetAccessory(item.uid, null);
                              onMessage?.call(tr('Accessoire retiré du caisson.'));
                            }
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Bouton pour ajouter un accessoire
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 38),
                side: BorderSide(color: _brandOrange.withValues(alpha: 0.5)),
              ),
              icon: const Icon(Icons.add, size: 18, color: _brandOrange),
              label: Text(tr('+ Équiper d’un accessoire (INOXA, Blum...)'), style: const TextStyle(color: _brandOrange, fontWeight: FontWeight.bold)),
              onPressed: editable
                  ? () => showKitchenAccessoriesDialog(
                        context,
                        state,
                        forCabinet: item,
                        onMessage: onMessage,
                      )
                  : null,
            ),
            // Suggestions d'accès rapide
            if (compatibles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final acc in compatibles)
                    ActionChip(
                      avatar: const Icon(Icons.add_circle_outline, size: 14, color: _brandOrange),
                      label: Text('${acc.code} ${acc.brand}', style: const TextStyle(fontSize: 11)),
                      onPressed: editable
                          ? () {
                              state.setCabinetAccessory(item.uid, acc.id);
                              onMessage?.call(trp('Caisson équipé de : {0}', ['${acc.brand} ${acc.code}']));
                            }
                          : null,
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
