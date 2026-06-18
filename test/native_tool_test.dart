import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/native_tool_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tiny Native Tool Proof (v0.29)', () {
    late Directory tempDir;
    late RuntimeBootstrapService runtime;
    late CommandService commandService;

    // 'success' | 'fail'
    String toolMode = 'success';

    const nativeChannel = MethodChannel('com.termode/native_shell');
    const sha256Hello =
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_native_tool');
      runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      commandService = CommandService(VirtualFileSystem(), 'native_tool_test');
      toolMode = 'success';

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (call) async {
            switch (call.method) {
              case 'nativeTool':
                if (toolMode == 'fail') {
                  throw PlatformException(
                    code: 'NATIVE_TOOL_FAILED',
                    message: 'boom',
                  );
                }
                final command = call.arguments['command'] as String;
                final args = call.arguments['args'] as String? ?? '';
                switch (command) {
                  case 'info':
                    return {
                      'ok': true,
                      'abi': 'arm64-v8a',
                      'pid': 1234,
                      'cwd': '/data/user/0/com.termode.termode/files/home',
                    };
                  case 'echo':
                    return {'ok': true, 'value': args};
                  case 'cwd':
                    return {
                      'ok': true,
                      'value': '/data/user/0/com.termode.termode/files/home',
                    };
                  case 'pid':
                    return {'ok': true, 'value': 1234};
                  case 'abi':
                    return {'ok': true, 'value': 'arm64-v8a'};
                  case 'hash':
                    return {
                      'ok': true,
                      'value': sha256Hello,
                      'hashType': 'SHA-256',
                    };
                  case 'time':
                    return {'ok': true, 'value': 1700000000000};
                  case 'env':
                    return {
                      'ok': true,
                      'env': {
                        'HOME': '/h',
                        'TMPDIR': '/t',
                        'TERMODE_HOME': '/th',
                        'TERMODE_USR': '/tu',
                        'TERMODE_BIN': '/tb',
                        'SECRET': 'leak',
                        'PATH': '/bin:/system/bin',
                      },
                    };
                  case 'doctor':
                    return {
                      'ok': true,
                      'abi': 'arm64-v8a',
                      'cwd': '/data/user/0/com.termode.termode/files/home',
                      'echoOk': true,
                      'hashOk': true,
                    };
                  default:
                    return {
                      'ok': false,
                      'error': 'unknown native tool command: $command',
                    };
                }
              case 'bundledRuntimeProof':
                return {
                  'token': 'termode-native-proof-ok',
                  'echo': 'hello',
                  'abi': 'arm64-v8a',
                  'pid': 4321,
                  'cwd': '/data/user/0/com.termode.termode/files/home',
                  'nativeBridge': true,
                  'apkNativeLayer': 'available',
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

    // ----- help -----

    test('native-tool help output', () async {
      final bare = await commandService.execute('native-tool');
      final help = await commandService.execute('native-tool help');
      for (final out in [bare.output, help.output]) {
        expect(out, contains('=== Native Tool ==='));
        expect(out, contains('native-tool echo <text>'));
        expect(out, contains('native-tool hash <text>'));
        expect(out, contains('native-tool doctor'));
        expect(out, contains('Node.js: not included'));
      }
    });

    // ----- info -----

    test('native-tool info output', () async {
      final result = await commandService.execute('native-tool info');
      expect(result.output, contains('=== Native Tool Info ==='));
      expect(result.output, contains('Native bridge: OK'));
      expect(result.output, contains('ABI: arm64-v8a'));
      expect(result.output, contains('PID: 1234'));
      expect(result.output, contains('CWD:'));
      expect(
        result.output,
        contains('Tools: echo, cwd, pid, abi, hash, time, env'),
      );
      expect(result.output, contains('Node.js: not included'));
    });

    // ----- echo / cwd / pid / abi -----

    test('native-tool echo output', () async {
      final result = await commandService.execute(
        'native-tool echo hello world',
      );
      expect(result.isError, isFalse);
      expect(result.output, 'hello world');
    });

    test('native-tool cwd output', () async {
      final result = await commandService.execute('native-tool cwd');
      expect(result.output, contains('/files/home'));
    });

    test('native-tool pid output', () async {
      final result = await commandService.execute('native-tool pid');
      expect(result.output, '1234');
    });

    test('native-tool abi output', () async {
      final result = await commandService.execute('native-tool abi');
      expect(result.output, 'arm64-v8a');
    });

    // ----- hash -----

    test('native-tool hash output', () async {
      final result = await commandService.execute('native-tool hash hello');
      expect(result.output, contains('Hash type: SHA-256'));
      expect(result.output, contains(sha256Hello));
    });

    test('native-tool hash requires text', () async {
      final result = await commandService.execute('native-tool hash');
      expect(result.isError, isTrue);
      expect(result.output, contains('Usage: native-tool hash <text>'));
    });

    // ----- time -----

    test('native-tool time output', () async {
      final result = await commandService.execute('native-tool time');
      expect(result.output, contains('Epoch ms: 1700000000000'));
      expect(result.output, contains('ISO:'));
    });

    // ----- env redaction -----

    test('native-tool env redacts and limits data', () async {
      final result = await commandService.execute('native-tool env');
      expect(result.output, contains('=== Native Tool Env ==='));
      expect(result.output, contains('HOME=/h'));
      expect(result.output, contains('TERMODE_HOME=/th'));
      expect(result.output, contains('TERMODE_BIN=/tb'));
      // Anything outside the whitelist must never be surfaced.
      expect(result.output, isNot(contains('SECRET')));
      expect(result.output, isNot(contains('leak')));
      expect(result.output, isNot(contains('PATH=')));
    });

    // ----- doctor -----

    test('native-tool doctor healthy output', () async {
      final result = await commandService.execute('native-tool doctor');
      expect(result.isError, isFalse);
      expect(result.output, contains('=== Native Tool Doctor ==='));
      expect(result.output, contains('Bridge: OK'));
      expect(result.output, contains('Echo: OK'));
      expect(result.output, contains('CWD: OK'));
      expect(result.output, contains('ABI: OK'));
      expect(result.output, contains('Hash: OK'));
      expect(result.output, contains('Overall: HEALTHY'));
    });

    // ----- bridge success / failure -----

    test('native bridge success mock', () async {
      final value = await NativeToolService().echo('ping');
      expect(value, 'ping');
    });

    test('native bridge failure mock is handled gracefully', () async {
      toolMode = 'fail';
      final echo = await commandService.execute('native-tool echo hi');
      expect(echo.output, contains('Native tool bridge unavailable.'));
      expect(echo.output, contains('Runtime remains limited.'));

      final doctor = await commandService.execute('native-tool doctor');
      expect(doctor.isError, isTrue);
      expect(doctor.output, contains('Bridge: FAIL'));
      expect(doctor.output, contains('Overall: UNHEALTHY'));
    });

    // ----- unknown subcommand -----

    test('unknown native-tool subcommand errors', () async {
      final result = await commandService.execute('native-tool frobnicate');
      expect(result.isError, isTrue);
      expect(
        result.output,
        contains('Unknown native-tool subcommand: frobnicate'),
      );
    });

    // ----- NORMAL vs REAL PTY -----

    test('native-tool commands work in NORMAL mode', () async {
      for (final cmd in [
        'native-tool',
        'native-tool info',
        'native-tool doctor',
      ]) {
        final result = await commandService.execute(cmd);
        expect(result.output, contains('Native Tool'));
      }
    });

    test('native-tool is intercepted inside REAL PTY mode', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('native-tool info');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('native-tool info'));
      expect(output, contains('=== Native Tool Info ==='));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });

    // ----- catalog / runtime integration / guardrails -----

    test('command catalog includes native-tool', () {
      expect(kTermodeCommands, contains('native-tool'));
    });

    test('help lists native tool commands', () async {
      final help = await commandService.execute('help');
      final result = await commandService.execute('native-tool help');
      expect(help.output, contains('native-tool help'));
      expect(result.output, contains('=== Native Tool ==='));
      expect(result.output, contains('native-tool echo <text>'));
    });

    test('runtime-plan includes tiny native tool proof', () async {
      final result = await commandService.execute('runtime-plan');
      expect(result.output, contains('5. Tiny native tool proof'));
      expect(result.output, contains('6. Native runtime candidate research'));
      expect(result.output, contains('7. Tiny JS/runtime feasibility proof'));
    });

    test('runtime-capabilities mentions native tools', () async {
      final result = await commandService.execute('runtime-capabilities');
      expect(result.output, contains('Tiny native tools via the JNI bridge'));
      expect(
        result.output,
        contains('Native tools are bridge-exposed, not package-installed'),
      );
    });

    test('bundled-runtime-doctor mentions native tools', () async {
      final result = await commandService.execute('bundled-runtime-doctor');
      expect(result.output, contains('Tiny native tool: available'));
    });

    test('pkg help still says native packages are unsupported', () async {
      final result = await commandService.execute('pkg help');
      expect(
        result.output,
        contains('Native binary packages are not supported'),
      );
      expect(
        result.output,
        contains('Native tools (native-tool) are built into Termode'),
      );
    });
  });
}
