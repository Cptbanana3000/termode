import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class RuntimeBootstrapService {
  static final RuntimeBootstrapService _instance = RuntimeBootstrapService._internal();
  factory RuntimeBootstrapService() => _instance;
  RuntimeBootstrapService._internal();

  Directory? _overrideBaseDir;

  set overrideBaseDir(Directory dir) {
    _overrideBaseDir = dir;
  }

  Future<Directory> _getBaseDir() async {
    if (_overrideBaseDir != null) {
      return _overrideBaseDir!;
    }
    final docDir = await getApplicationDocumentsDirectory();
    return docDir.parent; // Android sandbox root containing app_flutter/ and files/
  }

  Future<void> init() async {
    try {
      final base = await _getBaseDir();
      final filesDir = Directory('${base.path}/files');

      final home = Directory('${filesDir.path}/home');
      final usr = Directory('${filesDir.path}/usr');
      final bin = Directory('${filesDir.path}/usr/bin');
      final usrTmp = Directory('${filesDir.path}/usr/tmp');
      final tmp = Directory('${filesDir.path}/tmp');

      await home.create(recursive: true);
      await usr.create(recursive: true);
      await bin.create(recursive: true);
      await usrTmp.create(recursive: true);
      await tmp.create(recursive: true);

      final metaFile = File('${usr.path}/termode-runtime.json');
      Map<String, dynamic> metadata = {};
      final now = DateTime.now().toIso8601String();

      if (await metaFile.exists()) {
        try {
          final content = await metaFile.readAsString();
          metadata = jsonDecode(content) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('Error reading termode-runtime.json: $e');
        }
      }

      metadata['runtimeVersion'] = '0.7.0';
      metadata['createdAt'] ??= now;
      metadata['updatedAt'] = now;
      metadata['homePath'] = home.path;
      metadata['usrPath'] = usr.path;
      metadata['binPath'] = bin.path;
      metadata['tmpPath'] = tmp.path;

      await metaFile.writeAsString(jsonEncode(metadata));
    } catch (e) {
      debugPrint('RuntimeBootstrapService init error: $e');
    }
  }

  Future<Map<String, bool>> checkStatus() async {
    final base = await _getBaseDir();
    final filesDir = Directory('${base.path}/files');

    final home = Directory('${filesDir.path}/home');
    final usr = Directory('${filesDir.path}/usr');
    final bin = Directory('${filesDir.path}/usr/bin');
    final usrTmp = Directory('${filesDir.path}/usr/tmp');
    final tmp = Directory('${filesDir.path}/tmp');
    final metaFile = File('${usr.path}/termode-runtime.json');

    return {
      'files/home': await home.exists(),
      'files/usr': await usr.exists(),
      'files/usr/bin': await bin.exists(),
      'files/usr/tmp': await usrTmp.exists(),
      'files/tmp': await tmp.exists(),
      'termode-runtime.json': await metaFile.exists(),
    };
  }

  Future<Map<String, String>> getPaths() async {
    final base = await _getBaseDir();
    final filesDir = Directory('${base.path}/files');

    final home = Directory('${filesDir.path}/home');
    final usr = Directory('${filesDir.path}/usr');
    final bin = Directory('${filesDir.path}/usr/bin');
    final usrTmp = Directory('${filesDir.path}/usr/tmp');
    final tmp = Directory('${filesDir.path}/tmp');

    return {
      'home': home.path,
      'usr': usr.path,
      'bin': bin.path,
      'usrTmp': usrTmp.path,
      'tmp': tmp.path,
    };
  }

  Future<void> reset() async {
    try {
      final base = await _getBaseDir();
      final filesDir = Directory('${base.path}/files');

      final home = Directory('${filesDir.path}/home');
      final usr = Directory('${filesDir.path}/usr');
      final tmp = Directory('${filesDir.path}/tmp');

      if (await home.exists()) {
        await home.delete(recursive: true);
      }
      if (await usr.exists()) {
        await usr.delete(recursive: true);
      }
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }

      await init();
    } catch (e) {
      debugPrint('RuntimeBootstrapService reset error: $e');
    }
  }
}
