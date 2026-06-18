import 'package:flutter/material.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  double _fontSize = 14.0;
  double get fontSize => _fontSize;

  double _lineHeight = 1.3;
  double get lineHeight => _lineHeight;

  String _themeColor = 'Green'; // 'Green', 'Amber', 'White'
  String get themeColor => _themeColor;

  bool _showWelcomeBanner = true;
  bool get showWelcomeBanner => _showWelcomeBanner;

  bool _showLargeAsciiBanner = false;
  bool get showLargeAsciiBanner => _showLargeAsciiBanner;

  bool _immersiveMode = false;
  bool get immersiveMode => _immersiveMode;

  bool _showControlCharsHex = false;
  bool get showControlCharsHex => _showControlCharsHex;

  bool _enableAnsiRenderer = true;
  bool get enableAnsiRenderer => _enableAnsiRenderer;

  bool _ansiDebugMode = false;
  bool get ansiDebugMode => _ansiDebugMode;

  String _cursorStyle = 'block';
  String get cursorStyle => _cursorStyle;

  bool _blinkingCursor = true;
  bool get blinkingCursor => _blinkingCursor;

  bool _startInRealShell = true;
  bool get startInRealShell => _startInRealShell;

  int _maxScrollbackLines = 2000;
  int get maxScrollbackLines => _maxScrollbackLines;

  int _pasteWarningThreshold = 1000;
  int get pasteWarningThreshold => _pasteWarningThreshold;

  int _pasteHardLimit = 10000;
  int get pasteHardLimit => _pasteHardLimit;

  bool _keepScreenOn = false;
  bool get keepScreenOn => _keepScreenOn;

  void setFontSize(double size) {
    _fontSize = size;
    notifyListeners();
  }

  void setLineHeight(double value) {
    _lineHeight = value.clamp(1.0, 2.0).toDouble();
    notifyListeners();
  }

  void setThemeColor(String color) {
    _themeColor = color;
    notifyListeners();
  }

  void setShowWelcomeBanner(bool value) {
    _showWelcomeBanner = value;
    notifyListeners();
  }

  void setShowLargeAsciiBanner(bool value) {
    _showLargeAsciiBanner = value;
    notifyListeners();
  }

  void setImmersiveMode(bool value) {
    _immersiveMode = value;
    notifyListeners();
  }

  void setShowControlCharsHex(bool value) {
    _showControlCharsHex = value;
    notifyListeners();
  }

  void setEnableAnsiRenderer(bool value) {
    _enableAnsiRenderer = value;
    notifyListeners();
  }

  void setAnsiDebugMode(bool value) {
    _ansiDebugMode = value;
    notifyListeners();
  }

  void setCursorStyle(String style) {
    _cursorStyle = style;
    notifyListeners();
  }

  void setBlinkingCursor(bool value) {
    _blinkingCursor = value;
    notifyListeners();
  }

  void setStartInRealShell(bool value) {
    _startInRealShell = value;
    notifyListeners();
  }

  void setMaxScrollbackLines(int value) {
    const allowed = {500, 1000, 2000, 5000, 10000};
    _maxScrollbackLines = allowed.contains(value) ? value : 2000;
    notifyListeners();
  }

  void setPasteWarningThreshold(int value) {
    _pasteWarningThreshold = value.clamp(1, _pasteHardLimit).toInt();
    notifyListeners();
  }

  void setPasteHardLimit(int value) {
    _pasteHardLimit = value.clamp(1000, 50000).toInt();
    if (_pasteWarningThreshold > _pasteHardLimit) {
      _pasteWarningThreshold = _pasteHardLimit;
    }
    notifyListeners();
  }

  void setKeepScreenOn(bool value) {
    _keepScreenOn = value;
    notifyListeners();
  }

  /// Resets visual and terminal-rendering settings to their defaults.
  ///
  /// This is the data-safe reset used by `settings-reset-safe`. It deliberately
  /// does NOT touch packages, workspaces, sessions, history, repo config, or
  /// files. It also preserves [startInRealShell] so shell startup behavior is
  /// not changed unexpectedly.
  void resetVisualSettings() {
    _fontSize = 14.0;
    _lineHeight = 1.3;
    _themeColor = 'Green';
    _showWelcomeBanner = true;
    _showLargeAsciiBanner = false;
    _immersiveMode = false;
    _showControlCharsHex = false;
    _enableAnsiRenderer = true;
    _ansiDebugMode = false;
    _cursorStyle = 'block';
    _blinkingCursor = true;
    _maxScrollbackLines = 2000;
    _pasteHardLimit = 10000;
    _pasteWarningThreshold = 1000;
    _keepScreenOn = false;
    // startInRealShell is intentionally preserved.
    notifyListeners();
  }

  Map<String, dynamic> toJson() {
    return {
      'fontSize': _fontSize,
      'lineHeight': _lineHeight,
      'themeColor': _themeColor,
      'showWelcomeBanner': _showWelcomeBanner,
      'showLargeAsciiBanner': _showLargeAsciiBanner,
      'immersiveMode': _immersiveMode,
      'showControlCharsHex': _showControlCharsHex,
      'enableAnsiRenderer': _enableAnsiRenderer,
      'ansiDebugMode': _ansiDebugMode,
      'cursorStyle': _cursorStyle,
      'blinkingCursor': _blinkingCursor,
      'startInRealShell': _startInRealShell,
      'maxScrollbackLines': _maxScrollbackLines,
      'pasteWarningThreshold': _pasteWarningThreshold,
      'pasteHardLimit': _pasteHardLimit,
      'keepScreenOn': _keepScreenOn,
    };
  }

  void loadFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      _fontSize = 14.0;
      _lineHeight = 1.3;
      _themeColor = 'Green';
      _showWelcomeBanner = true;
      _showLargeAsciiBanner = false;
      _immersiveMode = false;
      _showControlCharsHex = false;
      _enableAnsiRenderer = true;
      _ansiDebugMode = false;
      _cursorStyle = 'block';
      _blinkingCursor = true;
      _startInRealShell = true;
      _maxScrollbackLines = 2000;
      _pasteWarningThreshold = 1000;
      _pasteHardLimit = 10000;
      _keepScreenOn = false;
      notifyListeners();
      return;
    }
    _fontSize = (json['fontSize'] as num?)?.toDouble() ?? 14.0;
    _lineHeight = ((json['lineHeight'] as num?)?.toDouble() ?? 1.3)
        .clamp(1.0, 2.0)
        .toDouble();
    _themeColor = json['themeColor'] as String? ?? 'Green';
    _showWelcomeBanner = json['showWelcomeBanner'] as bool? ?? true;
    _showLargeAsciiBanner = json['showLargeAsciiBanner'] as bool? ?? false;
    _immersiveMode = json['immersiveMode'] as bool? ?? false;
    _showControlCharsHex = json['showControlCharsHex'] as bool? ?? false;
    _enableAnsiRenderer = json['enableAnsiRenderer'] as bool? ?? true;
    _ansiDebugMode = json['ansiDebugMode'] as bool? ?? false;
    _cursorStyle = json['cursorStyle'] as String? ?? 'block';
    _blinkingCursor = json['blinkingCursor'] as bool? ?? true;
    _startInRealShell = json['startInRealShell'] as bool? ?? true;
    final maxScrollback = json['maxScrollbackLines'] as int? ?? 2000;
    const allowedScrollback = {500, 1000, 2000, 5000, 10000};
    _maxScrollbackLines = allowedScrollback.contains(maxScrollback)
        ? maxScrollback
        : 2000;
    _pasteHardLimit = ((json['pasteHardLimit'] as int?) ?? 10000)
        .clamp(1000, 50000)
        .toInt();
    _pasteWarningThreshold = ((json['pasteWarningThreshold'] as int?) ?? 1000)
        .clamp(1, _pasteHardLimit)
        .toInt();
    _keepScreenOn = json['keepScreenOn'] as bool? ?? false;
    notifyListeners();
  }

  Color get primaryColor {
    switch (_themeColor) {
      case 'Amber':
        return const Color(0xFFFFB000);
      case 'White':
        return const Color(0xFFE0E0E0);
      case 'Green':
      default:
        return const Color(0xFF5AF78E);
    }
  }

  Color get textColor {
    switch (_themeColor) {
      case 'Amber':
        return const Color(0xFFFFD37A);
      case 'White':
        return const Color(0xFFF5F5F5);
      case 'Green':
      default:
        return const Color(0xFFF1F1F0);
    }
  }

  Color get backgroundColor {
    switch (_themeColor) {
      case 'Amber':
        return const Color(0xFF0C0A05);
      case 'White':
        return const Color(0xFF121212);
      case 'Green':
      default:
        return const Color(0xFF0C0C0C);
    }
  }
}
