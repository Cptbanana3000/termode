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

  group('v0.39 UI / Settings Polish', () {
    late Directory tempDir;
    late CommandService commandService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('termode_ui_test');
      final runtime = RuntimeBootstrapService();
      runtime.overrideBaseDir = tempDir;
      await runtime.init();

      // Reset settings to defaults and clear any leftover singleton session
      // state so assertions about defaults are stable.
      SettingsService().loadFromJson(null);
      TerminalSessionService().clearMemoryStateForTesting();

      commandService = CommandService(VirtualFileSystem(), 'ui_test');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            (MethodCall call) async {
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

    test('settings-summary shows all key settings', () async {
      final result = await commandService.execute('settings-summary');

      expect(result.output, contains('=== Settings Summary ==='));
      expect(result.output, contains('Theme: dark'));
      expect(result.output, contains('Font size: 14.0'));
      expect(result.output, contains('Line height: 1.30'));
      expect(result.output, contains('Start in real shell: yes'));
      expect(result.output, contains('ANSI renderer: on'));
      expect(result.output, contains('ANSI debug: off'));
      expect(result.output, contains('Cursor: block'));
      expect(result.output, contains('Blink: yes'));
      expect(result.output, contains('Scrollback: 2000'));
      expect(result.output, contains('Paste warning: 1000'));
      expect(result.output, contains('Paste hard limit: 10000'));
      expect(result.output, contains('Keep screen on: no'));
      expect(result.output, contains('Welcome banner: on'));
    });

    test('settings-doctor reports font and line-height health', () async {
      final result = await commandService.execute('settings-doctor');

      expect(result.output, contains('=== Settings Doctor ==='));
      expect(result.output, contains('Font size: OK'));
      expect(result.output, contains('Line height: OK'));
      expect(result.output, contains('Scrollback limit: OK'));
      expect(result.output, contains('Paste limits: OK'));
      expect(result.output, contains('Overall: HEALTHY'));
      expect(result.isError, isFalse);
    });

    test('terminal-settings and keyboard-settings are readable', () async {
      final terminal = await commandService.execute('terminal-settings');
      expect(terminal.output, contains('Font size:'));
      expect(terminal.output, contains('Line height:'));
      expect(terminal.output, contains('ANSI debug: off'));

      final keyboard = await commandService.execute('keyboard-settings');
      expect(keyboard.output, contains('=== Keyboard Settings ==='));
      expect(keyboard.output, contains('Paste warning: 1000'));
      expect(keyboard.output, contains('Paste limit: 10000'));
    });

    test('theme-test output is readable and labeled', () async {
      final result = await commandService.execute('theme-test');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== Theme Test ==='));
      expect(result.output, contains('Normal text'));
      expect(result.output, contains('Dim text'));
      expect(result.output, contains('Bold text'));
      expect(result.output, contains('ANSI colors'));
      expect(result.output, contains('Background colors'));
      expect(result.output, contains('Status badge sample:'));
      expect(result.output, contains('REAL PTY'));
      expect(result.output, contains('NORMAL'));
      expect(result.output, contains('LIMITED'));
    });

    test('status output in NORMAL mode', () async {
      final result = await commandService.execute('status');

      expect(result.isError, isFalse);
      expect(result.output, contains('=== Termode Status ==='));
      expect(result.output, contains('Mode: NORMAL'));
      expect(result.output, contains('Shell: stopped'));
      expect(result.output, contains('Session:'));
      expect(result.output, contains('Workspace: none'));
      expect(result.output, contains('Packages: healthy'));
      expect(
        result.output,
        contains('Runtime: environment architecture active'),
      );
      expect(result.output, contains('Prefix:'));
      expect(result.output, contains('PATH overlay:'));
      expect(result.output, contains('Beta: ready with limitations'));
    });

    test('status output reflects REAL PTY mocked mode', () async {
      final session = TerminalSessionService().activeSession;
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      final result = await commandService.execute('status');

      expect(result.output, contains('Mode: REAL PTY'));
      expect(result.output, contains('Shell: running'));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });

    test('status reflects active workspace', () async {
      await commandService.execute('workspace-init statusws');
      await commandService.execute('workspace-cd statusws');

      final result = await commandService.execute('status');
      expect(result.output, contains('Workspace: statusws'));
    });

    test('settings-reset-safe requires --confirm', () async {
      SettingsService().setFontSize(20.0);

      final guard = await commandService.execute('settings-reset-safe');
      expect(guard.isError, isTrue);
      expect(guard.output, contains('Run: settings-reset-safe --confirm'));
      // Settings must NOT change without confirmation.
      expect(SettingsService().fontSize, 20.0);

      final confirmed = await commandService.execute(
        'settings-reset-safe --confirm',
      );
      expect(confirmed.isError, isFalse);
      expect(confirmed.output, contains('=== Safe Settings Reset ==='));
      expect(SettingsService().fontSize, 14.0);
    });

    test(
      'settings-reset-safe preserves shell preference and user data',
      () async {
        // A workspace stands in for user data that must survive a settings reset.
        await commandService.execute('workspace-init keepme');
        SettingsService().setStartInRealShell(false);
        SettingsService().setThemeColor('Amber');

        final result = await commandService.execute(
          'settings-reset-safe --confirm',
        );
        expect(result.output, contains('Kept: packages, workspaces, sessions'));

        // Visual setting reset to default.
        expect(SettingsService().themeColor, 'Green');
        // Shell preference preserved.
        expect(SettingsService().startInRealShell, isFalse);
        // Workspace data untouched.
        final list = await commandService.execute('workspace-list');
        expect(list.output, contains('keepme'));
      },
    );

    test('command catalog includes new v0.39 commands', () {
      for (final command in ['status', 'theme-test', 'settings-reset-safe']) {
        expect(kTermodeCommands, contains(command));
      }
    });

    test('REAL PTY host interception includes new v0.39 commands', () async {
      final sessionService = TerminalSessionService();
      final session = sessionService.activeSession;
      session.lines.clear();
      session.isRealPtyActive = true;
      session.isPtyInteractionActive = true;

      await sessionService.executeCommand('status');
      await sessionService.executeCommand('theme-test');
      await sessionService.executeCommand('settings-reset-safe');

      final output = session.lines.map((line) => line.text).join('\n');
      expect(output, contains('status'));
      expect(output, contains('=== Termode Status ==='));
      expect(output, contains('theme-test'));
      expect(output, contains('=== Theme Test ==='));
      expect(output, contains('settings-reset-safe'));
      expect(output, contains('Run: settings-reset-safe --confirm'));

      session.isPtyInteractionActive = false;
      session.isRealPtyActive = false;
    });
  });
}
