import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings_service.dart';
import '../services/terminal_session_service.dart';
import 'extra_keyboard_row.dart';
import 'terminal_view.dart';

/// An embeddable terminal component designed to be dropped directly into
/// external IDEs (such as Calypso IDE) or multi-panel Flutter layouts.
///
/// Features:
/// - In-process execution: Zero intents, zero SSH keys, zero background daemons.
/// - Configurable tabs: Host IDE can manage tabs externally or enable built-in tabs.
/// - Soft accessory keyboard row for mobile terminal navigation (ESC, CTRL, TAB, arrow keys).
/// - Dynamic working directory: binds directly to any project folder on disk.
class TermodeEmbeddableTerminal extends StatefulWidget {
  final String? initialWorkingDirectory;
  final bool showTabs;
  final bool showExtraKeyboardRow;
  final void Function(String command, String output)? onCommandExecuted;
  final Color? backgroundColor;

  const TermodeEmbeddableTerminal({
    super.key,
    this.initialWorkingDirectory,
    this.showTabs = false,
    this.showExtraKeyboardRow = true,
    this.onCommandExecuted,
    this.backgroundColor,
  });

  @override
  State<TermodeEmbeddableTerminal> createState() =>
      _TermodeEmbeddableTerminalState();
}

class _TermodeEmbeddableTerminalState extends State<TermodeEmbeddableTerminal> {
  final TerminalSessionService _sessionService = TerminalSessionService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isCtrlActive = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialWorkingDirectory != null) {
      _sessionService.activeSession.preferredWorkingDirectory =
          widget.initialWorkingDirectory;
    }
    _sessionService.addListener(_scrollToBottom);
    _textController.addListener(_onTextChanged);
    _setupFocusNodeKeyListener();
  }

  @override
  void dispose() {
    _sessionService.removeListener(_scrollToBottom);
    _textController.removeListener(_onTextChanged);
    _scrollController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_sessionService.activeSession.isPtyInteractionActive && _isCtrlActive) {
      final text = _textController.text;
      if (text.isNotEmpty) {
        final lastChar = text.characters.last.toLowerCase();
        if (lastChar == 'c') {
          _sessionService.sendRealPtyCtrlC();
        } else if (lastChar == 'd') {
          _sessionService.sendRealPtyCtrlD();
        } else if (lastChar == 'l') {
          _sessionService.sendRawRealPtyInput('\u000c');
        } else {
          _sessionService.sendRawRealPtyInput(lastChar);
        }
        _textController.clear();
        setState(() {
          _isCtrlActive = false;
        });
      }
    }
  }

  void _setupFocusNodeKeyListener() {
    _focusNode.onKeyEvent = (FocusNode node, KeyEvent event) {
      if (!_sessionService.activeSession.isPtyInteractionActive) {
        return KeyEventResult.ignored;
      }

      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        final key = event.logicalKey;
        final isControlPressed = HardwareKeyboard.instance.isControlPressed;

        if (isControlPressed) {
          if (key == LogicalKeyboardKey.keyC) {
            _sessionService.sendRealPtyCtrlC();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.keyD) {
            _sessionService.sendRealPtyCtrlD();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.keyL) {
            _sessionService.sendRawRealPtyInput('\u000c');
            return KeyEventResult.handled;
          }
        }

        if (key == LogicalKeyboardKey.arrowUp) {
          _sessionService.sendRawRealPtyInput('\x1b[A');
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.arrowDown) {
          _sessionService.sendRawRealPtyInput('\x1b[B');
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.arrowRight) {
          _sessionService.sendRawRealPtyInput('\x1b[C');
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.arrowLeft) {
          _sessionService.sendRawRealPtyInput('\x1b[D');
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.home) {
          _sessionService.sendRawRealPtyInput('\x1b[H');
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.end) {
          _sessionService.sendRawRealPtyInput('\x1b[F');
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.pageUp) {
          _sessionService.sendRawRealPtyInput('\x1b[5~');
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.pageDown) {
          _sessionService.sendRawRealPtyInput('\x1b[6~');
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.tab) {
          _sessionService.sendRawRealPtyInput('\t');
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.escape) {
          _sessionService.sendRawRealPtyInput('\x1b');
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _handleCommandSubmit(String text) async {
    final active = _sessionService.activeSession;
    if (active.isPtyInteractionActive) {
      if (text.isEmpty) {
        _sessionService.sendRealPtyInput('\n');
      } else {
        await _sessionService.executeCommand(text);
      }
    } else {
      await _sessionService.executeCommand(text);
    }
    _textController.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _sessionService,
      builder: (context, _) {
        final session = _sessionService.activeSession;
        final settings = SettingsService();

        return Container(
          color: widget.backgroundColor ?? settings.backgroundColor,
          child: Column(
            children: [
              if (widget.showTabs) _buildTabBar(settings),
              Expanded(
                child: TerminalView(
                  lines: session.lines,
                  scrollController: _scrollController,
                  showInput: !session.isPtyInteractionActive,
                  textController: _textController,
                  focusNode: _focusNode,
                  prompt: session.prompt,
                  onSubmit: _handleCommandSubmit,
                ),
              ),
              if (widget.showExtraKeyboardRow && settings.showExtraKeys)
                ExtraKeyboardRow(
                  onKeyPressed: (key) {
                    if (session.isPtyInteractionActive) {
                      _sessionService.handleExtraKey(key);
                    } else {
                      _textController.text += key;
                    }
                  },
                  onCtrlPressed: () {
                    setState(() {
                      _isCtrlActive = !_isCtrlActive;
                    });
                  },
                  isCtrlActive: _isCtrlActive,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabBar(SettingsService settings) {
    return Container(
      height: 36,
      color: settings.backgroundColor,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _sessionService.sessions.length,
        itemBuilder: (context, index) {
          final s = _sessionService.sessions[index];
          final isActive = s.id == _sessionService.activeSessionId;
          return InkWell(
            onTap: () => _sessionService.switchSession(s.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? settings.cursorColor : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                s.name,
                style: TextStyle(
                  color: isActive ? settings.textColor : Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
