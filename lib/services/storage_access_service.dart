import 'package:flutter/services.dart';

class StorageAccessService {
  static final StorageAccessService _instance = StorageAccessService._internal();
  factory StorageAccessService() => _instance;
  StorageAccessService._internal();

  static const _channel = MethodChannel('com.termode/native_shell');

  Future<String?> linkFolder() async {
    try {
      final String? result = await _channel.invokeMethod('pickStorageFolder');
      return result;
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw PlatformException(code: 'LINK_FAILED', message: e.toString());
    }
  }

  Future<Map<String, String>?> getStatus() async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getStorageStatus');
      if (result != null) {
        return Map<String, String>.from(result);
      }
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw PlatformException(code: 'STATUS_FAILED', message: e.toString());
    }
    return null;
  }

  Future<void> unlink() async {
    try {
      await _channel.invokeMethod('unlinkStorage');
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw PlatformException(code: 'UNLINK_FAILED', message: e.toString());
    }
  }

  Future<List<String>?> listFiles() async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod('listStorageFiles');
      if (result != null) {
        return List<String>.from(result);
      }
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw PlatformException(code: 'LIST_FAILED', message: e.toString());
    }
    return null;
  }

  Future<String?> readFile(String filename) async {
    try {
      final String? result = await _channel.invokeMethod('readStorageFile', {'filename': filename});
      return result;
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw PlatformException(code: 'READ_FAILED', message: e.toString());
    }
  }

  Future<bool> writeFile(String filename, String content) async {
    try {
      final bool? result = await _channel.invokeMethod('writeStorageFile', {
        'filename': filename,
        'content': content,
      });
      return result ?? false;
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw PlatformException(code: 'WRITE_FAILED', message: e.toString());
    }
  }

  Future<bool> deleteFile(String filename) async {
    try {
      final bool? result = await _channel.invokeMethod('deleteStorageFile', {'filename': filename});
      return result ?? false;
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw PlatformException(code: 'DELETE_FAILED', message: e.toString());
    }
  }

  Future<bool> supportsDelete(String filename) async {
    try {
      final bool? result = await _channel.invokeMethod('supportsDelete', {'filename': filename});
      return result ?? false;
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw PlatformException(code: 'SUPPORTS_DELETE_FAILED', message: e.toString());
    }
  }

  Future<bool> createDirectory(String folderName) async {
    try {
      final bool? result = await _channel.invokeMethod('createStorageDirectory', {'folderName': folderName});
      return result ?? false;
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw PlatformException(code: 'MKDIR_FAILED', message: e.toString());
    }
  }
}
