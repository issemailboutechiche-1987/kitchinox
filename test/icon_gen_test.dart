// Génère les icônes de l'app iPad à partir du logo kitchinox (assets/logo.svg), fond blanc opaque.
// Lancer : flutter test test/icon_gen_test.dart --dart-define=GEN_ICONS=1
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/ui/logo.dart';

void main() {
  testWidgets('icônes iOS', (t) async {
    if (const String.fromEnvironment('GEN_ICONS') != '1') return;
    final dir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
    final shape = LogoShape.parse(File('assets/logo.svg').readAsStringSync());
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png'))) {
      final m = RegExp(r'Icon-App-([\d.]+)x[\d.]+@(\d)x\.png$').firstMatch(f.path)!;
      final px = (double.parse(m[1]!) * int.parse(m[2]!)).round();
      await t.runAsync(() async {
        final rec = ui.PictureRecorder();
        final c = Canvas(rec);
        c.drawRect(Rect.fromLTWH(0, 0, px.toDouble(), px.toDouble()), Paint()..color = Colors.white);
        final pad = px * 0.1;
        c.translate(pad, pad);
        LogoPainter(shape).paint(c, Size(px - 2 * pad, px - 2 * pad));
        final img = await rec.endRecording().toImage(px, px);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        f.writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
  });
}
