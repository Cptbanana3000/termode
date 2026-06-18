import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Runtime Candidate Research Commands', () {
    late Directory tempDir;
    late RuntimeBootstrapService runtime;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'termode_runtime_candidate',
      );
      runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      commandService = CommandService(VirtualFileSystem(), 'candidate_test');

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

    test('runtime-candidates compact output', () async {
      final result = await commandService.execute('runtime-candidates');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== Runtime Candidates ==='));
      expect(result.output, contains('script-packages'));
      expect(result.output, contains('current'));
      expect(result.output, contains('jni-native-tools'));
      expect(result.output, contains('apk-native-libs'));
      expect(result.output, contains('bundled-executable'));
      expect(result.output, contains('embedded-js-engine'));
      expect(result.output, contains('node-binary'));
      expect(result.output, contains('termux-style-prefix'));
      expect(result.output, contains('remote-only'));
    });

    test('runtime-candidate script-packages details', () async {
      final result = await commandService.execute(
        'runtime-candidate script-packages',
      );

      expect(result.isError, isFalse);
      expect(result.output, contains('Script Packages Through /system/bin/sh'));
      expect(result.output, contains('Status: current'));
      expect(result.output, contains('Risk: low'));
      expect(result.output, contains('Android risk:'));
      expect(result.output, contains('Recommendation:'));
      expect(result.output, contains('docs/PACKAGE_AUTHORING.md'));
    });

    test('runtime-candidate jni-native-tools details', () async {
      final result = await commandService.execute(
        'runtime-candidate jni-native-tools',
      );

      expect(result.isError, isFalse);
      expect(result.output, contains('JNI Native Tools'));
      expect(result.output, contains('Current v0.29 proof'));
      expect(result.output, contains('not installable'));
      expect(result.output, contains('docs/NATIVE_TOOL_PROOF.md'));
    });

    test('runtime-candidate embedded-js-engine details', () async {
      final result = await commandService.execute(
        'runtime-candidate embedded-js-engine',
      );

      expect(result.isError, isFalse);
      expect(result.output, contains('Embedded JS Engine'));
      expect(result.output, contains('QuickJS'));
      expect(result.output, contains('Tiny JS proof is available'));
      expect(result.output, contains('v0.32 Embedded JS Engine'));
    });

    test('runtime-candidate node-binary details', () async {
      final result = await commandService.execute(
        'runtime-candidate node-binary',
      );

      expect(result.isError, isFalse);
      expect(result.output, contains('Node Binary'));
      expect(result.output, contains('Status: future'));
      expect(result.output, contains('Risk: high'));
      expect(result.output, contains('Do not attempt first'));
      expect(result.output, contains('not included'));
    });

    test('unknown runtime candidate errors', () async {
      final result = await commandService.execute(
        'runtime-candidate imaginary-runtime',
      );

      expect(result.isError, isTrue);
      expect(result.output, contains('Unknown runtime candidate'));
      expect(result.output, contains('script-packages'));
      expect(result.output, contains('node-binary'));
    });

    test('runtime-decision output', () async {
      final result = await commandService.execute('runtime-decision');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== Runtime Decision ==='));
      expect(result.output, contains('Keep script packages'));
      expect(result.output, contains('Keep JNI native tools'));
      expect(
        result.output,
        contains('Test tiny embedded JS engine before Node'),
      );
    });

    test('runtime-risks output', () async {
      final result = await commandService.execute('runtime-risks');

      expect(result.isError, isFalse);
      expect(result.output, contains('Android app-writable exec restrictions'));
      expect(result.output, contains('ABI differences'));
      expect(result.output, contains('native crash risk'));
      expect(result.output, contains('npm package compatibility'));
    });

    test('runtime-next output', () async {
      final result = await commandService.execute('runtime-next');

      expect(result.isError, isFalse);
      expect(result.output, contains('v0.32 Embedded JS Engine Decision'));
      expect(result.output, contains('Fallback'));
      expect(result.output, contains('Native Runtime Candidate Narrowing'));
    });

    test('runtime-research-doctor output', () async {
      final result = await commandService.execute('runtime-research-doctor');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== Runtime Research Doctor ==='));
      expect(result.output, contains('Native bridge available: YES'));
      expect(result.output, contains('Direct app-bin exec status: blocked'));
      expect(result.output, contains('ABI known: YES'));
      expect(result.output, contains('Docs present: YES'));
      expect(result.output, contains('Script packages supported: YES'));
      expect(result.output, contains('Preview/localhost supported: YES'));
      expect(result.output, contains('Overall readiness: LIMITED'));
    });

    test(
      'runtime-plan includes candidate research and tiny JS proof',
      () async {
        final result = await commandService.execute('runtime-plan');

        expect(result.output, contains('6. Native runtime candidate research'));
        expect(result.output, contains('7. Tiny JS/runtime feasibility proof'));
        expect(result.output, contains('8. Real embedded JS engine proof'));
        expect(result.output, contains('12. CalypsoIDE integration later'));
      },
    );

    test('runtime-capabilities mentions candidate research', () async {
      final result = await commandService.execute('runtime-capabilities');

      expect(result.output, contains('Native runtime candidate research'));
      expect(result.output, contains('runtime-candidates'));
      expect(result.output, contains('runtime-next'));
      expect(result.output, contains('Node.js'));
    });

    test('package help still says native packages unsupported', () async {
      final result = await commandService.execute('pkg help');

      expect(result.output, contains('Packages are script-only'));
      expect(
        result.output,
        contains('Native binary packages are not supported'),
      );
      expect(result.output, contains('Remote packages are script-only'));
      expect(
        result.output,
        contains('Native tools (native-tool) are built into Termode'),
      );
      expect(
        result.output,
        contains('Node.js/npm/Python/Git are not available yet'),
      );
    });

    test('command catalog includes runtime research commands', () {
      expect(kTermodeCommands, contains('runtime-candidates'));
      expect(kTermodeCommands, contains('runtime-candidate'));
      expect(kTermodeCommands, contains('runtime-decision'));
      expect(kTermodeCommands, contains('runtime-risks'));
      expect(kTermodeCommands, contains('runtime-next'));
      expect(kTermodeCommands, contains('runtime-research-doctor'));
    });

    test(
      'REAL PTY host interception includes runtime research commands',
      () async {
        final sessionService = TerminalSessionService();
        final session = sessionService.activeSession;
        session.lines.clear();
        session.isRealPtyActive = true;
        session.isPtyInteractionActive = true;

        await sessionService.executeCommand('runtime-candidates');
        await sessionService.executeCommand('runtime-next');

        final output = session.lines.map((line) => line.text).join('\n');
        expect(output, contains('runtime-candidates'));
        expect(output, contains('=== Runtime Candidates ==='));
        expect(output, contains('runtime-next'));
        expect(output, contains('v0.32 Embedded JS Engine Decision'));

        session.isPtyInteractionActive = false;
        session.isRealPtyActive = false;
      },
    );

    test('docs references are present', () {
      expect(File('docs/NATIVE_RUNTIME_CANDIDATES.md').existsSync(), isTrue);
      expect(File('docs/RUNTIME_STRATEGY.md').existsSync(), isTrue);
      expect(File('docs/BUNDLED_RUNTIME_PROOF.md').existsSync(), isTrue);
      expect(File('docs/NATIVE_TOOL_PROOF.md').existsSync(), isTrue);
      expect(File('docs/PACKAGE_AUTHORING.md').existsSync(), isTrue);
    });
  });
}
