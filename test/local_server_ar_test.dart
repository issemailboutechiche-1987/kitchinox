// App native : la vue 3D dépose le paquet AR sur le serveur interne, Flutter le reçoit pour le partager.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/ui/local_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // vraie connexion locale (le banc de test bloque le réseau par défaut)

  test('POST /__ar/scene.usdz : le paquet arrive entier à Flutter', () async {
    final base = await LocalServer.instance.start();
    final waiting = LocalServer.instance.nextArUpload();
    final bytes = List<int>.generate(300000, (i) => i % 251);
    final client = HttpClient();
    final req = await client.postUrl(Uri.parse('$base/__ar/scene.usdz'));
    req.add(bytes);
    final res = await req.close();
    expect(res.statusCode, HttpStatus.noContent);
    final got = await waiting.timeout(const Duration(seconds: 5));
    expect(got.length, bytes.length);
    expect(got[123456], bytes[123456]);
    client.close();
    await LocalServer.instance.stop();
  });
}
