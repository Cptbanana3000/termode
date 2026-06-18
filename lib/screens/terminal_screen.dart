import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/terminal_session_service.dart';
import '../services/settings_service.dart';
import '../services/command_catalog.dart';
import '../widgets/terminal_view.dart';
import '../widgets/extra_keyboard_row.dart';
import 'settings_screen.dart';
import 'help_screen.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final TerminalSessionService _sessionService = TerminalSessionService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isCtrlActive = false;
  Offset? _pointerDownPosition;

  @override
  void initState() {
    super.initState();
    _sessionService.addListener(_scrollToBottom);
    _textController.addListener(_onTextChanged);
    _setupFocusNodeKeyListener();
  }

  @override
  void dispose() {
    _sessionService.removeListener(_scrollToBottom);
    _textController.removeListener(_onTextChanged);
    _sessionService.dispose();
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

        if (isControlPressed || _isCtrlActive) {
          if (key == LogicalKeyboardKey.keyC) {
            _sessionService.sendRealPtyCtrlC();
            if (_isCtrlActive) {
              setState(() {
                _isCtrlActive = false;
              });
            }
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.keyD) {
            _sessionService.sendRealPtyCtrlD();
            if (_isCtrlActive) {
              setState(() {
                _isCtrlActive = false;
              });
            }
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.keyL) {
            _sessionService.sendRawRealPtyInput('\u000c');
            if (_isCtrlActive) {
              setState(() {
                _isCtrlActive = false;
              });
            }
            return KeyEventResult.handled;
          }
        }

        if (key == LogicalKeyboardKey.escape) {
          _sessionService.sendRawRealPtyInput('\u001B');
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.tab) {
          _sessionService.sendRawRealPtyInput('\t');
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          _sessionService.sendRawRealPtyInput('\u001B[A');
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _sessionService.sendRawRealPtyInput('\u001B[B');
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          _sessionService.sendRawRealPtyInput('\u001B[D');
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          _sessionService.sendRawRealPtyInput('\u001B[C');
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.home) {
          _sessionService.sendRawRealPtyInput('\u001B[H');
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.end) {
          _sessionService.sendRawRealPtyInput('\u001B[F');
          return KeyEventResult.handled;
        }
      }

      return KeyEventResult.ignored;
    };
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final position = _scrollController.position;
        final isNearBottom =
            position.maxScrollExtent - position.pixels < 80 ||
            _sessionService.activeSession.isPtyInteractionActive;
        if (!isNearBottom) return;
        _scrollController.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _onHistoryUp() {
    if (_sessionService.activeSession.isPtyInteractionActive) return;
    final command = _sessionService.navigateHistoryUp();
    if (command != null) {
      _textController.text = command;
      _textController.selection = TextSelection.collapsed(
        offset: command.length,
      );
    }
  }

  void _onHistoryDown() {
    if (_sessionService.activeSession.isPtyInteractionActive) return;
    final command = _sessionService.navigateHistoryDown();
    if (command != null) {
      _textController.text = command;
      _textController.selection = TextSelection.collapsed(
        offset: command.length,
      );
    }
  }

  void _onTabComplete() {
    if (_sessionService.activeSession.isPtyInteractionActive) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final parts = text.split(RegExp(r'\s+'));
    final lastWord = parts.last.toLowerCase();

    final matches = kTermodeCommands
        .where((cmd) => cmd.startsWith(lastWord))
        .toList();

    if (matches.length == 1) {
      parts[parts.length - 1] = matches[0];
      final newText = parts.join(' ');
      _textController.text = '$newText ';
      _textController.selection = TextSelection.collapsed(
        offset: _textController.text.length,
      );
    }
  }

  void _pageUp() {
    if (_scrollController.hasClients) {
      final viewportHeight = _scrollController.position.viewportDimension;
      final newOffset = (_scrollController.offset - viewportHeight).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        newOffset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _pageDown() {
    if (_scrollController.hasClients) {
      final viewportHeight = _scrollController.position.viewportDimension;
      final newOffset = (_scrollController.offset + viewportHeight).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        newOffset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildTabBar(BuildContext context, SettingsService settings) {
    return Container(
      color: const Color(0xFF1E1E1E),
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _sessionService.sessions.length,
              itemBuilder: (context, index) {
                final session = _sessionService.sessions[index];
                final isActive = index == _sessionService.activeSessionIndex;
                final badgeText = session.isPtyInteractionActive
                    ? 'REAL PTY'
                    : (session.isRealPtyActive ? 'PTY RUNNING' : 'NORMAL');
                final badgeColor = session.isPtyInteractionActive
                    ? const Color(0xFF5AF78E)
                    : (session.isRealPtyActive
                          ? const Color(0xFFFFB000)
                          : Colors.white30);
                final badgeBgColor = session.isPtyInteractionActive
                    ? const Color(0xFF5AF78E).withValues(alpha: 0.2)
                    : (session.isRealPtyActive
                          ? const Color(0xFFFFB000).withValues(alpha: 0.2)
                          : Colors.white10);
                final badgeBorderColor = session.isPtyInteractionActive
                    ? const Color(0xFF5AF78E)
                    : (session.isRealPtyActive
                          ? const Color(0xFFFFB000)
                          : Colors.transparent);

                return GestureDetector(
                  onTap: () {
                    _sessionService.setActiveSession(index);
                    _scrollToBottom();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isActive
                          ? settings.backgroundColor
                          : const Color(0xFF1E1E1E),
                      border: Border(
                        bottom: BorderSide(
                          color: isActive
                              ? settings.primaryColor
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            session.name,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white54,
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: badgeBgColor,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: badgeBorderColor,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            badgeText,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 8,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_sessionService.sessions.length > 1) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              _sessionService.removeSession(index);
                            },
                            child: Icon(
                              Icons.close,
                              size: 12,
                              color: isActive ? Colors.white70 : Colors.white38,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white, size: 20),
            onPressed: () {
              _sessionService.addSession();
              _scrollToBottom();
            },
            tooltip: 'New Tab',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: settings.backgroundColor,
          appBar: settings.immersiveMode
              ? null
              : AppBar(
                  title: const Text(
                    'Termode',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: const Color(0xFF1E1E1E),
                  elevation: 0,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.help_outline, color: Colors.white),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HelpScreen(),
                          ),
                        );
                      },
                      tooltip: 'Help',
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings, color: Colors.white),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsScreen(),
                          ),
                        );
                      },
                      tooltip: 'Settings',
                    ),
                  ],
                ),
          body: SafeArea(
            child: Stack(
              children: [
                ListenableBuilder(
                  listenable: _sessionService,
                  builder: (context, _) {
                    return Column(
                      children: [
                        if (!settings.immersiveMode) ...[
                          _buildTabBar(context, settings),
                          const Divider(height: 1, color: Color(0xFF2D2D2D)),
                        ],
                        Expanded(
                          child: Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: (event) {
                              _pointerDownPosition = event.position;
                            },
                            onPointerMove: (event) {
                              if (_pointerDownPosition != null) {
                                final distance =
                                    (event.position - _pointerDownPosition!)
                                        .distance;
                                if (distance > 10.0) {
                                  _pointerDownPosition = null;
                                }
                              }
                            },
                            onPointerUp: (event) {
                              if (_pointerDownPosition != null) {
                                final difference =
                                    (event.position - _pointerDownPosition!)
                                        .distance;
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
                              lines: _sessionService.lines,
                              scrollController: _scrollController,
                              showInput: !_sessionService
                                  .activeSession
                                  .isExecutingNativeCommand,
                              textController: _textController,
                              focusNode: _focusNode,
                              prompt: _sessionService.currentPrompt,
                              onSubmit: (val) {
                                _sessionService.executeCommand(val);
                              },
                            ),
                          ),
                        ),
                        if (_sessionService
                            .activeSession
                            .isExecutingNativeCommand) ...[
                          const Divider(height: 1, color: Color(0xFF2D2D2D)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            color: Colors.black26,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      settings.primaryColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Executing native command...',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _sessionService.cancelActiveNativeCommand();
                                  },
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'KILL',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Divider(height: 1, color: Color(0xFF2D2D2D)),
                        ExtraKeyboardRow(
                          controller: _textController,
                          focusNode: _focusNode,
                          history: _sessionService.commandHistory,
                          onHistoryUp: _onHistoryUp,
                          onHistoryDown: _onHistoryDown,
                          onTabComplete: _onTabComplete,
                          onPageUp: _pageUp,
                          onPageDown: _pageDown,
                          isPtyInteractionActive: _sessionService
                              .activeSession
                              .isPtyInteractionActive,
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
                    );
                  },
                ),
                if (settings.immersiveMode) ...[
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            _sessionService.activeSession.isPtyInteractionActive
                            ? const Color(0xFF5AF78E).withValues(alpha: 0.2)
                            : Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color:
                              _sessionService
                                  .activeSession
                                  .isPtyInteractionActive
                              ? const Color(0xFF5AF78E)
                              : Colors.white24,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _sessionService.activeSession.isPtyInteractionActive
                            ? 'REAL PTY MODE'
                            : (_sessionService.activeSession.isRealPtyActive
                                  ? 'PTY RUNNING'
                                  : 'NORMAL MODE'),
                        style: TextStyle(
                          color:
                              _sessionService
                                  .activeSession
                                  .isPtyInteractionActive
                              ? const Color(0xFF5AF78E)
                              : (_sessionService.activeSession.isRealPtyActive
                                    ? const Color(0xFFFFB000)
                                    : Colors.white54),
                          fontSize: 10,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Opacity(
                      opacity: 0.5,
                      child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        radius: 18,
                        child: IconButton(
                          icon: const Icon(
                            Icons.fullscreen_exit,
                            color: Colors.white,
                            size: 18,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            settings.setImmersiveMode(false);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
