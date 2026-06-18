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

  group('Tiny JS Proof (v0.31)', () {
    late Directory tempDir;
    late RuntimeBootstrapService runtime;
    late CommandService commandService;
    String bridgeMode = 'success';

    const nativeChannel = MethodChannel('com.termode/native_shell');

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_js_proof');
      runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      commandService = CommandService(VirtualFileSystem(), 'js_proof_test');
      bridgeMode = 'success';

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (call) async {
            if (call.method == 'jsProof') {
              if (bridgeMode == 'fail') {
                throw PlatformException(
                  code: 'JS_PROOF_FAILED',
                  message: 'boom',
                );
              }
              final command = call.arguments['command'] as String;
              final args = call.arguments['args'] as String? ?? '';
              switch (command) {
                case 'info':
                  return {
                    'ok': true,
                    'engine': 'tiny-js-proof',
                    'mode': 'native bridge',
                    'node': false,
                    'npm': false,
                    'shellExecution': false,
                    'status': 'PROOF',
                  };
                case 'eval':
                  if (args.contains('require') || args.contains('bad')) {
                    return {
                      'ok': false,
                      'error': 'Unsupported JS proof syntax.',
                      'engine': 'tiny-js-proof',
                      'mode': 'native bridge',
                    };
                  }
                  if (args.trim() == '1 + 2' || args.trim() == '1+2') {
                    return {'ok': true, 'result': '3'};
                  }
                  if (args.trim() == '1 + 2 * 3') {
                    return {'ok': true, 'result': '7'};
                  }
                  if (args.trim() == "'hello'") {
                    return {'ok': true, 'result': 'hello'};
                  }
                  if (args.trim() == 'true') {
                    return {'ok': true, 'result': 'true'};
                  }
                  return {'ok': true, 'result': args.trim()};
                case 'doctor':
                  return {
                    'ok': true,
                    'bridgeOk': true,
                    'evaluatorOk': true,
                    'errorsOk': true,
                    'engine': 'tiny-js-proof',
                    'mode': 'native bridge',
                  };
                case 'limits':
                  return {
                    'ok': true,
                    'engine': 'tiny-js-proof',
                    'mode': 'native bridge',
                    'maxCodeLength': 4096,
                    'maxFileSize': 32768,
                  };
              }
            }
            if (call.method == 'realPtySend') {
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

    test('js-proof help output', () async {
      final bare = await commandService.execute('js-proof');
      final help = await commandService.execute('js-proof help');

      for (final output in [bare.output, help.output]) {
        expect(output, contains('=== JS Proof ==='));
        expect(output, contains('js-proof eval <code>'));
        expect(output, contains('js-proof file <path>'));
        expect(output, contains('not Node.js'));
      }
    });

    test('js-proof info output', () async {
      final result = await commandService.execute('js-proof info');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== JS Proof Info ==='));
      expect(result.output, contains('Engine: tiny-js-proof'));
      expect(result.output, contains('Mode: native bridge'));
      expect(result.output, contains('Node.js: not included'));
      expect(result.output, contains('npm: not included'));
      expect(result.output, contains('Shell execution: no'));
      expect(result.output, contains('Status: PROOF'));
    });

    test('js-proof eval arithmetic success', () async {
      final simple = await commandService.execute('js-proof eval 1 + 2');
      final precedence = await commandService.execute(
        'js-proof eval 1 + 2 * 3',
      );

      expect(simple.isError, isFalse);
      expect(simple.output, 'Result: 3');
      expect(precedence.output, 'Result: 7');
    });

    test('js-proof eval unsupported syntax', () async {
      final result = await commandService.execute(
        "js-proof eval require('fs')",
      );

      expect(result.isError, isTrue);
      expect(result.output, contains('Unsupported JS proof syntax'));
      expect(result.output, contains('This is not Node.js'));
    });

    test('js-proof eval malformed input does not crash', () async {
      final result = await commandService.execute('js-proof eval bad !!!');

      expect(result.isError, isTrue);
      expect(result.output, contains('Unsupported JS proof syntax'));
    });

    test('js-proof eval length limit', () async {
      final longCode = List.filled(4097, '1').join();
      final result = await commandService.execute('js-proof eval $longCode');

      expect(result.isError, isTrue);
      expect(result.output, contains('exceeds 4096 characters'));
    });

    test('js-proof file safe path', () async {
      await commandService.execute('workspace-init jsdemo');
      await commandService.execute('workspace-cd jsdemo');
      await commandService.execute('host-write test.js 1 + 2');

      final result = await commandService.execute('js-proof file test.js');

      expect(result.isError, isFalse);
      expect(result.output, 'Result: 3');
    });

    test('js-proof file traversal blocked', () async {
      final outside = File('${tempDir.parent.path}/outside-js-proof.js');
      final result = await commandService.execute(
        'js-proof file ${outside.path}',
      );

      expect(result.isError, isTrue);
      expect(result.output, contains('path escapes Termode workspace'));
    });

    test('js-proof file size limit', () async {
      final paths = await runtime.getPaths();
      final big = File('${paths['home']}/big.js');
      await big.writeAsString('1' * 32769);

      final result = await commandService.execute('js-proof file big.js');

      expect(result.isError, isTrue);
      expect(result.output, contains('exceeds 32768 bytes'));
    });

    test('js-proof doctor healthy output', () async {
      final result = await commandService.execute('js-proof doctor');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== JS Proof Doctor ==='));
      expect(result.output, contains('Bridge: OK'));
      expect(result.output, contains('Evaluator: OK'));
      expect(result.output, contains('Errors: OK'));
      expect(result.output, contains('Node.js: not included'));
      expect(result.output, contains('Overall: HEALTHY'));
    });

    test('js-proof limits output', () async {
      final result = await commandService.execute('js-proof limits');

      expect(result.output, contains('Max code length: 4096'));
      expect(result.output, contains('Max file size: 32768'));
      expect(
        result.output,
        contains('Supported: arithmetic/string/boolean subset'),
      );
      expect(result.output, contains('Unsupported: Node APIs'));
    });

    test('js-proof plan output', () async {
      final result = await commandService.execute('js-proof plan');

      expect(result.output, contains('1. Tiny JS proof'));
      expect(result.output, contains('2. Embedded JS engine decision/probe'));
      expect(result.output, contains('3. v0.33 QuickJS Probe'));
      expect(result.output, contains('5. Node binary strategy later'));
      expect(result.output, contains('7. Vite later'));
    });

    test('native bridge success mock', () async {
      final result = await commandService.execute("js-proof eval 'hello'");

      expect(result.output, 'Result: hello');
    });

    test('native bridge failure mock', () async {
      bridgeMode = 'fail';

      final result = await commandService.execute('js-proof info');

      expect(result.output, contains('Native JS proof unavailable'));
      expect(result.output, contains('Runtime remains limited'));
    });

    test('runtime integration mentions tiny JS proof', () async {
      final plan = await commandService.execute('runtime-plan');
      final caps = await commandService.execute('runtime-capabilities');
      final next = await commandService.execute('runtime-next');

      expect(plan.output, contains('7. Tiny JS/runtime feasibility proof'));
      expect(
        plan.output,
        contains('8. Real embedded JS engine decision/probe'),
      );
      expect(caps.output, contains('Tiny JS proof via native bridge'));
      expect(caps.output, contains('does not prove Node compatibility'));
      expect(next.output, contains('v0.33 QuickJS Probe'));
    });

    test('help includes js-proof', () async {
      final help = await commandService.execute('help');
      final runtimeHelp = await commandService.execute('runtime-help');

      expect(help.output, contains('JS Proof Commands:'));
      expect(help.output, contains('js-proof eval <code>'));
      expect(runtimeHelp.output, contains('js-proof [sub]'));
    });

    test('autocomplete includes js-proof', () {
      expect(kTermodeCommands, contains('js-proof'));
    });

    test('REAL PTY host interception includes js-proof', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('js-proof info');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('js-proof info'));
      expect(output, contains('=== JS Proof Info ==='));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });
  });
}
