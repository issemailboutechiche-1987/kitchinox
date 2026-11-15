// Gestion et persistance des projets enregistrés Kitchinox.
// Chaque projet est horodaté (date et heure de création / modification précise).
// Permet de lister, charger, enregistrer, dupliquer, exporter (.kin) et supprimer des projets.
import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'kin_format.dart';
import 'project.dart';
import '../ui/web_io.dart';

class SavedProjectMeta {
  final String id;
  final String name;
  final String universe;
  final DateTime updatedAt;
  final String? clientName;
  final String? clientPhone;
  final String summary;

  const SavedProjectMeta({
    required this.id,
    required this.name,
    required this.universe,
    required this.updatedAt,
    this.clientName,
    this.clientPhone,
    required this.summary,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'universe': universe,
        'updated_at': updatedAt.toIso8601String(),
        if (clientName != null) 'client_name': clientName,
        if (clientPhone != null) 'client_phone': clientPhone,
        'summary': summary,
      };

  factory SavedProjectMeta.fromJson(Map<String, dynamic> j) => SavedProjectMeta(
        id: j['id'] as String? ?? 'proj_${DateTime.now().millisecondsSinceEpoch}',
        name: j['name'] as String? ?? 'Sans nom',
        universe: j['universe'] as String? ?? 'cuisine',
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
        clientName: j['client_name'] as String?,
        clientPhone: j['client_phone'] as String?,
        summary: j['summary'] as String? ?? '',
      );

  String get formattedDateTime {
    final d = updatedAt;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy à $hh:$min';
  }

  String get relativeTime {
    final diff = DateTime.now().difference(updatedAt);
    if (diff.inSeconds < 60) return 'À l’instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} jour(s)';
    return formattedDateTime;
  }
}

class SavedProjectsManager {
  static const String _indexKey = 'kitchinox.saved_projects_index';
  static const String _projPrefix = 'kitchinox.saved_project.';

  /// Liste tous les projets enregistrés, classés du plus récent au plus ancien.
  static List<SavedProjectMeta> listProjects() {
    final raw = storeGet(_indexKey);
    final list = <SavedProjectMeta>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final arr = jsonDecode(raw) as List;
        for (final item in arr) {
          if (item is Map<String, dynamic>) {
            list.add(SavedProjectMeta.fromJson(item));
          }
        }
      } catch (e) {
        debugPrint('Erreur lecture index projets: $e');
      }
    }
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// Sauvegarde un projet complet avec horodatage automatique.
  static Future<SavedProjectMeta> saveProject(
    Project project, {
    String? universe,
    String? customId,
    String? customName,
  }) async {
    final now = DateTime.now();
    final name = (customName != null && customName.trim().isNotEmpty)
        ? customName.trim()
        : (project.name.trim().isNotEmpty ? project.name.trim() : 'Projet sans nom');
    final id = customId ?? 'proj_${now.millisecondsSinceEpoch}';
    final u = universe ?? 'cuisine';

    // Résumé visuel
    final String summary;
    if (project.items.isNotEmpty) {
      final w = (project.room.width / 1000).toStringAsFixed(1).replaceAll('.', ',');
      final d = (project.room.depth / 1000).toStringAsFixed(1).replaceAll('.', ',');
      summary = '$w m × $d m · ${project.items.length} caisson(s)';
    } else if (project.manual.parts.isNotEmpty) {
      final totalP = project.manual.parts.fold<int>(0, (s, p) => s + p.qty);
      summary = '$totalP pièce(s) · ${project.manual.material}';
    } else {
      summary = 'Conception vierge';
    }

    final meta = SavedProjectMeta(
      id: id,
      name: name,
      universe: u,
      updatedAt: now,
      clientName: project.client.name.isNotEmpty ? project.client.name : null,
      clientPhone: null,
      summary: summary,
    );

    // Contenu JSON
    final jsonStr = jsonEncode(project.toJson());
    storeSet('$_projPrefix$id', jsonStr);

    // Sauvegarde fichier physique .kin
    try {
      final kinBytes = KinFormat.encode(jsonStr, projectName: name);
      downloadBytes('${id}_${_cleanName(name)}.kin', kinBytes);
    } catch (e) {
      debugPrint('Erreur sauvegarde fichier kin: $e');
    }

    // Mise à jour de l'index
    final list = listProjects().where((m) => m.id != id).toList();
    list.insert(0, meta);
    _saveIndex(list);

    return meta;
  }

  /// Charge un projet par son identifiant
  static Project? loadProject(String id) {
    final raw = storeGet('$_projPrefix$id');
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return Project.fromJson(map);
    } catch (e) {
      debugPrint('Erreur chargement projet $id: $e');
      return null;
    }
  }

  /// Duplique un projet existant avec nouvel horodatage
  static Future<SavedProjectMeta?> duplicateProject(String id) async {
    final p = loadProject(id);
    if (p == null) return null;
    final copyName = '${p.name} (Copie)';
    p.name = copyName;
    return saveProject(p, customName: copyName);
  }

  /// Supprime un projet
  static bool deleteProject(String id) {
    storeRemove('$_projPrefix$id');
    final list = listProjects().where((m) => m.id != id).toList();
    _saveIndex(list);
    return true;
  }

  /// Exporte un projet en bytes .kin
  static Uint8List? exportKinBytes(String id) {
    final raw = storeGet('$_projPrefix$id');
    if (raw == null || raw.isEmpty) return null;
    try {
      return KinFormat.encode(raw);
    } catch (e) {
      debugPrint('Erreur export kin: $e');
      return null;
    }
  }

  /// Importe un fichier .kin ou .json dans la bibliothèque de projets
  static Future<SavedProjectMeta?> importProjectBytes(String fileName, List<int> bytes) async {
    String text;
    try {
      text = KinFormat.decode(Uint8List.fromList(bytes));
    } catch (_) {
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        text = latin1.decode(bytes);
      }
    }

    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      final p = Project.fromJson(map);
      var name = p.name;
      if (name.isEmpty) {
        name = fileName.replaceAll(RegExp(r'\.(kin|json|sct)$', caseSensitive: false), '');
        p.name = name;
      }
      return saveProject(p, customName: name);
    } catch (e) {
      debugPrint('Erreur importation projet: $e');
      return null;
    }
  }

  static void _saveIndex(List<SavedProjectMeta> list) {
    final raw = jsonEncode(list.map((m) => m.toJson()).toList());
    storeSet(_indexKey, raw);
  }

  static String _cleanName(String s) => s.replaceAll(RegExp(r'[^\w\-_.]'), '_');
}
