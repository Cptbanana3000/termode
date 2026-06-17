import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/bundled_runtime_service.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bundled Runtime Proof (v0.28)', () {
    late Directory tempDir;
    late RuntimeBootstrapService runtime;
    late CommandService commandService;

    // 'success' | 'limited' | 'null' | 'throw'
    String proofMode = 'success';

    const nativeChannel = MethodChannel('com.termode/native_shell');

    setUp(() async {
      HttpOverrides.global = null;
      tempDir = await Directory.systemTemp.createTemp('termode_bundled_test');
      runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      commandService = CommandService(VirtualFileSystem(), 'bundled_test');
      proofMode = 'success';

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (call) async {
            switch (call.method) {
              case 'bundledRuntimeProof':
                switch (proofMode) {
                  case 'null':
                    return null;
                  case 'throw':
                    throw PlatformException(
                      code: 'PROOF_FAILED',
                      message: 'native proof failed',
                    );
                  case 'limited':
                    return {
                      'token': 'termode-native-proof-ok',
                      'echo': 'WRONG',
                      'abi': 'arm64-v8a',
                      'pid': 4321,
                      'cwd': '/data/user/0/com.termode.termode/files/home',
                      'nativeBridge': true,
                      'apkNativeLayer': 'available',
                    };
                  default:
                    return {
                      'token': 'termode-native-proof-ok',
                      'echo': 'hello',
                      'abi': 'arm64-v8a',
                      'pid': 4321,
                      'cwd': '/data/user/0/com.termode.termode/files/home',
                      'nativeBridge': true,
                      'apkNativeLayer': 'available',
                    };
                }
              case 'executeCommand':
                final command = call.arguments['command'] as String;
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
                return {'stdout': '', 'stderr': '', 'exitCode': 0};
              case 'getDiagnostics':
                return {
                  'userDir': '/data/user/0/com.termode.termode/files/home',
                  'cwd': '/data/user/0/com.termode.termode/files/home',
                  'pid': 1234,
                  'abi': 'arm64-v8a',
                  'testOutput': 'shell-ok',
                };
              case 'realPtySend':
                return true;
            }
            return null;
          });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    // ----- native bridge proof -----

    test('native bridge proof success mock', () async {
      final p = await BundledRuntimeService().proof();
      expect(p.bridgeOk, isTrue);
      expect(p.tokenOk, isTrue);
      expect(p.echoOk, isTrue);
      expect(p.abi, 'arm64-v8a');
      expect(p.readiness, 'PROOF READY');
    });

    test('native bridge proof failure handled gracefully (null)', () async {
      proofMode = 'null';
      final p = await BundledRuntimeService().proof();
      expect(p.bridgeOk, isFalse);
      expect(p.readiness, 'UNAVAILABLE');
    });

    test('native bridge proof failure handled gracefully (throw)', () async {
      proofMode = 'throw';
      final p = await BundledRuntimeService().proof();
      expect(p.bridgeOk, isFalse);
      expect(p.error, isNotNull);
      expect(p.readiness, 'UNAVAILABLE');
    });

    // ----- bundled-runtime-info -----

    test('bundled-runtime-info output', () async {
      final result = await commandService.execute('bundled-runtime-info');
      expect(result.isError, isFalse);
      expect(result.output, contains('=== Bundled Runtime Info ==='));
      expect(result.output, contains('ABI: arm64-v8a'));
      expect(result.output, contains('Native bridge: OK'));
      expect(result.output, contains('APK native layer: available'));
      expect(
        result.output,
        contains('Executable strategy: bridge/native-lib proof'),
      );
      expect(result.output, contains('Node.js: not included'));
      expect(result.output, contains('Overall: PROOF READY'));
    });

    test('bundled-runtime-info reports UNAVAILABLE when bridge fails', () async {
      proofMode = 'throw';
      final result = await commandService.execute('bundled-runtime-info');
      expect(result.output, contains('Native bridge: unavailable'));
      expect(result.output, contains('Overall: UNAVAILABLE'));
    });

    // ----- bundled-runtime-test -----

    test('bundled-runtime-test output', () async {
      final result = await commandService.execute('bundled-runtime-test');
      expect(result.isError, isFalse);
      expect(result.output, contains('=== Bundled Runtime Test ==='));
      expect(result.output, contains('Native bridge call: OK'));
      expect(result.output, contains('ABI: arm64-v8a'));
      expect(result.output, contains('Native cwd:'));
      expect(result.output, contains('Native pid: 4321'));
      expect(result.output, contains('Echo proof: OK'));
      expect(result.output, contains('Overall: PASS'));
    });

    test('bundled-runtime-test reports LIMITED on echo mismatch', () async {
      proofMode = 'limited';
      final result = await commandService.execute('bundled-runtime-test');
      expect(result.output, contains('Echo proof: FAIL'));
      expect(result.output, contains('Overall: LIMITED'));
    });

    test('bundled-runtime-test FAIL is an error', () async {
      proofMode = 'throw';
      final result = await commandService.execute('bundled-runtime-test');
      expect(result.isError, isTrue);
      expect(result.output, contains('Overall: FAIL'));
    });

    // ----- bundled-runtime-doctor -----

    test('bundled-runtime-doctor compact output', () async {
      final result = await commandService.execute('bundled-runtime-doctor');
      expect(result.isError, isFalse);
      expect(result.output, contains('=== Bundled Runtime Doctor ==='));
      expect(result.output, contains('Native bridge: OK'));
      expect(result.output, contains('Native proof token: OK'));
      expect(result.output, contains('Echo dispatcher: OK'));
      expect(result.output, contains('ABI: arm64-v8a'));
      expect(result.output, contains('APK native layer: available'));
      expect(result.output, contains('Bundled executable:'));
      expect(result.output, contains('Node.js: not included'));
      expect(result.output, contains('Overall: PROOF READY'));
    });

    test('bundled-runtime-doctor verbose output', () async {
      final result = await commandService.execute(
        'bundled-runtime-doctor --verbose',
      );
      expect(result.output, contains('Details:'));
      expect(
        result.output,
        contains('Native library: libtermode_pty.so'),
      );
      expect(
        result.output,
        contains('Native channel: com.termode/native_shell'),
      );
      expect(result.output, contains('Token value: termode-native-proof-ok'));
    });

    // ----- bundled-runtime-paths -----

    test('bundled-runtime-paths output', () async {
      final result = await commandService.execute('bundled-runtime-paths');
      expect(result.output, contains('=== Bundled Runtime Paths ==='));
      expect(result.output, contains('Native library: libtermode_pty.so'));
      expect(
        result.output,
        contains('Native bridge channel: com.termode/native_shell'),
      );
      expect(result.output, contains('App HOME:'));
      expect(result.output, contains('App USR:'));
      expect(result.output, contains('App BIN:'));
      expect(
        result.output,
        contains('app-writable usr/bin execution is blocked/limited'),
      );
    });

    // ----- bundled-runtime-plan -----

    test('bundled-runtime-plan output', () async {
      final result = await commandService.execute('bundled-runtime-plan');
      expect(result.output, contains('=== Bundled Runtime Plan ==='));
      expect(result.output, contains('Native bridge proof (v0.28)'));
      expect(result.output, contains('Native echo dispatcher proof'));
      expect(result.output, contains('Node.js: not included in v0.28.'));
    });

    // ----- runtime command integration -----

    test('runtime-doctor includes bundled proof status', () async {
      final result = await commandService.execute('runtime-doctor');
      expect(result.output, contains('Bundled proof: PROOF READY'));
    });

    test('runtime-exec-test includes bundled native proof', () async {
      final result = await commandService.execute('runtime-exec-test');
      expect(result.output, contains('bundled native proof: PASS'));
    });

    test('runtime-capabilities mentions bundled runtime proof', () async {
      final result = await commandService.execute('runtime-capabilities');
      expect(result.output, contains('Bundled native bridge proof'));
      expect(result.output, contains('Node.js not included'));
      // Still lists the unsupported runtimes.
      expect(result.output, contains('Native binary packages'));
      expect(result.output, contains('Node.js'));
    });

    test('runtime-plan includes bundled native proof', () async {
      final result = await commandService.execute('runtime-plan');
      expect(result.output, contains('4. Bundled native proof'));
      expect(result.output, contains('5. Tiny native tool proof'));
    });

    // ----- package guardrails -----

    test('pkg help still says native packages are not supported', () async {
      final result = await commandService.execute('pkg help');
      expect(
        result.output,
        contains('Native binary packages are not supported'),
      );
      expect(result.output, contains('Remote packages are script-only'));
      expect(
        result.output,
        contains('bundled runtime proof'),
      );
    });

    // ----- help / autocomplete -----

    test('help lists bundled runtime commands', () async {
      final result = await commandService.execute('help');
      expect(result.output, contains('bundled-runtime-info'));
      expect(result.output, contains('bundled-runtime-test'));
      expect(result.output, contains('bundled-runtime-doctor'));
    });

    test('command catalog includes bundled runtime commands', () {
      for (final cmd in [
        'bundled-runtime-info',
        'bundled-runtime-test',
        'bundled-runtime-doctor',
        'bundled-runtime-paths',
        'bundled-runtime-plan',
      ]) {
        expect(kTermodeCommands, contains(cmd));
      }
    });

    // ----- NORMAL mode vs REAL PTY interception -----

    test('commands work in NORMAL mode', () async {
      for (final cmd in [
        'bundled-runtime-info',
        'bundled-runtime-test',
        'bundled-runtime-doctor',
        'bundled-runtime-paths',
        'bundled-runtime-plan',
      ]) {
        final result = await commandService.execute(cmd);
        expect(result.output, contains('Bundled Runtime'));
      }
    });

    test('bundled-runtime commands are intercepted inside REAL PTY mode', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('bundled-runtime-info');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('bundled-runtime-info'));
      expect(output, contains('=== Bundled Runtime Info ==='));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });
  });
}
