import 'terminal_cell.dart';
import 'terminal_style.dart';

class TerminalEmulatorBuffer {
  int cols;
  int visibleRows;
  final int maxRows;
  final List<List<TerminalCell>> _rows = [];

  int _cursorX = 0;
  int _cursorY = 0;
  TerminalStyle _currentStyle = const TerminalStyle();

  TerminalEmulatorBuffer({
    this.cols = 80,
    this.maxRows = 1000,
    this.visibleRows = 24,
  }) {
    _ensureRowExists(0);
  }

  void resize(int newCols, [int? newRows]) {
    if (newCols <= 0) return;
    
    // Resize columns
    if (newCols != cols) {
      cols = newCols;
      for (int i = 0; i < _rows.length; i++) {
        final row = _rows[i];
        if (row.length < newCols) {
          row.addAll(List.generate(newCols - row.length, (_) => const TerminalCell(char: ' ')));
        } else if (row.length > newCols) {
          _rows[i] = row.sublist(0, newCols);
        }
      }
    }

    // Resize rows (visibleRows)
    if (newRows != null && newRows > 0) {
      visibleRows = newRows;
    }

    // Clamp cursor positions safely
    if (_cursorX >= cols) {
      _cursorX = cols - 1;
    }
    if (_cursorY >= _rows.length) {
      _cursorY = _rows.length - 1;
    }

    // Ensure cursor stays within the viewport limits
    final minVal = viewportStart;
    final maxVal = _rows.length - 1;
    if (_cursorY < minVal) {
      _cursorY = minVal;
    }
    if (_cursorY > maxVal) {
      _cursorY = maxVal;
    }
  }

  int get cursorX => _cursorX;
  int get cursorY => _cursorY;
  TerminalStyle get currentStyle => _currentStyle;
  List<List<TerminalCell>> get rows => _rows;

  int get viewportStart => (_rows.length - visibleRows).clamp(0, _rows.length);

  void setStyle(TerminalStyle style) {
    _currentStyle = style;
  }

  void clearScreen() {
    _rows.clear();
    _cursorX = 0;
    _cursorY = 0;
    _ensureRowExists(0);
  }

  void cursorHome() {
    cursorPosition(1, 1);
  }

  void cursorUp([int n = 1]) {
    final steps = n <= 0 ? 1 : n;
    _cursorY = (_cursorY - steps).clamp(viewportStart, _cursorY);
  }

  void cursorDown([int n = 1]) {
    final steps = n <= 0 ? 1 : n;
    final targetY = (_cursorY + steps).clamp(_cursorY, viewportStart + visibleRows - 1);
    _ensureRowExists(targetY);
    _cursorY = targetY;
  }

  void cursorForward([int n = 1]) {
    final steps = n <= 0 ? 1 : n;
    _cursorX = (_cursorX + steps).clamp(0, cols - 1);
  }

  void cursorBackward([int n = 1]) {
    final steps = n <= 0 ? 1 : n;
    _cursorX = (_cursorX - steps).clamp(0, cols - 1);
  }

  void cursorPosition(int row, int col) {
    final r = row <= 0 ? 1 : row;
    final c = col <= 0 ? 1 : col;

    final targetX = (c - 1).clamp(0, cols - 1);
    final targetY = viewportStart + (r - 1).clamp(0, visibleRows - 1);

    _ensureRowExists(targetY);
    _cursorX = targetX;
    _cursorY = targetY;
  }

  void clearLineFromCursor() {
    _ensureRowExists(_cursorY);
    final row = _rows[_cursorY];
    for (int x = _cursorX; x < cols; x++) {
      if (x < row.length) {
        row[x] = TerminalCell(char: ' ', style: _currentStyle);
      }
    }
  }

  void clearLineToCursor() {
    _ensureRowExists(_cursorY);
    final row = _rows[_cursorY];
    final limit = _cursorX.clamp(0, cols - 1);
    for (int x = 0; x <= limit; x++) {
      if (x < row.length) {
        row[x] = TerminalCell(char: ' ', style: _currentStyle);
      }
    }
  }

  void clearLine() {
    _ensureRowExists(_cursorY);
    final row = _rows[_cursorY];
    for (int x = 0; x < cols; x++) {
      if (x < row.length) {
        row[x] = TerminalCell(char: ' ', style: _currentStyle);
      }
    }
  }

  void clearScreenFromCursor() {
    clearLineFromCursor();
    final bottomRow = viewportStart + visibleRows - 1;
    for (int y = _cursorY + 1; y <= bottomRow; y++) {
      _ensureRowExists(y);
      final row = _rows[y];
      for (int x = 0; x < cols; x++) {
        row[x] = TerminalCell(char: ' ', style: _currentStyle);
      }
    }
  }

  void clearScreenToCursor() {
    for (int y = viewportStart; y < _cursorY; y++) {
      _ensureRowExists(y);
      final row = _rows[y];
      for (int x = 0; x < cols; x++) {
        row[x] = TerminalCell(char: ' ', style: _currentStyle);
      }
    }
    clearLineToCursor();
  }

  void clearViewport() {
    final bottomRow = viewportStart + visibleRows - 1;
    for (int y = viewportStart; y <= bottomRow; y++) {
      _ensureRowExists(y);
      final row = _rows[y];
      for (int x = 0; x < cols; x++) {
        row[x] = TerminalCell(char: ' ', style: _currentStyle);
      }
    }
  }

  void writeChar(String char) {
    if (char == '\n') {
      _cursorY++;
      _cursorX = 0;
      _ensureRowExists(_cursorY);
    } else if (char == '\r') {
      _cursorX = 0;
    } else if (char == '\b') {
      if (_cursorX > 0) {
        _cursorX--;
      }
    } else if (char == '\t') {
      int targetX = ((_cursorX + 8) ~/ 8) * 8;
      if (targetX > cols) {
        targetX = cols;
      }
      while (_cursorX < targetX) {
        _rows[_cursorY][_cursorX] = TerminalCell(char: ' ', style: _currentStyle);
        _cursorX++;
      }
      if (_cursorX >= cols) {
        _cursorX = 0;
        _cursorY++;
        _ensureRowExists(_cursorY);
      }
    } else {
      if (_cursorX >= cols) {
        _cursorX = 0;
        _cursorY++;
        _ensureRowExists(_cursorY);
      }
      _rows[_cursorY][_cursorX] = TerminalCell(char: char, style: _currentStyle);
      _cursorX++;
    }
  }

  void _ensureRowExists(int y) {
    while (_rows.length <= y) {
      _rows.add(List.generate(cols, (_) => const TerminalCell(char: ' ')));
    }
    if (_rows.length > maxRows) {
      final diff = _rows.length - maxRows;
      _rows.removeRange(0, diff);
      _cursorY = (_cursorY - diff).clamp(0, maxRows - 1);
    }
  }
}
