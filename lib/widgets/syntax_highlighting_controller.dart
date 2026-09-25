import 'package:flutter/material.dart';
import '../services/file_explorer_service.dart';

class _HighlightToken {
  final int start;
  final int end;
  final TextStyle style;

  _HighlightToken({
    required this.start,
    required this.end,
    required this.style,
  });
}

class SyntaxHighlightingEditingController extends TextEditingController {
  FileCategory category;

  SyntaxHighlightingEditingController({
    super.text,
    this.category = FileCategory.text,
  });

  // VS Code Dark+ / Slate theme colors
  static const Color keywordColor = Color(0xFF569CD6);
  static const Color stringColor = Color(0xFFCE9178);
  static const Color commentColor = Color(0xFF6A9955);
  static const Color numberColor = Color(0xFFB5CEA8);
  static const Color functionColor = Color(0xFFDCDCAA);
  static const Color variableColor = Color(0xFF9CDCFE);
  static const Color typeColor = Color(0xFF4EC9B0);
  static const Color defaultTextColor = Color(0xFFD4D4D4);

  void updateCategory(FileCategory newCategory) {
    if (category != newCategory) {
      category = newCategory;
      notifyListeners();
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final effectiveStyle = (style ?? const TextStyle()).copyWith(
      color: defaultTextColor,
      fontFamily: 'monospace',
    );

    if (text.isEmpty || category == FileCategory.binary) {
      return TextSpan(text: text, style: effectiveStyle);
    }

    final tokens = _extractTokens(text, category, effectiveStyle);
    if (tokens.isEmpty) {
      return TextSpan(text: text, style: effectiveStyle);
    }

    // Sort tokens by start position, then by length descending
    tokens.sort((a, b) {
      final cmp = a.start.compareTo(b.start);
      if (cmp != 0) return cmp;
      return b.end.compareTo(a.end);
    });

    // Remove overlapping tokens (first one wins)
    final nonOverlapping = <_HighlightToken>[];
    var lastEnd = 0;
    for (final token in tokens) {
      if (token.start >= lastEnd) {
        nonOverlapping.add(token);
        lastEnd = token.end;
      }
    }

    // Build TextSpan children
    final spans = <InlineSpan>[];
    var currentPos = 0;

    for (final token in nonOverlapping) {
      if (token.start > currentPos) {
        spans.add(
          TextSpan(
            text: text.substring(currentPos, token.start),
            style: effectiveStyle,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: text.substring(token.start, token.end),
          style: token.style,
        ),
      );
      currentPos = token.end;
    }

    if (currentPos < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(currentPos),
          style: effectiveStyle,
        ),
      );
    }

    return TextSpan(style: effectiveStyle, children: spans);
  }

  void _addStrings(
    void Function(RegExp, TextStyle) addPattern,
    TextStyle style, {
    bool includeTemplate = false,
    bool includeTriple = false,
  }) {
    if (includeTriple) {
      addPattern(RegExp(r'"""[\s\S]*?"""'), style);
      addPattern(RegExp(r"'''[\s\S]*?'''"), style);
    }
    if (includeTemplate) {
      addPattern(RegExp(r'`(?:[^`\\]|\\.)*`'), style);
    }
    addPattern(RegExp(r'"(?:[^"\\]|\\.)*"'), style);
    addPattern(RegExp(r"'(?:[^'\\]|\\.)*'"), style);
  }

  List<_HighlightToken> _extractTokens(
    String src,
    FileCategory cat,
    TextStyle baseStyle,
  ) {
    final tokens = <_HighlightToken>[];

    void addPattern(RegExp regex, TextStyle tokenStyle) {
      for (final match in regex.allMatches(src)) {
        tokens.add(
          _HighlightToken(
            start: match.start,
            end: match.end,
            style: tokenStyle,
          ),
        );
      }
    }

    final commentStyle = baseStyle.copyWith(
      color: commentColor,
      fontStyle: FontStyle.italic,
    );
    final strStyle = baseStyle.copyWith(color: stringColor);

    switch (cat) {
      case FileCategory.python:
        addPattern(RegExp(r'#.*$', multiLine: true), commentStyle);
        _addStrings(addPattern, strStyle, includeTriple: true);
        addPattern(
          RegExp(
            r'\b(def|class|if|elif|else|for|while|try|except|finally|with|as|return|yield|import|from|lambda|pass|break|continue|raise|assert|async|await|in|is|not|and|or|True|False|None)\b',
          ),
          baseStyle.copyWith(
            color: keywordColor,
            fontWeight: FontWeight.w600,
          ),
        );
        addPattern(
          RegExp(
            r'(@[a-zA-Z_][a-zA-Z0-9_]*|\b(?:print|len|range|open|list|dict|set|str|int|float|bool|super|type|enumerate|zip|map|filter)\b)',
          ),
          baseStyle.copyWith(color: functionColor),
        );
        addPattern(
          RegExp(r'\b\d+(?:\.\d+)?\b'),
          baseStyle.copyWith(color: numberColor),
        );
        break;

      case FileCategory.javascript:
        addPattern(RegExp(r'(//.*$|/\*[\s\S]*?\*/)', multiLine: true), commentStyle);
        _addStrings(addPattern, strStyle, includeTemplate: true);
        addPattern(
          RegExp(
            r'\b(const|let|var|function|return|if|else|for|while|do|switch|case|break|continue|default|try|catch|finally|throw|class|new|this|super|extends|import|export|from|as|default|async|await|typeof|instanceof|void|delete|null|undefined|true|false)\b',
          ),
          baseStyle.copyWith(
            color: keywordColor,
            fontWeight: FontWeight.w600,
          ),
        );
        addPattern(
          RegExp(
            r'\b(console|require|module|exports|process|Promise|JSON|Math|Array|Object|String|Number|Boolean|Date|RegExp|Error)\b',
          ),
          baseStyle.copyWith(color: typeColor),
        );
        addPattern(
          RegExp(r'\b\d+(?:\.\d+)?\b'),
          baseStyle.copyWith(color: numberColor),
        );
        break;

      case FileCategory.shell:
        addPattern(RegExp(r'#.*$', multiLine: true), commentStyle);
        _addStrings(addPattern, strStyle);
        addPattern(
          RegExp(
            r'\b(if|then|else|elif|fi|for|in|do|done|while|until|case|esac|function|select|return|exit)\b',
          ),
          baseStyle.copyWith(
            color: keywordColor,
            fontWeight: FontWeight.w600,
          ),
        );
        addPattern(
          RegExp(r'(\$[a-zA-Z_][a-zA-Z0-9_]*|\$\{[^}]+\}|\$[0-9#?*@!$])'),
          baseStyle.copyWith(color: variableColor),
        );
        addPattern(
          RegExp(
            r'\b(echo|cd|pwd|ls|cat|mkdir|rm|cp|mv|touch|grep|chmod|chown|source|export|alias|local|read|which|find)\b',
          ),
          baseStyle.copyWith(color: functionColor),
        );
        addPattern(
          RegExp(r'\b\d+\b'),
          baseStyle.copyWith(color: numberColor),
        );
        break;

      case FileCategory.json:
        for (final match
            in RegExp(r'("(?:\\.|[^"\\])*")(?=\s*:)').allMatches(src)) {
          tokens.add(
            _HighlightToken(
              start: match.start,
              end: match.end,
              style: baseStyle.copyWith(color: variableColor),
            ),
          );
        }
        addPattern(RegExp(r'"(?:[^"\\]|\\.)*"'), strStyle);
        addPattern(
          RegExp(r'\b-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b'),
          baseStyle.copyWith(color: numberColor),
        );
        addPattern(
          RegExp(r'\b(true|false|null)\b'),
          baseStyle.copyWith(
            color: keywordColor,
            fontWeight: FontWeight.w600,
          ),
        );
        break;

      case FileCategory.markdown:
        addPattern(
          RegExp(r'^#{1,6}\s+.*$', multiLine: true),
          baseStyle.copyWith(
            color: keywordColor,
            fontWeight: FontWeight.bold,
          ),
        );
        addPattern(
          RegExp(r'(`[^`]+`|```[\s\S]*?```)'),
          strStyle,
        );
        addPattern(RegExp(r'^>.*$', multiLine: true), commentStyle);
        addPattern(
          RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*|__[^_]+__|_[^_]+_)'),
          baseStyle.copyWith(
            color: functionColor,
            fontWeight: FontWeight.w600,
          ),
        );
        break;

      case FileCategory.c:
        addPattern(RegExp(r'(//.*$|/\*[\s\S]*?\*/)', multiLine: true), commentStyle);
        _addStrings(addPattern, strStyle);
        addPattern(
          RegExp(r'#\s*(?:include|define|ifdef|ifndef|endif|if|elif|else)\b.*$'),
          baseStyle.copyWith(color: typeColor),
        );
        addPattern(
          RegExp(
            r'\b(int|char|void|float|double|long|short|unsigned|signed|struct|union|enum|typedef|sizeof|return|if|else|for|while|do|switch|case|break|continue|default|static|const|volatile|extern)\b',
          ),
          baseStyle.copyWith(
            color: keywordColor,
            fontWeight: FontWeight.w600,
          ),
        );
        addPattern(
          RegExp(r'\b\d+(?:\.\d+)?\b'),
          baseStyle.copyWith(color: numberColor),
        );
        break;

      case FileCategory.text:
      default:
        addPattern(
          RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*(?==)', multiLine: true),
          baseStyle.copyWith(color: variableColor),
        );
        addPattern(RegExp(r'#.*$', multiLine: true), commentStyle);
        break;
    }

    return tokens;
  }
}
