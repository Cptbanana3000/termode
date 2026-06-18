import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/package_manager_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Runtime Strategy Commands', () {
    late Directory tempDir;
    late RuntimeBootstrapService runtime;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'termode_runtime_strategy',
      );
      runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            (MethodCall methodCall) async {
              if (methodCall.method == 'executeCommand') {
                final command = methodCall.arguments['command'] as String;
                if (command == '/system/bin/sh -c "echo shell-ok"') {
                  return {'stdout': 'shell-ok\n', 'stderr': '', 'exitCode': 0};
                }
                if (command == '/system/bin/toybox echo toybox-ok') {
                  return {'stdout': 'toybox-ok\n', 'stderr': '', 'exitCode': 0};
                }
                if (command.startsWith('/system/bin/sh ') &&
                    command.contains('runtime-exec-proof')) {
                  return {'stdout': 'script-ok\n', 'stderr': '', 'exitCode': 0};
                }
                if (command.contains('runtime-exec-proof')) {
                  return {
                    'stdout': '',
                    'stderr': 'Permission denied\n',
                    'exitCode': 126,
                  };
                }
              }
              if (methodCall.method == 'getDiagnostics') {
                return {
                  'userDir': '/data/user/0/com.termode.termode/files/home',
                  'cwd': '/data/user/0/com.termode.termode/files/home',
                  'pid': 1234,
                  'abi': 'arm64-v8a',
                  'testOutput': 'shell-ok',
                };
              }
              if (methodCall.method == 'realPtySend') {
                return true;
              }
              return null;
            },
          );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            null,
          );
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('runtime-doctor reports compact runtime health', () async {
      final service = CommandService(VirtualFileSystem(), 'runtime_strategy');

      final result = await service.execute('runtime-doctor');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== Runtime Doctor ==='));
      expect(result.output, contains('Shell: OK'));
      expect(result.output, contains('Toybox: OK'));
      expect(result.output, contains('App HOME: OK'));
      expect(result.output, contains('App USR: OK'));
      expect(result.output, contains('Scripts via sh: OK'));
      expect(result.output, contains('Direct app-bin exec: blocked'));
      expect(result.output, contains('Native bridge: OK'));
      expect(result.output, contains('Workspace cwd: OK'));
      expect(result.output, contains('Overall: LIMITED'));
    });

    test('runtime-doctor verbose includes paths and probe details', () async {
      final service = CommandService(VirtualFileSystem(), 'runtime_strategy');

      final result = await service.execute('runtime-doctor --verbose');

      expect(result.isError, isFalse);
      expect(result.output, contains('Probe details:'));
      expect(result.output, contains('App HOME path:'));
      expect(result.output, contains('Script via sh probe: exit=0'));
      expect(result.output, contains('ABI: arm64-v8a'));
    });

    test(
      'runtime-exec-test tolerates blocked direct app-bin execution',
      () async {
        final service = CommandService(VirtualFileSystem(), 'runtime_strategy');

        final result = await service.execute('runtime-exec-test');

        expect(result.isError, isFalse);
        expect(result.output, contains('=== Runtime Exec Test ==='));
        expect(result.output, contains('/system/bin/sh: PASS'));
        expect(result.output, contains('/system/bin/toybox: PASS'));
        expect(result.output, contains('script via /system/bin/sh: PASS'));
        expect(result.output, contains('direct app-bin exec: blocked'));
        expect(result.output, contains('native bridge probe: PASS'));
        expect(result.output, contains('Overall: LIMITED'));
      },
    );

    test(
      'runtime-capabilities lists supported and unsupported runtimes',
      () async {
        final service = CommandService(VirtualFileSystem(), 'runtime_strategy');

        final result = await service.execute('runtime-capabilities');

        expect(result.isError, isFalse);
        expect(result.output, contains('REAL PTY shell sessions'));
        expect(
          result.output,
          contains('Script packages through /system/bin/sh'),
        );
        expect(result.output, contains('Localhost diagnostics'));
        expect(result.output, contains('Native binary packages'));
        expect(result.output, contains('Node.js'));
        expect(result.output, contains('npm'));
        expect(result.output, contains('Python'));
        expect(result.output, contains('Git'));
      },
    );

    test('runtime-plan prints staged native runtime proof roadmap', () async {
      final service = CommandService(VirtualFileSystem(), 'runtime_strategy');

      final result = await service.execute('runtime-plan');

      expect(result.isError, isFalse);
      expect(result.output, contains('1. Script packages'));
      expect(result.output, contains('3. Localhost/preview workflow'));
      expect(result.output, contains('4. Bundled native proof'));
      expect(result.output, contains('5. Tiny native tool proof'));
      expect(result.output, contains('6. Native runtime candidate research'));
      expect(result.output, contains('7. Tiny JS/runtime feasibility proof'));
      expect(
        result.output,
        contains('8. Real embedded JS engine decision/probe'),
      );
      expect(result.output, contains('9. QuickJS probe'));
      expect(result.output, contains('13. Vite proof later'));
      expect(result.output, contains('14. CalypsoIDE integration later'));
    });

    test('runtime commands are intercepted inside REAL PTY mode', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('runtime-capabilities');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('runtime-capabilities'));
      expect(output, contains('=== Runtime Capabilities ==='));
      expect(output, contains('Node.js'));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });

    test(
      'path-lite script includes expanded runtime and workspace paths',
      () async {
        final paths = await runtime.getPaths();
        final pm = PackageManagerService();

        await pm.installPackage('path-lite');

        final script = File('${paths['usr']}/bin/path-lite').readAsStringSync();
        expect(script, contains('HOME='));
        expect(script, contains('TERMODE_HOME'));
        expect(script, contains('TERMODE_USR'));
        expect(script, contains('TERMODE_BIN'));
        expect(script, contains('TERMODE_PROJECTS'));
        expect(script, contains('TMPDIR'));
        expect(script, contains('WORKSPACE='));
        expect(script, contains('PREFERRED_CWD'));
      },
    );
  });
}
