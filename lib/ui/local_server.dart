// Petit serveur HTTP interne à l'app native (adresse 127.0.0.1, invisible du réseau) : il sert à la
// vue 3D (WKWebView) le moteur three.js, les modèles 3D et les images envoyées par Flutter.
// Les modules JavaScript ne se chargent pas depuis des fichiers locaux : il leur faut une adresse http.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class LocalServer {
  LocalServer._();
  static final instance = LocalServer._();

  HttpServer? _server;
  Future<String>? _starting;
  final _mem = <String, Uint8List>{}; // fichiers en mémoire (images, scènes), par chemin
  Completer<Uint8List>? _upload; // paquet AR attendu (envoyé par la vue 3D)

  /// Attend le prochain paquet AR déposé par la vue 3D (POST /__ar/scene.usdz).
  Future<Uint8List> nextArUpload() => (_upload = Completer<Uint8List>()).future;

  /// Adresse de base (http://127.0.0.1:port), le serveur démarre au premier appel.
  Future<String> start() => _starting ??= () async {
        final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        s.listen((r) => unawaited(_handle(r)));
        _server = s;
        return 'http://127.0.0.1:${s.port}';
      }();

  /// Dépose un fichier en mémoire sous [path] (sans « / » initial).
  void put(String path, Uint8List bytes) => _mem[path] = bytes;
  void remove(String path) => _mem.remove(path);

  static String _mime(String p) {
    final ext = p.contains('.') ? p.substring(p.lastIndexOf('.') + 1).toLowerCase() : '';
    return switch (ext) {
      'html' => 'text/html; charset=utf-8',
      'js' || 'mjs' => 'text/javascript; charset=utf-8',
      'json' || 'gltf' => 'application/json',
      'glb' => 'model/gltf-binary',
      'bin' => 'application/octet-stream',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _handle(HttpRequest r) async {
    try {
      var path = Uri.decodeComponent(r.uri.path);
      if (path.startsWith('/')) path = path.substring(1);
      if (path.isEmpty) path = 'index.html';
      if (r.method == 'POST' && path == '__ar/scene.usdz') {
        final b = BytesBuilder(copy: false);
        await for (final c in r) {
          b.add(c);
        }
        final u = _upload;
        _upload = null;
        if (u != null && !u.isCompleted) u.complete(b.takeBytes());
        r.response.statusCode = HttpStatus.noContent;
        await r.response.close();
        return;
      }
      var body = _mem[path];
      if (body == null && !path.contains('..')) {
        // page de la vue 3D, puis les fichiers du dossier web/ (three.js, modèles) embarqués dans l'app
        final asset = path == 'index.html' ? 'assets/web3d/index.html' : 'web/$path';
        try {
          final d = await rootBundle.load(asset);
          body = d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
        } catch (_) {
          body = null;
        }
      }
      if (body == null) {
        r.response.statusCode = HttpStatus.notFound;
      } else {
        r.response.headers.set(HttpHeaders.contentTypeHeader, _mime(path));
        r.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        r.response.add(body);
      }
    } catch (_) {
      r.response.statusCode = HttpStatus.internalServerError;
    }
    await r.response.close();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _starting = null;
  }
}
