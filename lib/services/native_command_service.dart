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
        {
          'command': command,
          'sessionId': sessionId,
          'timeoutMs': timeoutMs,
        },
      );

      if (result != null) {
        return NativeCommandResult(
          stdout: result['stdout'] as String? ?? '',
          stderr: result['stderr'] as String? ?? '',
          exitCode: result['exitCode'] as int? ?? 0,
        );
      }
      throw PlatformException(code: 'NULL_RESULT', message: 'Bridge returned null');
    } on PlatformException catch (e) {
      return NativeCommandResult(
        stdout: '',
        stderr: 'Error: ${e.message} (${e.code})',
        exitCode: -1,
      );
    } catch (e) {
      return NativeCommandResult(
        stdout: '',
        stderr: 'Error: $e',
        exitCode: -1,
      );
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
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getDiagnostics');
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
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getEnv');
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
}
