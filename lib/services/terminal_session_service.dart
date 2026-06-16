import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/terminal_line.dart';
import '../models/terminal_session.dart';
import 'command_service.dart';
import 'native_command_service.dart';
import 'virtual_filesystem.dart';
import 'persistence_service.dart';
import 'settings_service.dart';
import 'ansi_parser.dart';

class TerminalSessionService extends ChangeNotifier {
  static final TerminalSessionService _instance =
      TerminalSessionService._internal();
  factory TerminalSessionService() => _instance;

  final List<TerminalSession> _sessions = [];
  int _activeSessionIndex = 0;
  int _sessionCounter = 0;
  PersistenceService _persistenceService = PersistenceService();
  final Map<String, List<String>> _pendingSilentPtyInputs = {};
  final Map<String, StringBuffer> _pendingSilentPtyEchoBuffers = {};
  final Map<String, int> _pendingSilentPtyEchoChunks = {};

  static const String _helperReloadFailureMessage =
      'Helper reload failed. Run: reload-helpers';

  List<TerminalSession> get sessions => List.unmodifiable(_sessions);
  int get activeSessionIndex => _activeSessionIndex;
  TerminalSession get activeSession => _sessions[_activeSessionIndex];

  // Delegation helpers referencing the active session
  List<TerminalLine> get lines => activeSession.lines;
  List<String> get commandHistory => activeSession.commandHistory;
  int get historyIndex => activeSession.historyIndex;
  VirtualFileSystem get vfs => activeSession.vfs;
  String get currentPrompt {
    if (activeSession.isPtyInteractionActive) {
      return '';
    }
    return 'user@termode:${vfs.getPromptPath()}\$ ';
  }

  TerminalSessionService._internal() {
    _createNewSession();
    // Auto-save state when Settings change
    SettingsService().addListener(saveState);

    // Register PTY output event handlers
    const MethodChannel('com.termode/native_shell').setMethodCallHandler((
      call,
    ) async {
      switch (call.method) {
        case 'ptyOutput':
          final args = call.arguments as Map;
          final sessionId = args['sessionId'] as String;
          final output = args['output'] as String;
          appendPtyOutput(sessionId, output);
          break;
        case 'ptyExit':
          final args = call.arguments as Map;
          final sessionId = args['sessionId'] as String;
          _handlePtyExit(sessionId);
          break;
        case 'realPtyOutput':
          final args = call.arguments as Map;
          final sessionId = args['sessionId'] as String;
          final output = args['output'] as String;
          appendRealPtyOutput(sessionId, output);
          break;
        case 'realPtyExit':
          final args = call.arguments as Map;
          final sessionId = args['sessionId'] as String;
          _handleRealPtyExit(sessionId);
          break;
      }
    });
  }

  // Hook to override persistence service (for unit testing)
  set persistenceService(PersistenceService service) {
    _persistenceService = service;
  }

  void _createNewSession() {
    final sessionVfs = VirtualFileSystem();

    final lines = <TerminalLine>[];
    final settings = SettingsService();
    if (settings.showWelcomeBanner) {
      if (settings.showLargeAsciiBanner) {
        lines.addAll([
          TerminalLine(
            text: r' _____                       _ ',
            type: LineType.output,
          ),
          TerminalLine(
            text: r'|_   _|___ ___ _ _ _ ___ ___| |___',
            type: LineType.output,
          ),
          TerminalLine(
            text: r'  | | | -_|  _| | | | . | . |  _| -_|',
            type: LineType.output,
          ),
          TerminalLine(
            text: r'  |_| |___|_| |_____|___|___|_| |___|',
            type: LineType.output,
          ),
          TerminalLine(
            text: r'                                     ',
            type: LineType.output,
          ),
        ]);
      }
      lines.addAll([
        TerminalLine(text: 'Termode v0.9.2', type: LineType.output),
        TerminalLine(
          text: 'Type "help" to get started.',
          type: LineType.output,
        ),
        TerminalLine(
          text: 'Type "runtime-help" for native commands.',
          type: LineType.output,
        ),
        TerminalLine(
          text: 'Type "storage-help" for storage commands.',
          type: LineType.output,
        ),
      ]);
    }

    final session = TerminalSession(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_sessionCounter++}',
      name: 'Session ${_sessions.length + 1}',
      lines: lines,
      commandHistory: [],
      historyIndex: -1,
      vfs: sessionVfs,
    );

    _sessions.add(session);
  }

  void addSession() {
    _createNewSession();
    _activeSessionIndex = _sessions.length - 1;
    notifyListeners();
    saveState();
    _autoStartShellForActiveSession();
  }

  void removeSession(int index) {
    if (_sessions.length <= 1) return; // Keep at least one session
    final session = _sessions[index];
    if (session.isShellActive) {
      try {
        const MethodChannel(
          'com.termode/native_shell',
        ).invokeMethod('ptyStop', {'sessionId': session.id});
      } catch (e) {
        debugPrint('Error stopping experimental shell in removeSession: $e');
      }
    }
    if (session.isRealPtyActive) {
      try {
        const MethodChannel(
          'com.termode/native_shell',
        ).invokeMethod('realPtyStop', {'sessionId': session.id});
      } catch (e) {
        debugPrint('Error stopping real PTY in removeSession: $e');
      }
    }
    _sessions.removeAt(index);
    if (_activeSessionIndex >= _sessions.length) {
      _activeSessionIndex = _sessions.length - 1;
    }
    notifyListeners();
    saveState();
  }

  void setActiveSession(int index) {
    if (index >= 0 && index < _sessions.length) {
      _activeSessionIndex = index;
      notifyListeners();
      saveState();
    }
  }

  Future<void> executeCommand(String command) async {
    final trimmed = command.trim();

    // Intercept host commands if PTY interaction is active
    if (activeSession.isPtyInteractionActive) {
      final parts = trimmed.split(RegExp(r'\s+'));
      final firstToken = parts.isNotEmpty ? parts[0] : '';
      const hostCommands = {
        'pkg',
        'runtime-tools',
        'storage-status',
        'storage-link',
        'storage-unlink',
        'storage-list',
        'storage-read',
        'storage-write',
        'storage-delete',
        'storage-mkdir',
        'storage-test',
        'storage-help',
        'shell-doctor',
        'keyboard-help',
        'real-pty-help',
        'normal-mode',
        'stop-shell',
        'mode',
        'whereami',
        'default-shell',
        'termode-shell',
        'host-help',
        'reload-helpers',
      };

      if (hostCommands.contains(firstToken)) {
        // Log the command locally so it shows on screen
        _appendHostInterceptionOutput(activeSession, '$trimmed\n');

        // Execute host command via CommandService
        final commandService = CommandService(vfs, activeSession.id);
        final result = await commandService.execute(trimmed);

        if (result.shouldClear) {
          activeSession.lines.clear();
          activeSession.ansiBuffer.clearScreen();
        } else if (result.output.isNotEmpty) {
          _appendHostInterceptionOutput(
            activeSession,
            '${result.output}\n',
            isError: result.isError,
          );
        }

        if (!result.isError &&
            result.shouldReloadShellHelpers &&
            activeSession.isPtyInteractionActive) {
          final reloaded = await reloadShellHelpersForSession(
            activeSession.id,
            silent: true,
          );
          if (reloaded) {
            final message = result.helperReloadSuccessMessage;
            if (message != null && message.isNotEmpty) {
              _appendHostInterceptionOutput(activeSession, '$message\n');
            }
          } else {
            _appendHostInterceptionOutput(
              activeSession,
              '${result.helperReloadFailureMessage ?? 'Helper reload failed. Run: reload-helpers'}\n',
              isError: true,
            );
          }
        }

        // If interaction mode is still active, trigger new PTY prompt
        if (activeSession.isPtyInteractionActive) {
          final channel = const MethodChannel('com.termode/native_shell');
          try {
            await channel.invokeMethod('realPtySend', {
              'sessionId': activeSession.id,
              'text': '',
            });
          } catch (e) {
            debugPrint('Error triggering prompt refresh: $e');
          }
        }
        notifyListeners();
        return;
      }

      // Not a host command, forward directly to PTY
      final channel = const MethodChannel('com.termode/native_shell');
      try {
        _clearSilentPtyInputs(activeSession.id);
        await channel.invokeMethod('realPtySend', {
          'sessionId': activeSession.id,
          'text': command,
        });
      } catch (e) {
        activeSession.lines.add(
          TerminalLine(
            text: 'Error sending PTY input: $e',
            type: LineType.error,
          ),
        );
        notifyListeners();
      }
      return;
    }

    activeSession.isLastLinePty = false;
    if (SettingsService().enableAnsiRenderer) {
      final parser = AnsiParser(activeSession.ansiBuffer);
      parser.write('$currentPrompt$command\n');
    }

    // Guard against concurrent native executions in the same session
    if (activeSession.isExecutingNativeCommand) {
      activeSession.lines.add(
        TerminalLine(
          text:
              'android-shell: A native command is already executing in this session.',
          type: LineType.error,
        ),
      );
      notifyListeners();
      return;
    }

    // Add input prompt (with active directory) to terminal logs
    activeSession.lines.add(
      TerminalLine(text: '$currentPrompt$command', type: LineType.input),
    );

    if (trimmed.isNotEmpty) {
      // Add command to history if it's not identical to the last command
      if (activeSession.commandHistory.isEmpty ||
          activeSession.commandHistory.last != trimmed) {
        activeSession.commandHistory.add(trimmed);
      }
      activeSession.historyIndex = activeSession.commandHistory.length;

      final isNative = trimmed.startsWith('android-shell');
      if (isNative) {
        activeSession.isExecutingNativeCommand = true;
        notifyListeners();
      }

      try {
        // Run execution asynchronously
        final commandService = CommandService(vfs, activeSession.id);
        final result = await commandService.execute(trimmed);

        if (result.shouldClear) {
          activeSession.lines.clear();
          activeSession.ansiBuffer.clearScreen();
        } else if (result.output.isNotEmpty) {
          if (SettingsService().enableAnsiRenderer) {
            final parser = AnsiParser(activeSession.ansiBuffer);
            if (result.isError) {
              parser.write('\u001B[31m${result.output}\u001B[0m\n');
            } else {
              parser.write('${result.output}\n');
            }
          }
          activeSession.lines.add(
            TerminalLine(
              text: result.output,
              type: result.isError ? LineType.error : LineType.output,
            ),
          );
        }
      } finally {
        if (isNative) {
          activeSession.isExecutingNativeCommand = false;
          notifyListeners();
        }
      }
    }

    notifyListeners();
    saveState();
  }

  Future<void> cancelActiveNativeCommand() async {
    if (activeSession.isExecutingNativeCommand) {
      final nativeService = NativeCommandService();
      await nativeService.cancel(activeSession.id);
    }
  }

  String? navigateHistoryUp() {
    if (activeSession.commandHistory.isEmpty) return null;

    if (activeSession.historyIndex > 0) {
      activeSession.historyIndex--;
      return activeSession.commandHistory[activeSession.historyIndex];
    } else if (activeSession.historyIndex == 0) {
      return activeSession.commandHistory[0];
    }

    return null;
  }

  String? navigateHistoryDown() {
    if (activeSession.commandHistory.isEmpty) return null;

    if (activeSession.historyIndex < activeSession.commandHistory.length - 1) {
      activeSession.historyIndex++;
      return activeSession.commandHistory[activeSession.historyIndex];
    } else {
      activeSession.historyIndex = activeSession.commandHistory.length;
      return ''; // Clear input field
    }
  }

  void clearTerminal() {
    activeSession.lines.clear();
    activeSession.ansiBuffer.clearScreen();
    notifyListeners();
    saveState();
  }

  // Persistence Operations

  Future<void> saveState() async {
    final settings = SettingsService();
    final state = {
      'settings': settings.toJson(),
      'activeSessionIndex': _activeSessionIndex,
      'sessions': _sessions.map((s) => s.toJson()).toList(),
    };
    await _persistenceService.saveState(state);
  }

  Future<void> loadPersistedState() async {
    final state = await _persistenceService.loadState();
    if (state != null) {
      try {
        final settingsJson = state['settings'] as Map<String, dynamic>?;
        SettingsService().loadFromJson(settingsJson);

        final sessionsJson = state['sessions'] as List<dynamic>?;
        if (sessionsJson != null && sessionsJson.isNotEmpty) {
          _sessions.clear();
          for (final sessionJson in sessionsJson) {
            final session = TerminalSession.fromJson(
              sessionJson as Map<String, dynamic>,
            );
            session.isRealPtyActive = false;
            session.isPtyInteractionActive = false;
            session.isShellActive = false;
            session.isExecutingNativeCommand = false;
            session.isLastLinePty = false;
            session.isPtyInitializing = false;
            session.hasAttemptedAutoStart = false;
            session.ansiBuffer.clearScreen();
            _sessions.add(session);
          }
          _activeSessionIndex = state['activeSessionIndex'] as int? ?? 0;
          if (_activeSessionIndex >= _sessions.length) {
            _activeSessionIndex = 0;
          }
        }
      } catch (e) {
        debugPrint('Error loading persisted state: $e');
        _sessions.clear();
        _createNewSession();
        _activeSessionIndex = 0;
      }
      notifyListeners();
    }
    await _autoStartShellForActiveSession();
  }

  Future<void> resetState() async {
    await _persistenceService.clearState();

    SettingsService().loadFromJson({'fontSize': 14.0, 'themeColor': 'Green'});

    _sessions.clear();
    _createNewSession();
    _activeSessionIndex = 0;

    notifyListeners();
  }

  void clearMemoryStateForTesting() {
    _sessions.clear();
    _createNewSession();
    _activeSessionIndex = 0;
    _pendingSilentPtyInputs.clear();
    _pendingSilentPtyEchoBuffers.clear();
    _pendingSilentPtyEchoChunks.clear();
    notifyListeners();
  }

  String exportState() {
    final settings = SettingsService();
    final state = {
      'settings': settings.toJson(),
      'activeSessionIndex': _activeSessionIndex,
      'sessions': _sessions.map((s) => s.toJson()).toList(),
    };
    return jsonEncode(state);
  }

  Future<bool> importState(String jsonString) async {
    try {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;

      final settingsJson = decoded['settings'] as Map<String, dynamic>?;
      SettingsService().loadFromJson(settingsJson);

      final sessionsJson = decoded['sessions'] as List<dynamic>?;
      if (sessionsJson != null && sessionsJson.isNotEmpty) {
        _sessions.clear();
        for (final sessionJson in sessionsJson) {
          _sessions.add(
            TerminalSession.fromJson(sessionJson as Map<String, dynamic>),
          );
        }
        _activeSessionIndex = decoded['activeSessionIndex'] as int? ?? 0;
        if (_activeSessionIndex >= _sessions.length) {
          _activeSessionIndex = 0;
        }
      }

      notifyListeners();
      await saveState();
      return true;
    } catch (e) {
      debugPrint('Import state error: $e');
      return false;
    }
  }

  void setShellActive(String sessionId, bool active) {
    final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex != -1) {
      _sessions[sessionIndex].isShellActive = active;
      notifyListeners();
    }
  }

  void setPtyInteractionActive(String sessionId, bool active) {
    final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex != -1) {
      final session = _sessions[sessionIndex];
      session.isPtyInteractionActive = active;
      if (active) {
        session.isLastLinePty = false;
      }
      notifyListeners();
    }
  }

  String sanitizePtyOutput(String text) {
    final settings = SettingsService();
    final debugMode = settings.showControlCharsHex;

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final codeUnit = text.codeUnitAt(i);
      // Useful characters to preserve:
      // - backspace (0x08)
      // - tab (0x09)
      // - newline (0x0A)
      // - carriage return (0x0D)
      // - ESC (0x1B)
      // - normal printable characters (0x20 to 0x7E)
      // - UTF-8 / multi-byte characters (codeUnit >= 0x80)
      if (codeUnit == 0x08 ||
          codeUnit == 0x09 ||
          codeUnit == 0x0A ||
          codeUnit == 0x0D ||
          codeUnit == 0x1B ||
          (codeUnit >= 0x20 && codeUnit != 0x7F)) {
        buffer.writeCharCode(codeUnit);
      } else {
        if (debugMode) {
          final hexStr = codeUnit
              .toRadixString(16)
              .toUpperCase()
              .padLeft(2, '0');
          buffer.write('[0x$hexStr]');
        } else {
          // Filter out (do nothing)
        }
      }
    }
    return buffer.toString();
  }

  void _processPtyOutput(
    String sessionId,
    String text, {
    required bool isRealPty,
  }) {
    final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;
    final session = _sessions[sessionIndex];
    if (isRealPty) {
      session.isRealPtyActive = true;
    } else {
      session.isShellActive = true;
    }

    String sanitized = sanitizePtyOutput(text);

    if (isRealPty) {
      final filtered = _filterSilentPtyOutput(sessionId, sanitized);
      if (filtered == null) {
        notifyListeners();
        return;
      }
      if (filtered == _helperReloadFailureMessage) {
        _appendHelperReloadFailure(session);
        notifyListeners();
        return;
      }
      sanitized = filtered;
    }

    if (SettingsService().enableAnsiRenderer) {
      try {
        final parser = AnsiParser(session.ansiBuffer);
        parser.write(sanitized);
      } catch (e, stackTrace) {
        debugPrint('ANSI parsing error in _processPtyOutput: $e\n$stackTrace');
      }
    }

    // 2. Normalize CRLF and standalone CR to LF
    sanitized = sanitized.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 3. Split by LF
    final parts = sanitized.split('\n');

    // 4. Remove echoed command if applicable
    if (!session.isPtyInteractionActive) {
      final lastSentInput = isRealPty
          ? session.lastSentRealPtyInput
          : session.lastSentPtyInput;
      if (lastSentInput != null) {
        if (parts.isNotEmpty && parts.first == lastSentInput) {
          parts.removeAt(0);
          if (isRealPty) {
            session.lastSentRealPtyInput = null;
          } else {
            session.lastSentPtyInput = null;
          }
        } else if (parts.isNotEmpty && parts.first.startsWith(lastSentInput)) {
          parts[0] = parts[0].substring(lastSentInput.length).trim();
          if (parts[0].isEmpty) {
            parts.removeAt(0);
          }
          if (isRealPty) {
            session.lastSentRealPtyInput = null;
          } else {
            session.lastSentPtyInput = null;
          }
        }
      }
    }

    // 5. Remove trailing shell prompt to avoid duplicate prompts
    if (!session.isPtyInteractionActive) {
      if (parts.isNotEmpty && !text.endsWith('\n') && !text.endsWith('\r')) {
        final lastPart = parts.last;
        final promptRegex = RegExp(r'^(?:.*[\$#]\s*)$');
        if (promptRegex.hasMatch(lastPart)) {
          parts.removeLast();
        }
      }
    }

    if (parts.isEmpty) {
      return;
    }

    if (session.lines.isEmpty) {
      session.lines.add(TerminalLine(text: '', type: LineType.output));
    }

    final lastLine = session.lines.last;
    if (lastLine.type == LineType.output && session.isLastLinePty) {
      session.lines[session.lines.length - 1] = TerminalLine(
        text: lastLine.text + parts.first,
        type: LineType.output,
      );
    } else {
      session.lines.add(TerminalLine(text: parts.first, type: LineType.output));
    }

    for (int i = 1; i < parts.length; i++) {
      session.lines.add(TerminalLine(text: parts[i], type: LineType.output));
    }

    session.isLastLinePty = true;
    notifyListeners();
  }

  void appendPtyOutput(String sessionId, String text) {
    _processPtyOutput(sessionId, text, isRealPty: false);
  }

  void _handlePtyExit(String sessionId) {
    final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;
    final session = _sessions[sessionIndex];
    session.isShellActive = false;
    session.lines.add(
      TerminalLine(
        text: '[Experimental Shell process terminated]',
        type: LineType.output,
      ),
    );
    notifyListeners();
  }

  void setRealPtyActive(String sessionId, bool active) {
    final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex != -1) {
      _sessions[sessionIndex].isRealPtyActive = active;
      notifyListeners();
    }
  }

  void appendRealPtyOutput(String sessionId, String text) {
    _processPtyOutput(sessionId, text, isRealPty: true);
  }

  Future<void> sendRawRealPtyInput(String text) async {
    final channel = const MethodChannel('com.termode/native_shell');
    try {
      _clearSilentPtyInputs(activeSession.id);
      await channel.invokeMethod('realPtySendRaw', {
        'sessionId': activeSession.id,
        'text': text,
      });
    } catch (e) {
      activeSession.lines.add(
        TerminalLine(
          text: 'Error sending raw PTY input: $e',
          type: LineType.error,
        ),
      );
      notifyListeners();
    }
  }

  static const shellHelperReloadCommand =
      '[ -f "\$TERMODE_USR/termode-shell-helpers.sh" ] && . "\$TERMODE_USR/termode-shell-helpers.sh"\n';

  Future<bool> reloadShellHelpersForSession(
    String sessionId, {
    bool silent = false,
  }) async {
    final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) {
      return false;
    }
    final session = _sessions[sessionIndex];
    if (!session.isRealPtyActive) {
      return false;
    }

    final channel = const MethodChannel('com.termode/native_shell');
    try {
      if (silent) {
        _queueSilentPtyInput(sessionId, shellHelperReloadCommand);
      }
      final bool? success = await channel.invokeMethod('realPtySendRaw', {
        'sessionId': sessionId,
        'text': shellHelperReloadCommand,
      });
      final reloaded = success ?? true;
      if (!reloaded) {
        _clearSilentPtyInputs(sessionId);
      }
      return reloaded;
    } catch (e) {
      _clearSilentPtyInputs(sessionId);
      debugPrint('Error reloading shell helpers: $e');
      return false;
    }
  }

  void _queueSilentPtyInput(String sessionId, String command) {
    final normalized = command.trim();
    final pending = _pendingSilentPtyInputs.putIfAbsent(
      sessionId,
      () => <String>[],
    );
    if (!pending.contains(normalized)) {
      pending.add(normalized);
    }
    _pendingSilentPtyEchoBuffers[sessionId] = StringBuffer();
    _pendingSilentPtyEchoChunks[sessionId] = 0;
  }

  void _clearSilentPtyInputs(String sessionId) {
    _pendingSilentPtyInputs.remove(sessionId);
    _pendingSilentPtyEchoBuffers.remove(sessionId);
    _pendingSilentPtyEchoChunks.remove(sessionId);
  }

  String _normalizeForSilentEchoCompare(String text) {
    return text
        .replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), '')
        .replaceAll(RegExp(r'[\s<>]+'), '');
  }

  bool _isPromptOnlyLine(String line) {
    final trimmed = line
        .replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), '')
        .trim();
    if (trimmed.isEmpty) {
      return true;
    }
    return RegExp(r'^[^\n]*[$#]\s*$').hasMatch(trimmed);
  }

  bool _isSilentEchoFragment(String line, String command) {
    final lineNorm = _normalizeForSilentEchoCompare(line);
    if (lineNorm.length < 6) {
      return false;
    }
    final commandNorm = _normalizeForSilentEchoCompare(command);
    return lineNorm.contains(commandNorm) || commandNorm.contains(lineNorm);
  }

  String? _filterSilentPtyOutput(String sessionId, String text) {
    final pending = _pendingSilentPtyInputs[sessionId];
    if (pending == null || pending.isEmpty) {
      return text;
    }

    final command = pending.first;
    final normalizedText = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalizedText.split('\n');
    final kept = <String>[];
    var sawEcho = false;
    var sawPromptOnly = false;

    for (final line in lines) {
      if (_isSilentEchoFragment(line, command)) {
        sawEcho = true;
        continue;
      }
      if (_isPromptOnlyLine(line)) {
        sawPromptOnly = true;
        continue;
      }
      kept.add(line);
    }

    if (kept.isNotEmpty) {
      _clearSilentPtyInputs(sessionId);
      return _helperReloadFailureMessage;
    }

    if (sawEcho) {
      final buffer = _pendingSilentPtyEchoBuffers.putIfAbsent(
        sessionId,
        () => StringBuffer(),
      );
      buffer.write(_normalizeForSilentEchoCompare(normalizedText));
      final chunks = (_pendingSilentPtyEchoChunks[sessionId] ?? 0) + 1;
      _pendingSilentPtyEchoChunks[sessionId] = chunks;

      final commandNorm = _normalizeForSilentEchoCompare(command);
      if (buffer.toString().contains(commandNorm) || chunks >= 3) {
        pending.removeAt(0);
        if (pending.isEmpty) {
          _clearSilentPtyInputs(sessionId);
        }
      }
      return null;
    }

    if (sawPromptOnly) {
      pending.removeAt(0);
      if (pending.isEmpty) {
        _clearSilentPtyInputs(sessionId);
      }
      return null;
    }

    return text;
  }

  void _appendHelperReloadFailure(TerminalSession session) {
    if (SettingsService().enableAnsiRenderer) {
      try {
        final parser = AnsiParser(session.ansiBuffer);
        parser.write('\u001B[31m$_helperReloadFailureMessage\u001B[0m\n');
      } catch (e) {
        debugPrint('ANSI parsing error: $e');
      }
    }
    session.lines.add(
      TerminalLine(text: _helperReloadFailureMessage, type: LineType.error),
    );
    session.isLastLinePty = false;
  }

  Future<void> sendRealPtyCtrlC() async {
    final channel = const MethodChannel('com.termode/native_shell');
    try {
      await channel.invokeMethod('realPtySendCtrlC', {
        'sessionId': activeSession.id,
      });
    } catch (e) {
      activeSession.lines.add(
        TerminalLine(
          text: 'Error sending Ctrl-C to PTY: $e',
          type: LineType.error,
        ),
      );
      notifyListeners();
    }
  }

  Future<void> sendRealPtyCtrlD() async {
    final channel = const MethodChannel('com.termode/native_shell');
    try {
      await channel.invokeMethod('realPtySendCtrlD', {
        'sessionId': activeSession.id,
      });
    } catch (e) {
      activeSession.lines.add(
        TerminalLine(
          text: 'Error sending Ctrl-D to PTY: $e',
          type: LineType.error,
        ),
      );
      notifyListeners();
    }
  }

  void _handleRealPtyExit(String sessionId) {
    final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;
    final session = _sessions[sessionIndex];
    session.isRealPtyActive = false;
    session.isPtyInteractionActive = false;
    session.isLastLinePty = false;
    session.lines.add(
      TerminalLine(
        text: 'Real PTY shell exited. Returned to NORMAL mode.',
        type: LineType.output,
      ),
    );
    notifyListeners();
  }

  Future<bool> startRealPty(
    String sessionId, {
    int cols = 80,
    int rows = 24,
  }) async {
    final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return false;
    final session = _sessions[sessionIndex];
    if (session.isRealPtyActive) return true;
    if (session.isPtyInitializing) return false;

    session.isPtyInitializing = true;
    notifyListeners();

    final channel = const MethodChannel('com.termode/native_shell');
    try {
      final bool? started = await channel.invokeMethod('realPtyStart', {
        'sessionId': sessionId,
        'cols': cols,
        'rows': rows,
      });
      if (started == true) {
        setRealPtyActive(sessionId, true);
        setPtyInteractionActive(sessionId, true);
        return true;
      }
    } catch (e) {
      debugPrint('Error starting real PTY: $e');
    } finally {
      session.isPtyInitializing = false;
      notifyListeners();
    }
    return false;
  }

  void appendErrorToSession(String sessionId, String error) {
    final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex != -1) {
      _sessions[sessionIndex].lines.add(
        TerminalLine(text: error, type: LineType.error),
      );
      notifyListeners();
    }
  }

  Future<void> _autoStartShellForActiveSession() async {
    final settings = SettingsService();
    if (settings.startInRealShell) {
      final session = activeSession;
      if (!session.hasAttemptedAutoStart) {
        session.hasAttemptedAutoStart = true;
        if (!session.isRealPtyActive && !session.isPtyInitializing) {
          final success = await startRealPty(session.id);
          if (!success) {
            appendErrorToSession(
              session.id,
              'Error: Failed to start real PTY shell. Falling back to NORMAL mode.',
            );
            session.isRealPtyActive = false;
            session.isPtyInteractionActive = false;
            notifyListeners();
          }
        }
      }
    }
  }

  void _appendHostInterceptionOutput(
    TerminalSession session,
    String text, {
    bool isError = false,
  }) {
    if (SettingsService().enableAnsiRenderer) {
      try {
        final parser = AnsiParser(session.ansiBuffer);
        if (isError) {
          parser.write('\u001B[31m$text\u001B[0m');
        } else {
          parser.write(text);
        }
      } catch (e) {
        debugPrint('ANSI parsing error: $e');
      }
    }

    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final parts = normalized.split('\n');
    if (parts.isNotEmpty && parts.last.isEmpty && normalized.endsWith('\n')) {
      parts.removeLast();
    }

    for (final part in parts) {
      session.lines.add(
        TerminalLine(
          text: part,
          type: isError ? LineType.error : LineType.output,
        ),
      );
    }
    notifyListeners();
  }
}
