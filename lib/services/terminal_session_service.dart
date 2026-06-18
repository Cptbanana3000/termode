import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'preview_service.dart';
import 'runtime_bootstrap_service.dart';

class _HelperReloadState {
  final StringBuffer buffer = StringBuffer();
  final Completer<bool>? completer;
  final bool appendFailureOnFailure;
  Timer? timeout;
  int? statusCode;
  bool sawInternalOutput = false;
  bool completed = false;

  _HelperReloadState({this.completer, required this.appendFailureOnFailure});
}

class TerminalSessionService extends ChangeNotifier {
  static final TerminalSessionService _instance =
      TerminalSessionService._internal();
  factory TerminalSessionService() => _instance;

  final List<TerminalSession> _sessions = [];
  int _activeSessionIndex = 0;
  int _sessionCounter = 0;
  PersistenceService _persistenceService = PersistenceService();
  final Map<String, _HelperReloadState> _pendingHelperReloads = {};
  final Map<String, StringBuffer> _orphanHelperMarkerBuffers = {};

  static const String _helperReloadFailureMessage =
      'Helper reload failed. Run: reload-helpers';
  static const String helperReloadBeginMarker =
      '__TERMODE_HELPER_RELOAD_BEGIN__';
  static const String helperReloadStatusMarker =
      '__TERMODE_HELPER_RELOAD_STATUS__';
  static const String helperReloadEndMarker = '__TERMODE_HELPER_RELOAD_END__';

  List<TerminalSession> get sessions => List.unmodifiable(_sessions);
  int get activeSessionIndex => _activeSessionIndex;
  TerminalSession get activeSession => _sessions[_activeSessionIndex];

  // Delegation helpers referencing the active session
  List<TerminalLine> get lines => activeSession.lines;
  List<String> get commandHistory => activeSession.commandHistory;
  int get historyIndex => activeSession.historyIndex;
  VirtualFileSystem get vfs => activeSession.vfs;
  int get maxScrollbackLines => SettingsService().maxScrollbackLines;
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
    _trimSessionScrollback(session);
  }

  void _touchSession(TerminalSession session) {
    session.updatedAt = DateTime.now();
  }

  void _trimSessionScrollback(TerminalSession session) {
    final maxLines = SettingsService().maxScrollbackLines;
    if (session.lines.length > maxLines) {
      session.lines.removeRange(0, session.lines.length - maxLines);
    }
  }

  void _appendSessionLine(TerminalSession session, String text, LineType type) {
    session.lines.add(TerminalLine(text: text, type: type));
    session.isLastLinePty = false;
    _touchSession(session);
    _trimSessionScrollback(session);
  }

  void _recordHistory(TerminalSession session, String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return;
    if (session.commandHistory.isEmpty ||
        session.commandHistory.last != trimmed) {
      session.commandHistory.add(trimmed);
    }
    const maxHistory = 500;
    if (session.commandHistory.length > maxHistory) {
      session.commandHistory.removeRange(
        0,
        session.commandHistory.length - maxHistory,
      );
    }
    session.historyIndex = session.commandHistory.length;
    _touchSession(session);
  }

  void addSession() {
    _createNewSession();
    _activeSessionIndex = _sessions.length - 1;
    notifyListeners();
    saveState();
    _autoStartShellForActiveSession();
  }

  void removeSession(int index) {
    if (index < 0 || index >= _sessions.length) return;
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
    if (_sessions.isEmpty) {
      _createNewSession();
      _activeSessionIndex = 0;
    }
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

  Future<void> stopAllPtys() async {
    final channel = const MethodChannel('com.termode/native_shell');
    for (final session in _sessions) {
      if (session.isShellActive) {
        try {
          await channel.invokeMethod('ptyStop', {'sessionId': session.id});
        } catch (e) {
          debugPrint('Error stopping PTY during dispose: $e');
        }
        session.isShellActive = false;
      }
      if (session.isRealPtyActive) {
        try {
          await channel.invokeMethod('realPtyStop', {'sessionId': session.id});
        } catch (e) {
          debugPrint('Error stopping real PTY during dispose: $e');
        }
        session.isRealPtyActive = false;
        session.isPtyInteractionActive = false;
      }
    }
    notifyListeners();
    await saveState();
  }

  String tabsOutput() {
    final sb = StringBuffer('=== Tabs ===\n');
    for (var i = 0; i < _sessions.length; i++) {
      final session = _sessions[i];
      final marker = i == _activeSessionIndex ? '*' : ' ';
      final mode = session.isRealPtyActive
          ? 'REAL PTY'
          : session.isShellActive
          ? 'PTY'
          : 'NORMAL';
      sb.writeln('$marker ${i + 1}. ${session.name} [$mode]');
    }
    return sb.toString().trimRight();
  }

  Future<String> newTab() async {
    addSession();
    return 'Created ${activeSession.name}.';
  }

  String closeActiveTab() {
    final oldName = activeSession.name;
    removeSession(_activeSessionIndex);
    return 'Closed $oldName.';
  }

  String renameActiveTab(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'Usage: tab-rename <name>';
    }
    activeSession.name = trimmed;
    _touchSession(activeSession);
    notifyListeners();
    saveState();
    return 'Renamed tab to $trimmed.';
  }

  String switchTab(int oneBasedIndex) {
    final index = oneBasedIndex - 1;
    if (index < 0 || index >= _sessions.length) {
      return 'tab-switch: invalid tab number';
    }
    setActiveSession(index);
    return 'Switched to ${activeSession.name}.';
  }

  String sessionInfo() {
    final session = activeSession;
    final mode = session.isRealPtyActive
        ? 'REAL PTY'
        : session.isShellActive
        ? 'PTY'
        : 'NORMAL';
    final pty = session.isRealPtyActive || session.isShellActive
        ? 'running'
        : 'stopped';
    final sb = StringBuffer();
    sb.writeln('Session: ${session.name}');
    sb.writeln('Mode: $mode');
    sb.writeln('PTY: $pty');
    sb.writeln('Scrollback: ${session.lines.length} / $maxScrollbackLines');
    sb.writeln('History: ${session.commandHistory.length}');
    sb.writeln(
      'Preferred cwd: ${session.preferredWorkingDirectory ?? "(home)"}',
    );
    sb.writeln(
      'Tracked cwd: ${session.lastKnownWorkingDirectory ?? "(unknown)"}',
    );
    sb.writeln('Created: ${session.createdAt.toIso8601String()}');
    sb.write('Updated: ${session.updatedAt.toIso8601String()}');
    return sb.toString();
  }

  void setPreferredWorkingDirectory(String directory) {
    activeSession.preferredWorkingDirectory = directory;
    activeSession.lastKnownWorkingDirectory = directory;
    _touchSession(activeSession);
    notifyListeners();
    saveState();
  }

  Future<String> _safeInitialWorkingDirectory(TerminalSession session) async {
    final home = Directory(await _runtimeHomePath()).absolute;
    if (!home.existsSync()) {
      home.createSync(recursive: true);
    }
    final preferred = session.preferredWorkingDirectory;
    if (preferred == null || preferred.trim().isEmpty) {
      return home.path;
    }
    final dir = Directory(preferred).absolute;
    final dirPath = _normalizeHostPath(dir.path);
    final homePath = _normalizeHostPath(home.path);
    final safe =
        dirPath == homePath ||
        dirPath.startsWith('$homePath${Platform.pathSeparator}');
    if (safe && dir.existsSync()) {
      return dir.path;
    }
    session.preferredWorkingDirectory = home.path;
    session.lastKnownWorkingDirectory = home.path;
    return home.path;
  }

  Future<String> _runtimeHomePath() async {
    const channel = MethodChannel('com.termode/native_shell');
    try {
      final Map<dynamic, dynamic>? paths = await channel.invokeMethod(
        'getPaths',
      );
      final home = paths?['home']?.toString();
      if (home != null && home.isNotEmpty) return home;
    } catch (_) {
      // Fall back to Dart runtime paths below.
    }
    try {
      final paths = await RuntimeBootstrapService().getPaths();
      return paths['home']!;
    } catch (_) {
      return Directory.current.path;
    }
  }

  Future<void> sendCdToRealPty(String directory) async {
    final channel = const MethodChannel('com.termode/native_shell');
    final quoted = _shellQuote(directory);
    await channel.invokeMethod('realPtySend', {
      'sessionId': activeSession.id,
      'text': 'cd $quoted\n',
    });
    activeSession.lastKnownWorkingDirectory = directory;
    _touchSession(activeSession);
    await saveState();
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  String _normalizeHostPath(String path) {
    if (Platform.pathSeparator == r'\') {
      return path.replaceAll('/', r'\');
    }
    return path.replaceAll(r'\', '/');
  }

  void clearActiveTranscript() {
    activeSession.lines.clear();
    activeSession.ansiBuffer.clearScreen();
    _touchSession(activeSession);
    notifyListeners();
    saveState();
  }

  String historyOutput({bool clear = false}) {
    if (clear) {
      activeSession.commandHistory.clear();
      activeSession.historyIndex = 0;
      _touchSession(activeSession);
      saveState();
      return 'History cleared.';
    }
    if (activeSession.commandHistory.isEmpty) {
      return 'No command history.';
    }
    final sb = StringBuffer('=== History ===\n');
    for (var i = 0; i < activeSession.commandHistory.length; i++) {
      sb.writeln('${i + 1}. ${activeSession.commandHistory[i]}');
    }
    return sb.toString().trimRight();
  }

  String sessionDoctor({bool verbose = false}) {
    final activeValid =
        _activeSessionIndex >= 0 && _activeSessionIndex < _sessions.length;
    final duplicateIds =
        _sessions.map((s) => s.id).toSet().length != _sessions.length;
    final scrollbackOk = _sessions.every(
      (session) => session.lines.length <= maxScrollbackLines,
    );
    final historyOk = _sessions.every(
      (session) => session.commandHistory.length <= 500,
    );
    final ptyOk = !duplicateIds;
    final healthy = activeValid && ptyOk && scrollbackOk && historyOk;
    final sb = StringBuffer();
    sb.writeln('=== Session Doctor ===');
    sb.writeln('Sessions: ${_sessions.length}');
    sb.writeln('Active: ${activeValid ? _activeSessionIndex + 1 : "INVALID"}');
    sb.writeln('PTY: ${ptyOk ? "OK" : "CHECK"}');
    sb.writeln('Persistence: OK');
    sb.writeln('Scrollback: ${scrollbackOk ? "OK" : "CHECK"}');
    sb.writeln('History: ${historyOk ? "OK" : "CHECK"}');
    if (verbose) {
      sb.writeln('Max Scrollback: $maxScrollbackLines');
      for (final session in _sessions) {
        sb.writeln(
          '${session.id}: ${session.name}, lines=${session.lines.length}, history=${session.commandHistory.length}',
        );
      }
    }
    sb.write('Overall: ${healthy ? "HEALTHY" : "UNHEALTHY"}');
    return sb.toString();
  }

  String keyboardTestOutput() {
    final mode = activeSession.isPtyInteractionActive ? 'REAL PTY' : 'NORMAL';
    return '=== Keyboard Test ===\n'
        'CTRL: available\n'
        'ESC: available\n'
        'TAB: available\n'
        'Arrows: available\n'
        'Paste: available\n'
        'Mode: $mode';
  }

  String keyboardSettingsOutput() {
    final settings = SettingsService();
    return '=== Keyboard Settings ===\n'
        'CTRL toggle: available\n'
        'Paste warning: ${settings.pasteWarningThreshold}\n'
        'Paste limit: ${settings.pasteHardLimit}\n'
        'Mode: ${activeSession.isPtyInteractionActive ? "REAL PTY" : "NORMAL"}';
  }

  String terminalSettingsOutput() {
    final settings = SettingsService();
    return 'Font size: ${settings.fontSize.toStringAsFixed(1)}\n'
        'Line height: ${settings.lineHeight.toStringAsFixed(2)}\n'
        'Cursor: ${settings.cursorStyle}\n'
        'Blink: ${settings.blinkingCursor ? "yes" : "no"}\n'
        'Scrollback: ${settings.maxScrollbackLines}\n'
        'ANSI renderer: ${settings.enableAnsiRenderer ? "on" : "off"}\n'
        'ANSI debug: ${settings.ansiDebugMode ? "on" : "off"}';
  }

  String inputTestOutput() {
    return '=== Input Test ===\n'
        '- Type text\n'
        '- Backspace\n'
        '- Press Enter\n'
        '- Try arrows\n'
        '- Try Ctrl+C\n'
        '- Try paste';
  }

  String ansiTestOutput() {
    return '=== ANSI Test ===\n'
        'normal text\n'
        '\u001B[1mbold text\u001B[0m\n'
        '\u001B[4munderline text\u001B[0m\n'
        '\u001B[31mred\u001B[0m \u001B[32mgreen\u001B[0m \u001B[94mbright blue\u001B[0m\n'
        '\u001B[43mbackground yellow\u001B[0m\n'
        '\u001B[38;5;208m256-color orange\u001B[0m\n'
        '\u001B[38;2;120;200;255mtruecolor sky\u001B[0m\n'
        'wrap sample: abcdefghijklmnopqrstuvwxyz abcdefghijklmnopqrstuvwxyz';
  }

  String resizeInfoOutput() {
    final session = activeSession;
    return 'Cols: ${session.lastResizeCols ?? session.ansiBuffer.cols}\n'
        'Rows: ${session.lastResizeRows ?? session.ansiBuffer.visibleRows}\n'
        'Last resize: ${session.lastResizeAt?.toIso8601String() ?? "never"}\n'
        'PTY notified: ${session.lastResizeNotified ? "yes" : "no"}';
  }

  String scrollTestOutput(int requestedLines) {
    final count = requestedLines.clamp(1, 5000).toInt();
    final width = count < 1000 ? 3 : 4;
    return List.generate(
      count,
      (index) => '${(index + 1).toString().padLeft(width, '0')} test line',
    ).join('\n');
  }

  String handlePasteText(String text) {
    final settings = SettingsService();
    if (text.isEmpty) return 'Clipboard is empty.';
    if (text.length > settings.pasteHardLimit) {
      activeSession.blockedPasteText = null;
      return 'Paste too large. Limit: ${settings.pasteHardLimit} chars.';
    }
    if (text.length > settings.pasteWarningThreshold) {
      activeSession.blockedPasteText = text;
      return 'Paste is large: ${text.length} chars.\nUse paste-force to send it.';
    }
    activeSession.blockedPasteText = null;
    return '';
  }

  Future<String> pasteForce() async {
    final text = activeSession.blockedPasteText;
    if (text == null || text.isEmpty) return 'No blocked paste.';
    activeSession.blockedPasteText = null;
    if (activeSession.isPtyInteractionActive) {
      await sendRawRealPtyInput(text);
      return 'Pasted ${text.length} chars.';
    }
    return 'Paste ready: ${text.length} chars.';
  }

  Future<String> copyLastOutputLine() async {
    for (final line in activeSession.lines.reversed) {
      if (line.type != LineType.input && line.text.trim().isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: line.text));
        return 'Copied 1 line.';
      }
    }
    return 'No output line to copy.';
  }

  Future<String> copySessionLines([int? requested]) async {
    final maxLines = requested == null ? 100 : requested.clamp(1, 5000).toInt();
    final transcript = activeSession.lines
        .map((line) => line.text)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final selected = transcript.length > maxLines
        ? transcript.sublist(transcript.length - maxLines)
        : transcript;
    await Clipboard.setData(ClipboardData(text: selected.join('\n')));
    return 'Copied ${selected.length} lines.';
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
        'runtime-doctor',
        'runtime-capabilities',
        'runtime-exec-test',
        'runtime-plan',
        'runtime-candidates',
        'runtime-candidate',
        'runtime-decision',
        'runtime-risks',
        'runtime-next',
        'runtime-research-doctor',
        'bundled-runtime-info',
        'bundled-runtime-test',
        'bundled-runtime-doctor',
        'bundled-runtime-paths',
        'bundled-runtime-plan',
        'native-tool',
        'js-proof',
        'js-engine-candidates',
        'js-engine-candidate',
        'js-engine-decision',
        'js-engine-risks',
        'js-engine-next',
        'js-engine-doctor',
        'quickjs',
        'duktape',
        'localhost-doctor',
        'localhost-capabilities',
        'port-check',
        'http-test',
        'preview-url',
        'preview',
        'preview-copy',
        'preview-open',
        'preview-check',
        'preview-history',
        'preview-clear-history',
        'preview-settings',
        'preview-doctor',
        'preview-help',
        'devserver-help',
        'storage-status',
        'storage',
        'storage-link',
        'storage-unlink',
        'storage-list',
        'storage-read',
        'storage-write',
        'storage-delete',
        'storage-mkdir',
        'storage-projects',
        'storage-test',
        'storage-help',
        'workspace',
        'workspace-info',
        'workspace-init',
        'workspace-list',
        'workspace-cd',
        'workspace-open',
        'workspace-remove',
        'workspace-doctor',
        'workspace-import-storage',
        'workspace-export-storage',
        'pwd-host',
        'host-pwd',
        'host-ls',
        'host-cat',
        'host-write',
        'host-touch',
        'host-mkdir',
        'host-rm',
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
        'tabs',
        'tab-new',
        'tab-close',
        'tab-rename',
        'tab-switch',
        'session-info',
        'session-clear',
        'session-doctor',
        'history',
        'keyboard-test',
        'keyboard-settings',
        'terminal-settings',
        'input-test',
        'ansi-test',
        'resize-info',
        'scroll-test',
        'copy-last',
        'copy-session',
        'paste-force',
      };

      if (hostCommands.contains(firstToken)) {
        _recordHistory(activeSession, trimmed);
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
        saveState();
        return;
      }

      // Not a host command, forward directly to PTY
      final channel = const MethodChannel('com.termode/native_shell');
      try {
        _recordHistory(activeSession, command);
        _clearHelperReloadState(activeSession.id);
        await channel.invokeMethod('realPtySend', {
          'sessionId': activeSession.id,
          'text': command,
        });
        saveState();
      } catch (e) {
        _appendSessionLine(
          activeSession,
          'Error sending PTY input: $e',
          LineType.error,
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
    _appendSessionLine(activeSession, '$currentPrompt$command', LineType.input);

    if (trimmed.isNotEmpty) {
      _recordHistory(activeSession, trimmed);

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
          _appendSessionLine(
            activeSession,
            result.output,
            result.isError ? LineType.error : LineType.output,
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
    clearActiveTranscript();
  }

  // Persistence Operations

  Future<void> saveState() async {
    final settings = SettingsService();
    for (final session in _sessions) {
      _trimSessionScrollback(session);
    }
    final state = {
      'settings': settings.toJson(),
      'activeSessionIndex': _activeSessionIndex,
      'sessions': _sessions.map((s) => s.toJson()).toList(),
      'previewHistory': PreviewService().historyToJson(),
    };
    await _persistenceService.saveState(state);
  }

  Future<void> loadPersistedState() async {
    final state = await _persistenceService.loadState();
    if (state != null) {
      try {
        final settingsJson = state['settings'] as Map<String, dynamic>?;
        SettingsService().loadFromJson(settingsJson);

        PreviewService().loadHistoryFromJson(
          state['previewHistory'] as List<dynamic>?,
        );

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
            _trimSessionScrollback(session);
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
    for (final state in _pendingHelperReloads.values) {
      state.timeout?.cancel();
    }
    _pendingHelperReloads.clear();
    _orphanHelperMarkerBuffers.clear();
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
        for (final session in _sessions) {
          session.isRealPtyActive = false;
          session.isPtyInteractionActive = false;
          session.isShellActive = false;
          session.isExecutingNativeCommand = false;
          session.isLastLinePty = false;
          session.isPtyInitializing = false;
          session.hasAttemptedAutoStart = false;
          _trimSessionScrollback(session);
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
      final filtered = _filterHelperReloadOutput(sessionId, sanitized);
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

      final markerFiltered = _filterOrphanHelperReloadMarkers(
        sessionId,
        sanitized,
      );
      if (markerFiltered == null) {
        notifyListeners();
        return;
      }
      sanitized = markerFiltered;
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
    _touchSession(session);
    _trimSessionScrollback(session);
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
    session.lastExitMessage = '[shell exited]';
    _appendSessionLine(session, '[shell exited]', LineType.output);
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
      _clearHelperReloadState(activeSession.id);
      await channel.invokeMethod('realPtySendRaw', {
        'sessionId': activeSession.id,
        'text': text,
      });
    } catch (e) {
      _appendSessionLine(
        activeSession,
        'Error sending raw PTY input: $e',
        LineType.error,
      );
      notifyListeners();
    }
  }

  static const shellHelperReloadCommand =
      'printf "$helperReloadBeginMarker\\n"; '
      'if [ -f "\$TERMODE_USR/termode-shell-helpers.sh" ]; then '
      'if . "\$TERMODE_USR/termode-shell-helpers.sh" >/dev/null 2>&1; then '
      'printf "$helperReloadStatusMarker:0\\n"; '
      'else '
      'printf "$helperReloadStatusMarker:1\\n"; '
      'fi; '
      'else '
      'printf "$helperReloadStatusMarker:1\\n"; '
      'fi; '
      'printf "$helperReloadEndMarker\\n"\n';

  Future<bool> reloadShellHelpersForSession(
    String sessionId, {
    bool silent = false,
    bool waitForCompletion = false,
    Duration completionTimeout = const Duration(seconds: 2),
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
    final completer = waitForCompletion ? Completer<bool>() : null;
    try {
      if (silent || waitForCompletion) {
        _startHelperReloadTracking(
          sessionId,
          completer: completer,
          appendFailureOnFailure: !waitForCompletion,
        );
      }
      final bool? success = await channel.invokeMethod('realPtySendRaw', {
        'sessionId': sessionId,
        'text': shellHelperReloadCommand,
      });
      final reloaded = success ?? true;
      if (!reloaded) {
        _completeHelperReload(sessionId, false, appendFailure: false);
        return false;
      }
      if (waitForCompletion && completer != null) {
        return completer.future.timeout(
          completionTimeout,
          onTimeout: () {
            _completeHelperReload(sessionId, false);
            return false;
          },
        );
      }
      return reloaded;
    } catch (e) {
      _completeHelperReload(sessionId, false, appendFailure: false);
      debugPrint('Error reloading shell helpers: $e');
      return false;
    }
  }

  void _startHelperReloadTracking(
    String sessionId, {
    Completer<bool>? completer,
    required bool appendFailureOnFailure,
  }) {
    _clearHelperReloadState(sessionId);
    _pendingHelperReloads[sessionId] = _HelperReloadState(
      completer: completer,
      appendFailureOnFailure: appendFailureOnFailure,
    );
    _startHelperReloadTimeout(sessionId, _pendingHelperReloads[sessionId]!);
  }

  void _clearHelperReloadState(String sessionId) {
    final state = _pendingHelperReloads.remove(sessionId);
    state?.timeout?.cancel();
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

  List<String> get _helperReloadMarkers => const [
    helperReloadBeginMarker,
    helperReloadStatusMarker,
    helperReloadEndMarker,
  ];

  String _stripCompleteHelperReloadMarkerLines(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final hadTrailingNewline = normalized.endsWith('\n');
    final parts = normalized.split('\n');
    if (hadTrailingNewline && parts.isNotEmpty && parts.last.isEmpty) {
      parts.removeLast();
    }
    final kept = parts.where((line) {
      return !_helperReloadMarkers.any(line.contains);
    }).toList();
    if (kept.isEmpty) {
      return '';
    }
    return '${kept.join('\n')}${hadTrailingNewline ? '\n' : ''}';
  }

  bool _isHelperReloadMarkerPrefix(String text) {
    if (text.isEmpty) {
      return false;
    }
    return _helperReloadMarkers.any((marker) {
      final maxLen = text.length < marker.length ? text.length : marker.length;
      for (var len = 6; len <= maxLen; len++) {
        if (marker.startsWith(text.substring(text.length - len))) {
          return true;
        }
      }
      return false;
    });
  }

  String? _filterOrphanHelperReloadMarkers(String sessionId, String text) {
    final existing = _orphanHelperMarkerBuffers[sessionId];
    final combined = existing == null ? text : '${existing.toString()}$text';
    _orphanHelperMarkerBuffers.remove(sessionId);

    if (_helperReloadMarkers.any(combined.contains)) {
      final stripped = _stripCompleteHelperReloadMarkerLines(combined);
      if (stripped.isEmpty || _isHelperReloadMarkerPrefix(stripped)) {
        if (_isHelperReloadMarkerPrefix(stripped)) {
          _orphanHelperMarkerBuffers[sessionId] = StringBuffer(stripped);
        }
        return null;
      }
      return stripped;
    }

    if (_isHelperReloadMarkerPrefix(combined)) {
      _orphanHelperMarkerBuffers[sessionId] = StringBuffer(combined);
      return null;
    }

    return combined;
  }

  bool _isClearHelperReloadShellError(String text) {
    final lowered = text.toLowerCase();
    return lowered.contains('cannot open') ||
        lowered.contains('can\'t open') ||
        lowered.contains('permission denied') ||
        lowered.contains('syntax error') ||
        lowered.contains('not found');
  }

  void _startHelperReloadTimeout(String sessionId, _HelperReloadState state) {
    state.timeout?.cancel();
    state.timeout = Timer(const Duration(seconds: 2), () {
      _completeHelperReload(sessionId, false);
    });
  }

  void _completeHelperReload(
    String sessionId,
    bool success, {
    bool appendFailure = true,
  }) {
    final state = _pendingHelperReloads.remove(sessionId);
    if (state == null || state.completed) {
      return;
    }
    state.completed = true;
    state.timeout?.cancel();
    if (state.completer != null && !state.completer!.isCompleted) {
      state.completer!.complete(success);
    }
    if (!success && appendFailure && state.appendFailureOnFailure) {
      final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
      if (sessionIndex != -1) {
        _appendHelperReloadFailure(_sessions[sessionIndex]);
        notifyListeners();
      }
    }
  }

  String? _filterHelperReloadOutput(String sessionId, String text) {
    final state = _pendingHelperReloads[sessionId];
    if (state == null) {
      return text;
    }

    final normalizedText = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    if (_isClearHelperReloadShellError(normalizedText)) {
      state.statusCode = 1;
      _startHelperReloadTimeout(sessionId, state);
    }

    state.sawInternalOutput = true;
    final previousLength = state.buffer.length;
    state.buffer.write(normalizedText);
    _startHelperReloadTimeout(sessionId, state);

    final buffered = state.buffer.toString();
    final statusMatch = RegExp(
      '(?:^|\\n)\\s*${RegExp.escape(helperReloadStatusMarker)}\\s*:?\\s*(\\d+)\\s*(?=\\n|\$)',
    ).firstMatch(buffered);
    if (statusMatch != null) {
      state.statusCode = int.tryParse(statusMatch.group(1) ?? '1') ?? 1;
    }
    final endMatch = RegExp(
      '(?:^|\\n)\\s*${RegExp.escape(helperReloadEndMarker)}\\s*(?=\\n|\$)',
    ).firstMatch(buffered);
    if (endMatch != null) {
      final afterEndIndex = endMatch.end;
      var remainderStart = afterEndIndex - previousLength;
      if (remainderStart < 0) {
        remainderStart = 0;
      }
      if (remainderStart > normalizedText.length) {
        remainderStart = normalizedText.length;
      }
      _completeHelperReload(sessionId, state.statusCode == 0);
      var remainder = normalizedText.substring(remainderStart);
      remainder = remainder.replaceFirst(RegExp(r'^\n'), '');
      if (remainder.isEmpty || remainder.split('\n').every(_isPromptOnlyLine)) {
        return null;
      }
      return _stripCompleteHelperReloadMarkerLines(remainder);
    }

    return null;
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
    _appendSessionLine(session, _helperReloadFailureMessage, LineType.error);
    session.isLastLinePty = false;
  }

  Future<void> sendRealPtyCtrlC() async {
    final channel = const MethodChannel('com.termode/native_shell');
    try {
      await channel.invokeMethod('realPtySendCtrlC', {
        'sessionId': activeSession.id,
      });
    } catch (e) {
      _appendSessionLine(
        activeSession,
        'Error sending Ctrl-C to PTY: $e',
        LineType.error,
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
      _appendSessionLine(
        activeSession,
        'Error sending Ctrl-D to PTY: $e',
        LineType.error,
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
    session.lastExitMessage = '[shell exited]';
    _appendSessionLine(session, '[shell exited]', LineType.output);
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
        'workingDirectory': await _safeInitialWorkingDirectory(session),
      });
      if (started == true) {
        session.lastKnownWorkingDirectory = await _safeInitialWorkingDirectory(
          session,
        );
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
      _appendSessionLine(_sessions[sessionIndex], error, LineType.error);
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
    _touchSession(session);
    _trimSessionScrollback(session);
    notifyListeners();
  }
}
