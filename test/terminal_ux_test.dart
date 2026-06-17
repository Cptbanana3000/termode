import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/models/terminal_emulator_buffer.dart';
import 'package:termode/models/terminal_line.dart';
import 'package:termode/services/ansi_parser.dart';
import 'package:termode/services/command_service.dart';
import 'package:termode/services/settings_service.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/virtual_filesystem.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Terminal UX hardening commands', () {
    String clipboardText = '';

    setUp(() {
      SettingsService().loadFromJson({'startInRealShell': false});
      TerminalSessionService().clearMemoryStateForTesting();
      clipboardText = '';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            (MethodCall call) async {
              switch (call.method) {
                case 'realPtySendRaw':
                case 'realPtySend':
                  return true;
                case 'getPaths':
                  return {
                    'home': '/data/user/0/com.termode.termode/files/home',
                    'usr': '/data/user/0/com.termode.termode/files/usr',
                    'bin': '/data/user/0/com.termode.termode/files/usr/bin',
                    'tmp': '/data/user/0/com.termode.termode/files/tmp',
                  };
              }
              return null;
            },
          );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            if (call.method == 'Clipboard.setData') {
              final data = Map<String, dynamic>.from(call.arguments as Map);
              clipboardText = data['text']?.toString() ?? '';
              return null;
            }
            if (call.method == 'Clipboard.getData') {
              return {'text': clipboardText};
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.termode/native_shell'),
            null,
          );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('keyboard and terminal settings commands are compact', () async {
      final commandService = CommandService(VirtualFileSystem(), 'ux');

      final keyboard = await commandService.execute('keyboard-test');
      expect(keyboard.output, contains('=== Keyboard Test ==='));
      expect(keyboard.output, contains('CTRL: available'));
      expect(keyboard.output, contains('Mode: NORMAL'));

      final keyboardSettings = await commandService.execute(
        'keyboard-settings',
      );
      expect(keyboardSettings.output, contains('Paste warning: 1000'));
      expect(keyboardSettings.output, contains('Paste limit: 10000'));

      final terminalSettings = await commandService.execute(
        'terminal-settings',
      );
      expect(terminalSettings.output, contains('Font size:'));
      expect(terminalSettings.output, contains('Line height:'));
      expect(terminalSettings.output, contains('ANSI debug: off'));
    });

    test('large paste is blocked and paste-force sends it once', () async {
      final sessionService = TerminalSessionService();
      final commandService = CommandService(VirtualFileSystem(), 'ux');
      final large = 'x' * 1200;

      final message = sessionService.handlePasteText(large);
      expect(message, contains('Paste is large: 1200 chars'));

      sessionService.activeSession.isPtyInteractionActive = true;
      final result = await commandService.execute('paste-force');
      expect(result.output, contains('Pasted 1200 chars'));

      final second = await commandService.execute('paste-force');
      expect(second.output, contains('No blocked paste'));
    });

    test('paste hard limit is enforced', () {
      final sessionService = TerminalSessionService();
      final tooLarge = 'x' * 10001;

      final message = sessionService.handlePasteText(tooLarge);
      expect(message, contains('Paste too large. Limit: 10000 chars.'));
      expect(sessionService.activeSession.blockedPasteText, isNull);
    });

    test('resize-info and scroll-test output', () async {
      final sessionService = TerminalSessionService();
      final commandService = CommandService(VirtualFileSystem(), 'ux');
      sessionService.activeSession.lastResizeCols = 120;
      sessionService.activeSession.lastResizeRows = 40;
      sessionService.activeSession.lastResizeNotified = true;

      final resize = await commandService.execute('resize-info');
      expect(resize.output, contains('Cols: 120'));
      expect(resize.output, contains('Rows: 40'));
      expect(resize.output, contains('PTY notified: yes'));

      final scroll = await commandService.execute('scroll-test 3');
      expect(scroll.output, contains('001 test line'));
      expect(scroll.output, contains('003 test line'));
    });

    test('copy-last and copy-session copy transcript lines', () async {
      final sessionService = TerminalSessionService();
      final commandService = CommandService(VirtualFileSystem(), 'ux');
      sessionService.activeSession.lines
        ..add(TerminalLine(text: 'cmd', type: LineType.input))
        ..add(TerminalLine(text: 'first', type: LineType.output))
        ..add(TerminalLine(text: 'second', type: LineType.output));

      final last = await commandService.execute('copy-last');
      expect(last.output, contains('Copied 1 line'));
      var data = await Clipboard.getData(Clipboard.kTextPlain);
      expect(data?.text, 'second');

      final session = await commandService.execute('copy-session 2');
      expect(session.output, contains('Copied 2 lines'));
      data = await Clipboard.getData(Clipboard.kTextPlain);
      expect(data?.text, contains('first\nsecond'));
    });

    test('input-test and ansi-test are available', () async {
      final commandService = CommandService(VirtualFileSystem(), 'ux');
      final input = await commandService.execute('input-test');
      expect(input.output, contains('Backspace'));

      final ansi = await commandService.execute('ansi-test');
      expect(ansi.output, contains('bold text'));
      expect(ansi.output, contains('\u001B[38;5;208m'));
    });
  });

  group('ANSI parser extended color support', () {
    test('handles basic, background, 256-color, truecolor, dim, underline', () {
      final buffer = TerminalEmulatorBuffer(cols: 80, visibleRows: 24);
      final parser = AnsiParser(buffer);
      parser.write(
        '\u001B[1;4;31mbold red\u001B[0m\n'
        '\u001B[44mblue bg\u001B[0m\n'
        '\u001B[38;5;208morange\u001B[0m\n'
        '\u001B[48;2;1;2;3mtrue bg\u001B[0m\n'
        '\u001B[2mdim\u001B[0m',
      );

      expect(buffer.rows[0][0].style.bold, isTrue);
      expect(buffer.rows[0][0].style.underline, isTrue);
      expect(buffer.rows[1][0].style.backgroundColor, isNotNull);
      expect(buffer.rows[2][0].style.foregroundColor, isNotNull);
      expect(buffer.rows[3][0].style.backgroundColor, isNotNull);
      expect(buffer.rows[4][0].style.dim, isTrue);
    });

    test('unknown ANSI is hidden unless debug mode is enabled', () {
      final settings = SettingsService();
      settings.loadFromJson({'ansiDebugMode': false});
      var buffer = TerminalEmulatorBuffer(cols: 80, visibleRows: 24);
      var parser = AnsiParser(buffer);
      parser.write('a\u001B]bad\u0007b');
      expect(
        buffer.rows.first.map((cell) => cell.char).join(),
        isNot(contains('\u001B')),
      );

      settings.setAnsiDebugMode(true);
      buffer = TerminalEmulatorBuffer(cols: 80, visibleRows: 24);
      parser = AnsiParser(buffer);
      parser.write('a\u001B]bad\u0007b');
      expect(
        buffer.rows.first.map((cell) => cell.char).join(),
        contains('\u001B'),
      );
    });
  });
}
