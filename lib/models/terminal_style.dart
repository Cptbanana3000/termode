import 'package:flutter/material.dart';

const Map<int, Color> ansiColors = {
  0: Colors.black,
  1: Color(0xFFE33E3E), // Red
  2: Color(0xFF3EE33E), // Green
  3: Color(0xFFE3E33E), // Yellow
  4: Color(0xFF3E3EE3), // Blue
  5: Color(0xFFE33EE3), // Magenta
  6: Color(0xFF3EE3E3), // Cyan
  7: Color(0xFFE3E3E3), // White
};

const Map<int, Color> brightAnsiColors = {
  0: Color(0xFF555555), // Bright Black (Grey)
  1: Color(0xFFFF5555), // Bright Red
  2: Color(0xFF55FF55), // Bright Green
  3: Color(0xFFFFFF55), // Bright Yellow
  4: Color(0xFF5555FF), // Bright Blue
  5: Color(0xFFFF55FF), // Bright Magenta
  6: Color(0xFF55FFFF), // Bright Cyan
  7: Color(0xFFFFFFFF), // Bright White
};

class TerminalStyle {
  final Color? foregroundColor;
  final Color? backgroundColor;
  final bool bold;
  final bool dim;
  final bool underline;

  const TerminalStyle({
    this.foregroundColor,
    this.backgroundColor,
    this.bold = false,
    this.dim = false,
    this.underline = false,
  });

  TerminalStyle copyWith({
    Color? foregroundColor,
    Color? backgroundColor,
    bool? bold,
    bool? dim,
    bool? underline,
    bool clearForeground = false,
    bool clearBackground = false,
  }) {
    return TerminalStyle(
      foregroundColor: clearForeground
          ? null
          : (foregroundColor ?? this.foregroundColor),
      backgroundColor: clearBackground
          ? null
          : (backgroundColor ?? this.backgroundColor),
      bold: bold ?? this.bold,
      dim: dim ?? this.dim,
      underline: underline ?? this.underline,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalStyle &&
          runtimeType == other.runtimeType &&
          foregroundColor == other.foregroundColor &&
          backgroundColor == other.backgroundColor &&
          bold == other.bold &&
          dim == other.dim &&
          underline == other.underline;

  @override
  int get hashCode =>
      Object.hash(foregroundColor, backgroundColor, bold, dim, underline);
}
