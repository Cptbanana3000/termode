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

  group('Product Stabilization / Beta Readiness (v0.36)', () {
    late Directory tempDir;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_beta_test');
      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      commandService = CommandService(VirtualFileSystem(), 'beta_test');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            (call) async {
              if (call.method == 'executeCommand') {
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
              }
              if (call.method == 'getDiagnostics') {
                return {
                  'cwd': '/data/user/0/com.termode.termode/files/home',
                  'pid': 1234,
                  'abi': 'arm64-v8a',
                };
              }
              if (call.method == 'getStorageStatus') {
                return {'linked': 'false', 'displayName': ''};
              }
              if (call.method == 'nativeTool') {
                final args = Map<String, dynamic>.from(call.arguments as Map);
                if (args['command'] == 'doctor') {
                  return {
                    'ok': true,
                    'echoOk': true,
                    'cwd': '/native',
                    'abi': 'arm64-v8a',
                    'hashOk': true,
                  };
                }
              }
              if (call.method == 'jsProof') {
                final args = Map<String, dynamic>.from(call.arguments as Map);
                if (args['command'] == 'doctor') {
                  return {
                    'ok': true,
                    'bridgeOk': true,
                    'evaluatorOk': true,
                    'errorsOk': true,
                  };
                }
                if (args['command'] == 'info') {
                  return {'ok': true, 'status': 'PROOF'};
                }
              }
              if (call.method == 'realPtySend') {
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

    test('beta-status output', () async {
      final result = await commandService.execute('beta-status');

      expect(result.output, contains('=== Termode Beta Status ==='));
      expect(result.output, contains('PTY: OK'));
      expect(result.output, contains('Storage: LIMITED'));
      expect(result.output, contains('Runtime: FROZEN'));
      expect(result.output, contains('Overall: LIMITED'));
    });

    test('beta-doctor output', () async {
      final result = await commandService.execute('beta-doctor');

      expect(result.output, contains('=== Termode Beta Status ==='));
      expect(result.output, contains('=== Beta Readiness Score ==='));
      expect(result.output, contains('=== Beta Known Limits ==='));
    });

    test('beta-score output', () async {
      final result = await commandService.execute('beta-score');

      expect(result.output, contains('Core shell: 20/20'));
      expect(result.output, contains('Docs/help: 10/15'));
      expect(result.output, contains('Total: 95/100'));
    });

    test('beta-checklist output', () async {
      final result = await commandService.execute('beta-checklist');

      expect(result.output, contains('* Run default-shell'));
      expect(result.output, contains('* Run pkg doctor'));
      expect(result.output, contains('* Test scroll-test 300'));
    });

    test('beta-known-limits output', () async {
      final result = await commandService.execute('beta-known-limits');

      expect(result.output, contains('No Node.js/npm/Python/Git yet'));
      expect(
        result.output,
        contains('QuickJS/Duktape are probe surfaces only'),
      );
      expect(result.output, contains('This is beta software'));
    });

    test('beta-next output', () async {
      final result = await commandService.execute('beta-next');

      expect(
        result.output,
        contains('v0.37 Documentation / Onboarding Polish'),
      );
    });

    test('doctor compact and verbose output', () async {
      final compact = await commandService.execute('doctor');
      final verbose = await commandService.execute('doctor --verbose');

      expect(compact.output, contains('=== Termode Doctor ==='));
      expect(compact.output, contains('Package:'));
      expect(compact.output, contains('Runtime freeze: HEALTHY'));
      expect(compact.output, contains('Overall: LIMITED'));
      expect(verbose.output, contains('Verbose:'));
      expect(verbose.output, contains('run pkg doctor'));
    });

    test('welcome and getting-started output', () async {
      final welcome = await commandService.execute('welcome');
      final gettingStarted = await commandService.execute('getting-started');

      for (final output in [welcome.output, gettingStarted.output]) {
        expect(output, contains('Welcome to Termode.'));
        expect(output, contains('pkg install hello'));
        expect(output, contains('runtime-freeze status'));
      }
    });

    test('commands output and full catalog', () async {
      final compact = await commandService.execute('commands');
      final all = await commandService.execute('commands --all');

      expect(compact.output, contains('Shell:'));
      expect(compact.output, contains('Diagnostics:'));
      expect(compact.output, contains('Runtime:'));
      expect(all.output, contains('=== All Commands ==='));
      expect(all.output, contains('beta-status'));
      expect(all.output, contains('qa-checklist'));
    });

    test('settings summary and doctor output', () async {
      final summary = await commandService.execute('settings-summary');
      final doctor = await commandService.execute('settings-doctor');

      expect(summary.output, contains('=== Settings Summary ==='));
      expect(summary.output, contains('Start in real shell: yes'));
      expect(summary.output, contains('Paste hard limit: 10000'));
      expect(doctor.output, contains('=== Settings Doctor ==='));
      expect(doctor.output, contains('Overall: HEALTHY'));
    });

    test('version and release notes output', () async {
      final version = await commandService.execute('version');
      final notes = await commandService.execute('release-notes');
      final changelog = await commandService.execute('changelog');

      expect(version.output, contains('Termode v0.36'));
      expect(version.output, contains('Runtime: frozen'));
      expect(notes.output, contains('v0.35 Runtime Decision Freeze'));
      expect(changelog.output, contains('v0.31 JS Proof'));
    });

    test('bug-report output omits unsafe env dump', () async {
      final result = await commandService.execute('bug-report');

      expect(result.output, contains('=== Termode Bug Report ==='));
      expect(result.output, contains('Termode version: v0.36'));
      expect(result.output, contains('Android ABI: arm64-v8a'));
      expect(result.output, isNot(contains('PATH=')));
      expect(result.output, isNot(contains('TOKEN')));
      expect(result.output, isNot(contains('SECRET')));
    });

    test('qa-checklist output', () async {
      final result = await commandService.execute('qa-checklist');

      expect(result.output, contains('launch app'));
      expect(result.output, contains('package install/remove'));
      expect(result.output, contains('multiple tabs'));
    });

    test('help cleanup includes key categories', () async {
      final result = await commandService.execute('help');

      expect(result.output, contains('Start Here:'));
      expect(result.output, contains('Beta / Release Commands:'));
      expect(result.output, contains('Runtime Freeze Commands:'));
    });

    test('command catalog contains new commands', () {
      for (final command in [
        'welcome',
        'getting-started',
        'first-run',
        'commands',
        'doctor',
        'beta',
        'beta-status',
        'beta-doctor',
        'beta-score',
        'beta-checklist',
        'beta-known-limits',
        'beta-next',
        'settings-summary',
        'settings-doctor',
        'version',
        'release-notes',
        'changelog',
        'bug-report',
        'qa-checklist',
      ]) {
        expect(kTermodeCommands, contains(command));
      }
    });

    test('REAL PTY host interception includes new commands', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('beta-status');
      await sessionService.executeCommand('commands');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('beta-status'));
      expect(output, contains('=== Termode Beta Status ==='));
      expect(output, contains('commands'));
      expect(output, contains('=== Termode Commands ==='));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });

    test('docs are present', () {
      expect(File('docs/BETA_READINESS.md').existsSync(), isTrue);
      expect(File('docs/COMMAND_GUIDE.md').existsSync(), isTrue);
      expect(File('docs/QA_CHECKLIST.md').existsSync(), isTrue);
      expect(File('README.md').readAsStringSync(), contains('Termode'));
    });
  });
}
