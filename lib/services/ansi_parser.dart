import '../models/terminal_emulator_buffer.dart';
import '../models/terminal_style.dart';

class AnsiParser {
  final TerminalEmulatorBuffer buffer;

  AnsiParser(this.buffer);

  void write(String text) {
    int i = 0;
    try {
      while (i < text.length) {
        final char = text[i];
        if (char == '\u001B') {
          // Look ahead for CSI '['
          if (i + 1 < text.length && text[i + 1] == '[') {
            int start = i + 2;
            int end = start;
            while (end < text.length) {
              final code = text.codeUnitAt(end);
              // Command character is usually in range 0x40 to 0x7E (e.g. A-Z, a-z, etc.)
              if (code >= 0x40 && code <= 0x7E) {
                break;
              }
              end++;
            }
            if (end < text.length) {
              final sequenceStr = text.substring(start, end);
              final command = text[end];
              _handleSequence(sequenceStr, command);
              i = end + 1;
              continue;
            }
          }
        }

        if (char == '\n') {
          buffer.writeChar('\n');
        } else if (char == '\r') {
          buffer.writeChar('\r');
        } else if (char == '\b') {
          buffer.writeChar('\b');
        } else if (char == '\t') {
          buffer.writeChar('\t');
        } else {
          buffer.writeChar(char);
        }
        i++;
      }
    } catch (e) {
      // Fallback: write remaining text as plain text
      while (i < text.length) {
        final char = text[i];
        if (char == '\n') {
          buffer.writeChar('\n');
        } else if (char == '\r') {
          buffer.writeChar('\r');
        } else if (char == '\b') {
          buffer.writeChar('\b');
        } else if (char == '\t') {
          buffer.writeChar('\t');
        } else {
          buffer.writeChar(char);
        }
        i++;
      }
    }
  }

  int _parseSingleParam(String paramsStr, int defaultValue) {
    if (paramsStr.isEmpty) return defaultValue;
    return int.tryParse(paramsStr) ?? defaultValue;
  }

  List<int> _parseMultiParams(String paramsStr, int defaultValue) {
    if (paramsStr.isEmpty) return [defaultValue, defaultValue];
    final parts = paramsStr.split(';');
    final p1 = parts.isNotEmpty && parts[0].isNotEmpty ? (int.tryParse(parts[0]) ?? defaultValue) : defaultValue;
    final p2 = parts.length > 1 && parts[1].isNotEmpty ? (int.tryParse(parts[1]) ?? defaultValue) : defaultValue;
    return [p1, p2];
  }

  void _handleSequence(String paramsStr, String command) {
    if (command == 'm') {
      // Style / Color sequence
      final params = paramsStr.split(';').map((p) => int.tryParse(p) ?? 0).toList();
      if (params.isEmpty || (params.length == 1 && paramsStr.isEmpty)) {
        params.add(0); // Default to reset
      }

      TerminalStyle currentStyle = buffer.currentStyle;
      for (final param in params) {
        if (param == 0) {
          currentStyle = const TerminalStyle();
        } else if (param == 1) {
          currentStyle = currentStyle.copyWith(bold: true);
        } else if (param >= 30 && param <= 37) {
          final colorCode = param - 30;
          currentStyle = currentStyle.copyWith(
            foregroundColor: ansiColors[colorCode],
            clearForeground: false,
          );
        } else if (param >= 90 && param <= 97) {
          final colorCode = param - 90;
          currentStyle = currentStyle.copyWith(
            foregroundColor: brightAnsiColors[colorCode],
            clearForeground: false,
          );
        } else if (param >= 40 && param <= 47) {
          final colorCode = param - 40;
          currentStyle = currentStyle.copyWith(
            backgroundColor: ansiColors[colorCode],
            clearBackground: false,
          );
        } else if (param >= 100 && param <= 107) {
          final colorCode = param - 100;
          currentStyle = currentStyle.copyWith(
            backgroundColor: brightAnsiColors[colorCode],
            clearBackground: false,
          );
        } else if (param == 39) {
          currentStyle = currentStyle.copyWith(clearForeground: true);
        } else if (param == 49) {
          currentStyle = currentStyle.copyWith(clearBackground: true);
        }
      }
      buffer.setStyle(currentStyle);
    } else if (command == 'A') {
      final n = _parseSingleParam(paramsStr, 1);
      buffer.cursorUp(n);
    } else if (command == 'B') {
      final n = _parseSingleParam(paramsStr, 1);
      buffer.cursorDown(n);
    } else if (command == 'C') {
      final n = _parseSingleParam(paramsStr, 1);
      buffer.cursorForward(n);
    } else if (command == 'D') {
      final n = _parseSingleParam(paramsStr, 1);
      buffer.cursorBackward(n);
    } else if (command == 'H' || command == 'f') {
      final coords = _parseMultiParams(paramsStr, 1);
      buffer.cursorPosition(coords[0], coords[1]);
    } else if (command == 'K') {
      final mode = _parseSingleParam(paramsStr, 0);
      if (mode == 0) {
        buffer.clearLineFromCursor();
      } else if (mode == 1) {
        buffer.clearLineToCursor();
      } else if (mode == 2) {
        buffer.clearLine();
      }
    } else if (command == 'J') {
      final mode = _parseSingleParam(paramsStr, 0);
      if (mode == 0) {
        buffer.clearScreenFromCursor();
      } else if (mode == 1) {
        buffer.clearScreenToCursor();
      } else if (mode == 2) {
        buffer.clearScreen();
      }
    }
  }
}
