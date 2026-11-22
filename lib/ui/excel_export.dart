// Export natif Excel (.xlsx) 100% conforme au standard SketchCut PRO et QR Scanner.
// 3 feuilles exactes : 'Parts', 'Remains', 'Information '
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';

import '../engine/engine.dart';
import 'cut_pdf.dart';

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

class _SharedStrings {
  final Map<String, int> _map = {};
  final List<String> _list = [];

  int add(String s) {
    return _map.putIfAbsent(s, () {
      final idx = _list.length;
      _list.add(s);
      return idx;
    });
  }

  String toXml() {
    final sb = StringBuffer();
    sb.write('<?xml version="1.0" encoding="utf-8"?>');
    sb.write('<sst count="${_list.length}" uniqueCount="${_list.length}" xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    for (final s in _list) {
      sb.write('<si><t xml:space="preserve">${_xmlEscape(s)}</t></si>');
    }
    sb.write('</sst>');
    return sb.toString();
  }
}

/// Ajoute un fichier XML dans l'archive en utilisant la taille en octets (UTF-8), pas en caractères.
/// Évite le bug CRC-32 de ArchiveFile quand le XML contient des caractères accentués.
void _addXml(Archive archive, String name, String xml) {
  final bytes = utf8.encode(xml);
  archive.addFile(ArchiveFile(name, bytes.length, bytes));
}

/// Construit un classeur Excel .xlsx strictement identique au format SketchCut PRO (3 feuilles).
/// [material] : un seul panneau (caissons, façades ou fonds), à son format ; nul : tout le plan.
Uint8List buildExcelExport(CutPlan plan, {required Project project, String? order, String? material}) {
  final state = _Source(project, order ?? project.name);
  final cs = plan.settings;
  final parts = [for (final p in plan.parts) if (material == null || p.material == material) p];
  final sheets = [for (final s in plan.sheets) if (material == null || s.material == material) s];
  final sst = _SharedStrings();

  final sheet1 = _buildPartsSheet(state, parts, sst);
  final sheet2 = _buildRemainsSheet(sheets, sst);
  final sheet3 = _buildInformationSheet(state, parts, plan, sheets, material ?? cs.carcassMaterial, sst);
  final sharedStringsXml = sst.toXml();

  final archive = Archive();

  // 1. [Content_Types].xml
  const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default ContentType="application/xml" Extension="xml"/>'
      '<Default ContentType="application/vnd.openxmlformats-package.relationships+xml" Extension="rels"/>'
      '<Override ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml" PartName="/xl/workbook.xml"/>'
      '<Override ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml" PartName="/xl/worksheets/sheet1.xml"/>'
      '<Override ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml" PartName="/xl/styles.xml"/>'
      '<Override ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml" PartName="/xl/worksheets/sheet2.xml"/>'
      '<Override ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml" PartName="/xl/worksheets/sheet3.xml"/>'
      '<Override ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml" PartName="/xl/sharedStrings.xml"/>'
      '</Types>';
  _addXml(archive, '[Content_Types].xml', contentTypes);

  // 2. _rels/.rels
  const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';
  _addXml(archive, '_rels/.rels', rootRels);

  // 3. xl/_rels/workbook.xml.rels
  const wbRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>'
      '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>'
      '<Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>'
      '</Relationships>';
  _addXml(archive, 'xl/_rels/workbook.xml.rels', wbRels);

  // 4. xl/workbook.xml
  const workbookXml = '<?xml version="1.0" encoding="utf-8"?>'
      '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<bookViews><workbookView/></bookViews>'
      '<sheets>'
      '<sheet name="Parts" sheetId="1" r:id="rId1"/>'
      '<sheet name="Remains" sheetId="2" r:id="rId3"/>'
      '<sheet name="Information " sheetId="3" r:id="rId4"/>'
      '</sheets>'
      '<calcPr fullCalcOnLoad="1"/>'
      '</workbook>';
  _addXml(archive, 'xl/workbook.xml', workbookXml);

  // 5. xl/styles.xml
  _addXml(archive, 'xl/styles.xml', _sketchCutStylesXml);

  // 6. Sheets & SharedStrings
  _addXml(archive, 'xl/worksheets/sheet1.xml', sheet1);
  _addXml(archive, 'xl/worksheets/sheet2.xml', sheet2);
  _addXml(archive, 'xl/worksheets/sheet3.xml', sheet3);
  _addXml(archive, 'xl/sharedStrings.xml', sharedStringsXml);

  final zipEncoder = ZipEncoder();
  return Uint8List.fromList(zipEncoder.encode(archive));
}

/// Feuille 1 : 'Parts'
String _buildPartsSheet(_Source state, List<CutPart> parts, _SharedStrings sst) {
  final sb = StringBuffer();
  final lastRow = parts.length + 4;
  sb.write('<?xml version="1.0" encoding="utf-8"?>');
  sb.write('<worksheet xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
  sb.write('<dimension ref="A2:V$lastRow"/>');
  sb.write('<sheetViews><sheetView workbookViewId="0"/></sheetViews>');
  sb.write('<sheetFormatPr defaultRowHeight="15"/>');
  sb.write('<cols>');
  sb.write('<col min="1" max="1" width="5" customWidth="1"/>');
  sb.write('<col min="2" max="2" width="7" customWidth="1"/>');
  sb.write('<col min="3" max="3" width="15" customWidth="1"/>');
  sb.write('<col min="4" max="4" width="15" customWidth="1"/>');
  sb.write('<col min="5" max="5" width="12" customWidth="1"/>');
  sb.write('<col min="6" max="6" width="12" customWidth="1"/>');
  sb.write('<col min="7" max="7" width="30" customWidth="1"/>');
  sb.write('<col min="8" max="8" width="3" customWidth="1"/>');
  sb.write('<col min="9" max="9" width="4" customWidth="1"/>');
  sb.write('<col min="10" max="10" width="4" customWidth="1"/>');
  sb.write('<col min="11" max="11" width="4" customWidth="1"/>');
  sb.write('<col min="12" max="12" width="4" customWidth="1"/>');
  sb.write('<col min="13" max="13" width="3" customWidth="1"/>');
  sb.write('<col min="14" max="14" width="4" customWidth="1"/>');
  sb.write('<col min="15" max="15" width="4" customWidth="1"/>');
  sb.write('<col min="16" max="16" width="4" customWidth="1"/>');
  sb.write('<col min="17" max="17" width="4" customWidth="1"/>');
  sb.write('<col min="18" max="18" width="3" customWidth="1"/>');
  sb.write('<col min="19" max="19" width="4" customWidth="1"/>');
  sb.write('<col min="20" max="20" width="4" customWidth="1"/>');
  sb.write('<col min="21" max="21" width="4" customWidth="1"/>');
  sb.write('<col min="22" max="22" width="4" customWidth="1"/>');
  sb.write('</cols>');

  sb.write('<sheetData>');

  // Row 2 : Title 'Parts'
  sb.write('<row r="2"><c r="B2" s="1" t="s"><v>${sst.add("Parts")}</v></c></row>');

  // Row 3 : Super headers '2 ', '0.4 ', 'Grooves'
  sb.write('<row r="3">');
  sb.write('<c r="I3" s="8" t="s"><v>${sst.add("2 ")}</v></c>');
  sb.write('<c r="J3" s="10"/><c r="K3" s="10"/><c r="L3" s="13"/><c r="M3" s="6"/>');
  sb.write('<c r="N3" s="8" t="s"><v>${sst.add("0.4 ")}</v></c>');
  sb.write('<c r="O3" s="10"/><c r="P3" s="10"/><c r="Q3" s="13"/><c r="R3" s="6"/>');
  sb.write('<c r="S3" s="8" t="s"><v>${sst.add("Grooves")}</v></c>');
  sb.write('<c r="T3" s="10"/><c r="U3" s="10"/><c r="V3" s="13"/>');
  sb.write('</row>');

  // Row 4 : Column headers
  sb.write('<row r="4">');
  sb.write('<c r="B4" s="4" t="s"><v>${sst.add("#")}</v></c>');
  sb.write('<c r="C4" s="5" t="s"><v>${sst.add("Length")}</v></c>');
  sb.write('<c r="D4" s="5" t="s"><v>${sst.add("Width")}</v></c>');
  sb.write('<c r="E4" s="3" t="s"><v>${sst.add("Quantity")}</v></c>');
  sb.write('<c r="F4" s="3" t="s"><v>${sst.add("Rotation")}</v></c>');
  sb.write('<c r="G4" s="3" t="s"><v>${sst.add("Description")}</v></c>');
  sb.write('<c r="I4" s="9" t="s"><v>${sst.add("Length")}</v></c><c r="J4" s="11"/>');
  sb.write('<c r="K4" s="12" t="s"><v>${sst.add("Width")}</v></c><c r="L4" s="14"/>');
  sb.write('<c r="N4" s="9" t="s"><v>${sst.add("Length")}</v></c><c r="O4" s="11"/>');
  sb.write('<c r="P4" s="12" t="s"><v>${sst.add("Width")}</v></c><c r="Q4" s="14"/>');
  sb.write('<c r="S4" s="9" t="s"><v>${sst.add("Length")}</v></c><c r="T4" s="11"/>');
  sb.write('<c r="U4" s="12" t="s"><v>${sst.add("Width")}</v></c><c r="V4" s="14"/>');
  sb.write('</row>');

  // Rows 5+ : Parts
  final sp = state.project.specs;
  for (var i = 0; i < parts.length; i++) {
    final r = i + 5;
    final p = parts[i];
    final isFront = isFrontPart(p);
    final is2mm = isFront ? (sp.frontEdge >= 1.5) : (sp.carcassEdge >= 1.5);
    final desc = '${p.name} ${p.cabinet}'.trim();

    // 2mm edges
    final l1_2 = is2mm && p.edgeLong >= 1 ? '1' : '';
    final l2_2 = is2mm && p.edgeLong >= 2 ? '1' : '';
    final w1_2 = is2mm && p.edgeShort >= 1 ? '1' : '';
    final w2_2 = is2mm && p.edgeShort >= 2 ? '1' : '';

    // 0.4mm edges
    final l1_04 = !is2mm && p.edgeLong >= 1 ? '1' : '';
    final l2_04 = !is2mm && p.edgeLong >= 2 ? '1' : '';
    final w1_04 = !is2mm && p.edgeShort >= 1 ? '1' : '';
    final w2_04 = !is2mm && p.edgeShort >= 2 ? '1' : '';

    // Grooves
    final gL1 = p.grooveLong >= 1 ? '1' : '';
    final gL2 = p.grooveLong >= 2 ? '1' : '';
    final gW1 = p.grooveShort >= 1 ? '1' : '';
    final gW2 = p.grooveShort >= 2 ? '1' : '';

    sb.write('<row r="$r">');
    sb.write('<c r="B$r" s="19"><v>${i + 1}</v></c>');
    sb.write('<c r="C$r" s="21"><v>${p.length}</v></c>');
    sb.write('<c r="D$r" s="21"><v>${p.width}</v></c>');
    sb.write('<c r="E$r" s="22"><v>${p.qty}</v></c>');
    sb.write('<c r="F$r" s="16" t="s"><v>${sst.add(p.canRotate ? "Yes" : "No")}</v></c>');
    sb.write('<c r="G$r" s="16" t="s"><v>${sst.add(desc)}</v></c>');
    sb.write('<c r="H$r" s="2"/>');

    // 2 mm
    sb.write(l1_2.isNotEmpty ? '<c r="I$r" s="23"><v>1</v></c>' : '<c r="I$r" s="23"/>');
    sb.write(l2_2.isNotEmpty ? '<c r="J$r" s="24"><v>1</v></c>' : '<c r="J$r" s="24"/>');
    sb.write(w1_2.isNotEmpty ? '<c r="K$r" s="24"><v>1</v></c>' : '<c r="K$r" s="24"/>');
    sb.write(w2_2.isNotEmpty ? '<c r="L$r" s="25"><v>1</v></c>' : '<c r="L$r" s="25"/>');
    sb.write('<c r="M$r" s="2"/>');

    // 0.4 mm
    sb.write(l1_04.isNotEmpty ? '<c r="N$r" s="23"><v>1</v></c>' : '<c r="N$r" s="23"/>');
    sb.write(l2_04.isNotEmpty ? '<c r="O$r" s="24"><v>1</v></c>' : '<c r="O$r" s="24"/>');
    sb.write(w1_04.isNotEmpty ? '<c r="P$r" s="24"><v>1</v></c>' : '<c r="P$r" s="24"/>');
    sb.write(w2_04.isNotEmpty ? '<c r="Q$r" s="25"><v>1</v></c>' : '<c r="Q$r" s="25"/>');
    sb.write('<c r="R$r" s="2"/>');

    // Grooves
    sb.write(gL1.isNotEmpty ? '<c r="S$r" s="23"><v>1</v></c>' : '<c r="S$r" s="23"/>');
    sb.write(gL2.isNotEmpty ? '<c r="T$r" s="24"><v>1</v></c>' : '<c r="T$r" s="24"/>');
    sb.write(gW1.isNotEmpty ? '<c r="U$r" s="24"><v>1</v></c>' : '<c r="U$r" s="24"/>');
    sb.write(gW2.isNotEmpty ? '<c r="V$r" s="25"><v>1</v></c>' : '<c r="V$r" s="25"/>');
    sb.write('</row>');
  }

  sb.write('</sheetData>');

  // Merges
  sb.write('<mergeCells>');
  sb.write('<mergeCell ref="B2:D2"/>');
  sb.write('<mergeCell ref="I3:L3"/>');
  sb.write('<mergeCell ref="I4:J4"/>');
  sb.write('<mergeCell ref="K4:L4"/>');
  sb.write('<mergeCell ref="N3:Q3"/>');
  sb.write('<mergeCell ref="N4:O4"/>');
  sb.write('<mergeCell ref="P4:Q4"/>');
  sb.write('<mergeCell ref="S3:V3"/>');
  sb.write('<mergeCell ref="S4:T4"/>');
  sb.write('<mergeCell ref="U4:V4"/>');
  sb.write('</mergeCells>');

  sb.write('<headerFooter/>');
  sb.write('</worksheet>');
  return sb.toString();
}

/// Feuille 2 : 'Remains'
String _buildRemainsSheet(List<CutSheet> sheets, _SharedStrings sst) {
  final sb = StringBuffer();
  // Collecter les chutes notables (>= 200 mm)
  final remains = <(int, int, int)>[];
  for (final s in sheets) {
    for (final r in s.remnants) {
      if (r.$3 >= 200 && r.$4 >= 200) {
        remains.add((r.$3.round(), r.$4.round(), 1));
      }
    }
  }

  final lastRow = math.max(5, remains.length + 4);
  sb.write('<?xml version="1.0" encoding="utf-8"?>');
  sb.write('<worksheet xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
  sb.write('<dimension ref="A2:F$lastRow"/>');
  sb.write('<sheetViews><sheetView workbookViewId="0"/></sheetViews>');
  sb.write('<sheetFormatPr defaultRowHeight="15"/>');
  sb.write('<cols>');
  sb.write('<col min="1" max="1" width="5" customWidth="1"/>');
  sb.write('<col min="2" max="2" width="7" customWidth="1"/>');
  sb.write('<col min="3" max="3" width="15" customWidth="1"/>');
  sb.write('<col min="4" max="4" width="15" customWidth="1"/>');
  sb.write('<col min="5" max="5" width="12" customWidth="1"/>');
  sb.write('</cols>');

  sb.write('<sheetData>');
  sb.write('<row r="2"><c r="B2" s="1" t="s"><v>${sst.add("Remains")}</v></c></row>');
  sb.write('<row r="4">');
  sb.write('<c r="B4" s="27" t="s"><v>${sst.add("#")}</v></c>');
  sb.write('<c r="C4" s="28" t="s"><v>${sst.add("Length")}</v></c>');
  sb.write('<c r="D4" s="28" t="s"><v>${sst.add("Width")}</v></c>');
  sb.write('<c r="E4" s="26" t="s"><v>${sst.add("Quantity")}</v></c>');
  sb.write('<c r="F4" s="26" t="s"><v>${sst.add("Trim")}</v></c>');
  sb.write('</row>');

  if (remains.isEmpty) {
    sb.write('<row r="5"><c r="B5" s="20"/><c r="C5" s="20"/><c r="D5" s="20"/><c r="E5" s="20"/></row>');
  } else {
    for (var i = 0; i < remains.length; i++) {
      final r = i + 5;
      final rem = remains[i];
      sb.write('<row r="$r">');
      sb.write('<c r="B$r" s="19"><v>${i + 1}</v></c>');
      sb.write('<c r="C$r" s="21"><v>${rem.$1}</v></c>');
      sb.write('<c r="D$r" s="21"><v>${rem.$2}</v></c>');
      sb.write('<c r="E$r" s="22"><v>${rem.$3}</v></c>');
      sb.write('<c r="F$r" s="16" t="s"><v>${sst.add("Yes")}</v></c>');
      sb.write('</row>');
    }
  }

  sb.write('</sheetData>');
  sb.write('<mergeCells><mergeCell ref="B2:D2"/></mergeCells>');
  sb.write('<headerFooter/>');
  sb.write('</worksheet>');
  return sb.toString();
}

/// Feuille 3 : 'Information '
String _buildInformationSheet(_Source state, List<CutPart> parts, CutPlan plan, List<CutSheet> sheets, String material, _SharedStrings sst) {
  final sb = StringBuffer();
  final p = state.project;
  final cs = plan.settings;
  final (mL, mW) = cs.sheetDimensionsFor(material);
  final sp = p.specs;
  final now = DateTime.now();
  final dateStr = '${now.month}/${now.day}/${now.year}';

  final fSheet = cs.sheetDimensionsFor(cs.frontKey), bSheet = cs.sheetDimensionsFor(cs.backMaterial);
  final sheetArea = mL * mW / 1e6;
  final numSheets = sheets.where((s) => !s.fromStock).length;
  final allSheetsArea = sheets.fold<double>(0, (a, s) => a + s.length * s.width) / 1e6; // chaque panneau a son format
  final partsCount = parts.fold<int>(0, (a, x) => a + x.qty);
  final partsArea = parts.fold<double>(0, (a, x) => a + x.area * x.qty) / 1e6;
  final remnArea = sheets.expand((s) => s.remnants).fold<double>(0, (a, r) => a + r.$3 * r.$4) / 1e6;
  final wasteArea = math.max(0.0, allSheetsArea - partsArea - remnArea);
  final cutLen = plan.cutLengthOf(material);
  final groovesLen = parts.fold<double>(0, (a, x) => a + x.grooveLength * x.qty) / 1000;

  final edge2 = parts.where((x) => isFrontPart(x) ? (sp.frontEdge >= 1.5) : (sp.carcassEdge >= 1.5))
      .fold<double>(0, (a, x) => a + x.edgeLength * x.qty) / 1000;
  final edge04 = parts.where((x) => isFrontPart(x) ? (sp.frontEdge < 1.5) : (sp.carcassEdge < 1.5))
      .fold<double>(0, (a, x) => a + x.edgeLength * x.qty) / 1000;

  sb.write('<?xml version="1.0" encoding="utf-8"?>');
  sb.write('<worksheet xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
  sb.write('<dimension ref="A2:E30"/>');
  sb.write('<sheetViews><sheetView workbookViewId="0"/></sheetViews>');
  sb.write('<sheetFormatPr defaultRowHeight="15"/>');
  sb.write('<cols>');
  sb.write('<col min="1" max="1" width="5" customWidth="1"/>');
  sb.write('<col min="2" max="2" width="35" customWidth="1"/>');
  sb.write('<col min="3" max="3" width="20" customWidth="1"/>');
  sb.write('<col min="4" max="4" width="35" customWidth="1"/>');
  sb.write('<col min="5" max="5" width="20" customWidth="1"/>');
  sb.write('</cols>');

  sb.write('<sheetData>');

  // Row 2 : Order
  sb.write('<row r="2">');
  sb.write('<c r="B2" s="30" t="s"><v>${sst.add("Order:")}</v></c>');
  sb.write('<c r="C2" s="29" t="s"><v>${sst.add(state.order)}</v></c>');
  sb.write('<c r="D2" s="1"/><c r="E2" s="1"/>');
  sb.write('</row>');

  // Row 4 : Date
  sb.write('<row r="4">');
  sb.write('<c r="B4" s="31" t="s"><v>${sst.add("Date:")}</v></c>');
  sb.write('<c r="C4" s="7" t="s"><v>${sst.add(dateStr)}</v></c>');
  sb.write('</row>');

  // Row 5 : Date of completion
  sb.write('<row r="5">');
  sb.write('<c r="B5" s="31" t="s"><v>${sst.add("Date of completion:")}</v></c>');
  sb.write('<c r="C5" s="7"/>');
  sb.write('</row>');

  // Row 7 : Material & Thickness
  sb.write('<row r="7">');
  sb.write('<c r="B7" s="31" t="s"><v>${sst.add("Material:")}</v></c>');
  sb.write('<c r="C7" s="7" t="s"><v>${sst.add(material)}</v></c>');
  sb.write('<c r="D7" s="31" t="s"><v>${sst.add("Thickness:")}</v></c>');
  sb.write('<c r="E7" s="7" t="s"><v>${sst.add("${cs.thicknessFor(material)}")}</v></c>');
  sb.write('</row>');

  // Row 8 : Sheet size & Square of sheet
  sb.write('<row r="8">');
  sb.write('<c r="B8" s="31" t="s"><v>${sst.add("Sheet Size")}</v></c>');
  sb.write('<c r="C8" s="7" t="s"><v>${sst.add("$mL X $mW")}</v></c>');
  sb.write('<c r="D8" s="31" t="s"><v>${sst.add("Square of sheet:")}</v></c>');
  sb.write('<c r="E8" s="7" t="s"><v>${sst.add("${sheetArea.toStringAsFixed(2)} sq.m.")}</v></c>');
  sb.write('</row>');

  // Row 9 : Number of sheets & Square of all sheets
  sb.write('<row r="9">');
  sb.write('<c r="B9" s="31" t="s"><v>${sst.add("Number of sheets:")}</v></c>');
  sb.write('<c r="C9" s="7"><v>$numSheets</v></c>');
  sb.write('<c r="D9" s="31" t="s"><v>${sst.add("Square of all sheets:")}</v></c>');
  sb.write('<c r="E9" s="7" t="s"><v>${sst.add("${allSheetsArea.toStringAsFixed(2)} sq.m.")}</v></c>');
  sb.write('</row>');

  // Row 10 : Remains used
  sb.write('<row r="10">');
  sb.write('<c r="B10" s="31" t="s"><v>${sst.add("Number of used remains:")}</v></c>');
  sb.write('<c r="C10" s="7"><v>0</v></c>');
  sb.write('<c r="D10" s="31" t="s"><v>${sst.add("Square of used remains:")}</v></c>');
  sb.write('<c r="E10" s="7" t="s"><v>${sst.add("0 sq.m.")}</v></c>');
  sb.write('</row>');

  // Row 12 : Number of parts & Square of parts
  sb.write('<row r="12">');
  sb.write('<c r="B12" s="31" t="s"><v>${sst.add("Number of parts:")}</v></c>');
  sb.write('<c r="C12" s="7"><v>$partsCount</v></c>');
  sb.write('<c r="D12" s="31" t="s"><v>${sst.add("Square of parts:")}</v></c>');
  sb.write('<c r="E12" s="7" t="s"><v>${sst.add("${partsArea.toStringAsFixed(3)} sq.m.")}</v></c>');
  sb.write('</row>');

  // Row 14 : Square of new remains & Square of waste
  sb.write('<row r="14">');
  sb.write('<c r="B14" s="31" t="s"><v>${sst.add("Square of new remains:")}</v></c>');
  sb.write('<c r="C14" s="7" t="s"><v>${sst.add("${remnArea.toStringAsFixed(2)} sq.m.")}</v></c>');
  sb.write('<c r="D14" s="31" t="s"><v>${sst.add("Square of waste:")}</v></c>');
  sb.write('<c r="E14" s="7" t="s"><v>${sst.add("${wasteArea.toStringAsFixed(2)} sq.m.")}</v></c>');
  sb.write('</row>');

  // Row 16 : Length of cuts & Grooves length
  sb.write('<row r="16">');
  sb.write('<c r="B16" s="31" t="s"><v>${sst.add("Length of cuts:")}</v></c>');
  sb.write('<c r="C16" s="7" t="s"><v>${sst.add("${cutLen.toStringAsFixed(1)} m.")}</v></c>');
  sb.write('<c r="D16" s="31" t="s"><v>${sst.add("Grooves length:")}</v></c>');
  sb.write('<c r="E16" s="7" t="s"><v>${sst.add("${groovesLen.toStringAsFixed(1)} m.")}</v></c>');
  sb.write('</row>');

  // Row 18 : Edging length title
  sb.write('<row r="18"><c r="B18" s="32" t="s"><v>${sst.add("Edging length")}</v></c></row>');

  // Row 19 : Edging 2mm & 0.4mm
  sb.write('<row r="19">');
  sb.write('<c r="B19" s="31" t="s"><v>${sst.add("2 ")}</v></c>');
  sb.write('<c r="C19" s="7" t="s"><v>${sst.add("${edge2.toStringAsFixed(2)} m.")}</v></c>');
  sb.write('<c r="D19" s="31" t="s"><v>${sst.add("0.4 ")}</v></c>');
  sb.write('<c r="E19" s="7" t="s"><v>${sst.add("${edge04.toStringAsFixed(2)} m.")}</v></c>');
  sb.write('</row>');

  // Row 21 : Information title
  sb.write('<row r="21"><c r="B21" s="32" t="s"><v>${sst.add("Information:")}</v></c></row>');

  // Rows 22-30 : Information block (merged B22:E30)
  final clientInfo = p.client.name.isNotEmpty ? 'Client : ${p.client.name}\n' : '';
  final infoText = 'Kitchinox - Atelier de menuiserie\nProjet : ${p.name}\n$clientInfo'
      'Trait de scie : ${cs.kerf} mm · Recoupe bords : ${cs.trim} mm\n'
      'Caissons : ${cs.carcassMaterial} (${cs.sheetLength}×${cs.sheetWidth}×${cs.carcassThickness} mm)\n'
      'Façades : ${cs.frontMaterial} (${fSheet.$1}×${fSheet.$2}×${cs.doorThickness} mm)\n'
      'Fonds : ${cs.backMaterial} (${bSheet.$1}×${bSheet.$2}×${cs.backThickness} mm)\n';

  sb.write('<row r="22"><c r="B22" s="33" t="s"><v>${sst.add(infoText)}</v></c><c r="C22" s="15"/><c r="D22" s="15"/><c r="E22" s="36"/></row>');
  for (var r = 23; r <= 29; r++) {
    sb.write('<row r="$r"><c r="B$r" s="34"/><c r="E$r" s="37"/></row>');
  }
  sb.write('<row r="30"><c r="B30" s="35"/><c r="C30" s="17"/><c r="D30" s="17"/><c r="E30" s="18"/></row>');

  sb.write('</sheetData>');
  sb.write('<mergeCells><mergeCell ref="B22:E30"/></mergeCells>');
  sb.write('<headerFooter/>');
  sb.write('</worksheet>');
  return sb.toString();
}

/// Feuille de style identique au format exporté par SketchCut PRO
const _sketchCutStylesXml = '<?xml version="1.0" encoding="utf-8"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="0"/>'
    '<fonts count="5">'
    '<font><sz val="11"/><name val="Calibri"/></font>'
    '<font><sz val="14"/><name val="Calibri"/></font>'
    '<font><sz val="10"/><name val="Calibri"/></font>'
    '<font><sz val="12"/><name val="Calibri"/></font>'
    '<font><sz val="11"/><color rgb="FFFFFFFF" tint="0"/><name val="Calibri"/></font>'
    '</fonts>'
    '<fills count="4">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFDCDCDC" tint="0"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FF969696" tint="0"/></patternFill></fill>'
    '</fills>'
    '<borders count="27">'
    '<border><left/><right/><top/><bottom/><diagonal/></border>'
    '<border><left style="thick"/><right/><top style="thick"/><bottom style="thick"/><diagonal/></border>'
    '<border><left/><right style="thick"/><top style="thick"/><bottom style="thick"/><diagonal/></border>'
    '<border><left style="thick"/><right style="thick"/><top style="thick"/><bottom style="thick"/><diagonal/></border>'
    '<border><left/><right style="thin"/><top style="thick"/><bottom style="thick"/><diagonal/></border>'
    '<border><left/><right/><top style="thin"/><bottom/><diagonal/></border>'
    '<border><left style="thin"/><right/><top style="thin"/><bottom style="thin"/><diagonal/></border>'
    '<border><left/><right style="thin"/><top style="thin"/><bottom style="thin"/><diagonal/></border>'
    '<border><left style="thin"/><right style="thin"/><top style="thin"/><bottom style="thin"/><diagonal/></border>'
    '<border><left style="thin"/><right/><top/><bottom/><diagonal/></border>'
    '<border><left/><right style="thin"/><top/><bottom/><diagonal/></border>'
    '<border><left style="thin"/><right/><top style="thin"/><bottom/><diagonal/></border>'
    '<border><left/><right style="thin"/><top style="thin"/><bottom/><diagonal/></border>'
    '<border><left style="thin"/><right/><top/><bottom style="thin"/><diagonal/></border>'
    '<border><left/><right style="thin"/><top/><bottom style="thin"/><diagonal/></border>'
    '<border><left/><right/><top/><bottom style="thin"/><diagonal/></border>'
    '<border><left style="thin"/><right/><top style="thick"/><bottom style="thick"/><diagonal/></border>'
    '<border><left style="thick"/><right/><top/><bottom/><diagonal/></border>'
    '<border><left/><right style="thick"/><top/><bottom/><diagonal/></border>'
    '<border><left style="thick"/><right/><top style="thin"/><bottom/><diagonal/></border>'
    '<border><left/><right style="thick"/><top style="thin"/><bottom/><diagonal/></border>'
    '<border><left style="thick"/><right/><top/><bottom style="thin"/><diagonal/></border>'
    '<border><left/><right style="thick"/><top/><bottom style="thin"/><diagonal/></border>'
    '<border><left style="thick"/><right/><top style="thick"/><bottom/><diagonal/></border>'
    '<border><left/><right style="thick"/><top style="thick"/><bottom/><diagonal/></border>'
    '<border><left style="thick"/><right/><top/><bottom style="thick"/><diagonal/></border>'
    '<border><left/><right style="thick"/><top/><bottom style="thick"/><diagonal/></border>'
    '</borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="38">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="2" borderId="8" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="2" borderId="1" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="2" borderId="4" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="8" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="2" borderId="1" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="2" borderId="0" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="2" borderId="16" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="3" borderId="2" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="2" borderId="2" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="5" xfId="0"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="8" xfId="0"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="15" xfId="0"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="22" xfId="0"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="6" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="8" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="8" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="8" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="6" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="8" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="7" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="2" borderId="8" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="2" borderId="1" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="2" borderId="4" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="3" fillId="0" borderId="8" xfId="0"><alignment horizontal="center"/></xf>'
    '<xf numFmtId="0" fontId="3" fillId="0" borderId="8" xfId="0"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="8" xfId="0"/>'
    '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="19" xfId="0"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="17" xfId="0"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="21" xfId="0"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="20" xfId="0"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="18" xfId="0"/>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '<dxfs count="0"/>'
    '</styleSheet>';

class _Source {
  final Project project;
  final String order;
  const _Source(this.project, this.order);
}
