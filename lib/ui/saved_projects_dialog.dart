// Interface de gestion des projets enregistrés (avec horodatage précis).
// Permet d'ouvrir, dupliquer, exporter et supprimer chaque projet horodaté.
import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../engine/saved_projects.dart';
import 'app_state.dart';
import 'i18n.dart';
import 'web_io.dart';

Future<void> showSavedProjectsDialog(
  BuildContext context,
  AppState state, {
  void Function(String universe, Project project)? onOpenProject,
  VoidCallback? onRefresh,
}) =>
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => SavedProjectsDialog(
        state: state,
        onOpenProject: onOpenProject,
        onRefresh: onRefresh,
      ),
    );

class SavedProjectsDialog extends StatefulWidget {
  final AppState state;
  final void Function(String universe, Project project)? onOpenProject;
  final VoidCallback? onRefresh;

  const SavedProjectsDialog({
    super.key,
    required this.state,
    this.onOpenProject,
    this.onRefresh,
  });

  @override
  State<SavedProjectsDialog> createState() => _SavedProjectsDialogState();
}

class _SavedProjectsDialogState extends State<SavedProjectsDialog> {
  late List<SavedProjectMeta> _projects;
  String _filterUniverse = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _projects = SavedProjectsManager.listProjects();
    });
  }

  List<SavedProjectMeta> get _filteredProjects {
    return _projects.where((p) {
      if (_filterUniverse != 'all' && p.universe != _filterUniverse) return false;
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchName = p.name.toLowerCase().contains(q);
        final matchClient = (p.clientName ?? '').toLowerCase().contains(q);
        final matchPhone = (p.clientPhone ?? '').contains(q);
        if (!matchName && !matchClient && !matchPhone) return false;
      }
      return true;
    }).toList();
  }

  Color _universeColor(String u) {
    switch (u) {
      case 'cuisine':
        return const Color(0xFFF26522);
      case 'dressing':
        return const Color(0xFF7B1FA2);
      case 'bain':
        return const Color(0xFF00897B);
      case 'tv':
        return const Color(0xFF1565C0);
      case 'interieur':
        return const Color(0xFF5D4037);
      case 'buanderie':
        return const Color(0xFF00ACC1);
      case 'art':
        return const Color(0xFFE91E63);
      case 'debit':
        return const Color(0xFFE65100);
      default:
        return const Color(0xFFF26522);
    }
  }

  String _universeLabel(String u) {
    switch (u) {
      case 'cuisine':
        return tr('Cuisine');
      case 'dressing':
        return tr('Dressing');
      case 'bain':
        return tr('Salle de bain');
      case 'tv':
        return tr('Meuble TV');
      case 'interieur':
        return tr('Intérieur');
      case 'buanderie':
        return tr('Buanderie');
      case 'art':
        return tr('Art');
      case 'debit':
        return tr('Débitage');
      default:
        return tr('Cuisine');
    }
  }

  Future<void> _saveCurrentProject() async {
    final nameCtrl = TextEditingController(text: widget.state.project.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Enregistrer le projet actuel')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Donnez un nom à ce projet pour le retrouver horodaté dans la liste :')),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('Nom du projet'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Enregistrer'))),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      widget.state.project.name = nameCtrl.text.trim();
      await SavedProjectsManager.saveProject(
        widget.state.project,
        customName: nameCtrl.text.trim(),
      );
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Projet horodaté et enregistré avec succès'))),
        );
      }
    }
  }

  Future<void> _importKin() async {
    final f = await pickFile(accept: '.kin');
    if (f == null || !mounted) return;
    final meta = await SavedProjectsManager.importProjectBytes(f.name, f.bytes);
    if (meta != null) {
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(trp('Projet « {0} » importé avec succès', [meta.name]))),
        );
      }
    }
  }

  void _openProject(SavedProjectMeta meta) {
    final proj = SavedProjectsManager.loadProject(meta.id);
    if (proj == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Erreur : impossible de charger ce projet.'))),
      );
      return;
    }
    Navigator.pop(context);
    if (widget.onOpenProject != null) {
      widget.onOpenProject!(meta.universe, proj);
    } else {
      widget.state.project = proj;
      widget.state.refresh();
      widget.onRefresh?.call();
    }
  }

  Future<void> _deleteProject(SavedProjectMeta meta) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Supprimer le projet ?')),
        content: Text(trp('Voulez-vous supprimer définitivement le projet « {0} » ?', [meta.name])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Supprimer')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      SavedProjectsManager.deleteProject(meta.id);
      _reload();
    }
  }

  Future<void> _duplicateProject(SavedProjectMeta meta) async {
    final copy = await SavedProjectsManager.duplicateProject(meta.id);
    if (copy != null) {
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(trp('Copie créée : « {0} »', [copy.name]))),
        );
      }
    }
  }

  void _exportKin(SavedProjectMeta meta) {
    final bytes = SavedProjectsManager.exportKinBytes(meta.id);
    if (bytes != null) {
      downloadBytes('${meta.name}.kin', bytes, mime: 'application/octet-stream');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final filtered = _filteredProjects;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Entête
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF26522).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.folder_special_outlined, color: Color(0xFFF26522), size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Projets enregistrés'), style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                          trp('{0} projet(s) horodaté(s)', [_projects.length]),
                          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _importKin,
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: Text(tr('Importer .kin')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saveCurrentProject,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(tr('Enregistrer le projet actuel')),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Barre de recherche et filtres d'univers
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 20),
                        hintText: tr('Rechercher un projet, un client...'),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                ],
              ),
            ),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Row(
                children: [
                  for (final (u, label) in [
                    ('all', tr('Tous')),
                    ('cuisine', tr('Cuisine')),
                    ('dressing', tr('Dressing')),
                    ('bain', tr('Salle de bain')),
                    ('tv', tr('Meuble TV')),
                    ('buanderie', tr('Buanderie')),
                    ('interieur', tr('Intérieur')),
                    ('debit', tr('Débitage')),
                    ('art', tr('Art')),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(label),
                        selected: _filterUniverse == u,
                        onSelected: (_) => setState(() => _filterUniverse = u),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Liste des projets horodatés
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open_outlined, size: 64, color: scheme.outlineVariant),
                          const SizedBox(height: 12),
                          Text(
                            _projects.isEmpty
                                ? tr('Aucun projet enregistré pour le moment.')
                                : tr('Aucun projet correspondant à votre recherche.'),
                            style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 16),
                          if (_projects.isEmpty)
                            FilledButton.icon(
                              onPressed: _saveCurrentProject,
                              icon: const Icon(Icons.save_outlined),
                              label: Text(tr('Enregistrer le projet actuel')),
                            ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final p = filtered[i];
                        final uColor = _universeColor(p.universe);
                        return Card(
                          elevation: 0.5,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                // Badge Univers
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: uColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: uColor.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    _universeLabel(p.universe),
                                    style: TextStyle(color: uColor, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Détails du projet + Horodatage
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              p.name,
                                              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (p.clientName != null) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: scheme.surfaceContainerHighest,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.person_outline, size: 13, color: scheme.primary),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    p.clientName!,
                                                    style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      Row(
                                        children: [
                                          // Horodatage précis
                                          Icon(Icons.schedule, size: 14, color: scheme.primary),
                                          const SizedBox(width: 4),
                                          Text(
                                            p.formattedDateTime,
                                            style: textTheme.bodySmall?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: scheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '(${p.relativeTime})',
                                            style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                                          ),
                                          const SizedBox(width: 14),
                                          // Résumé dimensions / caissons
                                          Icon(Icons.straighten, size: 14, color: scheme.outline),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              p.summary,
                                              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Boutons d'action
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: tr('Dupliquer'),
                                      icon: const Icon(Icons.copy_outlined, size: 20),
                                      onPressed: () => _duplicateProject(p),
                                    ),
                                    IconButton(
                                      tooltip: tr('Exporter (.kin)'),
                                      icon: const Icon(Icons.download_outlined, size: 20),
                                      onPressed: () => _exportKin(p),
                                    ),
                                    IconButton(
                                      tooltip: tr('Supprimer'),
                                      icon: Icon(Icons.delete_outline, size: 20, color: scheme.error),
                                      onPressed: () => _deleteProject(p),
                                    ),
                                    const SizedBox(width: 6),
                                    FilledButton.icon(
                                      onPressed: () => _openProject(p),
                                      icon: const Icon(Icons.folder_open, size: 18),
                                      label: Text(tr('Ouvrir')),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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
