/// Excel (.xlsx) : lecture d'un classeur et écriture d'un tableau simple. Les seuls formats de l'app sont .kin, .sct et Excel.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'manual_cut.dart';

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _unesc(String s) => s
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

String _col(int i) {
  var n = i + 1, s = '';
  while (n > 0) {
    s = String.fromCharCode(65 + (n - 1) % 26) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

int _colIndex(String ref) {
  var n = 0;
  for (final c in ref.codeUnits) {
    if (c < 65 || c > 90) break;
    n = n * 26 + c - 64;
  }
  return n - 1;
}

/// Classeur d'une feuille ; la première ligne (en-tête) est en gras.
Uint8List xlsxTable(String sheet, List<List<Object?>> rows, {List<int> widths = const []}) {
  final sb = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
  if (widths.isNotEmpty) {
    sb.write('<cols>');
    for (var i = 0; i < widths.length; i++) {
      sb.write('<col min="${i + 1}" max="${i + 1}" width="${widths[i]}" customWidth="1"/>');
    }
    sb.write('</cols>');
  }
  sb.write('<sheetData>');
  for (var r = 0; r < rows.length; r++) {
    sb.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      if (v == null || v == '') continue;
      final ref = '${_col(c)}${r + 1}', st = r == 0 ? ' s="1"' : '';
      sb.write(v is num ? '<c r="$ref"$st><v>$v</v></c>' : '<c r="$ref"$st t="inlineStr"><is><t xml:space="preserve">${_esc('$v')}</t></is></c>');
    }
    sb.write('</row>');
  }
  sb.write('</sheetData></worksheet>');
  final a = Archive();
  void add(String name, String xml) {
    final b = utf8.encode(xml);
    a.addFile(ArchiveFile(name, b.length, b));
  }

  const head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  const ns = 'http://schemas.openxmlformats.org';
  add('[Content_Types].xml', '$head<Types xmlns="$ns/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>');
  add('_rels/.rels', '$head<Relationships xmlns="$ns/package/2006/relationships"><Relationship Id="rId1" Type="$ns/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>');
  add('xl/workbook.xml', '$head<workbook xmlns="$ns/spreadsheetml/2006/main" xmlns:r="$ns/officeDocument/2006/relationships"><sheets><sheet name="${_esc(sheet)}" sheetId="1" r:id="rId1"/></sheets></workbook>');
  add('xl/_rels/workbook.xml.rels', '$head<Relationships xmlns="$ns/package/2006/relationships"><Relationship Id="rId1" Type="$ns/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="$ns/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>');
  add('xl/styles.xml', '$head<styleSheet xmlns="$ns/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders>'
      '<cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf fontId="0"/><xf fontId="1" applyFont="1"/></cellXfs></styleSheet>');
  add('xl/worksheets/sheet1.xml', sb.toString());
  return Uint8List.fromList(ZipEncoder().encode(a));
}

/// Feuilles d'un classeur, dans l'ordre : nom et lignes (cellules en texte). Null si ce n'est pas un classeur Excel.
List<(String, List<List<String>>)>? readXlsx(List<int> bytes) {
  try {
    final a = ZipDecoder().decodeBytes(bytes);
    String? text(String name) {
      final f = a.findFile(name);
      return f == null ? null : utf8.decode(f.content as List<int>, allowMalformed: true);
    }

    String attr(String tag, String name) => RegExp('\\b$name="([^"]*)"').firstMatch(tag)?.group(1) ?? '';

    final wb = text('xl/workbook.xml');
    if (wb == null) return null;
    final rels = {
      for (final m in RegExp(r'<(?:\w+:)?Relationship\b[^>]*>').allMatches(text('xl/_rels/workbook.xml.rels') ?? ''))
        attr(m[0]!, 'Id'): attr(m[0]!, 'Target'),
    };
    String joined(String xml) => [for (final t in RegExp(r'<(?:\w+:)?t(?:\s[^>]*)?>([\s\S]*?)</(?:\w+:)?t>').allMatches(xml)) _unesc(t[1]!)].join();
    final shared = [for (final m in RegExp(r'<(?:\w+:)?si>([\s\S]*?)</(?:\w+:)?si>|<(?:\w+:)?si/>').allMatches(text('xl/sharedStrings.xml') ?? '')) joined(m[1] ?? '')];
    final out = <(String, List<List<String>>)>[];
    for (final s in RegExp(r'<(?:\w+:)?sheet\b[^>]*>').allMatches(wb)) {
      final name = _unesc(RegExp(r'\bname="([^"]*)"').firstMatch(s[0]!)?[1] ?? '');
      final id = RegExp(r'\br:id="([^"]+)"').firstMatch(s[0]!)?[1] ?? '';
      var target = rels[id] ?? '';
      target = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      final xml = text(target);
      if (xml == null) continue;
      final rows = <List<String>>[];
      for (final r in RegExp(r'<(?:\w+:)?row\b([^>]*)>([\s\S]*?)</(?:\w+:)?row>').allMatches(xml)) {
        final cells = <String>[];
        for (final c in RegExp(r'<(?:\w+:)?c\b([^>]*?)(?:/>|>([\s\S]*?)</(?:\w+:)?c>)').allMatches(r[2]!)) {
          final ref = RegExp(r'\br="([A-Z]+)\d+"').firstMatch(c[1]!)?[1];
          final i = ref == null ? cells.length : _colIndex(ref);
          while (cells.length <= i) {
            cells.add('');
          }
          final type = RegExp(r'\bt="([^"]+)"').firstMatch(c[1]!)?[1];
          final body = c[2] ?? '';
          final v = RegExp(r'<(?:\w+:)?v>([\s\S]*?)</(?:\w+:)?v>').firstMatch(body)?[1];
          cells[i] = type == 's'
              ? (() {
                  final k = int.tryParse(v ?? '') ?? -1;
                  return k >= 0 && k < shared.length ? shared[k] : '';
                })()
              : type == 'inlineStr'
                  ? joined(body)
                  : _unesc(v ?? '');
        }
        rows.add(cells);
      }
      out.add((name, rows));
    }
    return out;
  } catch (_) {
    return null;
  }
}

double? _num(String s) => double.tryParse(s.trim().replaceAll(' ', '').replaceAll(',', '.'));

/// Débit lu dans un classeur Excel : celui de SketchCut PRO / kitchinox (feuille « Parts »), ou un simple tableau
/// « nom, longueur, largeur, quantité, épaisseur » avec ou sans en-tête. Null si aucune pièce n'est trouvée.
ManualCut? manualCutFromXlsx(List<int> bytes, {String order = 'Débit manuel'}) {
  final sheets = readXlsx(bytes);
  if (sheets == null || sheets.isEmpty) return null;
  final job = ManualCut(order: order);
  final rows = (sheets.where((s) => s.$1.trim().toLowerCase() == 'parts').firstOrNull ?? sheets.first).$2;
  // colonnes d'après l'en-tête
  int find(List<String> row, RegExp re) => row.indexWhere((c) => re.hasMatch(c.trim().toLowerCase()));
  var head = -1, cl = -1, cw = -1, cq = -1, cr = -1, cd = -1, ct = -1;
  for (var i = 0; i < rows.length && i < 12; i++) {
    final l = find(rows[i], RegExp(r'^(length|longueur|long\.?|l)\b')), w = find(rows[i], RegExp(r'^(width|largeur|larg\.?|w)\b'));
    if (l < 0 || w < 0) continue;
    head = i;
    cl = l;
    cw = w;
    cq = find(rows[i], RegExp(r'^(quantity|quantit|qt|nombre|nb)'));
    cr = find(rows[i], RegExp(r'^rot'));
    cd = find(rows[i], RegExp(r'^(description|d[ée]signation|nom|name|pi[èe]ce)'));
    ct = find(rows[i], RegExp(r'^(thickness|[ée]pais|ep\b)'));
    break;
  }
  final sketch = head >= 0 && rows[head].length > 10 && cl < 5; // colonnes de chants et de rainures de SketchCut
  for (final row in rows.skip(head + 1)) {
    String at(int i) => i >= 0 && i < row.length ? row[i].trim() : '';
    var name = at(cd);
    double? l, w, q, th;
    if (head >= 0) {
      l = _num(at(cl));
      w = _num(at(cw));
      q = _num(at(cq));
      th = _num(at(ct));
    } else {
      // sans en-tête : le premier nombre est la longueur, ce qui précède est le nom
      final k = row.indexWhere((c) => _num(c) != null);
      if (k < 0) continue;
      name = row.sublist(0, k).where((c) => c.trim().isNotEmpty).join(' ');
      l = _num(at(k));
      w = _num(at(k + 1));
      q = _num(at(k + 2));
      th = _num(at(k + 3));
    }
    if (l == null || w == null || l <= 0 || w <= 0) continue;
    int edges(int c) => [for (var i = c; i < c + 2; i++) if (at(i) == '1') 1].length;
    if (th != null && th > 0 && job.parts.isEmpty) job.thickness = th.round();
    job.parts.add(ManualPart(
      length: l.round(),
      width: w.round(),
      qty: (q ?? 1).round().clamp(1, 999),
      rotate: !RegExp(r'^(no|non|0)$').hasMatch(at(cr).toLowerCase()),
      edgeLong: sketch ? edges(8) + edges(13) : 0,
      edgeShort: sketch ? edges(10) + edges(15) : 0,
      grooveLong: sketch ? edges(18) : 0,
      grooveShort: sketch ? edges(20) : 0,
      desc: name,
    ));
  }
  if (job.parts.isEmpty) return null;
  // feuille « Information » : commande, matière, épaisseur, format
  final info = sheets.where((s) => s.$1.trim().toLowerCase() == 'information').firstOrNull?.$2 ?? const [];
  String value(String label) {
    for (final r in info) {
      for (var i = 0; i + 1 < r.length; i++) {
        if (r[i].trim().toLowerCase() == label) return r[i + 1].trim();
      }
    }
    return '';
  }

  if (value('order:').isNotEmpty) job.order = value('order:');
  if (value('material:').isNotEmpty) job.material = value('material:');
  job.thickness = int.tryParse(value('thickness:')) ?? job.thickness;
  final f = RegExp(r'(\d+)\s*[xX×]\s*(\d+)').firstMatch(value('sheet size'));
  if (f != null) {
    job.sheetLength = int.parse(f[1]!);
    job.sheetWidth = int.parse(f[2]!);
  }
  return job;
}
