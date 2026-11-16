// Export natif Excel (.xlsx) sans dépendance tierce (OpenXML via archive).
// Feuilles : Projet, Débit & Pièces, Nomenclature (BOM), Quincaillerie & Équipements.
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'cut_pdf.dart';
import 'tech_drawings.dart';

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Construit un classeur Excel .xlsx complet et stylé d'après l'état actuel du projet.
Uint8List buildExcelExport(AppState state) {
  final p = state.project;
  final e = state.engine;
  final bom = state.bom;
  final cs = p.cut;
  final reps = repereNumbers(e);
  final parts = cutList(e, cs, reps);
  final db = state.db;
  final specs = p.specs;
  final hardware = db != null ? hardwareList(e, db, specs, parts, bom.plinthLength) : <SupplyLine>[];

  // Construction des feuilles
  final sheet1 = _buildProjectSheet(state);
  final sheet2 = _buildCutSheet(state, parts);
  final sheet3 = _buildBomSheet(state);
  final sheet4 = _buildHardwareSheet(state, hardware);

  final archive = Archive();

  // 1. [Content_Types].xml
  const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet4.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>''';
  archive.addFile(ArchiveFile('[Content_Types].xml', contentTypes.length, utf8.encode(contentTypes)));

  // 2. _rels/.rels
  const rootRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';
  archive.addFile(ArchiveFile('_rels/.rels', rootRels.length, utf8.encode(rootRels)));

  // 3. xl/_rels/workbook.xml.rels
  const wbRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet4.xml"/>
</Relationships>''';
  archive.addFile(ArchiveFile('xl/_rels/workbook.xml.rels', wbRels.length, utf8.encode(wbRels)));

  // 4. xl/workbook.xml
  const workbookXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Projet" sheetId="1" r:id="rId1"/>
    <sheet name="Débit &amp; Pièces" sheetId="2" r:id="rId2"/>
    <sheet name="Nomenclature (BOM)" sheetId="3" r:id="rId3"/>
    <sheet name="Quincaillerie" sheetId="4" r:id="rId4"/>
  </sheets>
</workbook>''';
  archive.addFile(ArchiveFile('xl/workbook.xml', workbookXml.length, utf8.encode(workbookXml)));

  // 5. xl/styles.xml
  final stylesXml = _buildStylesXml();
  archive.addFile(ArchiveFile('xl/styles.xml', stylesXml.length, utf8.encode(stylesXml)));

  // 6. Feuilles
  archive.addFile(ArchiveFile('xl/worksheets/sheet1.xml', sheet1.length, utf8.encode(sheet1)));
  archive.addFile(ArchiveFile('xl/worksheets/sheet2.xml', sheet2.length, utf8.encode(sheet2)));
  archive.addFile(ArchiveFile('xl/worksheets/sheet3.xml', sheet3.length, utf8.encode(sheet3)));
  archive.addFile(ArchiveFile('xl/worksheets/sheet4.xml', sheet4.length, utf8.encode(sheet4)));

  final zipEncoder = ZipEncoder();
  final bytes = zipEncoder.encode(archive);
  return Uint8List.fromList(bytes);
}

String _buildStylesXml() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="4">
    <font><sz val="10"/><name val="Segoe UI"/></font>
    <font><b/><sz val="10"/><name val="Segoe UI"/></font>
    <font><b/><sz val="14"/><color rgb="FFF26522"/><name val="Segoe UI"/></font>
    <font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Segoe UI"/></font>
  </fonts>
  <fills count="5">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF2D3748"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFF7FAFC"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFFFF5EB"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/></border>
    <border>
      <left style="thin"><color rgb="FFD2D6DC"/></left>
      <right style="thin"><color rgb="FFD2D6DC"/></right>
      <top style="thin"><color rgb="FFD2D6DC"/></top>
      <bottom style="thin"><color rgb="FFD2D6DC"/></bottom>
    </border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="9">
    <!-- 0: Default -->
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <!-- 1: Grand Titre -->
    <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
    <!-- 2: En-tête de tableau (sombre, texte blanc, centré) -->
    <xf numFmtId="0" fontId="3" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
      <alignment horizontal="center" vertical="center" wrapText="1"/>
    </xf>
    <!-- 3: Cellule texte standard -->
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1">
      <alignment vertical="center"/>
    </xf>
    <!-- 4: Cellule nombre / droite -->
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1">
      <alignment horizontal="right" vertical="center"/>
    </xf>
    <!-- 5: Cellule centrée -->
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1">
      <alignment horizontal="center" vertical="center"/>
    </xf>
    <!-- 6: Cellule libellé gras -->
    <xf numFmtId="0" fontId="1" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1">
      <alignment vertical="center"/>
    </xf>
    <!-- 7: Ligne alternée (fond très clair) -->
    <xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1">
      <alignment vertical="center"/>
    </xf>
    <!-- 8: Accentuation / Badge -->
    <xf numFmtId="0" fontId="1" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
      <alignment horizontal="center" vertical="center"/>
    </xf>
  </cellXfs>
</styleSheet>''';

String _colName(int colIdx) {
  var s = '';
  var c = colIdx;
  while (c > 0) {
    c--;
    s = String.fromCharCode(65 + (c % 26)) + s;
    c ~/= 26;
  }
  return s;
}

class _SheetBuilder {
  final List<double> colWidths;
  final StringBuffer _rows = StringBuffer();
  int _rowIdx = 0;

  _SheetBuilder(this.colWidths);

  void addRow(List<({Object value, int style, bool isNum})> cells, {double? height}) {
    _rowIdx++;
    _rows.write('<row r="$_rowIdx"');
    if (height != null) _rows.write(' ht="$height" customHeight="1"');
    _rows.write('>');
    for (var i = 0; i < cells.length; i++) {
      final col = _colName(i + 1);
      final c = cells[i];
      final rRef = '$col$_rowIdx';
      if (c.isNum) {
        _rows.write('<c r="$rRef" s="${c.style}"><v>${c.value}</v></c>');
      } else {
        _rows.write('<c r="$rRef" t="inlineStr" s="${c.style}"><is><t>${_xmlEscape(c.value.toString())}</t></is></c>');
      }
    }
    _rows.write('</row>');
  }

  void addBlankRow() {
    _rowIdx++;
    _rows.write('<row r="$_rowIdx"/>');
  }

  String build() {
    final sb = StringBuffer();
    sb.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n');
    sb.write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\n');
    sb.write('<cols>\n');
    for (var i = 0; i < colWidths.length; i++) {
      sb.write('<col min="${i + 1}" max="${i + 1}" width="${colWidths[i]}" customWidth="1"/>\n');
    }
    sb.write('</cols>\n');
    sb.write('<sheetData>\n');
    sb.write(_rows.toString());
    sb.write('</sheetData>\n');
    sb.write('</worksheet>');
    return sb.toString();
  }
}

({Object value, int style, bool isNum}) _str(Object v, [int style = 3]) => (value: v, style: style, isNum: false);
({Object value, int style, bool isNum}) _num(num v, [int style = 4]) => (value: v, style: style, isNum: true);

String _buildProjectSheet(AppState state) {
  final p = state.project;
  final r = p.room;
  final bom = state.bom;
  final b = _SheetBuilder([26, 32, 22, 28]);

  // Titre
  b.addRow([_str('KITCHINOX · RÉCAPITULATIF PROJET', 1)], height: 26);
  b.addBlankRow();

  // Section Informations Projet
  b.addRow([_str('Projet', 2), _str('Valeur', 2), _str('Client', 2), _str('Coordonnées', 2)], height: 20);
  b.addRow([_str('Nom du projet', 6), _str(p.name, 3), _str('Nom du client', 6), _str(p.client.name.isNotEmpty ? p.client.name : 'Non renseigné', 3)]);
  b.addRow([_str('Univers', 6), _str(p.universe.toUpperCase(), 3), _str('Société', 6), _str(p.client.company.isNotEmpty ? p.client.company : '-', 3)]);
  b.addRow([_str('Date d\'exportation', 6), _str(DateTime.now().toLocal().toString().split('.')[0], 3), _str('ICE Client', 6), _str(p.client.ice.isNotEmpty ? p.client.ice : '-', 3)]);
  b.addRow([_str('Statut', 6), _str(state.issues.isEmpty ? 'Conforme (0 anomalie)' : '${state.issues.length} points à vérifier', 8), _str('Désignation', 6), _str(p.client.label.isNotEmpty ? p.client.label : '-', 3)]);
  b.addBlankRow();

  // Section Dimensions et Volumes
  b.addRow([_str('Pièce & Volumes', 2), _str('Mesure', 2), _str('Métrés & Quantités', 2), _str('Total', 2)], height: 20);
  b.addRow([_str('Largeur de la pièce', 6), _str('${r.width} mm', 5), _str('Nombre total de caissons', 6), _num(p.items.length, 5)]);
  b.addRow([_str('Profondeur de la pièce', 6), _str('${r.depth} mm', 5), _str('Longueur plan de travail', 6), _str('${(bom.worktopLength / 1000).toStringAsFixed(2)} m', 5)]);
  b.addRow([_str('Hauteur sous plafond', 6), _str('${r.height} mm', 5), _str('Longueur plinthes', 6), _str('${(bom.plinthLength / 1000).toStringAsFixed(2)} m', 5)]);
  b.addRow([_str('Surface au sol', 6), _str('${r.area.toStringAsFixed(2)} m²', 5), _str('Ouvertures (portes/fenêtres)', 6), _num(p.openings.length, 5)]);
  b.addRow([_str('Nombre de murs', 6), _num(r.order.length, 5), _str('Appareillage électrique / Réseaux', 6), _num(p.points.length, 5)]);
  b.addBlankRow();

  // Section Styles et Finitions
  b.addRow([_str('Élément de style', 2), _str('Finition choisie', 2), _str('Standard atelier', 2), _str('Valeur', 2)], height: 20);
  b.addRow([_str('Façades', 6), _str(p.style.front, 3), _str('Épaisseur caisson', 6), _str('${p.cut.carcassThickness} mm', 5)]);
  b.addRow([_str('Plan de travail', 6), _str(p.style.worktop, 3), _str('Épaisseur façade', 6), _str('${p.cut.doorThickness} mm', 5)]);
  b.addRow([_str('Caissons intérieurs', 6), _str(p.style.carcass, 3), _str('Hauteur plinthes', 6), _str('${p.standards.plinthHeight} mm', 5)]);
  b.addRow([_str('Modèle de poignée', 6), _str(p.style.handle, 3), _str('Épaisseur plan', 6), _str('${p.standards.worktopThickness} mm', 5)]);
  b.addRow([_str('Revêtement de sol', 6), _str(p.style.floor, 3), _str('Trait de scie (kerf)', 6), _str('${p.cut.kerf} mm', 5)]);
  b.addRow([_str('Finition murs', 6), _str(p.style.wall, 3), _str('Recoupe bord (trim)', 6), _str('${p.cut.trim} mm', 5)]);

  return b.build();
}

String _buildCutSheet(AppState state, List<CutPart> parts) {
  final b = _SheetBuilder([6, 18, 26, 12, 12, 10, 8, 14, 18, 12, 12, 12, 12, 14, 14, 14, 10, 20]);

  b.addRow([_str('KITCHINOX · LISTE DES PIÈCES & DÉBIT ATELIER', 1)], height: 26);
  b.addBlankRow();

  // En-tête du tableau
  b.addRow([
    _str('#', 2),
    _str('Meuble / Caisson', 2),
    _str('Désignation de la pièce', 2),
    _str('Long. (mm)', 2),
    _str('Larg. (mm)', 2),
    _str('Ép. (mm)', 2),
    _str('Qté', 2),
    _str('Surf. Tot (m²)', 2),
    _str('Matériau / Panneau', 2),
    _str('Chant L1', 2),
    _str('Chant L2', 2),
    _str('Chant l1', 2),
    _str('Chant l2', 2),
    _str('Chant Tot (m)', 2),
    _str('Rainure', 2),
    _str('Long. Rainure (mm)', 2),
    _str('Rotation', 2),
    _str('Code-barres / Tag', 2),
  ], height: 24);

  final cs = state.project.cut;
  var totalArea = 0.0;
  var totalEdgeMeters = 0.0;
  var totalQty = 0;

  for (var i = 0; i < parts.length; i++) {
    final p = parts[i];
    final partNum = i + 1;
    final areaM2 = (p.length * p.width * p.qty) / 1e6;
    final edgeM = (p.edgeLength * p.qty) / 1000.0;
    final thick = isFrontPart(p) ? cs.doorThickness : cs.carcassThickness;
    final isAlt = i % 2 == 1;
    final sTxt = isAlt ? 7 : 3;
    final sNum = isAlt ? 7 : 4;
    final sCen = isAlt ? 7 : 5;

    totalArea += areaM2;
    totalEdgeMeters += edgeM;
    totalQty += p.qty;

    final barcodeTag = 'KIT-P${partNum.toString().padLeft(2, '0')}-${p.length}x${p.width}';
    final grooveStr = p.grooveLength == 0 ? 'Aucune' : (p.grooveLong > 0 ? 'Long. (fond)' : 'Larg.');

    b.addRow([
      _num(partNum, 8),
      _str(p.cabinet, sTxt),
      _str(p.name, sTxt),
      _num(p.length, sNum),
      _num(p.width, sNum),
      _num(thick, sCen),
      _num(p.qty, sCen),
      _num(double.parse(areaM2.toStringAsFixed(3)), sNum),
      _str(p.material, sTxt),
      _str(p.edgeLong >= 1 ? 'Oui' : '-', sCen),
      _str(p.edgeLong >= 2 ? 'Oui' : '-', sCen),
      _str(p.edgeShort >= 1 ? 'Oui' : '-', sCen),
      _str(p.edgeShort >= 2 ? 'Oui' : '-', sCen),
      _num(double.parse(edgeM.toStringAsFixed(2)), sNum),
      _str(grooveStr, sCen),
      _num(p.grooveLength * p.qty, sNum),
      _str(p.canRotate ? 'Oui' : 'Non (fil)', sCen),
      _str(barcodeTag, sTxt),
    ]);
  }

  // Ligne de totaux
  b.addRow([
    _str('TOTAL', 2),
    _str('${parts.length} types de pièces', 2),
    _str('-', 2),
    _str('-', 2),
    _str('-', 2),
    _str('-', 2),
    _num(totalQty, 2),
    _num(double.parse(totalArea.toStringAsFixed(3)), 2),
    _str('-', 2),
    _str('-', 2),
    _str('-', 2),
    _str('-', 2),
    _str('-', 2),
    _num(double.parse(totalEdgeMeters.toStringAsFixed(2)), 2),
    _str('-', 2),
    _str('-', 2),
    _str('-', 2),
    _str('-', 2),
  ], height: 22);

  return b.build();
}

String _buildBomSheet(AppState state) {
  final b = _SheetBuilder([18, 22, 34, 20, 32, 10, 10]);

  b.addRow([_str('KITCHINOX · NOMENCLATURE DES COMPOSANTS (BOM)', 1)], height: 26);
  b.addBlankRow();

  b.addRow([
    _str('Catégorie / Section', 2),
    _str('Référence', 2),
    _str('Désignation', 2),
    _str('Dimensions (mm)', 2),
    _str('Détails & Équipements', 2),
    _str('Quantité', 2),
    _str('Unité', 2),
  ], height: 22);

  final lines = state.bom.lines;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final isAlt = i % 2 == 1;
    final sTxt = isAlt ? 7 : 3;
    final sCen = isAlt ? 7 : 5;

    b.addRow([
      _str(l.section, sTxt),
      _str(l.ref, sTxt),
      _str(l.name, sTxt),
      _str(l.dims, sCen),
      _str(l.details, sTxt),
      _num(l.qty, sCen),
      _str(l.unit, sCen),
    ]);
  }

  return b.build();
}

String _buildHardwareSheet(AppState state, List<SupplyLine> hardware) {
  final b = _SheetBuilder([20, 34, 38, 12, 12]);

  b.addRow([_str('KITCHINOX · QUINCAILLERIE & ACCESSOIRES ATELIER', 1)], height: 26);
  b.addBlankRow();

  b.addRow([
    _str('Section', 2),
    _str('Désignation', 2),
    _str('Détails & Affectation', 2),
    _str('Quantité', 2),
    _str('Unité', 2),
  ], height: 22);

  if (hardware.isEmpty) {
    b.addRow([
      _str('Quincaillerie', 3),
      _str('Quincaillerie calculée selon caissons', 3),
      _str('Charnières invisibles, coulisses tiroirs, taquets et pieds', 3),
      _num(state.project.items.length * 4, 5),
      _str('pce', 5),
    ]);
  } else {
    for (var i = 0; i < hardware.length; i++) {
      final h = hardware[i];
      final isAlt = i % 2 == 1;
      final sTxt = isAlt ? 7 : 3;
      final sCen = isAlt ? 7 : 5;
      final sNum = isAlt ? 7 : 4;

      b.addRow([
        _str(h.section, sTxt),
        _str(h.name, sTxt),
        _str(h.detail, sTxt),
        _num(h.qty == h.qty.roundToDouble() ? h.qty.round() : double.parse(h.qty.toStringAsFixed(1)), sNum),
        _str(h.unit, sCen),
      ]);
    }
  }

  return b.build();
}
