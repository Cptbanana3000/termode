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

  group('Runtime Decision Freeze (v0.35)', () {
    late Directory tempDir;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_runtime_freeze');
      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      commandService = CommandService(VirtualFileSystem(), 'freeze_test');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            (MethodCall methodCall) async {
              if (methodCall.method == 'realPtySend') {
                return true;
              }
              if (methodCall.method == 'executeCommand') {
                return {'stdout': '', 'stderr': '', 'exitCode': 0};
              }
              if (methodCall.method == 'getDiagnostics') {
                return {
                  'cwd': '/data/user/0/com.termode.termode/files/home',
                  'pid': 1234,
                  'abi': 'arm64-v8a',
                };
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

    test('runtime-freeze help output', () async {
      final bare = await commandService.execute('runtime-freeze');
      final help = await commandService.execute('runtime-freeze help');

      for (final output in [bare.output, help.output]) {
        expect(output, contains('=== Runtime Freeze ==='));
        expect(output, contains('runtime-freeze status'));
        expect(output, contains('runtime-freeze doctor'));
      }
    });

    test('runtime-freeze status output', () async {
      final result = await commandService.execute('runtime-freeze status');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== Runtime Freeze Status ==='));
      expect(result.output, contains('Decision: frozen'));
      expect(result.output, contains('Current JS path: js-proof'));
      expect(result.output, contains('QuickJS: deferred'));
      expect(result.output, contains('Duktape: deferred'));
      expect(result.output, contains('Overall: FROZEN'));
    });

    test('runtime-freeze decision output', () async {
      final result = await commandService.execute('runtime-freeze decision');

      expect(result.output, contains('=== Runtime Freeze Decision ==='));
      expect(result.output, contains('js-proof remains the active'));
      expect(result.output, contains('quickjs and duktape remain probe'));
      expect(result.output, contains('Node.js and npm are future'));
    });

    test('runtime-freeze deferred output', () async {
      final result = await commandService.execute('runtime-freeze deferred');

      expect(result.output, contains('Node.js/npm are not included yet'));
      expect(result.output, contains('Python is not included yet'));
      expect(result.output, contains('Git has a pipeline'));
      expect(
        result.output,
        contains('Runtime package installer is prototype-only'),
      );
      expect(
        result.output,
        contains('QuickJS/Duktape are probe surfaces only'),
      );
      expect(result.output, contains('Remote packages remain script-only'));
    });

    test('runtime-freeze why output', () async {
      final result = await commandService.execute('runtime-freeze why');

      expect(result.output, contains('stabilizing the app users have today'));
      expect(result.output, contains('source, sandboxing, timeout'));
      expect(result.output, contains('Node/npm are much larger'));
      expect(result.output, contains('Product stability matters first'));
    });

    test('runtime-freeze next output', () async {
      final result = await commandService.execute('runtime-freeze next');

      expect(
        result.output,
        contains('v0.53 Git Source + Dependency Preparation'),
      );
      expect(
        result.output,
        contains('acquire reviewed Git and dependency sources'),
      );
      expect(result.output, contains('prove git --version on device'));
      expect(result.output, contains('checksum and ABI validation on device'));
      expect(result.output, contains('keep Node/npm/Python planned'));
      expect(result.output, contains('runtime expansion is planned'));
    });

    test('runtime-freeze doctor output', () async {
      final result = await commandService.execute('runtime-freeze doctor');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== Runtime Freeze Doctor ==='));
      expect(result.output, contains('js-proof: healthy'));
      expect(result.output, contains('Decision docs: OK'));
      expect(result.output, contains('Overall: HEALTHY'));
    });

    test('runtime plan and next reflect product stabilization', () async {
      final plan = await commandService.execute('runtime-plan');
      final next = await commandService.execute('runtime-next');

      expect(plan.output, contains('11. Runtime decision freeze'));
      expect(plan.output, contains('12. Product stabilization'));
      expect(plan.output, contains('16. CalypsoIDE integration later'));
      expect(
        next.output,
        contains('v0.36 Product Stabilization / Beta Readiness Pass'),
      );
    });

    test('js-engine-next points to product stabilization', () async {
      final result = await commandService.execute('js-engine-next');

      expect(
        result.output,
        contains('v0.36 Product Stabilization / Beta Readiness Pass'),
      );
      expect(result.output, contains('product stabilization'));
      expect(result.output, contains('quickjs/duktape deferred'));
    });

    test('probe plans and js-proof plan reflect freeze', () async {
      final proof = await commandService.execute('js-proof plan');
      final quickjs = await commandService.execute('quickjs plan');
      final duktape = await commandService.execute('duktape plan');

      expect(proof.output, contains('active current JS path'));
      expect(proof.output, contains('Runtime decision freeze - complete'));
      expect(quickjs.output, contains('QuickJS integration deferred'));
      expect(duktape.output, contains('Duktape integration deferred'));
    });

    test('help and autocomplete include runtime-freeze', () async {
      final help = await commandService.execute('help');
      final runtimeHelp = await commandService.execute('runtime-help');

      expect(help.output, contains('runtime-freeze help'));
      expect(help.output, contains('Known limits:'));
      expect(runtimeHelp.output, contains('runtime-freeze [sub]'));
      expect(runtimeHelp.output, contains('Show frozen runtime direction'));
      expect(kTermodeCommands, contains('runtime-freeze'));
    });

    test('REAL PTY host interception includes runtime-freeze', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('runtime-freeze status');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('runtime-freeze status'));
      expect(output, contains('=== Runtime Freeze Status ==='));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });

    test('docs references are present', () {
      expect(File('docs/RUNTIME_DECISION_FREEZE.md').existsSync(), isTrue);
      expect(
        File('docs/RUNTIME_STRATEGY.md').readAsStringSync(),
        contains('Product Stabilization'),
      );
    });
  });
}
