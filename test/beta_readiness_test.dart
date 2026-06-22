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

  group(
    'Product Stabilization / Device QA / Onboarding / UI / Beta (v0.36-v0.58)',
    () {
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
                    return {
                      'stdout': 'shell-ok\n',
                      'stderr': '',
                      'exitCode': 0,
                    };
                  }
                  if (command == '/system/bin/toybox echo toybox-ok') {
                    return {
                      'stdout': 'toybox-ok\n',
                      'stderr': '',
                      'exitCode': 0,
                    };
                  }
                  if (command.startsWith('/system/bin/sh ') &&
                      command.contains('runtime-exec-proof')) {
                    return {
                      'stdout': 'script-ok\n',
                      'stderr': '',
                      'exitCode': 0,
                    };
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

        expect(result.output, contains('Node.js/npm are not included yet'));
        expect(result.output, contains('Python/Git are not included yet'));
        expect(
          result.output,
          contains('QuickJS/Duktape are probe surfaces only'),
        );
        expect(result.output, contains('Termode is beta software'));
      });

      test('beta-next output', () async {
        final result = await commandService.execute('beta-next');

        expect(result.output, contains('v0.59 Git Build Fixes'));
      });

      test('doctor compact and verbose output', () async {
        final compact = await commandService.execute('doctor');
        final verbose = await commandService.execute('doctor --verbose');

        expect(compact.output, contains('=== Termode Doctor ==='));
        expect(compact.output, contains('Package: HEALTHY'));
        expect(compact.output, contains('Runtime freeze: HEALTHY'));
        expect(compact.output, contains('Native tools: HEALTHY'));
        expect(compact.output, contains('Overall: LIMITED'));
        expect(verbose.output, contains('Verbose:'));
        expect(verbose.output, contains('run pkg doctor'));
      });

      test('welcome and getting-started output', () async {
        final welcome = await commandService.execute('welcome');
        final gettingStarted = await commandService.execute('getting-started');
        final firstRun = await commandService.execute('first-run');

        for (final output in [
          welcome.output,
          gettingStarted.output,
          firstRun.output,
        ]) {
          expect(output, contains('Welcome to Termode.'));
          expect(output, contains('Start here:'));
          expect(output, contains('pkg install hello'));
          expect(output, contains('workspace-init demo'));
          expect(output, contains('qa-status'));
          expect(output, contains('Run beta-known-limits'));
        }
      });

      test('commands output and full catalog', () async {
        final compact = await commandService.execute('commands');
        final all = await commandService.execute('commands --all');

        expect(compact.output, contains('Getting started:'));
        expect(compact.output, contains('Shell / PTY:'));
        expect(compact.output, contains('Workspace / files:'));
        expect(compact.output, contains('QA / beta:'));
        expect(all.output, contains('=== All Commands ==='));
        expect(all.output, contains('examples'));
        expect(all.output, contains('glossary'));
        expect(all.output, contains('onboarding-doctor'));
        expect(all.output, contains('beta-status'));
        expect(all.output, contains('qa-checklist'));
      });

      test('examples output is grouped and copy-friendly', () async {
        final root = await commandService.execute('examples');
        final packages = await commandService.execute('examples packages');
        final workspace = await commandService.execute('examples workspace');
        final unknown = await commandService.execute('examples banana');

        expect(root.output, contains('examples shell'));
        expect(root.output, contains('examples runtime'));
        expect(packages.output, contains('pkg install hello'));
        expect(packages.output, contains('pkg verify hello'));
        expect(workspace.output, contains('workspace-init demo'));
        expect(workspace.output, contains('host-write hello.txt "hello"'));
        expect(unknown.isError, isTrue);
        expect(unknown.output, contains('Unknown examples category: banana'));
      });

      test('glossary and onboarding doctor output', () async {
        final glossary = await commandService.execute('glossary');
        final doctor = await commandService.execute('onboarding-doctor');

        expect(glossary.output, contains('REAL PTY:'));
        expect(glossary.output, contains('Host command:'));
        expect(glossary.output, contains('Runtime frozen:'));
        expect(doctor.output, contains('=== Onboarding Doctor ==='));
        expect(doctor.output, contains('Welcome: OK'));
        expect(doctor.output, contains('Docs: OK'));
        expect(doctor.output, contains('Overall: HEALTHY'));
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

        expect(version.output, contains('Termode v0.58'));
        expect(version.output, contains('Runtime: frozen'));
        expect(
          notes.output,
          contains('v0.44 Binary Package Installer Prototype'),
        );
        expect(
          notes.output,
          contains('v0.43 Prefix / PATH / Environment System'),
        );
        expect(notes.output, contains('v0.42 Runtime Expansion Architecture'));
        expect(
          notes.output,
          contains('v0.41 Beta Feedback Fixes / RC Cleanup'),
        );
        expect(notes.output, contains('v0.40 Beta Candidate Packaging'));
        expect(notes.output, contains('v0.39 UI / Settings Polish'));
        expect(
          notes.output,
          contains('v0.38 Documentation / Onboarding Polish'),
        );
        expect(notes.output, contains('v0.37 Device QA Bug Bash'));
        expect(notes.output, contains('v0.35 Runtime Decision Freeze'));
        expect(changelog.output, contains('v0.31 JS Proof'));
      });

      test('bug-report output omits unsafe env dump', () async {
        final result = await commandService.execute('bug-report');

        expect(result.output, contains('=== Termode Bug Report ==='));
        expect(result.output, contains('Termode version: v0.58'));
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

      test('qa-run output', () async {
        final result = await commandService.execute('qa-run');

        expect(result.output, contains('=== QA Run ==='));
        expect(result.output, contains('Startup:'));
        expect(result.output, contains('Shell / PTY:'));
        expect(result.output, contains('Packages:'));
        expect(result.output, contains('Doctors:'));
      });

      test('qa-status output', () async {
        final result = await commandService.execute('qa-status');

        expect(result.output, contains('=== QA Status ==='));
        expect(result.output, contains('Doctor:'));
        expect(result.output, contains('Beta:'));
        expect(result.output, contains('Packages: OK'));
        expect(result.output, contains('Runtime freeze: OK'));
        expect(result.output, contains('Overall: READY WITH LIMITATIONS'));
      });

      test('qa-report output is compact and safe', () async {
        final result = await commandService.execute('qa-report');

        expect(result.output, contains('=== QA Bug Bash Report ==='));
        expect(result.output, contains('Termode v0.58'));
        expect(result.output, contains('Doctor summary:'));
        expect(result.output, contains('Suggested next tests:'));
        expect(result.output, isNot(contains('PATH=')));
        expect(result.output, isNot(contains('TOKEN')));
        expect(result.output, isNot(contains('SECRET')));
      });

      test('qa-reset does not delete user state', () async {
        await commandService.execute('workspace-init qakeep');
        final result = await commandService.execute('qa-reset');
        final list = await commandService.execute('workspace-list');

        expect(result.output, contains('QA tracking state reset'));
        expect(result.output, contains('were not changed'));
        expect(list.output, contains('qakeep'));
      });

      test('help cleanup includes key categories', () async {
        final result = await commandService.execute('help');

        expect(result.output, contains('=== Termode Help ==='));
        expect(result.output, contains('Start:'));
        expect(result.output, contains('Sub-help:'));
        expect(result.output, contains('Known limits:'));
      });

      test('command catalog contains new commands', () {
        for (final command in [
          'welcome',
          'getting-started',
          'first-run',
          'commands',
          'examples',
          'glossary',
          'onboarding-doctor',
          'doctor',
          'beta',
          'beta-status',
          'beta-doctor',
          'beta-score',
          'beta-checklist',
          'beta-known-limits',
          'beta-next',
          'prefix-status',
          'path-status',
          'path-preview',
          'path-doctor',
          'env-status',
          'env-preview',
          'env-doctor',
          'env-check',
          'env-script',
          'bin-list',
          'bin-which',
          'bin-doctor',
          'shim-info',
          'shim-list',
          'shim-doctor',
          'settings-summary',
          'settings-doctor',
          'version',
          'release-notes',
          'changelog',
          'bug-report',
          'qa-checklist',
          'qa-run',
          'qa-status',
          'qa-report',
          'qa-reset',
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
        await sessionService.executeCommand('examples packages');
        await sessionService.executeCommand('glossary');
        await sessionService.executeCommand('onboarding-doctor');
        await sessionService.executeCommand('qa-status');

        final output = session.lines.map((line) => line.text).join('\n');
        expect(output, contains('beta-status'));
        expect(output, contains('=== Termode Beta Status ==='));
        expect(output, contains('commands'));
        expect(output, contains('=== Termode Commands ==='));
        expect(output, contains('examples packages'));
        expect(output, contains('pkg install hello'));
        expect(output, contains('glossary'));
        expect(output, contains('REAL PTY:'));
        expect(output, contains('onboarding-doctor'));
        expect(output, contains('=== Onboarding Doctor ==='));
        expect(output, contains('qa-status'));
        expect(output, contains('=== QA Status ==='));

        session.isPtyInteractionActive = false;
        session.isRealPtyActive = false;
      });

      test('docs are present', () {
        expect(File('docs/BETA_READINESS.md').existsSync(), isTrue);
        expect(File('docs/COMMAND_GUIDE.md').existsSync(), isTrue);
        expect(File('docs/GETTING_STARTED.md').existsSync(), isTrue);
        expect(File('docs/KNOWN_LIMITATIONS.md').existsSync(), isTrue);
        expect(File('docs/QA_CHECKLIST.md').existsSync(), isTrue);
        expect(File('docs/ROADMAP.md').existsSync(), isTrue);
        expect(File('docs/DEVICE_QA_BUG_BASH.md').existsSync(), isTrue);
        expect(File('README.md').readAsStringSync(), contains('v0.58'));
        expect(
          File('docs/GIT_ARTIFACT_PRODUCTION_STATUS.md').existsSync(),
          isTrue,
        );
        expect(File('docs/GIT_TRUSTED_BUILD.md').existsSync(), isTrue);
      });
    },
  );
}
