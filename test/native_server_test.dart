// App native (iPad) : le serveur interne sert à la vue 3D la page, le moteur three.js, les modèles
// et les fichiers déposés en mémoire (images, scène).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/ui/local_server.dart';

Future<(int, String, List<int>)> get(String url) async {
  final c = HttpClient();
  try {
    final r = await (await c.getUrl(Uri.parse(url))).close();
    final body = await r.fold<List<int>>([], (a, b) => a..addAll(b));
    return (r.statusCode, r.headers.contentType?.mimeType ?? '', body);
  } finally {
    c.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('serveur interne : page 3D, moteur, modèles, mémoire, chemins refusés', () async {
    await TestWidgetsFlutterBinding.instance.runAsync(() async {
      final base = await LocalServer.instance.start();
      expect(base, startsWith('http://127.0.0.1:'));
      final (s1, t1, b1) = await get('$base/index.html');
      expect(s1, 200);
      expect(t1, 'text/html');
      expect(utf8.decode(b1), contains('kitchen3dNative'));
      final (s2, t2, b2) = await get('$base/three_view.js');
      expect((s2, t2), (200, 'text/javascript'));
      expect(b2.length, greaterThan(10000));
      final (s3, _, _) = await get('$base/vendor/three.module.min.js');
      expect(s3, 200);
      final thumb = Directory('web/objects/kenney/thumbs').listSync().whereType<File>().first.path.replaceAll('\\', '/').substring(4);
      final (s4, t4, _) = await get('$base/$thumb');
      expect((s4, t4), (200, 'image/png'));
      LocalServer.instance.put('mem/scene/1.json', Uint8List.fromList(utf8.encode('{"a":1}')));
      final (s5, _, b5) = await get('$base/mem/scene/1.json');
      expect((s5, utf8.decode(b5)), (200, '{"a":1}'));
      LocalServer.instance.remove('mem/scene/1.json');
      expect((await get('$base/mem/scene/1.json')).$1, 404);
      expect((await get('$base/..%2Fpubspec.yaml')).$1, 404);
      await LocalServer.instance.stop();
    });
  });
}
