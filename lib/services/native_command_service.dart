import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeCommandResult {
  final String stdout;
  final String stderr;
  final int exitCode;

  NativeCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });
}

class NativeCommandService {
  static const _channel = MethodChannel('com.termode/native_shell');

  Future<NativeCommandResult> execute(
    String command,
    String sessionId, {
    int timeoutMs = 10000,
  }) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod(
        'executeCommand',
        {'command': command, 'sessionId': sessionId, 'timeoutMs': timeoutMs},
      );

      if (result != null) {
        return NativeCommandResult(
          stdout: result['stdout'] as String? ?? '',
          stderr: result['stderr'] as String? ?? '',
          exitCode: result['exitCode'] as int? ?? 0,
        );
      }
      throw PlatformException(
        code: 'NULL_RESULT',
        message: 'Bridge returned null',
      );
    } on PlatformException catch (e) {
      return NativeCommandResult(
        stdout: '',
        stderr: 'Error: ${e.message} (${e.code})',
        exitCode: -1,
      );
    } catch (e) {
      return NativeCommandResult(stdout: '', stderr: 'Error: $e', exitCode: -1);
    }
  }

  Future<void> cancel(String sessionId) async {
    try {
      await _channel.invokeMethod('cancelCommand', {'sessionId': sessionId});
    } on PlatformException catch (e) {
      // Fail silently, log for dev debugging
      debugPrint('Platform cancel error: ${e.message}');
    } catch (e) {
      debugPrint('Cancel error: $e');
    }
  }

  Future<Map<String, dynamic>?> getDiagnostics() async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod(
        'getDiagnostics',
      );
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } on PlatformException catch (e) {
      debugPrint('Platform diagnostics error: ${e.message}');
    } catch (e) {
      debugPrint('Diagnostics error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getEnv() async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod(
        'getEnv',
      );
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } on PlatformException catch (e) {
      debugPrint('Platform env error: ${e.message}');
    } catch (e) {
      debugPrint('Env error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getExecutablePaths() async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod(
        'getExecutablePaths',
      );
      if (result != null) return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      debugPrint('Executable path lookup failed: ${e.message}');
    } catch (e) {
      debugPrint('Executable path lookup failed: $e');
    }
    return null;
  }

  Future<NativeCommandResult> executeBundledGit(
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod(
        'executeBundledGit',
        {'arguments': arguments, 'workingDirectory': ?workingDirectory},
      );
      if (result == null) {
        throw PlatformException(
          code: 'NULL_RESULT',
          message: 'Git bridge returned null',
        );
      }
      return NativeCommandResult(
        stdout: result['stdout'] as String? ?? '',
        stderr: result['stderr'] as String? ?? '',
        exitCode: result['exitCode'] as int? ?? -1,
      );
    } on PlatformException catch (e) {
      return NativeCommandResult(
        stdout: '',
        stderr: 'Error: ${e.message} (${e.code})',
        exitCode: -1,
      );
    } catch (e) {
      return NativeCommandResult(stdout: '', stderr: 'Error: $e', exitCode: -1);
    }
  }

  Future<NativeCommandResult> executeBundledNode(
    List<String> arguments, {
    String? workingDirectory,
    int timeoutMs = 15000,
  }) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod(
        'executeBundledNode',
        {
          'arguments': arguments,
          'workingDirectory': ?workingDirectory,
          'timeoutMs': timeoutMs,
        },
      );
      if (result == null) {
        throw PlatformException(
          code: 'NULL_RESULT',
          message: 'Node bridge returned null',
        );
      }
      return NativeCommandResult(
        stdout: result['stdout'] as String? ?? '',
        stderr: result['stderr'] as String? ?? '',
        exitCode: result['exitCode'] as int? ?? -1,
      );
    } on PlatformException catch (e) {
      return NativeCommandResult(
        stdout: '',
        stderr: 'Error: ${e.message} (${e.code})',
        exitCode: -1,
      );
    } catch (e) {
      return NativeCommandResult(stdout: '', stderr: 'Error: $e', exitCode: -1);
    }
  }

  Future<List<Map<String, dynamic>>> listDevServers() async {
    try {
      final List<dynamic>? result =
          await _channel.invokeMethod('listDevServers');
      if (result == null) return [];
      return result
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> stopDevServer({
    String? id,
    int? port,
    int? pid,
    bool all = false,
  }) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod(
        'stopDevServer',
        {'id': id, 'port': port, 'pid': pid, 'all': all},
      );
      if (result == null) return {'stoppedCount': 0, 'success': false};
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return {'stoppedCount': 0, 'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> getDevServerLogs({
    String? id,
    int? port,
  }) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod(
        'getDevServerLogs',
        {'id': id, 'port': port},
      );
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (_) {
      return null;
    }
  }
}

