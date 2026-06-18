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

  group('Duktape Probe (v0.34)', () {
    late Directory tempDir;
    late RuntimeBootstrapService runtime;
    late CommandService commandService;
    String bridgeMode = 'success';

    const nativeChannel = MethodChannel('com.termode/native_shell');

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_duktape');
      runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      commandService = CommandService(VirtualFileSystem(), 'duktape_test');
      bridgeMode = 'success';

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (call) async {
            if (call.method == 'duktape') {
              if (bridgeMode == 'throw') {
                throw PlatformException(
                  code: 'DUKTAPE_FAILED',
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
                    'engine': 'Duktape',
                    'mode': 'native embedded engine',
                    'status': bridgeMode == 'limited' ? 'UNAVAILABLE' : 'PROBE',
                    'limited': bridgeMode == 'limited',
                  };
                case 'eval':
                  if (bridgeMode == 'limited') {
                    return {
                      'ok': false,
                      'engine': 'Duktape',
                      'mode': 'native embedded engine',
                      'limited': true,
                      'error':
                          'Duktape engine is not integrated in this build.',
                    };
                  }
                  if (args.contains('bad')) {
                    return {
                      'ok': false,
                      'engine': 'Duktape',
                      'error': 'SyntaxError: unexpected token',
                    };
                  }
                  if (args.contains('longOutput')) {
                    return {
                      'ok': true,
                      'engine': 'Duktape',
                      'result': List.filled(9000, 'a').join(),
                    };
                  }
                  if (args.trim() == '1 + 2') {
                    return {'ok': true, 'engine': 'Duktape', 'result': '3'};
                  }
                  if (args.trim() == "'hello'.toUpperCase()") {
                    return {'ok': true, 'engine': 'Duktape', 'result': 'HELLO'};
                  }
                  if (args.trim() == 'var x = 5; x * 2') {
                    return {'ok': true, 'engine': 'Duktape', 'result': '10'};
                  }
                  return {'ok': true, 'engine': 'Duktape', 'result': args};
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

    test('duktape help output', () async {
      final bare = await commandService.execute('duktape');
      final help = await commandService.execute('duktape help');

      for (final output in [bare.output, help.output]) {
        expect(output, contains('=== Duktape Probe ==='));
        expect(output, contains('duktape eval <code>'));
        expect(output, contains('duktape file <path>'));
        expect(output, contains('not Node.js'));
      }
    });

    test('duktape info output', () async {
      final result = await commandService.execute('duktape info');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== Duktape Probe Info ==='));
      expect(result.output, contains('Engine: Duktape'));
      expect(result.output, contains('Mode: native embedded engine'));
      expect(result.output, contains('Node.js: not included'));
      expect(result.output, contains('npm: not included'));
      expect(result.output, contains('Filesystem API: disabled'));
      expect(result.output, contains('Network API: disabled'));
      expect(result.output, contains('Status: PROBE'));
    });

    test('duktape eval arithmetic success when mocked', () async {
      final result = await commandService.execute('duktape eval 1 + 2');

      expect(result.isError, isFalse);
      expect(result.output, contains('Engine: Duktape'));
      expect(result.output, contains('Result: 3'));
    });

    test('duktape eval string success when mocked', () async {
      final result = await commandService.execute(
        "duktape eval 'hello'.toUpperCase()",
      );

      expect(result.isError, isFalse);
      expect(result.output, contains('Result: HELLO'));
    });

    test('duktape eval var expression success when mocked', () async {
      final result = await commandService.execute(
        'duktape eval var x = 5; x * 2',
      );

      expect(result.isError, isFalse);
      expect(result.output, contains('Result: 10'));
    });

    test('duktape eval malformed JS does not crash', () async {
      final result = await commandService.execute('duktape eval bad !!!');

      expect(result.isError, isTrue);
      expect(result.output, contains('SyntaxError'));
    });

    test('duktape eval Node API blocked before bridge', () async {
      final result = await commandService.execute("duktape eval require('fs')");

      expect(result.isError, isTrue);
      expect(result.output, contains('Node APIs are not available'));
      expect(result.output, contains('embedded JavaScript, not Node.js'));
    });

    test('duktape eval code length limit', () async {
      final longCode = List.filled(4097, '1').join();
      final result = await commandService.execute('duktape eval $longCode');

      expect(result.isError, isTrue);
      expect(result.output, contains('exceeds 4096 characters'));
    });

    test('duktape output length limit', () async {
      final result = await commandService.execute('duktape eval longOutput()');

      expect(result.isError, isFalse);
      expect(result.output, contains('[Output truncated'));
      expect(result.output.length, lessThan(8300));
    });

    test('duktape file safe path', () async {
      await commandService.execute('workspace-init dukdemo');
      await commandService.execute('workspace-cd dukdemo');
      await commandService.execute('host-write test.js 1 + 2');

      final result = await commandService.execute('duktape file test.js');

      expect(result.isError, isFalse);
      expect(result.output, contains('Result: 3'));
    });

    test('duktape file traversal blocked', () async {
      final outside = File('${tempDir.parent.path}/outside-duktape.js');
      final result = await commandService.execute(
        'duktape file ${outside.path}',
      );

      expect(result.isError, isTrue);
      expect(result.output, contains('path escapes Termode workspace'));
    });

    test('duktape file size limit', () async {
      final paths = await runtime.getPaths();
      final big = File('${paths['home']}/big.js');
      await big.writeAsString('1' * 32769);

      final result = await commandService.execute('duktape file big.js');

      expect(result.isError, isTrue);
      expect(result.output, contains('exceeds 32768 bytes'));
    });

    test('duktape limits output', () async {
      final result = await commandService.execute('duktape limits');

      expect(result.output, contains('Max inline code length: 4096 chars'));
      expect(result.output, contains('Max file size: 32768 bytes'));
      expect(result.output, contains('Max output length: 8192 chars'));
      expect(result.output, contains('Filesystem: disabled'));
      expect(result.output, contains('Network: disabled'));
      expect(result.output, contains('Node APIs: disabled'));
      expect(result.output, contains('Timeout: not supported yet'));
      expect(result.output, contains('Loop guard: limited'));
    });

    test('duktape doctor healthy and limited output', () async {
      final healthy = await commandService.execute('duktape doctor');
      bridgeMode = 'limited';
      final limited = await commandService.execute('duktape doctor');

      expect(healthy.isError, isFalse);
      expect(healthy.output, contains('=== Duktape Doctor ==='));
      expect(healthy.output, contains('Bridge: OK'));
      expect(healthy.output, contains('Engine: OK'));
      expect(healthy.output, contains('Overall: HEALTHY'));
      expect(limited.isError, isFalse);
      expect(limited.output, contains('Engine: LIMITED'));
      expect(limited.output, contains('Overall: LIMITED'));
    });

    test('duktape plan output', () async {
      final result = await commandService.execute('duktape plan');

      expect(result.output, contains('1. Duktape probe'));
      expect(result.output, contains('Duktape integration deferred'));
      expect(result.output, contains('3. Product stabilization'));
      expect(result.output, contains('7. Vite later'));
    });

    test('Duktape bridge failure mock', () async {
      bridgeMode = 'throw';

      final result = await commandService.execute('duktape info');

      expect(result.isError, isFalse);
      expect(result.output, contains('Duktape bridge unavailable'));
      expect(result.output, contains('Runtime remains limited'));
    });

    test('Duktape bridge unavailable mock', () async {
      bridgeMode = 'unavailable';

      final result = await commandService.execute('duktape eval 1 + 2');

      expect(result.isError, isTrue);
      expect(result.output, contains('Duktape bridge unavailable'));
    });

    test('Duktape limited engine output', () async {
      bridgeMode = 'limited';

      final info = await commandService.execute('duktape info');
      final eval = await commandService.execute('duktape eval 1 + 2');

      expect(info.isError, isTrue);
      expect(info.output, contains('Status: UNAVAILABLE'));
      expect(eval.isError, isTrue);
      expect(eval.output, contains('engine is not integrated'));
    });

    test('runtime integration mentions Duktape probe', () async {
      final plan = await commandService.execute('runtime-plan');
      final caps = await commandService.execute('runtime-capabilities');
      final next = await commandService.execute('runtime-next');

      expect(plan.output, contains('10. Duktape probe/fallback'));
      expect(plan.output, contains('12. Product stabilization'));
      expect(plan.output, contains('16. CalypsoIDE integration later'));
      expect(caps.output, contains('Duktape probe command surface'));
      expect(next.output, contains('v0.36 Product Stabilization'));
    });

    test('js-engine commands mention Duktape fallback status', () async {
      final decision = await commandService.execute('js-engine-decision');
      final next = await commandService.execute('js-engine-next');
      final doctor = await commandService.execute('js-engine-doctor');

      expect(decision.output, contains('QuickJS and Duktape remain deferred'));
      expect(next.output, contains('v0.36 Product Stabilization'));
      expect(doctor.output, contains('Duktape probe: deferred'));
      expect(doctor.output, contains('Overall: LIMITED'));
    });

    test('help includes duktape', () async {
      final help = await commandService.execute('help');
      final duktapeHelp = await commandService.execute('duktape help');
      final runtimeHelp = await commandService.execute('runtime-help');

      expect(help.output, contains('commands --all'));
      expect(duktapeHelp.output, contains('=== Duktape Probe ==='));
      expect(duktapeHelp.output, contains('duktape eval <code>'));
      expect(runtimeHelp.output, contains('duktape [sub]'));
    });

    test('autocomplete includes duktape', () {
      expect(kTermodeCommands, contains('duktape'));
    });

    test('REAL PTY host interception includes duktape', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('duktape info');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('duktape info'));
      expect(output, contains('=== Duktape Probe Info ==='));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });
  });
}
