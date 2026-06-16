import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/native_command_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeCommandService Platform Channel Tests', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.termode/native_shell'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'executeCommand') {
            final command = methodCall.arguments['command'] as String;
            final timeoutMs = methodCall.arguments['timeoutMs'] as int;

            if (command == 'timeout_cmd') {
              throw PlatformException(
                code: 'TIMEOUT',
                message: 'Command timed out after $timeoutMs ms',
              );
            }

            if (command == 'ls -la') {
              return {
                'stdout': 'drwxr-xr-x  2 root  root  4096 Jun 15 23:00 .\n',
                'stderr': '',
                'exitCode': 0,
              };
            }

            if (command == 'invalid_cmd') {
              return {
                'stdout': '',
                'stderr': 'sh: invalid_cmd: not found\n',
                'exitCode': 127,
              };
            }

            if (command == 'permission_denied_cmd') {
              return {
                'stdout': '',
                'stderr': 'sh: permission denied\n',
                'exitCode': 126,
              };
            }

            if (command == 'long_running_cmd') {
              // Simulate execution time
              await Future.delayed(const Duration(milliseconds: 100));
              return {
                'stdout': 'done',
                'stderr': '',
                'exitCode': 0,
              };
            }

            if (command == 'huge_output_cmd') {
              return {
                'stdout': 'mock output\n[Output truncated: exceeded limit of 50000 characters]\n',
                'stderr': '',
                'exitCode': 0,
              };
            }

            return {
              'stdout': 'mock output\n',
              'stderr': '',
              'exitCode': 0,
            };
          } else if (methodCall.method == 'cancelCommand') {
            return true;
          } else if (methodCall.method == 'getDiagnostics') {
            return {
              'userDir': '/data/user/0/com.termode.termode/files',
              'pathEnv': '/sbin:/system/bin:/system/xbin',
              'uid': 10234,
              'testOutput': 'shell-ok',
              'runtimeHome': '/data/user/0/com.termode.termode/files/home',
              'runtimePath': '/data/user/0/com.termode.termode/files/usr/bin:/system/bin:/system/xbin:/vendor/bin:/product/bin',
              'fileChecks': [
                {
                  'path': '/system',
                  'exists': true,
                  'canRead': true,
                  'canExecute': true,
                },
                {
                  'path': '/system/bin',
                  'exists': true,
                  'canRead': true,
                  'canExecute': true,
                },
                {
                  'path': '/system/bin/sh',
                  'exists': true,
                  'canRead': true,
                  'canExecute': true,
                },
                {
                  'path': '/system/bin/toybox',
                  'exists': false,
                  'canRead': false,
                  'canExecute': false,
                },
                {
                  'path': '/system/bin/ls',
                  'exists': true,
                  'canRead': true,
                  'canExecute': true,
                },
              ],
            };
          } else if (methodCall.method == 'getEnv') {
            return {
              'HOME': '/data/user/0/com.termode.termode/files/home',
              'TERMODE_HOME': '/data/user/0/com.termode.termode/files/home',
              'TERMODE_USR': '/data/user/0/com.termode.termode/files/usr',
              'TERMODE_BIN': '/data/user/0/com.termode.termode/files/usr/bin',
              'TMPDIR': '/data/user/0/com.termode.termode/files/tmp',
              'PATH': '/data/user/0/com.termode.termode/files/usr/bin:/system/bin:/system/xbin:/vendor/bin:/product/bin',
              'workingDirectory': '/data/user/0/com.termode.termode/files/home',
            };
          }
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.termode/native_shell'),
        null,
      );
    });

    test('Execute successful native command', () async {
      final nativeService = NativeCommandService();
      final result = await nativeService.execute('ls -la', 'session_1');

      expect(result.exitCode, 0);
      expect(result.stdout, contains('drwxr-xr-x'));
      expect(result.stderr, isEmpty);
    });

    test('Execute failing native command', () async {
      final nativeService = NativeCommandService();
      final result = await nativeService.execute('invalid_cmd', 'session_1');

      expect(result.exitCode, 127);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('not found'));
    });

    test('Handle execution timeouts', () async {
      final nativeService = NativeCommandService();
      final result = await nativeService.execute('timeout_cmd', 'session_1');

      expect(result.exitCode, -1);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('TIMEOUT'));
    });

    test('CommandService android-shell parsing integration', () async {
      final vfs = VirtualFileSystem();
      
      // Successful integration
      var commandService = CommandService(vfs, 'session_1');
      final resultSuccess = await commandService.execute('android-shell ls -la');
      expect(resultSuccess.isError, isFalse);
      expect(resultSuccess.output, contains('drwxr-xr-x'));

      // Empty arguments error
      final resultEmpty = await commandService.execute('android-shell');
      expect(resultEmpty.isError, isTrue);
      expect(resultEmpty.output, contains('missing command operand'));

      // Failing command integration (exitCode 127)
      final resultFail127 = await commandService.execute('android-shell invalid_cmd');
      expect(resultFail127.isError, isTrue);
      expect(resultFail127.output, contains('command not found'));

      // Failing command integration (exitCode 126)
      final resultFail126 = await commandService.execute('android-shell permission_denied_cmd');
      expect(resultFail126.isError, isTrue);
      expect(resultFail126.output, contains('permission denied'));
    });

    test('Concurrency block and active flag in TerminalSessionService', () async {
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();

      final session = sessionService.activeSession;
      expect(session.isExecutingNativeCommand, isFalse);

      // Execute a long-running native command asynchronously
      final futureResult = Future(() => sessionService.executeCommand('android-shell long_running_cmd'));

      // Allow microtasks/execution to start, setting the flag
      await Future.delayed(const Duration(milliseconds: 20));
      expect(session.isExecutingNativeCommand, isTrue);

      // Try executing another command concurrently while the flag is true
      sessionService.executeCommand('android-shell ls -la');

      // Wait for the long running command to finish
      await futureResult;

      expect(session.isExecutingNativeCommand, isFalse);
      
      final outputs = session.lines.map((l) => l.text).toList();
      expect(outputs, anyElement(contains('A native command is already executing')));
    });

    test('Cancel active native command (KILL)', () async {
      final sessionService = TerminalSessionService();
      sessionService.clearMemoryStateForTesting();

      final session = sessionService.activeSession;

      // Start long running command
      final futureResult = Future(() => sessionService.executeCommand('android-shell long_running_cmd'));

      await Future.delayed(const Duration(milliseconds: 20));
      expect(session.isExecutingNativeCommand, isTrue);

      // Cancel it
      await sessionService.cancelActiveNativeCommand();

      // Wait for completion
      await futureResult;

      expect(session.isExecutingNativeCommand, isFalse);
    });

    test('CommandService android-shell-diagnostics integration', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_1');

      final result = await commandService.execute('android-shell-diagnostics');
      expect(result.isError, isFalse);
      expect(result.output, contains('=== Termode Native Diagnostics ==='));
      expect(result.output, contains('CWD: /data/user/0/com.termode.termode/files'));
      expect(result.output, contains('UID: 10234'));
      expect(result.output, contains('Runtime Home: /data/user/0/com.termode.termode/files/home'));
      expect(result.output, contains('Runtime PATH: /data/user/0/com.termode.termode/files/usr/bin:/system/bin:/system/xbin:/vendor/bin:/product/bin'));
      expect(result.output, contains('PATH env:'));
      expect(result.output, contains('- /sbin'));
      expect(result.output, contains('- /system/bin'));
      expect(result.output, contains('/system/bin/toybox: [NOT FOUND]'));
      expect(result.output, contains('/system/bin/sh: [OK] r:y x:y'));
      expect(result.output, contains('Test run (sh -c "echo shell-ok"): shell-ok'));
    });

    test('CommandService android-shell-env integration', () async {
      final vfs = VirtualFileSystem();
      final commandService = CommandService(vfs, 'session_1');

      final result = await commandService.execute('android-shell-env');
      expect(result.isError, isFalse);
      expect(result.output, contains('=== Effective Native Runtime Environment ==='));
      expect(result.output, contains('HOME:              /data/user/0/com.termode.termode/files/home'));
      expect(result.output, contains('TERMODE_HOME:      /data/user/0/com.termode.termode/files/home'));
      expect(result.output, contains('TERMODE_USR:       /data/user/0/com.termode.termode/files/usr'));
      expect(result.output, contains('TERMODE_BIN:       /data/user/0/com.termode.termode/files/usr/bin'));
      expect(result.output, contains('TMPDIR:            /data/user/0/com.termode.termode/files/tmp'));
      expect(result.output, contains('PATH:              /data/user/0/com.termode.termode/files/usr/bin:/system/bin:/system/xbin:/vendor/bin:/product/bin'));
      expect(result.output, contains('Working Directory: /data/user/0/com.termode.termode/files/home'));
    });
  });
}
