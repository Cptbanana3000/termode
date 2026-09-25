import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/terminal_line.dart';
import '../models/terminal_session.dart';
import '../services/settings_service.dart';
import '../services/terminal_session_service.dart';
import 'extra_keyboard_row.dart';
import 'terminal_view.dart';

/// Styling configuration for [TermodeEmbeddableTerminal].
class TerminalThemeData {
  final Color? backgroundColor;
  final Color? textColor;
  final Color? primaryColor;
  final Color? cursorColor;
  final String fontFamily;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const TerminalThemeData({
    this.backgroundColor,
    this.textColor,
    this.primaryColor,
    this.cursorColor,
    this.fontFamily = 'monospace',
    this.fontSize = 13.0,
    this.padding = const EdgeInsets.all(8.0),
  });
}

/// External programmatic controller for [TermodeEmbeddableTerminal].
///
/// Allows external host applications (such as Calypso IDE) to send commands,
/// send raw keyboard input, manage working directories, and inspect session state.
class TermodeTerminalController extends ChangeNotifier {
  final TerminalSessionService _sessionService = TerminalSessionService();
  _TermodeEmbeddableTerminalState? _state;

  void _attach(_TermodeEmbeddableTerminalState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  /// Requests keyboard focus on the embedded terminal.
  void requestFocus() {
    _state?._focusNode.requestFocus();
  }

  /// Active terminal session.
  TerminalSession get activeSession => _sessionService.activeSession;

  /// Active list of terminal output lines.
  List<TerminalLine> get lines => _sessionService.lines;

  /// Whether the real PTY interactive shell is currently active.
  bool get isPtyActive => activeSession.isPtyInteractionActive;

  /// Programmatically submits and executes a command string.
  Future<void> execute(String command) async {
    await _sessionService.executeCommand(command);
    if (_state?.widget.onCommandExecuted != null) {
      final active = _sessionService.activeSession;
      final lastLine = active.lines.isNotEmpty ? active.lines.last.text : '';
      _state!.widget.onCommandExecuted!(command, lastLine);
    }
    notifyListeners();
  }

  /// Programmatically sends raw input or escape sequences to the terminal.
  Future<void> sendRawInput(String text) async {
    if (activeSession.isPtyInteractionActive) {
      await _sessionService.sendRawRealPtyInput(text);
    } else {
      await _sessionService.executeCommand(text);
    }
    notifyListeners();
  }

  /// Sends a SIGINT (Ctrl+C) to the running PTY process.
  void sendCtrlC() {
    _sessionService.sendRealPtyCtrlC();
    notifyListeners();
  }

  /// Sends an EOF (Ctrl+D) to the running PTY process.
  void sendCtrlD() {
    _sessionService.sendRealPtyCtrlD();
    notifyListeners();
  }

  /// Clears the active session transcript history.
  void clear() {
    _sessionService.clearActiveTranscript();
    notifyListeners();
  }

  /// Updates the preferred working directory for the active session.
  void setWorkingDirectory(String path) {
    activeSession.preferredWorkingDirectory = path;
    activeSession.lastKnownWorkingDirectory = path;
    notifyListeners();
  }

  /// Switches the active session by index.
  void setActiveSession(int index) {
    _sessionService.setActiveSession(index);
    notifyListeners();
  }
}

/// An embeddable terminal component designed to be dropped directly into
/// external IDEs (such as Calypso IDE) or multi-panel Flutter layouts.
///
/// Features:
/// - In-process execution: Zero intents, zero SSH keys, zero background daemons.
/// - Full programmatic control via [TermodeTerminalController].
/// - Configurable tabs: Host IDE can manage tabs externally or enable built-in tabs.
/// - Soft accessory keyboard row for mobile terminal navigation (ESC, CTRL, TAB, arrow keys).
/// - Dynamic working directory: binds directly to any project folder on disk.
/// - Customizable styling via [TerminalThemeData].
class TermodeEmbeddableTerminal extends StatefulWidget {
  final String? initialWorkingDirectory;
  final bool showTabs;
  final bool showExtraKeyboardRow;
  final void Function(String command, String output)? onCommandExecuted;
  final Color? backgroundColor;
  final TerminalThemeData? theme;
  final TermodeTerminalController? controller;

  const TermodeEmbeddableTerminal({
    super.key,
    this.initialWorkingDirectory,
    this.showTabs = false,
    this.showExtraKeyboardRow = true,
    this.onCommandExecuted,
    this.backgroundColor,
    this.theme,
    this.controller,
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
  Offset? _pointerDownPosition;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    if (widget.initialWorkingDirectory != null) {
      _sessionService.activeSession.preferredWorkingDirectory =
          widget.initialWorkingDirectory;
      _sessionService.activeSession.lastKnownWorkingDirectory =
          widget.initialWorkingDirectory;
    }
    _sessionService.addListener(_scrollToBottom);
    _textController.addListener(_onTextChanged);
    _setupFocusNodeKeyListener();
  }

  @override
  void didUpdateWidget(TermodeEmbeddableTerminal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(this);
    }
    if (widget.initialWorkingDirectory != null &&
        widget.initialWorkingDirectory != oldWidget.initialWorkingDirectory) {
      _sessionService.activeSession.preferredWorkingDirectory =
          widget.initialWorkingDirectory;
      _sessionService.activeSession.lastKnownWorkingDirectory =
          widget.initialWorkingDirectory;
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
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
        _sessionService.sendRawRealPtyInput('\n');
      } else {
        await _sessionService.executeCommand(text);
      }
    } else {
      await _sessionService.executeCommand(text);
    }
    _textController.clear();
    _focusNode.requestFocus();
    if (widget.onCommandExecuted != null) {
      final lastLine = active.lines.isNotEmpty ? active.lines.last.text : '';
      widget.onCommandExecuted!(text, lastLine);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _sessionService,
      builder: (context, _) {
        final session = _sessionService.activeSession;
        final settings = SettingsService();
        final effectiveBg = widget.theme?.backgroundColor ??
            widget.backgroundColor ??
            settings.backgroundColor;

        return Container(
          color: effectiveBg,
          padding: widget.theme?.padding ?? EdgeInsets.zero,
          child: Column(
            children: [
              if (widget.showTabs) _buildTabBar(settings),
              Expanded(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (event) {
                    _pointerDownPosition = event.position;
                  },
                  onPointerMove: (event) {
                    if (_pointerDownPosition != null) {
                      final distance =
                          (event.position - _pointerDownPosition!).distance;
                      if (distance > 10.0) {
                        _pointerDownPosition = null;
                      }
                    }
                  },
                  onPointerUp: (event) {
                    if (_pointerDownPosition != null) {
                      final difference =
                          (event.position - _pointerDownPosition!).distance;
                      if (difference < 10.0) {
                        Future.delayed(
                          const Duration(milliseconds: 50),
                          () {
                            _focusNode.requestFocus();
                            SystemChannels.textInput.invokeMethod(
                              'TextInput.show',
                            );
                          },
                        );
                      }
                    }
                    _pointerDownPosition = null;
                  },
                  child: TerminalView(
                    lines: session.lines,
                    scrollController: _scrollController,
                    showInput: !session.isExecutingNativeCommand,
                    textController: _textController,
                    focusNode: _focusNode,
                    prompt: _sessionService.currentPrompt,
                    onSubmit: _handleCommandSubmit,
                  ),
                ),
              ),
              if (widget.showExtraKeyboardRow)
                ExtraKeyboardRow(
                  controller: _textController,
                  focusNode: _focusNode,
                  history: _sessionService.commandHistory,
                  onHistoryUp: () {
                    if (session.isPtyInteractionActive) return;
                    final cmd = _sessionService.navigateHistoryUp();
                    if (cmd != null) {
                      _textController.text = cmd;
                      _textController.selection =
                          TextSelection.collapsed(offset: cmd.length);
                    }
                  },
                  onHistoryDown: () {
                    if (session.isPtyInteractionActive) return;
                    final cmd = _sessionService.navigateHistoryDown();
                    if (cmd != null) {
                      _textController.text = cmd;
                      _textController.selection =
                          TextSelection.collapsed(offset: cmd.length);
                    }
                  },
                  onTabComplete: () {},
                  onPageUp: () {},
                  onPageDown: () {},
                  isPtyInteractionActive: session.isPtyInteractionActive,
                  isCtrlActive: _isCtrlActive,
                  onCtrlToggle: () {
                    setState(() {
                      _isCtrlActive = !_isCtrlActive;
                    });
                  },
                  onSendRawPtyInput: (val) {
                    _sessionService.sendRawRealPtyInput(val);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabBar(SettingsService settings) {
    final activeColor = widget.theme?.primaryColor ?? settings.primaryColor;
    final textColor = widget.theme?.textColor ?? settings.textColor;

    return Container(
      height: 36,
      color: widget.theme?.backgroundColor ?? settings.backgroundColor,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _sessionService.sessions.length,
        itemBuilder: (context, index) {
          final s = _sessionService.sessions[index];
          final isActive = index == _sessionService.activeSessionIndex;
          return InkWell(
            onTap: () => _sessionService.setActiveSession(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? activeColor : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                s.name,
                style: TextStyle(
                  color: isActive ? textColor : Colors.grey,
                  fontSize: widget.theme?.fontSize != null
                      ? (widget.theme!.fontSize - 1)
                      : 12,
                  fontFamily: widget.theme?.fontFamily,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
