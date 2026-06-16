import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class PersistenceService {
  final File? overrideFile;

  PersistenceService({this.overrideFile});

  Future<File> _getLocalFile() async {
    final localFile = overrideFile;
    if (localFile != null) {
      return localFile;
    }
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/termode_state.json');
  }

  Future<void> saveState(Map<String, dynamic> state) async {
    try {
      final file = await _getLocalFile();
      final jsonString = jsonEncode(state);
      await file.writeAsString(jsonString);
    } catch (e) {
      debugPrint('PersistenceService save error: $e');
    }
  }

  Future<Map<String, dynamic>?> loadState() async {
    try {
      final file = await _getLocalFile();
      if (!await file.exists()) {
        return null;
      }
      final jsonString = await file.readAsString();
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('PersistenceService load error: $e');
      return null;
    }
  }

  Future<void> clearState() async {
    try {
      final file = await _getLocalFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('PersistenceService clear error: $e');
    }
  }
}
