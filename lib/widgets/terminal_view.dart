import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/terminal_line.dart';
import '../services/settings_service.dart';

import '../models/terminal_cell.dart';
import '../services/terminal_session_service.dart';
import 'blinking_cursor.dart';

class TerminalView extends StatelessWidget {
  final List<TerminalLine> lines;
  final ScrollController scrollController;
  final bool showInput;
  final TextEditingController textController;
  final FocusNode focusNode;
  final String prompt;
  final ValueChanged<String> onSubmit;

  const TerminalView({
    super.key,
    required this.lines,
    required this.scrollController,
    required this.showInput,
    required this.textController,
    required this.focusNode,
    required this.prompt,
    required this.onSubmit,
  });

  Widget _buildAnsiRowText(
    List<TerminalCell> row,
    TextStyle baseStyle,
    SettingsService settings,
  ) {
    if (row.isEmpty) {
      return RichText(
        text: TextSpan(text: ' ', style: baseStyle),
      );
    }

    final List<TextSpan> spans = [];
    int start = 0;
    while (start < row.length) {
      final style = row[start].style;
      int end = start;
      while (end < row.length && row[end].style == style) {
        end++;
      }

      final text = row.sublist(start, end).map((c) => c.char).join('');
      Color color = style.foregroundColor ?? settings.textColor;
      Color? bgColor = style.backgroundColor;
      FontWeight fontWeight = style.bold ? FontWeight.bold : FontWeight.normal;
      final effectiveColor = style.dim ? color.withValues(alpha: 0.65) : color;

      spans.add(
        TextSpan(
          text: text,
          style: baseStyle.copyWith(
            color: effectiveColor,
            backgroundColor: bgColor,
            fontWeight: fontWeight,
            decoration: style.underline ? TextDecoration.underline : null,
          ),
        ),
      );

      start = end;
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final baseStyle = TextStyle(
          fontFamily: 'monospace',
          fontSize: settings.fontSize,
          height: settings.lineHeight,
          color: settings.textColor,
        );

        final useAnsi = settings.enableAnsiRenderer;
        final sessionService = TerminalSessionService();
        final ansiBuffer = sessionService.sessions.isNotEmpty
            ? sessionService.activeSession.ansiBuffer
            : null;

        final itemCount = useAnsi && ansiBuffer != null
            ? ansiBuffer.rows.length + (showInput ? 1 : 0)
            : lines.length + (showInput ? 1 : 0);

        return Container(
          color: settings.backgroundColor,
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
          child: SelectionArea(
            child: ListView.builder(
              controller: scrollController,
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (useAnsi && ansiBuffer != null) {
                  if (index == ansiBuffer.rows.length) {
                    return _buildActivePromptLine(context, settings, baseStyle);
                  }

                  final row = ansiBuffer.rows[index];
                  int lastNonSpace = row.length - 1;
                  while (lastNonSpace >= 0 && row[lastNonSpace].char == ' ') {
                    lastNonSpace--;
                  }
                  final visibleCells = lastNonSpace >= 0
                      ? row.sublist(0, lastNonSpace + 1)
                      : <TerminalCell>[];

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: GestureDetector(
                      onLongPress: () {
                        final plainText = visibleCells
                            .map((c) => c.char)
                            .join('')
                            .trimRight();
                        Clipboard.setData(ClipboardData(text: plainText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Copied: "${plainText.length > 30 ? '${plainText.substring(0, 30)}...' : plainText}"',
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                            backgroundColor: settings.primaryColor,
                            duration: const Duration(milliseconds: 800),
                            behavior: SnackBarBehavior.floating,
                            width: 250,
                          ),
                        );
                      },
                      child: _buildAnsiRowText(
                        visibleCells,
                        baseStyle,
                        settings,
                      ),
                    ),
                  );
                } else {
                  if (index == lines.length) {
                    return _buildActivePromptLine(context, settings, baseStyle);
                  }

                  final line = lines[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: GestureDetector(
                      onLongPress: () {
                        Clipboard.setData(ClipboardData(text: line.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Copied: "${line.text.length > 30 ? '${line.text.substring(0, 30)}...' : line.text}"',
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                            backgroundColor: settings.primaryColor,
                            duration: const Duration(milliseconds: 800),
                            behavior: SnackBarBehavior.floating,
                            width: 250,
                          ),
                        );
                      },
                      child: _buildLineText(context, line, baseStyle, settings),
                    ),
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildActivePromptLine(
    BuildContext context,
    SettingsService settings,
    TextStyle baseStyle,
  ) {
    final sessionService = TerminalSessionService();
    final isPty =
        sessionService.sessions.isNotEmpty &&
        sessionService.activeSession.isPtyInteractionActive;

    if (isPty) {
      return ListenableBuilder(
        listenable: Listenable.merge([textController, focusNode]),
        builder: (context, _) {
          final hasFocus = focusNode.hasFocus;
          final isEmpty = textController.text.isEmpty;
          final text = textController.text;
          final selection = textController.selection;

          String leftText = text;
          String rightText = '';
          if (selection.isValid &&
              selection.baseOffset >= 0 &&
              selection.baseOffset <= text.length) {
            leftText = text.substring(0, selection.baseOffset);
            rightText = text.substring(selection.baseOffset);
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Stack(
              children: [
                IgnorePointer(
                  child: RichText(
                    text: TextSpan(
                      style: baseStyle.copyWith(color: Colors.white),
                      children: [
                        TextSpan(text: leftText),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.bottom,
                          child: BlinkingCursor(
                            color: settings.primaryColor,
                            style: settings.cursorStyle,
                            blink: settings.blinkingCursor && hasFocus,
                            fontSize: settings.fontSize,
                          ),
                        ),
                        TextSpan(text: rightText),
                        if (!hasFocus && isEmpty)
                          TextSpan(
                            text: 'Tap terminal to type',
                            style: baseStyle.copyWith(
                              color: Colors.white30,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                TextField(
                  controller: textController,
                  focusNode: focusNode,
                  showCursor: false,
                  style: baseStyle.copyWith(color: Colors.transparent),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (value) {
                    onSubmit(value);
                    textController.clear();
                    focusNode.requestFocus();
                  },
                ),
              ],
            ),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prompt,
            style: baseStyle.copyWith(
              color: settings.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: TextField(
              controller: textController,
              focusNode: focusNode,
              cursorColor: settings.primaryColor,
              style: baseStyle.copyWith(color: Colors.white),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (value) {
                onSubmit(value);
                textController.clear();
                focusNode.requestFocus();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineText(
    BuildContext context,
    TerminalLine line,
    TextStyle baseStyle,
    SettingsService settings,
  ) {
    Color color = settings.textColor;
    if (line.type == LineType.input) {
      color = settings.primaryColor;
    } else if (line.type == LineType.error) {
      color = const Color(0xFFFF5C5C); // Pastelly red for errors
    }

    // High-fidelity coloring for directories on standard outputs (from ls)
    if (line.type == LineType.output) {
      final parts = line.text.split('  ');
      if (parts.length > 1 || line.text.endsWith('/')) {
        final List<InlineSpan> spans = [];
        for (int i = 0; i < parts.length; i++) {
          final part = parts[i];
          final isDirectory = part.endsWith('/');

          spans.add(
            TextSpan(
              text: part,
              style: TextStyle(
                color: isDirectory
                    ? const Color(0xFF62A0EA) // Accent blue for folders
                    : settings.textColor,
                fontWeight: isDirectory ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );

          if (i < parts.length - 1) {
            spans.add(const TextSpan(text: '  '));
          }
        }
        return RichText(
          text: TextSpan(style: baseStyle, children: spans),
        );
      }
    }

    return Text(line.text, style: baseStyle.copyWith(color: color));
  }
}
