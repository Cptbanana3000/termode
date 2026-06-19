import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/settings_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v0.45 Git Support Feasibility / Installer Path', () {
    late Directory tempDir;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_git_test');
      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      SettingsService().loadFromJson(null);
      TerminalSessionService().clearMemoryStateForTesting();
      commandService = CommandService(VirtualFileSystem(), 'git_test');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            (call) async {
              switch (call.method) {
                case 'getStorageStatus':
                  return null;
                case 'realPtySend':
                case 'realPtySendRaw':
                  return true;
                case 'getDiagnostics':
                  return {'abi': 'arm64-v8a', 'pid': 9001};
                case 'getPaths':
                  return {
                    'home': '${tempDir.path}/files/home',
                    'usr': '${tempDir.path}/files/usr',
                    'bin': '${tempDir.path}/files/usr/bin',
                    'tmp': '${tempDir.path}/files/tmp',
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
      SettingsService().loadFromJson(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('git-status reports planned/not installed', () async {
      final result = await commandService.execute('git-status');
      expect(result.output, contains('=== Git Status ==='));
      expect(result.output, contains('Installed: no'));
      expect(result.output, contains('Command: git'));
      expect(result.output, contains('Version: not available'));
      expect(result.output, contains('Overall: PLANNED'));
      expect(result.isError, isFalse);
    });

    test('git-info explains Git and install path', () async {
      final result = await commandService.execute('git-info');
      expect(result.output, contains('=== Git Info ==='));
      expect(result.output, contains('Installed: no'));
      expect(result.output, contains('runtime-install plan git'));
      expect(result.output, contains('git-artifact bundle-status'));
    });

    test('git-plan shows the staged Git support plan', () async {
      final result = await commandService.execute('git-plan');
      expect(result.output, contains('=== Git Support Plan ==='));
      expect(result.output, contains('Verify ABI'));
      expect(result.output, contains('Register git shim'));
      expect(result.output, contains('Run git --version'));
      expect(result.output, contains('no safe Git artifact'));
      expect(result.output, contains('git-artifact bundle-status'));
    });

    test('git-version does not print a fake version', () async {
      final result = await commandService.execute('git-version');
      expect(result.output, contains('Git is not installed yet.'));
      expect(result.output, contains('git-artifact bundle-status'));
      expect(result.output, contains('runtime-install plan git'));
      expect(result.output, isNot(contains('git version')));
    });

    test('git-doctor reports PLANNED, not UNHEALTHY, when absent', () async {
      final result = await commandService.execute('git-doctor');
      expect(result.output, contains('=== Git Doctor ==='));
      expect(result.output, contains('Git package: not installed'));
      expect(result.output, contains('bin-which git: not found'));
      expect(result.output, contains('Overall: PLANNED'));
      expect(result.isError, isFalse);
    });

    test('git-test-plan is blocked until Git exists', () async {
      final result = await commandService.execute('git-test-plan');
      expect(result.output, contains('=== Git Test Plan ==='));
      expect(result.output, contains('blocked until a Git artifact exists'));
      expect(result.output, contains('git init'));
      expect(result.output, contains('git commit -m "Initial commit"'));
    });

    test('bare git gives a friendly message when not installed', () async {
      final result = await commandService.execute('git');
      expect(result.output, contains('Git is not installed yet.'));
      expect(result.output, contains('git-artifact bundle-status'));
      expect(result.output, contains('runtime-install plan git'));
    });

    test('runtime-pkg info git shows planned package', () async {
      final result = await commandService.execute('runtime-pkg info git');
      expect(result.output, contains('=== Runtime Package: git ==='));
      expect(result.output, contains('Kind: native-tool'));
      expect(result.output, contains('Status: planned (artifact'));
      expect(result.output, contains('Command: git'));
      expect(result.output, contains('Artifact available: no'));
      expect(result.isError, isFalse);
    });

    test(
      'runtime-pkg install git refuses safely without an artifact',
      () async {
        final result = await commandService.execute('runtime-pkg install git');
        expect(
          result.output,
          contains('Git artifact is not available in this build.'),
        );
        expect(result.output, contains('Current state:'));
        expect(result.output, contains('git-artifact bundle-status'));

        // Nothing was installed.
        final list = await commandService.execute('runtime-pkg list');
        expect(list.output, isNot(contains('git [')));
        final which = await commandService.execute('bin-which git');
        expect(which.output, contains('Not found in Termode PATH'));
      },
    );

    test('runtime-pkg verify/remove git report not installed', () async {
      final verify = await commandService.execute('runtime-pkg verify git');
      expect(verify.isError, isTrue);
      expect(verify.output, contains('Runtime package not installed: git'));

      final remove = await commandService.execute('runtime-pkg remove git');
      expect(remove.isError, isTrue);
      expect(remove.output, contains('Runtime package not installed: git'));
    });

    test('runtime-pkg available separates hello-bin and planned git', () async {
      final result = await commandService.execute('runtime-pkg available');
      expect(result.output, contains('Prototype available now:'));
      expect(result.output, contains('hello-bin'));
      expect(result.output, contains('Planned real tools:'));
      expect(result.output, contains('* git'));
    });

    test('runtime-install plan git and list include git', () async {
      final plan = await commandService.execute('runtime-install plan git');
      expect(plan.output, contains('=== Runtime Install Plan: Git ==='));
      expect(plan.output, contains('Validate Git package manifest'));
      expect(plan.output, contains('Register git shim'));
      expect(plan.output, contains('Test Git inside a workspace'));

      final list = await commandService.execute('runtime-install list');
      expect(list.output, contains('Real tools:'));
      expect(list.output, contains('* git'));
    });

    test('runtime-install doctor handles Git planned state', () async {
      final result = await commandService.execute('runtime-install doctor');
      expect(result.output, contains('Git artifact:'));
      expect(result.output, contains('Git: planned (not installed)'));
      expect(result.output, contains('Overall: PROTOTYPE READY'));
    });

    test('toolchain integration reflects Git feasibility', () async {
      final info = await commandService.execute('toolchain-info git');
      expect(info.output, contains('=== Toolchain: Git ==='));
      expect(info.output, contains('Installed: no'));
      expect(info.output, contains('Feasibility: active'));

      final status = await commandService.execute('toolchain-status');
      expect(status.output, contains('Git bundle pipeline: ready'));

      final dev = await commandService.execute('dev-doctor');
      expect(dev.output, contains('Git bundle pipeline: ready'));
    });

    test('shim-list does not show active git when absent', () async {
      final result = await commandService.execute('shim-list');
      expect(result.output, isNot(contains('git -> ')));
    });

    test('beta-candidate ready still succeeds despite Git planned', () async {
      final result = await commandService.execute('beta-candidate ready');
      expect(result.output, contains('Ready for beta testing.'));
      expect(result.isError, isFalse);
    });

    test('version surfaces mention v0.48', () async {
      final version = await commandService.execute('version');
      final notes = await commandService.execute('release-notes');
      final changelog = await commandService.execute('changelog');
      final bug = await commandService.execute('bug-report');
      final qa = await commandService.execute('qa-report');

      expect(version.output, contains('Termode v0.48'));
      expect(
        notes.output,
        contains('v0.48 Verified Git Artifact Bundle / Smoke Test'),
      );
      expect(
        changelog.output,
        contains('v0.48 Verified Git Artifact Bundle / Smoke Test'),
      );
      expect(bug.output, contains('Termode version: v0.48'));
      expect(qa.output, contains('Termode v0.48'));
    });

    test('build-info reports Git bundle path and v0.48', () async {
      final result = await commandService.execute('build-info');
      expect(result.output, contains('Version: v0.48'));
      expect(result.output, contains('Git bundle pipeline: ready'));
      expect(
        result.output,
        contains('Artifact: Termode-v0.48-git-bundle-debug.apk'),
      );
    });

    test('catalog, help, commands include git commands', () async {
      for (final command in [
        'git',
        'git-status',
        'git-info',
        'git-plan',
        'git-version',
        'git-doctor',
        'git-test-plan',
      ]) {
        expect(kTermodeCommands, contains(command));
      }

      final help = await commandService.execute('help');
      expect(help.output, contains('git-status'));

      final commands = await commandService.execute('commands');
      expect(commands.output, contains('git-status'));

      final all = await commandService.execute('commands --all');
      expect(all.output, contains('git-doctor'));
    });

    test('REAL PTY host interception includes git commands', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('git-status');
      await sessionService.executeCommand('git');
      await sessionService.executeCommand('runtime-pkg install git');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('=== Git Status ==='));
      expect(output, contains('Git is not installed yet.'));
      expect(output, contains('Git artifact is not available'));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });
  });
}
