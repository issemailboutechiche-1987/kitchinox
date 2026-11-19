// Boîte de dialogue de démarrage de projet pour les univers Kitchinox :
// Permet de choisir entre :
// 1. Nouveau projet avec dimensions de la pièce & fiche client
// 2. Ouvrir un fichier .kin existant (universel, cross-modes)
// 3. Reprendre la session en cours (si existante)
import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'theme.dart';
import 'web_io.dart';
import 'i18n.dart';

class ProjectStartDialog extends StatefulWidget {
  final String universeId;
  final String universeTitle;
  final IconData universeIcon;
  final AppState state;
  final bool hasWorkInProgress;
  final String currentProjectName;
  final int currentCabinetCount;
  final void Function(Project freshProject) onNewProject;
  final void Function(String kinJson) onOpenKin;
  final VoidCallback onResume;

  const ProjectStartDialog({
    super.key,
    required this.universeId,
    required this.universeTitle,
    required this.universeIcon,
    required this.state,
    required this.hasWorkInProgress,
    required this.currentProjectName,
    required this.currentCabinetCount,
    required this.onNewProject,
    required this.onOpenKin,
    required this.onResume,
  });

  static Future<void> show({
    required BuildContext context,
    required String universeId,
    required String universeTitle,
    required IconData universeIcon,
    required AppState state,
    required bool hasWorkInProgress,
    required String currentProjectName,
    required int currentCabinetCount,
    required void Function(Project freshProject) onNewProject,
    required void Function(String kinJson) onOpenKin,
    required VoidCallback onResume,
  }) =>
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => ProjectStartDialog(
          universeId: universeId,
          universeTitle: universeTitle,
          universeIcon: universeIcon,
          state: state,
          hasWorkInProgress: hasWorkInProgress,
          currentProjectName: currentProjectName,
          currentCabinetCount: currentCabinetCount,
          onNewProject: onNewProject,
          onOpenKin: onOpenKin,
          onResume: onResume,
        ),
      );

  @override
  State<ProjectStartDialog> createState() => _ProjectStartDialogState();
}

class _ProjectStartDialogState extends State<ProjectStartDialog> {
  bool _showNewForm = false;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _clientCtrl;
  late final TextEditingController _widthCtrl;
  late final TextEditingController _depthCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _sheetLCtrl;
  late final TextEditingController _sheetWCtrl;
  late final TextEditingController _kerfCtrl;
  late final TextEditingController _trimCtrl;
  late final TextEditingController _carcassThickCtrl;
  String _interiorBase = 'free'; // 'free' | 'cuisine' | 'dressing' | 'bain'

  @override
  void initState() {
    super.initState();
    final defaultName = '${widget.universeTitle} 01';
    _nameCtrl = TextEditingController(text: defaultName);
    _clientCtrl = TextEditingController();
    _widthCtrl = TextEditingController(text: '3600');
    _depthCtrl = TextEditingController(text: '3000');
    _heightCtrl = TextEditingController(text: '2600');
    _sheetLCtrl = TextEditingController(text: '${widget.state.project.cut.sheetLength}');
    _sheetWCtrl = TextEditingController(text: '${widget.state.project.cut.sheetWidth}');
    _kerfCtrl = TextEditingController(text: '${widget.state.project.cut.kerf}');
    _trimCtrl = TextEditingController(text: '${widget.state.project.cut.trim}');
    _carcassThickCtrl = TextEditingController(text: '${widget.state.project.cut.carcassThickness}');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _clientCtrl.dispose();
    _widthCtrl.dispose();
    _depthCtrl.dispose();
    _heightCtrl.dispose();
    _sheetLCtrl.dispose();
    _sheetWCtrl.dispose();
    _kerfCtrl.dispose();
    _trimCtrl.dispose();
    _carcassThickCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickKinFile() async {
    final f = await pickFile(accept: '.kin,.json');
    if (f == null || !mounted) return;
    try {
      final jsonStr = KinFormat.decode(f.bytes);
      Navigator.of(context).pop();
      widget.onOpenKin(jsonStr);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trp('Fichier illisible : {0}', [e]))),
      );
    }
  }

  void _submitNewProject() {
    final w = (double.tryParse(_widthCtrl.text) ?? 3600).clamp(1500.0, 15000.0);
    final d = (double.tryParse(_depthCtrl.text) ?? 3000).clamp(1500.0, 15000.0);
    final h = (double.tryParse(_heightCtrl.text) ?? 2600).clamp(2000.0, 4500.0);

    final name = _nameCtrl.text.trim().isEmpty ? '${widget.universeTitle} 01' : _nameCtrl.text.trim();
    final clientName = _clientCtrl.text.trim();

    final fresh = Project(
      name: name,
      universe: widget.universeId,
      room: Room(width: w, depth: d, height: h),
    )..client.name = clientName;

    // Paramètres avancés de débit
    fresh.cut.sheetLength = int.tryParse(_sheetLCtrl.text) ?? fresh.cut.sheetLength;
    fresh.cut.sheetWidth = int.tryParse(_sheetWCtrl.text) ?? fresh.cut.sheetWidth;
    fresh.cut.kerf = int.tryParse(_kerfCtrl.text) ?? fresh.cut.kerf;
    fresh.cut.trim = int.tryParse(_trimCtrl.text) ?? fresh.cut.trim;
    fresh.cut.carcassThickness = int.tryParse(_carcassThickCtrl.text) ?? fresh.cut.carcassThickness;

    Navigator.of(context).pop();
    widget.onNewProject(fresh);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: scheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // En-tête
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(widget.universeIcon, color: scheme.primary, size: 28),
                  ),
                  const SizedBox(width: Tokens.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.universeTitle,
                          style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.universeId == 'interieur'
                              ? tr('Création de scène, aménagement & décoration')
                              : tr('Démarrage de votre projet de conception'),
                          style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
              const SizedBox(height: Tokens.s4),
              const Divider(height: 1),
              const SizedBox(height: Tokens.s4),

              // Contenu principal
              Expanded(
                child: SingleChildScrollView(
                  child: _showNewForm ? _buildNewForm(scheme, t) : _buildChoiceList(scheme, t),
                ),
              ),

              // Actions inférieures
              if (_showNewForm) ...[
                const SizedBox(height: Tokens.s3),
                // les deux boutons passent l'un sous l'autre si la place manque (textes longs, arabe)
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: Tokens.s2,
                  runSpacing: Tokens.s2,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _showNewForm = false),
                      child: Text(tr('Retour aux options')),
                    ),
                    FilledButton.icon(
                      onPressed: _submitNewProject,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(
                        widget.universeId == 'interieur' ? tr('Créer la scène') : tr('Créer le projet'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceList(ColorScheme scheme, TextTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Option 1 : Nouveau projet / Nouvelle scène
        _ActionCard(
          icon: Icons.add_box_outlined,
          title: widget.universeId == 'interieur' ? tr('Créer une nouvelle scène') : tr('Nouveau projet'),
          subtitle: widget.universeId == 'interieur'
              ? tr('Définir les dimensions de la pièce pour agencer déco, objets, peintures et mobilier')
              : tr('Définir les dimensions de la pièce et commencer une conception vierge'),
          primary: true,
          onTap: () => setState(() => _showNewForm = true),
        ),
        const SizedBox(height: Tokens.s3),

        // Option 2 : Ouvrir un fichier .kin
        _ActionCard(
          icon: Icons.folder_open_outlined,
          title: widget.universeId == 'interieur'
              ? tr('Travailler sur un projet (.kin) existant')
              : tr('Ouvrir un projet (.kin)…'),
          subtitle: widget.universeId == 'interieur'
              ? tr('Importer une cuisine, dressing, ou meuble déjà conçu pour y ajouter déco, objets et finitions')
              : tr('Charger un fichier de conception Kitchinox (.kin)'),
          onTap: _pickKinFile,
        ),

        // Option 3 : Reprendre le travail en cours (si session active)
        if (widget.hasWorkInProgress) ...[
          const SizedBox(height: Tokens.s3),
          _ActionCard(
            icon: Icons.history,
            title: tr('Reprendre le travail en cours'),
            subtitle: trp('Continuer la session : « {0} » ({1} caissons)', [
              widget.currentProjectName,
              widget.currentCabinetCount,
            ]),
            onTap: () {
              Navigator.of(context).pop();
              widget.onResume();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildNewForm(ColorScheme scheme, TextTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.universeId == 'interieur' ? tr('Nouvelle scène d\'intérieur') : tr('Paramètres du nouveau projet'),
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Tokens.s3),

        // Nom du projet et Client
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: tr('Nom du projet'),
                  prefixIcon: const Icon(Icons.edit_outlined),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: TextField(
                controller: _clientCtrl,
                decoration: InputDecoration(
                  labelText: tr('Nom du client (optionnel)'),
                  prefixIcon: const Icon(Icons.person_outline),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s4),

        // Dimensions de la pièce
        Text(
          tr('Dimensions de la pièce (mm)'),
          style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Tokens.s2),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _widthCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Largeur'),
                  suffixText: 'mm',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: Tokens.s2),
            Expanded(
              child: TextField(
                controller: _depthCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Profondeur'),
                  suffixText: 'mm',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: Tokens.s2),
            Expanded(
              child: TextField(
                controller: _heightCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Hauteur plafond'),
                  suffixText: 'mm',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),

        if (widget.universeId == 'interieur') ...[
          const SizedBox(height: Tokens.s4),
          Text(
            tr('Base d\'aménagement'),
            style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Tokens.s2),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'free',
                label: Text(tr('Scène libre')),
                icon: const Icon(Icons.weekend_outlined),
              ),
              ButtonSegment(
                value: 'cuisine',
                label: Text(tr('+ Cuisine')),
                icon: const Icon(Icons.kitchen_outlined),
              ),
              ButtonSegment(
                value: 'dressing',
                label: Text(tr('+ Dressing')),
                icon: const Icon(Icons.checkroom_outlined),
              ),
              ButtonSegment(
                value: 'bain',
                label: Text(tr('+ Salle de bain')),
                icon: const Icon(Icons.wc_outlined),
              ),
            ],
            selected: {_interiorBase},
            onSelectionChanged: (s) => setState(() => _interiorBase = s.first),
          ),
        ],

        const SizedBox(height: Tokens.s4),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune, color: Color(0xFFF26522)),
            title: Text(tr('Options avancées de débit (panneaux, trait de scie)'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            children: [
              const SizedBox(height: Tokens.s2),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _sheetLCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: tr('Longueur panneau (mm)'), border: const OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: Tokens.s2),
                  Expanded(
                    child: TextField(
                      controller: _sheetWCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: tr('Largeur panneau (mm)'), border: const OutlineInputBorder(), isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.s2),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _kerfCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: tr('Trait de scie (mm)'), border: const OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: Tokens.s2),
                  Expanded(
                    child: TextField(
                      controller: _trimCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: tr('Recoupe bords (mm)'), border: const OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: Tokens.s2),
                  Expanded(
                    child: TextField(
                      controller: _carcassThickCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: tr('Épaisseur (mm)'), border: const OutlineInputBorder(), isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.s2),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool primary;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.primary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(Tokens.s3),
        decoration: BoxDecoration(
          color: primary ? scheme.primary.withValues(alpha: 0.07) : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: primary ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.6),
            width: primary ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: primary ? scheme.primary : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: primary ? scheme.onPrimary : scheme.onSurfaceVariant,
                size: 24,
              ),
            ),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: primary ? scheme.primary : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: primary ? scheme.primary : scheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}
