import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/services/command_catalog.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/runtime_bootstrap_service.dart';
import 'package:termode/services/settings_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v0.41 Beta Feedback Fixes / RC Cleanup', () {
    late Directory tempDir;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_rc41_test');
      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();
      SettingsService().loadFromJson(null);
      TerminalSessionService().clearMemoryStateForTesting();
      commandService = CommandService(VirtualFileSystem(), 'rc41_test');

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

    test('feedback default output lists reporting steps', () async {
      final bare = await commandService.execute('feedback');
      final help = await commandService.execute('feedback help');

      for (final out in [bare.output, help.output]) {
        expect(out, contains('=== Beta Feedback ==='));
        expect(out, contains('1. bug-report'));
        expect(out, contains('2. qa-report'));
        expect(out, contains('3. beta-candidate status'));
        expect(out, contains('steps to reproduce'));
        expect(out, contains('expected result'));
        expect(out, contains('actual result'));
      }
    });

    test('feedback template is copy-friendly', () async {
      final result = await commandService.execute('feedback template');

      expect(result.output, contains('Termode version:'));
      expect(result.output, contains('Device:'));
      expect(result.output, contains('Android version:'));
      expect(result.output, contains('Steps to reproduce:'));
      expect(result.output, contains('Expected:'));
      expect(result.output, contains('Actual:'));
      expect(result.output, contains('Does it happen after restart:'));
      expect(result.output, contains('Output from bug-report:'));
      expect(result.output, contains('Output from qa-report:'));
    });

    test('feedback checklist output', () async {
      final result = await commandService.execute('feedback checklist');

      expect(result.output, contains('=== Beta Feedback Checklist ==='));
      expect(result.output, contains('* launch'));
      expect(result.output, contains('* typing'));
      expect(result.output, contains('* REAL PTY'));
      expect(result.output, contains('* package install/remove'));
      expect(result.output, contains('* workspace file write/read'));
      expect(result.output, contains('* force close/reopen'));
      expect(result.output, contains('* settings reset safe'));
      expect(result.output, contains('* beta-candidate ready'));
    });

    test('unknown feedback subcommand errors', () async {
      final result = await commandService.execute('feedback banana');
      expect(result.isError, isTrue);
      expect(result.output, contains('Unknown feedback subcommand'));
    });

    test('rc-checklist output', () async {
      final result = await commandService.execute('rc-checklist');

      expect(result.output, contains('=== Release Candidate Checklist ==='));
      expect(result.output, contains('* flutter analyze'));
      expect(result.output, contains('* flutter test'));
      expect(result.output, contains('* debug APK build'));
      expect(result.output, contains('* install APK on real Android device'));
      expect(result.output, contains('* versionName/versionCode confirmed'));
      expect(result.output, contains('* beta-candidate ready checked'));
      expect(result.output, contains('* known limitations reviewed'));
    });

    test('rc-status treats frozen runtime as acceptable', () async {
      final result = await commandService.execute('rc-status');

      expect(result.output, contains('=== Release Candidate Status ==='));
      expect(result.output, contains('Version: v0.42'));
      expect(result.output, contains('Beta candidate: yes'));
      expect(result.output, contains('Core systems: OK'));
      expect(result.output, contains('Known limitations: intentional'));
      expect(result.output, contains('Overall: RC CLEANUP READY'));
      expect(result.isError, isFalse);
    });

    test('beta-candidate ready still ready under intentional limits', () async {
      final result = await commandService.execute('beta-candidate ready');
      expect(result.output, contains('Ready for beta testing.'));
      expect(result.isError, isFalse);
    });

    test('version and build-info report v0.41', () async {
      final version = await commandService.execute('version');
      final build = await commandService.execute('build-info');

      expect(version.output, contains('Termode v0.42'));
      expect(build.output, contains('Version: v0.42'));
      expect(build.output, contains('Artifact: Termode-v0.42-beta-debug.apk'));
    });

    test('settings-reset-safe stays protected by --confirm', () async {
      SettingsService().setFontSize(18.0);
      final guard = await commandService.execute('settings-reset-safe');
      expect(guard.isError, isTrue);
      expect(guard.output, contains('Run: settings-reset-safe --confirm'));
      expect(SettingsService().fontSize, 18.0);

      final confirmed = await commandService.execute(
        'settings-reset-safe --confirm',
      );
      expect(confirmed.isError, isFalse);
      expect(SettingsService().fontSize, 14.0);
    });

    test('command catalog includes feedback and rc commands', () {
      for (final command in ['feedback', 'rc-checklist', 'rc-status']) {
        expect(kTermodeCommands, contains(command));
      }
    });

    test('help and commands surface feedback and rc commands', () async {
      final help = await commandService.execute('help');
      final commands = await commandService.execute('commands');

      expect(help.output, contains('feedback'));
      expect(help.output, contains('rc-status'));
      expect(commands.output, contains('feedback'));
      expect(commands.output, contains('rc-status'));
    });

    test('REAL PTY host interception includes feedback and rc commands', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('feedback');
      await sessionService.executeCommand('rc-status');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('feedback'));
      expect(output, contains('=== Beta Feedback ==='));
      expect(output, contains('rc-status'));
      expect(output, contains('=== Release Candidate Status ==='));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });
  });
}
