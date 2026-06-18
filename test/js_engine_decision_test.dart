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

  group('JS Engine Decision Commands', () {
    late Directory tempDir;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'termode_js_engine_decision',
      );
      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      commandService = CommandService(VirtualFileSystem(), 'js_engine_test');

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
                  'cwd': '/data/user/0/com.termode.termode/files/home',
                  'pid': 1234,
                  'abi': 'arm64-v8a',
                };
              }
              if (methodCall.method == 'jsProof') {
                final args = Map<String, dynamic>.from(
                  methodCall.arguments as Map,
                );
                if (args['command'] == 'info') {
                  return {
                    'ok': true,
                    'engine': 'tiny-js-proof',
                    'mode': 'native bridge',
                    'status': 'PROOF',
                  };
                }
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

    test('js-engine-candidates output', () async {
      final result = await commandService.execute('js-engine-candidates');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== JS Engine Candidates ==='));
      expect(result.output, contains('current-proof'));
      expect(result.output, contains('quickjs'));
      expect(result.output, contains('duktape'));
      expect(result.output, contains('javascriptcore'));
      expect(result.output, contains('v8'));
      expect(result.output, contains('node'));
      expect(result.output, contains('no-engine-yet'));
    });

    test('js-engine-candidate current-proof', () async {
      final result = await commandService.execute(
        'js-engine-candidate current-proof',
      );

      expect(result.isError, isFalse);
      expect(result.output, contains('What it is:'));
      expect(result.output, contains('js-proof'));
      expect(result.output, contains('Very small and safe'));
      expect(result.output, contains('Recommendation:'));
    });

    test('js-engine-candidate quickjs', () async {
      final result = await commandService.execute(
        'js-engine-candidate quickjs',
      );

      expect(result.isError, isFalse);
      expect(result.output, contains('small embeddable JavaScript engine'));
      expect(result.output, contains('timeout/resource limits'));
      expect(result.output, contains('v0.33 proof'));
    });

    test('js-engine-candidate duktape', () async {
      final result = await commandService.execute(
        'js-engine-candidate duktape',
      );

      expect(result.isError, isFalse);
      expect(result.output, contains('mature small embeddable'));
      expect(result.output, contains('fallback'));
      expect(result.output, contains('Less modern'));
    });

    test('js-engine-candidate node', () async {
      final result = await commandService.execute('js-engine-candidate node');

      expect(result.isError, isFalse);
      expect(result.output, contains('Node.js is a full runtime'));
      expect(result.output, contains('npm expectations'));
      expect(result.output, contains('Not included'));
    });

    test('unknown js-engine candidate errors', () async {
      final result = await commandService.execute(
        'js-engine-candidate imaginary',
      );

      expect(result.isError, isTrue);
      expect(result.output, contains('Unknown JS engine candidate'));
      expect(result.output, contains('quickjs'));
      expect(result.output, contains('no-engine-yet'));
    });

    test('js-engine-decision output', () async {
      final result = await commandService.execute('js-engine-decision');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== JS Engine Decision ==='));
      expect(result.output, contains('QuickJS remains a limited v0.33 probe'));
      expect(result.output, contains('v0.34 Duktape Probe'));
      expect(result.output, contains('Node.js included: NO'));
    });

    test('js-engine-risks output', () async {
      final result = await commandService.execute('js-engine-risks');

      expect(result.isError, isFalse);
      expect(result.output, contains('Infinite loops'));
      expect(result.output, contains('Memory growth'));
      expect(result.output, contains('APK size'));
      expect(result.output, contains('Node.js/npm compatibility'));
    });

    test('js-engine-next output', () async {
      final result = await commandService.execute('js-engine-next');

      expect(result.isError, isFalse);
      expect(result.output, contains('v0.34 Duktape Probe'));
      expect(result.output, contains('Fallback'));
      expect(result.output, contains('Node.js/npm: still not included'));
    });

    test('js-engine-doctor output', () async {
      final result = await commandService.execute('js-engine-doctor');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== JS Engine Doctor ==='));
      expect(result.output, contains('Current proof: js-proof'));
      expect(result.output, contains('QuickJS probe: limited/unavailable'));
      expect(result.output, contains('Real embedded engine: not integrated'));
      expect(result.output, contains('Overall: LIMITED'));
    });

    test(
      'runtime-plan includes real embedded JS engine decision/probe',
      () async {
        final result = await commandService.execute('runtime-plan');

        expect(
          result.output,
          contains('8. Real embedded JS engine decision/probe'),
        );
        expect(result.output, contains('9. QuickJS probe'));
        expect(result.output, contains('14. CalypsoIDE integration later'));
      },
    );

    test('runtime-next recommends v0.34 Duktape fallback', () async {
      final result = await commandService.execute('runtime-next');

      expect(result.output, contains('v0.34 Duktape Probe'));
      expect(result.output, contains('Fallback'));
      expect(result.output, contains('Duktape'));
      expect(result.output, contains('Node.js/npm: still not included'));
    });

    test('js-proof plan mentions JS engine decision', () async {
      final plan = await commandService.execute('js-proof plan');
      final info = await commandService.execute('js-proof info');

      expect(plan.output, contains('Embedded JS engine decision/probe'));
      expect(plan.output, contains('QuickJS probe command surface'));
      expect(info.output, contains('QuickJS probe'));
    });

    test('command catalog includes JS engine commands', () {
      expect(kTermodeCommands, contains('js-engine-candidates'));
      expect(kTermodeCommands, contains('js-engine-candidate'));
      expect(kTermodeCommands, contains('js-engine-decision'));
      expect(kTermodeCommands, contains('js-engine-risks'));
      expect(kTermodeCommands, contains('js-engine-next'));
      expect(kTermodeCommands, contains('js-engine-doctor'));
    });

    test('REAL PTY host interception includes JS engine commands', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('js-engine-candidates');
      await sessionService.executeCommand('js-engine-next');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('js-engine-candidates'));
      expect(output, contains('=== JS Engine Candidates ==='));
      expect(output, contains('js-engine-next'));
      expect(output, contains('v0.34 Duktape Probe'));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });

    test('docs references are present', () {
      expect(File('docs/JS_ENGINE_DECISION.md').existsSync(), isTrue);
      expect(File('docs/JS_PROOF.md').readAsStringSync(), contains('v0.32'));
      expect(
        File('docs/RUNTIME_STRATEGY.md').readAsStringSync(),
        contains('Duktape Probe'),
      );
      expect(
        File('docs/NATIVE_RUNTIME_CANDIDATES.md').readAsStringSync(),
        contains('JS_ENGINE_DECISION.md'),
      );
    });
  });
}
