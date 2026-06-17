import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/terminal_session_service.dart';

class ExtraKeyboardRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> history;
  final VoidCallback onHistoryUp;
  final VoidCallback onHistoryDown;
  final VoidCallback onTabComplete;
  final VoidCallback onPageUp;
  final VoidCallback onPageDown;
  final bool isPtyInteractionActive;
  final bool isCtrlActive;
  final VoidCallback onCtrlToggle;
  final ValueChanged<String>? onSendRawPtyInput;

  const ExtraKeyboardRow({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.history,
    required this.onHistoryUp,
    required this.onHistoryDown,
    required this.onTabComplete,
    required this.onPageUp,
    required this.onPageDown,
    required this.isPtyInteractionActive,
    required this.isCtrlActive,
    required this.onCtrlToggle,
    this.onSendRawPtyInput,
  });

  void _insertText(String val) {
    final text = controller.text;
    final selection = controller.selection;
    if (selection.isValid) {
      final start = selection.start;
      final end = selection.end;
      final newText = text.replaceRange(start, end, val);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + val.length),
      );
    } else {
      controller.text += val;
    }
  }

  void _moveCursorLeft() {
    final selection = controller.selection;
    if (selection.isValid &&
        selection.isCollapsed &&
        selection.baseOffset > 0) {
      controller.selection = TextSelection.collapsed(
        offset: selection.baseOffset - 1,
      );
    }
  }

  void _moveCursorRight() {
    final text = controller.text;
    final selection = controller.selection;
    if (selection.isValid &&
        selection.isCollapsed &&
        selection.baseOffset < text.length) {
      controller.selection = TextSelection.collapsed(
        offset: selection.baseOffset + 1,
      );
    }
  }

  void _pasteFromClipboard(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    final message = TerminalSessionService().handlePasteText(text);
    if (message.isNotEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _insertText(text);
  }

  void _showHistoryBottomSheet(BuildContext context) {
    if (history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No command history yet'),
          duration: Duration(milliseconds: 700),
          behavior: SnackBarBehavior.floating,
          width: 220,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  'Command History',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const Divider(color: Color(0xFF2D2D2D), height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final cmd = history[history.length - 1 - index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        cmd,
                        style: const TextStyle(
                          color: Color(0xFF5AF78E),
                          fontFamily: 'monospace',
                          fontSize: 14,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.keyboard_arrow_right,
                        color: Colors.white24,
                        size: 16,
                      ),
                      onTap: () {
                        controller.text = cmd;
                        controller.selection = TextSelection.collapsed(
                          offset: cmd.length,
                        );
                        Navigator.pop(context);
                        focusNode.requestFocus();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          _buildButton(context, 'ESC', () {
            if (isPtyInteractionActive) {
              onSendRawPtyInput?.call('\u001B');
            } else {
              controller.clear();
            }
          }),
          _buildButton(
            context,
            isCtrlActive ? 'CTRL*' : 'CTRL',
            onCtrlToggle,
            textColor: isCtrlActive ? const Color(0xFF5AF78E) : Colors.white,
            backgroundColor: isCtrlActive ? const Color(0x223EEA7A) : null,
          ),
          _buildButton(context, 'ALT', () {}),
          _buildButton(context, 'TAB', () {
            if (isPtyInteractionActive) {
              onSendRawPtyInput?.call('\t');
            } else {
              onTabComplete();
            }
          }),
          _buildButton(context, 'HOME', () {
            if (isPtyInteractionActive) {
              onSendRawPtyInput?.call('\u001B[H');
            } else {
              controller.selection = const TextSelection.collapsed(offset: 0);
            }
          }),
          _buildButton(context, 'END', () {
            if (isPtyInteractionActive) {
              onSendRawPtyInput?.call('\u001B[F');
            } else {
              controller.selection = TextSelection.collapsed(
                offset: controller.text.length,
              );
            }
          }),
          _buildButton(context, 'PGUP', onPageUp),
          _buildButton(context, 'PGDN', onPageDown),
          _buildButton(context, 'PASTE', () => _pasteFromClipboard(context)),
          _buildButton(context, 'HIST', () => _showHistoryBottomSheet(context)),
          _buildButton(context, '/', () => _insertText('/')),
          _buildButton(context, '-', () => _insertText('-')),
          _buildButton(context, 'UP', () {
            if (isPtyInteractionActive) {
              onSendRawPtyInput?.call('\u001B[A');
            } else {
              onHistoryUp();
            }
          }),
          _buildButton(context, 'DN', () {
            if (isPtyInteractionActive) {
              onSendRawPtyInput?.call('\u001B[B');
            } else {
              onHistoryDown();
            }
          }),
          _buildButton(context, 'LT', () {
            if (isPtyInteractionActive) {
              onSendRawPtyInput?.call('\u001B[D');
            } else {
              _moveCursorLeft();
            }
          }),
          _buildButton(context, 'RT', () {
            if (isPtyInteractionActive) {
              onSendRawPtyInput?.call('\u001B[C');
            } else {
              _moveCursorRight();
            }
          }),
        ],
      ),
    );
  }

  Widget _buildButton(
    BuildContext context,
    String label,
    VoidCallback onPressed, {
    Color textColor = Colors.white,
    Color? backgroundColor,
  }) {
    return InkWell(
      onTap: () {
        onPressed();
        focusNode.requestFocus();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        color: backgroundColor,
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
