// Panneau « Objets » : sanitaires paramétriques kitchinox et objets de décoration (catalogue libre CC0) ;
// un clic pose l'objet. Fiche d'un objet posé : taille, rotation, plaquer au mur, dupliquer, supprimer.
import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'art_library.dart';
import 'theme.dart';
import 'web_io.dart';
import 'i18n.dart';

class ObjectsPanel extends StatefulWidget {
  final AppState state;
  final void Function(String) onMessage;
  const ObjectsPanel({super.key, required this.state, required this.onMessage});
  @override
  State<ObjectsPanel> createState() => _ObjectsPanelState();
}

class _ObjectsPanelState extends State<ObjectsPanel> {
  static const Map<String, List<String>> _universeCats = {
    'dressing': ['Chambre', 'Décoration', 'Éclairage', 'Importés'],
    'cuisine': ['Électroménager', 'Repas', 'Décoration', 'Éclairage', 'Importés'],
    'bain': ['Sanitaires', 'Salle de bain', 'Éclairage', 'Décoration', 'Importés'],
    'buanderie': ['Électroménager', 'Sanitaires', 'Décoration', 'Éclairage', 'Importés'],
    'tv': ['Salon', 'Décoration', 'Éclairage', 'Importés'],
    'interieur': ['Tous', 'Salon', 'Repas', 'Bureau', 'Chambre', 'Décoration', 'Éclairage', 'Sanitaires', 'Importés'],
  };

  String? cat;
  String query = '';

  Future<void> _importObject() async {
    final f = await pickFile(accept: '.glb,.gltf,.obj,.3ds');
    if (f == null) return;
    try {
      final safeName = f.name.replaceAll(RegExp(r'\.(glb|gltf|obj|3ds)$', caseSensitive: false), '');
      final objId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
      final path = 'imported/${f.name}';
      saveImportedAsset(f.name, f.bytes);

      final newObj = CatalogObject(
        objId,
        safeName,
        'Importés',
        path,
        'objects/polyhaven/thumbs/sofa_02.png',
        600,
        800,
        600,
        false,
        source: 'import',
      );

      widget.state.objectCatalog.add(newObj);
      setState(() => cat = 'Importés');
      widget.onMessage(trp('Modèle 3D {0} importé avec succès', [f.name]));
      widget.state.addObject(objId);
    } catch (e) {
      widget.onMessage(trp('Erreur d\'import : {0}', [e]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final universe = st.project.universe;
    final allowedCats = _universeCats[universe] ?? ['Salon', 'Repas', 'Bureau', 'Chambre', 'Décoration', 'Éclairage'];
    final visible = st.objectCatalog.where((o) => !o.hidden).toList();
    final hasImported = visible.any((o) => o.category == 'Importés');

    // Pour bain uniquement : Sanitaires est inclus en premier. Pour les autres univers : catégories de l'univers uniquement.
    final cats = [
      // meubles créés dans l'atelier, en tête quand il y en a
      if (visible.any((o) => o.category == libraryCategory)) libraryCategory,
      if (universe == 'bain') 'Sanitaires',
      for (final c in allowedCats)
        if (c != 'Sanitaires' && (visible.any((o) => o.category == c) || c == allowedCats.first)) c,
      if (hasImported) 'Importés',
    ];

    if (cat == null || !cats.contains(cat)) {
      cat = cats.isNotEmpty ? cats.first : 'Décoration';
    }

    final q = query.toLowerCase();
    final currentCat = cat!;
    final fixtures = ((currentCat == 'Sanitaires' || currentCat == 'Tous') && (universe == 'bain' || universe == 'interieur'))
        ? fixtureTypes.where((f) => q.isEmpty || f.name.toLowerCase().contains(q) || tr(f.name).toLowerCase().contains(q)).toList()
        : <FixtureType>[];
    final objs = visible.where((o) {
      if (currentCat == 'Tous') {
        return q.isEmpty || o.name.toLowerCase().contains(q) || tr(o.name).toLowerCase().contains(q);
      }
      if (currentCat == 'Sanitaires') {
        return o.category == 'Salle de bain' && (q.isEmpty || o.name.toLowerCase().contains(q) || tr(o.name).toLowerCase().contains(q));
      }
      return o.category == currentCat && (q.isEmpty || o.name.toLowerCase().contains(q) || tr(o.name).toLowerCase().contains(q));
    }).toList();

    Widget tile({required Widget icon, required String name, required String dims, required VoidCallback onTap}) => Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Column(children: [
                Expanded(child: Center(child: FittedBox(child: icon))),
                const SizedBox(height: 4),
                Text(name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(dims, style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
          ),
        );
    void add(String ref) {
      widget.onMessage(st.addObject(ref));
      if (st.view == ViewMode.view3d || st.view == ViewMode.front) return;
    }

    return Material(
      color: scheme.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s3, Tokens.s2, 0),
          child: Row(children: [
            Expanded(child: Text(tr('Objets'), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(
              tooltip: tr('Importer un objet 3D (.glb, .obj, .3ds)'),
              icon: const Icon(Icons.file_upload_outlined),
              onPressed: _importObject,
            ),
            IconButton(tooltip: tr('Fermer'), onPressed: () => st.openObjects(false), icon: const Icon(Icons.close)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr('Rechercher…'),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
        ),
        const SizedBox(height: Tokens.s2),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Tokens.s4), children: [
            for (final c in cats)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(tr(c)),
                  selected: currentCat == c,
                  onSelected: (_) => setState(() => cat = c),
                ),
              ),
          ]),
        ),
        Expanded(
          child: (fixtures.isEmpty && objs.isEmpty)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Tokens.s4),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.search_off_outlined, size: 48, color: scheme.outline),
                      const SizedBox(height: Tokens.s2),
                      Text(tr('Aucun objet trouvé'), style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ]),
                  ),
                )
              : GridView.extent(
                  padding: const EdgeInsets.all(Tokens.s3),
                  maxCrossAxisExtent: 160,
                  mainAxisSpacing: Tokens.s2,
                  crossAxisSpacing: Tokens.s2,
                  childAspectRatio: 0.78,
                  children: [
                    for (final f in fixtures)
                      tile(
                        icon: SizedBox(width: 64, height: 64, child: CustomPaint(painter: FixtureIcon(f.id))),
                        name: tr(f.name),
                        dims: f.sizes.map((s) => '${s.$1}×${s.$2}').take(2).join(' · '),
                        onTap: () => add('fixture:${f.id}'),
                      ),
                    for (final o in objs)
                      tile(
                        icon: o.id.startsWith('lib:')
                            ? Icon(Icons.inventory_2_outlined, size: 48, color: scheme.primary)
                            : (nativeIoEnabled
                            ? Image.asset('web/${o.thumb}', height: 66, fit: BoxFit.contain, errorBuilder: (_, _, _) => Icon(Icons.chair_outlined, size: 40, color: scheme.outline))
                            : Image.network(o.thumb, height: 66, fit: BoxFit.contain, errorBuilder: (_, _, _) => Icon(Icons.chair_outlined, size: 40, color: scheme.outline))),
                        name: tr(o.name),
                        dims: '${o.w}×${o.d} · H${o.h}',
                        onTap: () => add(o.id),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(Tokens.s3),
          child: Text(tr('Mobilier : modèles Poly Haven et Kenney, licence CC0 (libres de droits). Sanitaires : modèles kitchinox aux cotes réelles.'), style: t.labelSmall),
        ),
      ]),
    );
  }
}

/// Icône d'un sanitaire (même symbole que sur le plan).
class FixtureIcon extends CustomPainter {
  final String id;
  FixtureIcon(this.id);
  @override
  void paint(Canvas c, Size s) {
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF4A4F55);
    final fill = Paint()..color = const Color(0xFFF7F5F2);
    final r = Offset.zero & s;
    switch (id) {
      case 'wc_suspendu' || 'wc_sol' || 'bidet':
        final bowl = Rect.fromLTWH(s.width * 0.22, s.height * 0.2, s.width * 0.56, s.height * 0.72);
        if (id == 'wc_sol') c.drawRect(Rect.fromLTWH(s.width * 0.18, s.height * 0.04, s.width * 0.64, s.height * 0.18), ink);
        c.drawOval(bowl, fill);
        c.drawOval(bowl, ink);
        c.drawOval(bowl.deflate(8), ink);
      case 'lavabo' || 'vasque_double':
        final top = Rect.fromLTWH(2, s.height * 0.25, s.width - 4, s.height * 0.5);
        c.drawRect(top, fill);
        c.drawRect(top, ink);
        final n = id == 'vasque_double' ? 2 : 1;
        for (var i = 0; i < n; i++) {
          c.drawOval(Rect.fromCenter(center: Offset(s.width * (i + 0.5) / n, s.height * 0.52), width: s.width / n * 0.6, height: s.height * 0.3), ink);
        }
      case 'baignoire':
        final b = Rect.fromLTWH(2, s.height * 0.28, s.width - 4, s.height * 0.44);
        c.drawRRect(RRect.fromRectAndRadius(b, const Radius.circular(4)), fill);
        c.drawRRect(RRect.fromRectAndRadius(b, const Radius.circular(4)), ink);
        c.drawRRect(RRect.fromRectAndRadius(b.deflate(5), const Radius.circular(10)), ink);
      case 'douche' || 'douche_italienne':
        final b = r.deflate(6);
        c.drawRect(b, Paint()..color = const Color(0xFFEAF2F6));
        c.drawRect(b, ink);
        c.drawLine(b.topLeft, b.bottomRight, ink..strokeWidth = 1);
        c.drawLine(b.topRight, b.bottomLeft, ink);
      case 'seche_serviettes':
        final b = Rect.fromLTWH(s.width * 0.3, 4, s.width * 0.4, s.height - 8);
        c.drawRect(b, fill);
        c.drawRect(b, ink);
        for (var i = 1; i < 6; i++) {
          c.drawLine(Offset(b.left, b.top + b.height * i / 6), Offset(b.right, b.top + b.height * i / 6), ink);
        }
      case 'miroir':
        final b = Rect.fromLTWH(s.width * 0.12, s.height * 0.12, s.width * 0.76, s.height * 0.6);
        c.drawRect(b, Paint()..color = const Color(0xFFDCE8EC));
        c.drawRect(b, ink);
        c.drawLine(Offset(b.left + b.width * 0.25, b.bottom), Offset(b.left + b.width * 0.6, b.top), Paint()
          ..color = Colors.white
          ..strokeWidth = 3);
      case 'chauffe_eau':
        final b = Rect.fromLTWH(s.width * 0.28, 4, s.width * 0.44, s.height - 8);
        c.drawRRect(RRect.fromRectAndRadius(b, const Radius.circular(14)), fill);
        c.drawRRect(RRect.fromRectAndRadius(b, const Radius.circular(14)), ink);
      default:
        c.drawRect(r.deflate(8), ink);
    }
  }

  @override
  bool shouldRepaint(FixtureIcon o) => o.id != id;
}

/// Fiche d'un objet posé.
class ObjectCard extends StatelessWidget {
  final AppState state;
  final void Function(String) onMessage;
  const ObjectCard({super.key, required this.state, required this.onMessage});

  @override
  Widget build(BuildContext context) {
    final o = state.selectedObjectObj!;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final f = o.fixture;
    final cat = f == null ? state.objectCatalog.where((c) => c.id == o.ref).firstOrNull : null;
    final name = f?.name ?? cat?.name ?? 'Objet';
    Widget num(String label, int v, void Function(int) on) => SizedBox(
          width: 110,
          child: TextFormField(
            key: ValueKey('${o.uid}-$label-$v'),
            initialValue: '$v',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label, suffixText: 'mm', isDense: true, border: const OutlineInputBorder()),
            onFieldSubmitted: (s) {
              final n = int.tryParse(s);
              if (n != null && n > 0) state.editObject(o.uid, (x) => on(n));
            },
          ),
        );
    return SizedBox(
      width: 380,
      child: Card(
        margin: EdgeInsets.zero,
        child: ListView(padding: const EdgeInsets.all(Tokens.s4), children: [
          Row(children: [
            Expanded(child: Text(name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(tooltip: tr('Fermer'), onPressed: () => state.selectObject(null), icon: const Icon(Icons.close)),
          ]),
          Text(f?.category ?? cat?.category ?? '', style: t.bodySmall),
          if (f != null && f.note.isNotEmpty) ...[
            const SizedBox(height: Tokens.s2),
            Text(tr(f.note), style: t.bodySmall),
          ],
          if (f != null && f.sizes.length > 1) ...[
            const SizedBox(height: Tokens.s3),
            Text(tr('Taille'), style: t.labelLarge),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (w, d) in f.sizes)
                ChoiceChip(
                  label: Text(trp('{0} × {1}', [w, d])),
                  selected: o.w == w && o.d == d,
                  onSelected: (_) => state.editObject(o.uid, (x) {
                    x
                      ..w = w
                      ..d = d;
                    snapToWall(state.project.room, x);
                  }),
                ),
            ]),
          ],
          const SizedBox(height: Tokens.s3),
          Text(tr('Dimensions'), style: t.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: Tokens.s2, runSpacing: Tokens.s3, children: [
            num('Largeur', o.w, (v) => o.w = v),
            num('Profondeur', o.d, (v) => o.d = v),
            num('Hauteur', o.h, (v) => o.h = v),
            num('Du sol', o.z.round(), (v) => o.z = v.toDouble()),
          ]),
          if (f != null) ...[
            const SizedBox(height: Tokens.s3),
            Row(children: [
              Icon(Icons.water_drop_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    f.water.isEmpty
                        ? tr('Électricité seulement')
                        : trp('{0} arrivée(s) d’eau, {1} évacuation(s) · dégagement {2} mm devant', [f.water.where((w) => w.$1 != 'evac').length, f.water.where((w) => w.$1 == 'evac').length, f.clearance]),
                    style: t.bodySmall),
              ),
            ]),
          ],
          const SizedBox(height: Tokens.s4),
          Wrap(spacing: Tokens.s2, runSpacing: Tokens.s2, children: [
            OutlinedButton.icon(onPressed: () => state.rotateObject(o.uid, 90), icon: const Icon(Icons.rotate_right), label: Text(tr('Tourner'))),
            OutlinedButton.icon(
                onPressed: () => state.editObject(o.uid, (x) => snapToWall(state.project.room, x)),
                icon: const Icon(Icons.vertical_align_top),
                label: Text(tr('Contre le mur'))),
            OutlinedButton.icon(onPressed: () => state.duplicateObject(o.uid), icon: const Icon(Icons.copy), label: Text(tr('Dupliquer'))),
            TextButton.icon(onPressed: () => state.deleteObject(o.uid), icon: const Icon(Icons.delete_outline), label: Text(tr('Supprimer'))),
          ]),
          const SizedBox(height: Tokens.s2),
          Text(tr('Glissez l’objet en vue du dessus : près d’un mur, il s’y plaque dos au mur.'), style: t.bodySmall),
        ]),
      ),
    );
  }
}
