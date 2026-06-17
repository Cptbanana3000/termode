import 'package:flutter_test/flutter_test.dart';
import 'package:termode/models/terminal_emulator_buffer.dart';
import 'package:termode/models/terminal_style.dart';
import 'package:termode/services/ansi_parser.dart';
import 'package:termode/services/terminal_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ANSI Renderer and Emulator Buffer Tests', () {
    test('plain text rendering', () {
      final buffer = TerminalEmulatorBuffer(cols: 80);
      final parser = AnsiParser(buffer);

      parser.write('Hello World');
      final row = buffer.rows[0];
      final text = row.sublist(0, 11).map((c) => c.char).join('');
      expect(text, equals('Hello World'));
      expect(buffer.cursorX, equals(11));
      expect(buffer.cursorY, equals(0));
    });

    test('newline handling', () {
      final buffer = TerminalEmulatorBuffer(cols: 80);
      final parser = AnsiParser(buffer);

      parser.write('Line 1\nLine 2');
      expect(buffer.cursorY, equals(1));
      expect(buffer.cursorX, equals(6));

      final line1 = buffer.rows[0].sublist(0, 6).map((c) => c.char).join('');
      final line2 = buffer.rows[1].sublist(0, 6).map((c) => c.char).join('');
      expect(line1, equals('Line 1'));
      expect(line2, equals('Line 2'));
    });

    test('carriage return overwrite behavior', () {
      final buffer = TerminalEmulatorBuffer(cols: 80);
      final parser = AnsiParser(buffer);

      parser.write('Hello\rWorld');
      final line = buffer.rows[0].sublist(0, 5).map((c) => c.char).join('');
      expect(line, equals('World'));
      expect(buffer.cursorX, equals(5));
    });

    test('backspace behavior', () {
      final buffer = TerminalEmulatorBuffer(cols: 80);
      final parser = AnsiParser(buffer);

      parser.write('Hello\b\b\babc');
      final line = buffer.rows[0].sublist(0, 5).map((c) => c.char).join('');
      expect(line, equals('Heabc'));
      expect(buffer.cursorX, equals(5));
    });

    test('tab expansion', () {
      final buffer = TerminalEmulatorBuffer(cols: 80);
      final parser = AnsiParser(buffer);

      parser.write('A\tB');
      expect(buffer.cursorX, equals(9));
      expect(buffer.rows[0][0].char, equals('A'));
      expect(buffer.rows[0][1].char, equals(' '));
      expect(buffer.rows[0][7].char, equals(' '));
      expect(buffer.rows[0][8].char, equals('B'));
    });

    test('red/green/reset ANSI colors', () {
      final buffer = TerminalEmulatorBuffer(cols: 80);
      final parser = AnsiParser(buffer);

      parser.write('\u001B[31mRed\u001B[32mGreen\u001B[0mNormal');

      expect(buffer.rows[0][0].style.foregroundColor, equals(ansiColors[1]));
      expect(buffer.rows[0][3].style.foregroundColor, equals(ansiColors[2]));
      expect(buffer.rows[0][8].style.foregroundColor, isNull);
    });

    test('bold style', () {
      final buffer = TerminalEmulatorBuffer(cols: 80);
      final parser = AnsiParser(buffer);

      parser.write('\u001B[1mBold');
      expect(buffer.rows[0][0].style.bold, isTrue);
    });

    test('clear screen', () {
      final buffer = TerminalEmulatorBuffer(cols: 80);
      final parser = AnsiParser(buffer);

      parser.write('Line 1\nLine 2');
      expect(buffer.rows.length, equals(2));

      parser.write('\u001B[2J');
      expect(buffer.rows.length, equals(1));
      expect(buffer.cursorX, equals(0));
      expect(buffer.cursorY, equals(0));
    });

    test('cursor home', () {
      final buffer = TerminalEmulatorBuffer(cols: 80);
      final parser = AnsiParser(buffer);

      parser.write('Hello');
      expect(buffer.cursorX, equals(5));

      parser.write('\u001B[H');
      expect(buffer.cursorX, equals(0));
      expect(buffer.cursorY, equals(0));
    });

    test('mixed ANSI and normal text', () {
      final buffer = TerminalEmulatorBuffer(cols: 80);
      final parser = AnsiParser(buffer);

      parser.write('Normal \u001B[31mRed \u001B[0mNormal');
      expect(buffer.rows[0][6].style.foregroundColor, isNull);
      expect(buffer.rows[0][7].style.foregroundColor, equals(ansiColors[1]));
      expect(buffer.rows[0][11].style.foregroundColor, isNull);
    });

    test('fallback behavior on malformed ANSI', () {
      final buffer = TerminalEmulatorBuffer(cols: 80);
      final parser = AnsiParser(buffer);

      parser.write('Hello \u001B[31');
      expect(buffer.rows[0][6].char, equals(' '));
      expect(buffer.rows[0][7].char, equals(' '));
      expect(buffer.rows[0][8].char, equals(' '));
      expect(buffer.rows[0][9].char, equals(' '));
    });

    test('crash recovery on style exception', () {
      final buffer = ThrowingBuffer();
      final parser = AnsiParser(buffer);

      parser.write('A\u001B[31mBC');
      expect(buffer.rows[0][0].char, equals('A'));
      expect(buffer.rows[0][1].char, equals('B'));
      expect(buffer.rows[0][2].char, equals('C'));
    });

    test('sanitizePtyOutput preserves backspaces', () {
      final service = TerminalSessionService();
      final sanitized = service.sanitizePtyOutput('Hello\bWorld');
      expect(sanitized, equals('Hello\bWorld'));
    });

    test('cursor relative movements', () {
      final buffer = TerminalEmulatorBuffer(cols: 80, visibleRows: 24);
      final parser = AnsiParser(buffer);

      parser.write('Hello\nWorld');
      expect(buffer.cursorX, equals(5));
      expect(buffer.cursorY, equals(1));

      // Up 1
      parser.write('\u001B[A');
      expect(buffer.cursorX, equals(5));
      expect(buffer.cursorY, equals(0));

      // Down 1
      parser.write('\u001B[B');
      expect(buffer.cursorX, equals(5));
      expect(buffer.cursorY, equals(1));

      // Forward 2
      parser.write('\u001B[2C');
      expect(buffer.cursorX, equals(7));
      expect(buffer.cursorY, equals(1));

      // Backward 3
      parser.write('\u001B[3D');
      expect(buffer.cursorX, equals(4));
      expect(buffer.cursorY, equals(1));
    });

    test('absolute cursor position', () {
      final buffer = TerminalEmulatorBuffer(cols: 80, visibleRows: 24);
      final parser = AnsiParser(buffer);

      parser.write('\u001B[3;5H');
      expect(buffer.cursorX, equals(4));
      expect(buffer.cursorY, equals(2));

      parser.write('\u001B[f');
      expect(buffer.cursorX, equals(0));
      expect(buffer.cursorY, equals(0));

      parser.write('\u001B[2;4f');
      expect(buffer.cursorX, equals(3));
      expect(buffer.cursorY, equals(1));
    });

    test('line clearing ESC[K, ESC[0K, ESC[1K, ESC[2K', () {
      final buffer = TerminalEmulatorBuffer(cols: 5, visibleRows: 24);
      final parser = AnsiParser(buffer);

      // Clear from cursor to end (ESC[K)
      parser.write(
        '12345\u001B[3D\u001B[K',
      ); // Write 12345, back 3 to index 2, clear right
      expect(buffer.rows[0].map((c) => c.char).join(''), equals('12   '));

      buffer.clearScreen();

      // Clear from start to cursor (ESC[1K)
      parser.write(
        '12345\u001B[3D\u001B[1K',
      ); // Write 12345, back 3 to index 2, clear left
      expect(buffer.rows[0].map((c) => c.char).join(''), equals('   45'));

      buffer.clearScreen();

      // Clear entire line (ESC[2K)
      parser.write('12345\u001B[2K');
      expect(buffer.rows[0].map((c) => c.char).join(''), equals('     '));
    });

    test('screen clearing ESC[0J, ESC[1J', () {
      final buffer = TerminalEmulatorBuffer(cols: 5, visibleRows: 5);
      final parser = AnsiParser(buffer);

      // Clear screen down (ESC[J or ESC[0J)
      parser.write('line1\nline2\nline3');
      parser.write('\u001B[2;3H\u001B[0J'); // Row 2, Col 3 (index 1, 2)
      expect(buffer.rows[0].map((c) => c.char).join(''), equals('line1'));
      expect(buffer.rows[1].map((c) => c.char).join(''), equals('li   '));
      expect(buffer.rows[2].map((c) => c.char).join(''), equals('     '));

      buffer.clearScreen();

      // Clear screen up (ESC[1J)
      parser.write('line1\nline2\nline3');
      parser.write('\u001B[2;3H\u001B[1J'); // Row 2, Col 3 (index 1, 2)
      expect(buffer.rows[0].map((c) => c.char).join(''), equals('     '));
      expect(buffer.rows[1].map((c) => c.char).join(''), equals('   e2'));
      expect(buffer.rows[2].map((c) => c.char).join(''), equals('line3'));
    });

    test('writing after cursor movement', () {
      final buffer = TerminalEmulatorBuffer(cols: 5, visibleRows: 5);
      final parser = AnsiParser(buffer);

      parser.write('\u001B[1;1HA\u001B[2;2HB');
      expect(buffer.rows[0][0].char, equals('A'));
      expect(buffer.rows[1][1].char, equals('B'));
    });

    test('scrolling when writing past bottom row', () {
      final buffer = TerminalEmulatorBuffer(cols: 5, visibleRows: 5);
      final parser = AnsiParser(buffer);

      parser.write('1\n2\n3\n4\n5');
      expect(buffer.rows.length, equals(5));
      expect(buffer.viewportStart, equals(0));

      parser.write('\n6');
      expect(buffer.rows.length, equals(6));
      expect(buffer.viewportStart, equals(1));
      expect(buffer.cursorY, equals(5));
      expect(buffer.rows[0].map((c) => c.char).join('').trim(), equals('1'));
      expect(buffer.rows[5].map((c) => c.char).join('').trim(), equals('6'));
    });

    test('resize preserving/clamping content', () {
      final buffer = TerminalEmulatorBuffer(cols: 10, visibleRows: 5);
      final parser = AnsiParser(buffer);

      parser.write('1234567890');
      expect(buffer.cursorX, equals(10));

      buffer.resize(5);
      expect(buffer.cols, equals(5));
      expect(buffer.rows[0].map((c) => c.char).join(''), equals('12345'));
      expect(buffer.cursorX, equals(4)); // clamped

      buffer.resize(10, 3);
      expect(buffer.cols, equals(10));
      expect(buffer.visibleRows, equals(3));
    });
  });
}

class ThrowingBuffer extends TerminalEmulatorBuffer {
  ThrowingBuffer() : super(cols: 80);

  @override
  void setStyle(_) {
    throw Exception('Simulated styling error');
  }
}
