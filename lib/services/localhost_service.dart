import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'workspace_service.dart';

class PortCheckResult {
  final int port;
  final String host;
  final bool isOpen;
  final String? error;
  final int timeoutMs;

  PortCheckResult({
    required this.port,
    required this.host,
    required this.isOpen,
    required this.timeoutMs,
    this.error,
  });
}

class HttpTestResult {
  final Uri uri;
  final bool reached;
  final int? statusCode;
  final String? reasonPhrase;
  final String? contentType;
  final int bytes;
  final Map<String, List<String>> headers;
  final String? error;

  HttpTestResult({
    required this.uri,
    required this.reached,
    required this.bytes,
    required this.headers,
    this.statusCode,
    this.reasonPhrase,
    this.contentType,
    this.error,
  });
}

class LocalhostService {
  static const int defaultPreviewPort = 3000;
  static const int defaultTimeoutMs = 800;

  int? parsePort(String value) {
    final port = int.tryParse(value.trim());
    if (port == null || port < 1 || port > 65535) {
      return null;
    }
    return port;
  }

  String? validatePortArg(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Error: Missing port.\nUsage: port-check <port>';
    }
    if (int.tryParse(value.trim()) == null) {
      return 'Error: Port must be numeric.';
    }
    final port = int.parse(value.trim());
    if (port < 1 || port > 65535) {
      return 'Error: Port must be between 1 and 65535.';
    }
    return null;
  }

  Future<PortCheckResult> checkPort(
    int port, {
    String host = '127.0.0.1',
    int timeoutMs = defaultTimeoutMs,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      return PortCheckResult(
        port: port,
        host: host,
        isOpen: true,
        timeoutMs: timeoutMs,
      );
    } catch (e) {
      return PortCheckResult(
        port: port,
        host: host,
        isOpen: false,
        timeoutMs: timeoutMs,
        error: e.toString(),
      );
    } finally {
      socket?.destroy();
    }
  }

  Uri normalizeHttpTarget(String target) {
    final trimmed = target.trim();
    final port = parsePort(trimmed);
    if (port != null) {
      return Uri.parse('http://127.0.0.1:$port');
    }
    if (trimmed.contains('://')) {
      return Uri.parse(trimmed);
    }
    return Uri.parse('http://$trimmed');
  }

  Future<HttpTestResult> testHttp(
    Uri uri, {
    int timeoutMs = defaultTimeoutMs,
  }) async {
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = Duration(milliseconds: timeoutMs);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(Duration(milliseconds: timeoutMs));
      final response = await request.close().timeout(
        Duration(milliseconds: timeoutMs),
      );
      var bytes = 0;
      await for (final chunk in response.timeout(
        Duration(milliseconds: timeoutMs),
      )) {
        bytes += chunk.length;
        if (bytes > 1024 * 1024) {
          break;
        }
      }
      final headers = <String, List<String>>{};
      response.headers.forEach((name, values) {
        headers[name] = values;
      });
      return HttpTestResult(
        uri: uri,
        reached: true,
        statusCode: response.statusCode,
        reasonPhrase: response.reasonPhrase,
        contentType: response.headers.contentType?.toString(),
        bytes: bytes,
        headers: headers,
      );
    } catch (e) {
      return HttpTestResult(
        uri: uri,
        reached: false,
        bytes: 0,
        headers: const {},
        error: e.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String> doctor({bool verbose = false}) async {
    final checkedAt = DateTime.now().toIso8601String();
    final loopback127 = await checkPort(defaultPreviewPort);
    final loopbackLocalhost = await checkPort(
      defaultPreviewPort,
      host: 'localhost',
    );
    final workspacePaths = await WorkspaceService().paths();
    final workspaceOk = Directory(workspacePaths['projectsRoot']!).existsSync();
    final httpClientOk = await _httpClientAvailable();
    final loopbackOk = InternetAddress.loopbackIPv4.address == '127.0.0.1';
    final portError = loopback127.error?.toLowerCase();
    final portProbeOk =
        portError == null ||
        portError.contains('refused') ||
        portError.contains('timed out') ||
        portError.contains('timeout');
    final healthy = loopbackOk && httpClientOk && portProbeOk && workspaceOk;

    final sb = StringBuffer();
    sb.writeln('=== Localhost Doctor ===');
    sb.writeln('Loopback: ${loopbackOk ? "OK" : "MISSING"}');
    sb.writeln('HTTP client: ${httpClientOk ? "OK" : "MISSING"}');
    sb.writeln('Port check: ${portProbeOk ? "OK" : "MISSING"}');
    sb.writeln('Workspace: ${workspaceOk ? "OK" : "MISSING"}');
    sb.writeln('Preview URL: ${previewUrl(defaultPreviewPort)}');
    if (verbose) {
      sb.writeln();
      sb.writeln('Tested hostnames: 127.0.0.1, localhost');
      sb.writeln('127.0.0.1 result: ${_portStatus(loopback127)}');
      sb.writeln('localhost result: ${_portStatus(loopbackLocalhost)}');
      sb.writeln(
        'Android loopback notes: 127.0.0.1 points at the Termode app process network namespace.',
      );
      sb.writeln('Last checked: $checkedAt');
      if (loopback127.error != null) {
        sb.writeln('127.0.0.1 exception: ${loopback127.error}');
      }
      if (loopbackLocalhost.error != null) {
        sb.writeln('localhost exception: ${loopbackLocalhost.error}');
      }
    }
    sb.write('Overall: ${healthy ? "HEALTHY" : "UNHEALTHY"}');
    return sb.toString();
  }

  String capabilities() {
    return '=== Localhost Capabilities ===\n'
        'Supported:\n'
        '  - checking local ports\n'
        '  - testing HTTP localhost URLs\n'
        '  - generating preview URLs\n'
        '  - copying preview URLs to the clipboard\n'
        '  - opening preview URLs externally (Android)\n'
        '  - preview history of recent ports\n'
        '  - detecting basic dev server readiness\n\n'
        'Not supported yet:\n'
        '  - bundled Node.js\n'
        '  - npm dev servers\n'
        '  - built-in WebView preview\n'
        '  - automatic port discovery';
  }

  String previewUrl(int port) => 'http://127.0.0.1:$port';

  Future<String> previewUrlOutput(int port, {bool copy = false}) async {
    final url = previewUrl(port);
    if (copy) {
      await Clipboard.setData(ClipboardData(text: url));
      return 'Copied preview URL.\n$url';
    }
    final workspace = await WorkspaceService().currentWorkspaceName();
    final sb = StringBuffer();
    sb.writeln('Preview URL:');
    sb.write(url);
    if (workspace != '(none)') {
      sb.write('\nWorkspace: $workspace');
    }
    return sb.toString();
  }

  String portCheckOutput(PortCheckResult result, {bool verbose = false}) {
    final sb = StringBuffer();
    sb.writeln('Port ${result.port}: ${result.isOpen ? "open" : "closed"}');
    if (verbose) {
      sb.writeln('Host: ${result.host}');
      sb.writeln('Timeout: ${result.timeoutMs}ms');
      if (result.error != null) {
        sb.write('Exception: ${result.error}');
      }
    }
    return sb.toString().trimRight();
  }

  String httpTestOutput(HttpTestResult result, {bool headers = false}) {
    if (!result.reached) {
      return 'Error: Could not reach ${result.uri}\n'
          'Tip: Make sure the dev server is running.';
    }
    final sb = StringBuffer();
    sb.writeln(
      'HTTP: ${result.statusCode} ${result.reasonPhrase ?? _defaultReason(result.statusCode)}',
    );
    sb.writeln('Content-Type: ${result.contentType ?? "(none)"}');
    sb.writeln('Bytes: ${result.bytes}');
    if (headers && result.headers.isNotEmpty) {
      sb.writeln('Headers:');
      for (final entry in result.headers.entries) {
        sb.writeln('  ${entry.key}: ${entry.value.join(", ")}');
      }
    }
    return sb.toString().trimRight();
  }

  String help() {
    return '=== Dev Server / Localhost Help ===\n'
        'Commands:\n'
        '  localhost-doctor          - Check localhost readiness\n'
        '  localhost-doctor --verbose - Show loopback probe details\n'
        '  localhost-capabilities    - Show current localhost support\n'
        '  port-check <port>         - Check if 127.0.0.1:<port> is open\n'
        '  port-check <port> --verbose - Include timeout and exception details\n'
        '  http-test <port-or-url>   - GET a local HTTP target\n'
        '  http-test <url> --headers - Include compact response headers\n'
        '  preview-url <port>        - Print browser preview URL\n'
        '  preview-url <port> --copy - Copy preview URL when clipboard is available\n\n'
        'Preview Workflow:\n'
        '  preview                   - Show compact preview status\n'
        '  preview-copy <port>       - Copy a preview URL to the clipboard\n'
        '  preview-open <port>       - Open a preview URL (checks the port first)\n'
        '  preview-open <port> --force - Open without checking the port\n'
        '  preview-check <port>      - Combine port-check and http-test\n'
        '  preview-history           - Show recent preview URLs\n'
        '  preview-clear-history     - Clear preview history\n'
        '  preview-settings          - Show preview defaults\n'
        '  preview-doctor            - Diagnose preview capabilities\n'
        '  preview-help              - Show preview workflow help\n\n'
        '  devserver-help            - Show this help reference\n\n'
        'Notes:\n'
        '  - Termode does not ship Node.js or npm yet.\n'
        '  - These commands only prove readiness for future dev servers.';
  }

  Future<bool> _httpClientAvailable() async {
    try {
      final client = HttpClient();
      client.findProxy = (_) => 'DIRECT';
      client.close(force: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _portStatus(PortCheckResult result) {
    return result.isOpen ? 'open' : 'closed';
  }

  String _defaultReason(int? statusCode) {
    if (statusCode == 200) return 'OK';
    if (statusCode == 404) return 'Not Found';
    if (statusCode == 500) return 'Internal Server Error';
    return '';
  }
}
