// Documents : les PDF enregistrés (plans, étiquettes…) et les fichiers d'atelier, accessibles à tout moment.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'i18n.dart';
import 'pdf_preview.dart';
import 'theme.dart';
import 'web_io.dart';
import 'workshop_page.dart';

Future<void> openDocuments(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DocumentsPage()));

/// Ouvre un fichier d'atelier (.kin) : l'atelier de découpe ; renvoie faux si ce n'en est pas un.
Future<bool> openWorkshopFile(BuildContext context, List<int> bytes) async {
  try {
    final j = jsonDecode(KinFormat.decode(Uint8List.fromList(bytes))) as Map<String, dynamic>;
    if (!WorkshopJob.isJob(j)) return false;
    if (!context.mounted) return true;
    await openWorkshop(context, WorkshopJob.fromJson(j));
    return true;
  } catch (_) {
    return false;
  }
}

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});
  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  List<DocEntry>? docs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await docList();
    if (mounted) setState(() => docs = l);
  }

  Future<void> _open(DocEntry d) async {
    final bytes = await docGet(d.name);
    if (bytes == null || !mounted) return;
    if (d.name.toLowerCase().endsWith('.kin')) {
      await openWorkshopFile(context, bytes);
      return _load();
    }
    await showPdfPreview(context, title: d.name, bytes: bytes, onSave: () => downloadBytes(d.name, bytes, mime: 'application/pdf'));
  }

  Future<void> _delete(DocEntry d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Supprimer le document ?')),
        content: Text(d.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Supprimer'))),
        ],
      ),
    );
    if (ok != true) return;
    await docDelete(d.name);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    String date(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      key: const ValueKey('documents_page'),
      appBar: AppBar(title: Text(tr('Documents'))),
      body: docs == null
          ? const Center(child: CircularProgressIndicator())
          : docs!.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Tokens.s4),
                    child: Text(tr('Aucun document pour l’instant. Les PDF enregistrés (plans, étiquettes) et les fichiers d’atelier viennent ici.'),
                        textAlign: TextAlign.center, style: t.bodyLarge),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(Tokens.s4),
                  itemCount: docs!.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = docs![i];
                    final atelier = d.name.toLowerCase().endsWith('.kin');
                    return ListTile(
                      key: ValueKey('doc_${d.name}'),
                      leading: Icon(atelier ? Icons.precision_manufacturing_outlined : Icons.picture_as_pdf_outlined, color: scheme.primary),
                      title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${atelier ? tr('Fichier d’atelier') : 'PDF'} · ${date(d.date)} · ${(d.size / 1024).ceil()} Ko'),
                      onTap: () => _open(d),
                      trailing: IconButton(tooltip: tr('Supprimer'), icon: const Icon(Icons.delete_outline), onPressed: () => _delete(d)),
                    );
                  },
                ),
    );
  }
}
