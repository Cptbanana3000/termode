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

  group('QuickJS Probe (v0.33)', () {
    late Directory tempDir;
    late RuntimeBootstrapService runtime;
    late CommandService commandService;
    String bridgeMode = 'success';

    const nativeChannel = MethodChannel('com.termode/native_shell');

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_quickjs');
      runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      commandService = CommandService(VirtualFileSystem(), 'quickjs_test');
      bridgeMode = 'success';

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (call) async {
            if (call.method == 'quickJs') {
              if (bridgeMode == 'throw') {
                throw PlatformException(
                  code: 'QUICKJS_FAILED',
                  message: 'boom',
                );
              }
              if (bridgeMode == 'unavailable') {
                return null;
              }
              final command = call.arguments['command'] as String;
              final args = call.arguments['args'] as String? ?? '';
              switch (command) {
                case 'info':
                  return {
                    'ok': true,
                    'engine': 'QuickJS',
                    'mode': 'native embedded engine',
                    'status': bridgeMode == 'limited' ? 'UNAVAILABLE' : 'PROBE',
                    'limited': bridgeMode == 'limited',
                  };
                case 'eval':
                  if (bridgeMode == 'limited') {
                    return {
                      'ok': false,
                      'engine': 'QuickJS',
                      'mode': 'native embedded engine',
                      'limited': true,
                      'error':
                          'QuickJS engine is not integrated in this build.',
                    };
                  }
                  if (args.contains('bad')) {
                    return {
                      'ok': false,
                      'engine': 'QuickJS',
                      'error': 'SyntaxError: unexpected token',
                    };
                  }
                  if (args.contains('longOutput')) {
                    return {
                      'ok': true,
                      'engine': 'QuickJS',
                      'result': List.filled(9000, 'a').join(),
                    };
                  }
                  if (args.trim() == '1 + 2') {
                    return {'ok': true, 'engine': 'QuickJS', 'result': '3'};
                  }
                  if (args.trim() == "'hello'.toUpperCase()") {
                    return {'ok': true, 'engine': 'QuickJS', 'result': 'HELLO'};
                  }
                  if (args.trim() == 'const x = 5; x * 2') {
                    return {'ok': true, 'engine': 'QuickJS', 'result': '10'};
                  }
                  return {'ok': true, 'engine': 'QuickJS', 'result': args};
                case 'doctor':
                  return {
                    'ok': true,
                    'bridgeOk': true,
                    'engineOk': bridgeMode != 'limited',
                    'evalOk': bridgeMode != 'limited',
                    'errorsOk': true,
                    'overall': bridgeMode == 'limited' ? 'LIMITED' : 'HEALTHY',
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

    test('quickjs help output', () async {
      final bare = await commandService.execute('quickjs');
      final help = await commandService.execute('quickjs help');

      for (final output in [bare.output, help.output]) {
        expect(output, contains('=== QuickJS Probe ==='));
        expect(output, contains('quickjs eval <code>'));
        expect(output, contains('quickjs file <path>'));
        expect(output, contains('not Node.js'));
      }
    });

    test('quickjs info output', () async {
      final result = await commandService.execute('quickjs info');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== QuickJS Probe Info ==='));
      expect(result.output, contains('Engine: QuickJS'));
      expect(result.output, contains('Mode: native embedded engine'));
      expect(result.output, contains('Node.js: not included'));
      expect(result.output, contains('npm: not included'));
      expect(result.output, contains('Filesystem API: disabled'));
      expect(result.output, contains('Network API: disabled'));
      expect(result.output, contains('Status: PROBE'));
    });

    test('quickjs eval arithmetic success when mocked', () async {
      final result = await commandService.execute('quickjs eval 1 + 2');

      expect(result.isError, isFalse);
      expect(result.output, contains('Engine: QuickJS'));
      expect(result.output, contains('Result: 3'));
    });

    test('quickjs eval string success when mocked', () async {
      final result = await commandService.execute(
        "quickjs eval 'hello'.toUpperCase()",
      );

      expect(result.isError, isFalse);
      expect(result.output, contains('Result: HELLO'));
    });

    test('quickjs eval const expression success when mocked', () async {
      final result = await commandService.execute(
        'quickjs eval const x = 5; x * 2',
      );

      expect(result.isError, isFalse);
      expect(result.output, contains('Result: 10'));
    });

    test('quickjs eval malformed JS does not crash', () async {
      final result = await commandService.execute('quickjs eval bad !!!');

      expect(result.isError, isTrue);
      expect(result.output, contains('SyntaxError'));
    });

    test('quickjs eval Node API blocked before bridge', () async {
      final result = await commandService.execute("quickjs eval require('fs')");

      expect(result.isError, isTrue);
      expect(result.output, contains('Node APIs are not available'));
      expect(result.output, contains('embedded JavaScript, not Node.js'));
    });

    test('quickjs eval code length limit', () async {
      final longCode = List.filled(4097, '1').join();
      final result = await commandService.execute('quickjs eval $longCode');

      expect(result.isError, isTrue);
      expect(result.output, contains('exceeds 4096 characters'));
    });

    test('quickjs output length limit', () async {
      final result = await commandService.execute('quickjs eval longOutput()');

      expect(result.isError, isFalse);
      expect(result.output, contains('[Output truncated'));
      expect(result.output.length, lessThan(8300));
    });

    test('quickjs file safe path', () async {
      await commandService.execute('workspace-init quickdemo');
      await commandService.execute('workspace-cd quickdemo');
      await commandService.execute('host-write test.js 1 + 2');

      final result = await commandService.execute('quickjs file test.js');

      expect(result.isError, isFalse);
      expect(result.output, contains('Result: 3'));
    });

    test('quickjs file traversal blocked', () async {
      final outside = File('${tempDir.parent.path}/outside-quickjs.js');
      final result = await commandService.execute(
        'quickjs file ${outside.path}',
      );

      expect(result.isError, isTrue);
      expect(result.output, contains('path escapes Termode workspace'));
    });

    test('quickjs file size limit', () async {
      final paths = await runtime.getPaths();
      final big = File('${paths['home']}/big.js');
      await big.writeAsString('1' * 32769);

      final result = await commandService.execute('quickjs file big.js');

      expect(result.isError, isTrue);
      expect(result.output, contains('exceeds 32768 bytes'));
    });

    test('quickjs limits output', () async {
      final result = await commandService.execute('quickjs limits');

      expect(result.output, contains('Max inline code length: 4096 chars'));
      expect(result.output, contains('Max file size: 32768 bytes'));
      expect(result.output, contains('Max output length: 8192 chars'));
      expect(result.output, contains('Filesystem: disabled'));
      expect(result.output, contains('Network: disabled'));
      expect(result.output, contains('Node APIs: disabled'));
      expect(result.output, contains('Timeout: not supported yet'));
    });

    test('quickjs doctor healthy and limited output', () async {
      final healthy = await commandService.execute('quickjs doctor');
      bridgeMode = 'limited';
      final limited = await commandService.execute('quickjs doctor');

      expect(healthy.isError, isFalse);
      expect(healthy.output, contains('=== QuickJS Doctor ==='));
      expect(healthy.output, contains('Bridge: OK'));
      expect(healthy.output, contains('Engine: OK'));
      expect(healthy.output, contains('Overall: HEALTHY'));
      expect(limited.isError, isFalse);
      expect(limited.output, contains('Engine: LIMITED'));
      expect(limited.output, contains('Overall: LIMITED'));
    });

    test('quickjs plan output', () async {
      final result = await commandService.execute('quickjs plan');

      expect(result.output, contains('1. QuickJS probe'));
      expect(result.output, contains('2. QuickJS safety hardening'));
      expect(result.output, contains('3. Optional JS script package bridge'));
      expect(result.output, contains('6. Vite later'));
    });

    test('QuickJS bridge failure mock', () async {
      bridgeMode = 'throw';

      final result = await commandService.execute('quickjs info');

      expect(result.isError, isFalse);
      expect(result.output, contains('QuickJS bridge unavailable'));
      expect(result.output, contains('Runtime remains limited'));
    });

    test('QuickJS bridge unavailable mock', () async {
      bridgeMode = 'unavailable';

      final result = await commandService.execute('quickjs eval 1 + 2');

      expect(result.isError, isTrue);
      expect(result.output, contains('QuickJS bridge unavailable'));
    });

    test('QuickJS limited engine output', () async {
      bridgeMode = 'limited';

      final info = await commandService.execute('quickjs info');
      final eval = await commandService.execute('quickjs eval 1 + 2');

      expect(info.isError, isTrue);
      expect(info.output, contains('Status: UNAVAILABLE'));
      expect(eval.isError, isTrue);
      expect(eval.output, contains('engine is not integrated'));
    });

    test('runtime integration mentions QuickJS probe', () async {
      final plan = await commandService.execute('runtime-plan');
      final caps = await commandService.execute('runtime-capabilities');
      final next = await commandService.execute('runtime-next');

      expect(plan.output, contains('9. QuickJS probe'));
      expect(plan.output, contains('14. CalypsoIDE integration later'));
      expect(caps.output, contains('QuickJS probe command surface'));
      expect(next.output, contains('v0.34 Duktape Probe'));
    });

    test('js-engine commands mention QuickJS fallback status', () async {
      final decision = await commandService.execute('js-engine-decision');
      final next = await commandService.execute('js-engine-next');
      final doctor = await commandService.execute('js-engine-doctor');

      expect(
        decision.output,
        contains('QuickJS remains a limited v0.33 probe'),
      );
      expect(next.output, contains('v0.34 Duktape Probe'));
      expect(doctor.output, contains('QuickJS probe: limited/unavailable'));
      expect(doctor.output, contains('Overall: LIMITED'));
    });

    test('help includes quickjs', () async {
      final help = await commandService.execute('help');
      final runtimeHelp = await commandService.execute('runtime-help');

      expect(help.output, contains('QuickJS Probe Commands:'));
      expect(help.output, contains('quickjs eval <code>'));
      expect(runtimeHelp.output, contains('quickjs [sub]'));
    });

    test('autocomplete includes quickjs', () {
      expect(kTermodeCommands, contains('quickjs'));
    });

    test('REAL PTY host interception includes quickjs', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('quickjs info');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('quickjs info'));
      expect(output, contains('=== QuickJS Probe Info ==='));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });
  });
}
