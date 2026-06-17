import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'localhost_service.dart';
import 'workspace_service.dart';

/// Result of a preview command, ready to be wrapped into a CommandResult.
class PreviewActionResult {
  final String output;
  final bool isError;

  const PreviewActionResult(this.output, {this.isError = false});
}

/// Result of validating a port argument.
class PortValidation {
  final int? port;
  final String? error;

  const PortValidation({this.port, this.error});

  bool get isValid => error == null && port != null;
}

/// A single remembered preview URL.
class PreviewHistoryEntry {
  final String url;
  final int port;
  final DateTime createdAt;
  final String? workspace;
  final String? sessionId;

  const PreviewHistoryEntry({
    required this.url,
    required this.port,
    required this.createdAt,
    this.workspace,
    this.sessionId,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'port': port,
    'createdAt': createdAt.toIso8601String(),
    if (workspace != null) 'workspace': workspace,
    if (sessionId != null) 'sessionId': sessionId,
  };

  static PreviewHistoryEntry? fromJson(Map<String, dynamic> json) {
    final url = json['url']?.toString();
    final port = json['port'] is int
        ? json['port'] as int
        : int.tryParse(json['port']?.toString() ?? '');
    if (url == null || url.isEmpty || port == null) {
      return null;
    }
    return PreviewHistoryEntry(
      url: url,
      port: port,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      workspace: json['workspace']?.toString(),
      sessionId: json['sessionId']?.toString(),
    );
  }
}

/// Prepares Termode for a future dev-server preview workflow.
///
/// This service only generates, copies, opens, remembers, and diagnoses
/// localhost preview URLs. It deliberately ships no runtime: no Node.js, npm,
/// Vite, or in-app WebView panel yet.
class PreviewService {
  static final PreviewService _instance = PreviewService._internal();
  factory PreviewService() => _instance;
  PreviewService._internal();

  static const String defaultHost = '127.0.0.1';
  static const String defaultScheme = 'http';
  static const int defaultPort = 3000;
  static const int historyLimit = 10;
  static const Set<String> allowedOpenSchemes = {'http', 'https'};
  static const String _channelName = 'com.termode/native_shell';

  // Dependencies default to the real singletons but can be overridden in tests.
  LocalhostService get _localhostService =>
      _localhostOverride ?? LocalhostService();
  WorkspaceService get _workspaceService =>
      _workspaceOverride ?? WorkspaceService();

  LocalhostService? _localhostOverride;
  WorkspaceService? _workspaceOverride;

  final List<PreviewHistoryEntry> _history = [];

  // --------------------------------------------------------------------------
  // Shared port / URL helpers
  // --------------------------------------------------------------------------

  /// Validates a port argument, reusing the canonical localhost parser.
  PortValidation validatePort(String? input) {
    final error = _localhostService.validatePortArg(input);
    if (error != null) {
      return PortValidation(error: error);
    }
    return PortValidation(port: _localhostService.parsePort(input!.trim()));
  }

  /// Builds a clean preview URL for the given port.
  String normalizePreviewUrl(int port) =>
      '$defaultScheme://$defaultHost:$port';

  /// Normalizes an http-test target (port or URL) into a full URI string.
  String normalizeHttpTestUrl(String input) =>
      _localhostService.normalizeHttpTarget(input).toString();

  /// Whether a URL is safe to hand to an external Android activity.
  bool isSafeOpenUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      return false;
    }
    return allowedOpenSchemes.contains(uri.scheme.toLowerCase());
  }

  // --------------------------------------------------------------------------
  // History
  // --------------------------------------------------------------------------

  List<PreviewHistoryEntry> get history => List.unmodifiable(_history);

  void _remember(
    int port,
    String url, {
    String? workspace,
    String? sessionId,
  }) {
    _history.removeWhere((entry) => entry.url == url);
    _history.insert(
      0,
      PreviewHistoryEntry(
        url: url,
        port: port,
        createdAt: DateTime.now(),
        workspace: (workspace == null || workspace == '(none)')
            ? null
            : workspace,
        sessionId: sessionId,
      ),
    );
    if (_history.length > historyLimit) {
      _history.removeRange(historyLimit, _history.length);
    }
  }

  List<int> _recentPorts() {
    final ports = <int>[];
    for (final entry in _history) {
      if (!ports.contains(entry.port)) {
        ports.add(entry.port);
      }
    }
    return ports;
  }

  List<Map<String, dynamic>> historyToJson() =>
      _history.map((entry) => entry.toJson()).toList();

  void loadHistoryFromJson(List<dynamic>? json) {
    _history.clear();
    if (json == null) {
      return;
    }
    for (final item in json) {
      if (item is Map) {
        final entry = PreviewHistoryEntry.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (entry != null && _history.length < historyLimit) {
          _history.add(entry);
        }
      }
    }
  }

  @visibleForTesting
  void resetForTesting({
    LocalhostService? localhost,
    WorkspaceService? workspace,
  }) {
    _history.clear();
    _localhostOverride = localhost;
    _workspaceOverride = workspace;
  }

  // --------------------------------------------------------------------------
  // External open
  // --------------------------------------------------------------------------

  Future<bool> _nativeOpenUrl(String url) async {
    final result = await const MethodChannel(
      _channelName,
    ).invokeMethod<bool>('openUrl', {'url': url});
    return result ?? false;
  }

  /// Attempts to open [url] in an external Android app.
  Future<PreviewActionResult> openExternally(String url) async {
    if (!isSafeOpenUrl(url)) {
      return const PreviewActionResult(
        'Refused to open URL: only http and https are allowed.',
        isError: true,
      );
    }
    try {
      final ok = await _nativeOpenUrl(url);
      if (ok) {
        return PreviewActionResult('Opening preview: $url');
      }
      return PreviewActionResult(
        'Could not open external app for $url.\n'
        'No browser may be installed.',
        isError: true,
      );
    } on MissingPluginException {
      return PreviewActionResult(
        'External open is unavailable on this platform.\nURL: $url',
        isError: true,
      );
    } on PlatformException catch (e) {
      return PreviewActionResult(
        'Could not open external app for $url.\n${e.message ?? e.code}',
        isError: true,
      );
    } catch (e) {
      return PreviewActionResult(
        'Could not open external app for $url.\n$e',
        isError: true,
      );
    }
  }

  // --------------------------------------------------------------------------
  // Commands
  // --------------------------------------------------------------------------

  /// `preview` — compact preview status.
  String statusOutput() {
    final lastUrl = _history.isNotEmpty ? _history.first.url : null;
    final recentPorts = _recentPorts();
    final tipPort = _history.isNotEmpty ? _history.first.port : defaultPort;
    final sb = StringBuffer();
    sb.writeln('Preview support: available');
    sb.writeln('Last preview: ${lastUrl ?? 'none'}');
    sb.writeln(
      'Recent ports: ${recentPorts.isEmpty ? 'none' : recentPorts.join(', ')}',
    );
    sb.write('Tip: preview-open $tipPort');
    return sb.toString();
  }

  /// `preview-copy <port>` — copy preview URL to the clipboard.
  Future<PreviewActionResult> copy(String? portArg, {String? sessionId}) async {
    final validation = validatePort(portArg);
    if (!validation.isValid) {
      return PreviewActionResult(validation.error!, isError: true);
    }
    final port = validation.port!;
    final url = normalizePreviewUrl(port);
    final workspace = await _safeWorkspaceName();
    _remember(port, url, workspace: workspace, sessionId: sessionId);

    final copied = await _copyToClipboard(url);
    if (copied) {
      return PreviewActionResult('Copied preview URL.\n$url');
    }
    return PreviewActionResult('$url\nClipboard unavailable.');
  }

  /// `preview-open <port> [--force]` — open the preview URL externally.
  Future<PreviewActionResult> open(
    String? portArg, {
    bool force = false,
    String? sessionId,
  }) async {
    final validation = validatePort(portArg);
    if (!validation.isValid) {
      return PreviewActionResult(validation.error!, isError: true);
    }
    final port = validation.port!;
    final url = normalizePreviewUrl(port);

    if (!force) {
      final portResult = await _localhostService.checkPort(port);
      if (!portResult.isOpen) {
        return PreviewActionResult(
          'Port $port is closed.\n'
          'Start your dev server first.\n'
          'Use preview-open $port --force to open anyway.',
        );
      }
    }

    final workspace = await _safeWorkspaceName();
    _remember(port, url, workspace: workspace, sessionId: sessionId);
    return openExternally(url);
  }

  /// `preview-check <port>` — combined port + HTTP probe for a preview URL.
  Future<PreviewActionResult> check(String? portArg) async {
    final validation = validatePort(portArg);
    if (!validation.isValid) {
      return PreviewActionResult(validation.error!, isError: true);
    }
    final port = validation.port!;
    final url = normalizePreviewUrl(port);

    final portResult = await _localhostService.checkPort(port);
    final httpResult = await _localhostService.testHttp(Uri.parse(url));

    final sb = StringBuffer();
    sb.writeln('Port: ${portResult.isOpen ? 'open' : 'closed'}');
    sb.writeln('HTTP: ${httpResult.reached ? 'reachable' : 'unreachable'}');
    sb.write('URL: $url');
    return PreviewActionResult(sb.toString());
  }

  /// `preview-history` — list recent preview URLs.
  String historyOutput() {
    if (_history.isEmpty) {
      return 'No preview history.';
    }
    final sb = StringBuffer('=== Preview History ===\n');
    for (var i = 0; i < _history.length; i++) {
      final entry = _history[i];
      final workspace = entry.workspace != null ? ' (${entry.workspace})' : '';
      sb.writeln('${i + 1}. ${entry.url}$workspace');
    }
    return sb.toString().trimRight();
  }

  /// `preview-clear-history` — drop all remembered preview URLs.
  String clearHistory() {
    final count = _history.length;
    _history.clear();
    if (count == 0) {
      return 'Preview history already empty.';
    }
    return 'Cleared $count preview ${count == 1 ? 'entry' : 'entries'}.';
  }

  /// `preview-settings` — show preview defaults.
  String settingsOutput() {
    final sb = StringBuffer();
    sb.writeln('Default host: $defaultHost');
    sb.writeln('Default scheme: $defaultScheme');
    sb.writeln('Port check before open: yes');
    sb.write('History limit: $historyLimit');
    return sb.toString();
  }

  /// `preview-doctor [--verbose]` — diagnose preview capabilities.
  Future<PreviewActionResult> doctor({bool verbose = false}) async {
    // URL generation, port checking, and history are always available in this
    // build. HTTP client and clipboard/external-open are probed at runtime.
    final clipboardStatus = await _clipboardStatus();
    final externalOpenStatus = _externalOpenStatus();
    final httpTestOk = _httpClientAvailable();

    final coreOk = httpTestOk; // url gen, port check, history are always OK
    final String overall;
    if (!coreOk) {
      overall = 'UNHEALTHY';
    } else if (clipboardStatus == 'OK' && externalOpenStatus == 'OK') {
      overall = 'HEALTHY';
    } else {
      overall = 'LIMITED';
    }

    final sb = StringBuffer();
    sb.writeln('=== Preview Doctor ===');
    sb.writeln('URL generation: OK');
    sb.writeln('Clipboard: $clipboardStatus');
    sb.writeln('External open: $externalOpenStatus');
    sb.writeln('Port check: OK');
    sb.writeln('HTTP test: ${httpTestOk ? 'OK' : 'MISSING'}');
    sb.writeln('History: OK');
    if (verbose) {
      sb.writeln();
      sb.writeln('Details:');
      sb.writeln('  Default host: $defaultHost');
      sb.writeln('  Default scheme: $defaultScheme');
      sb.writeln('  Allowed open schemes: ${allowedOpenSchemes.join(', ')}');
      sb.writeln('  Native channel: $_channelName (openUrl)');
      sb.writeln('  Platform: ${_platformLabel()}');
      sb.writeln(
        '  External open path: ${Platform.isAndroid ? 'Android ACTION_VIEW intent' : 'not available off Android'}',
      );
      sb.writeln('  History entries: ${_history.length} / $historyLimit');
      sb.writeln('  Sample URL: ${normalizePreviewUrl(defaultPort)}');
    }
    sb.write('Overall: $overall');
    return PreviewActionResult(sb.toString());
  }

  /// `preview-help` — explain commands and the future dev-server workflow.
  String help() {
    return '=== Termode Preview Workflow ===\n'
        'Preview commands generate, copy, open, remember, and diagnose\n'
        'localhost preview URLs. They prepare for future Vite/Next.js dev\n'
        'servers. Termode does not ship Node.js or npm yet.\n\n'
        'Commands:\n'
        '  preview                 - Show compact preview status\n'
        '  preview-url <port>      - Print http://127.0.0.1:<port>\n'
        '  preview-copy <port>     - Copy a preview URL to the clipboard\n'
        '  preview-open <port>     - Open a preview URL (checks the port first)\n'
        '  preview-open <port> --force - Open without checking the port\n'
        '  preview-check <port>    - Combine port-check and http-test\n'
        '  preview-history         - Show recent preview URLs\n'
        '  preview-clear-history   - Clear preview history\n'
        '  preview-settings        - Show preview defaults\n'
        '  preview-doctor          - Diagnose preview capabilities\n'
        '  preview-doctor --verbose - Show channel and platform details\n'
        '  preview-help            - Show this help reference\n\n'
        'Future Dev Server Workflow:\n'
        '  1. Node proof\n'
        '  2. npm proof\n'
        '  3. Vite dev server\n'
        '  4. In-app preview panel\n'
        '  5. CalypsoIDE preview integration later';
  }

  // --------------------------------------------------------------------------
  // Probes
  // --------------------------------------------------------------------------

  Future<String> _safeWorkspaceName() async {
    try {
      return await _workspaceService.currentWorkspaceName();
    } catch (_) {
      return '(none)';
    }
  }

  Future<bool> _copyToClipboard(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _clipboardStatus() async {
    try {
      await Clipboard.getData(Clipboard.kTextPlain);
      return 'OK';
    } catch (_) {
      return 'unknown';
    }
  }

  String _externalOpenStatus() {
    return Platform.isAndroid ? 'OK' : 'unknown';
  }

  bool _httpClientAvailable() {
    try {
      final client = HttpClient();
      client.close(force: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _platformLabel() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
