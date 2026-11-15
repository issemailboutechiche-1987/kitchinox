// Format de fichier Kitchinox (.kin) : archive ZIP cryptée contenant le projet,
// les métadonnées et ses ressources éventuelles.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class KinFormat {
  // En-tête magique pour identification rapide
  static const _magic = [0x4B, 0x49, 0x4E, 0x31]; // 'K', 'I', 'N', '1'

  // Clé d'obfuscation / chiffrement Kitchinox
  static const _key = [
    0x4B, 0x69, 0x74, 0x63, 0x68, 0x69, 0x6E, 0x6F,
    0x78, 0x50, 0x72, 0x6F, 0x32, 0x30, 0x32, 0x36
  ]; // 'KitchinoxPro2026'

  /// Chiffre / déchiffre les octets en flux (XOR avec rotation de clé + sel)
  static Uint8List _crypt(Uint8List input) {
    final out = Uint8List(input.length);
    for (var i = 0; i < input.length; i++) {
      final k = _key[i % _key.length] ^ ((i * 31) & 0xFF);
      out[i] = input[i] ^ k;
    }
    return out;
  }

  /// Exporte un projet en données .kin cryptées
  static Uint8List encode(String projectJson, {String? projectName}) {
    final archive = Archive();

    // 1. Fichier project.json
    final jsonBytes = utf8.encode(projectJson);
    archive.addFile(ArchiveFile('project.json', jsonBytes.length, jsonBytes));

    // 2. Fichier meta.json
    final meta = jsonEncode({
      'format': 'kitchinox',
      'version': '1.0',
      'created': DateTime.now().toIso8601String(),
      'name': projectName ?? 'Projet',
      'generator': 'kitchinox app',
    });
    final metaBytes = utf8.encode(meta);
    archive.addFile(ArchiveFile('meta.json', metaBytes.length, metaBytes));

    // Compression Zip
    final zipEncoder = ZipEncoder();
    final zipBytes = Uint8List.fromList(zipEncoder.encode(archive));

    // Cryptage
    final encrypted = _crypt(zipBytes);

    // Résultat : Magique + données cryptées
    final out = Uint8List(_magic.length + encrypted.length);
    out.setRange(0, _magic.length, _magic);
    out.setRange(_magic.length, out.length, encrypted);
    return out;
  }

  /// Décode un fichier (.kin ou .json rétrocompatible) en JSON de projet
  static String decode(Uint8List bytes) {
    // Vérifier si c'est un fichier .kin
    final isKin = bytes.length >= 4 &&
        bytes[0] == _magic[0] &&
        bytes[1] == _magic[1] &&
        bytes[2] == _magic[2] &&
        bytes[3] == _magic[3];

    if (isKin) {
      final encrypted = bytes.sublist(_magic.length);
      final decrypted = _crypt(encrypted);

      final zipDecoder = ZipDecoder();
      final archive = zipDecoder.decodeBytes(decrypted);

      final file = archive.findFile('project.json');
      if (file != null) {
        return utf8.decode(file.content);
      }
      throw FormatException('Archive .kin invalide ou endommagée');
    }

    // Si c'est du zip brut (sans en-tête)
    try {
      final zipDecoder = ZipDecoder();
      final archive = zipDecoder.decodeBytes(bytes);
      final file = archive.findFile('project.json');
      if (file != null) {
        return utf8.decode(file.content);
      }
    } catch (_) {
      // Pas du zip
    }

    // Rétrocompatibilité : JSON brut
    return utf8.decode(bytes);
  }
}
