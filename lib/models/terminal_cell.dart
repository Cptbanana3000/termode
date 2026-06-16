import 'terminal_style.dart';

class TerminalCell {
  final String char;
  final TerminalStyle style;

  const TerminalCell({
    this.char = ' ',
    this.style = const TerminalStyle(),
  });
}
