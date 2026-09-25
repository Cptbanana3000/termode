import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'dev_server_service.dart';

/// HTTP and socket diagnostics for a monitored local port.
class PortInspectionResult {
  final int port;
  final String url;
  final bool isReachable;
  final int? statusCode;
  final String? statusReason;
  final String? contentType;
  final String? serverHeader;
  final int? contentLength;
  final int latencyMs;
  final Map<String, String> headers;
  final DateTime timestamp;
  final String? error;

  const PortInspectionResult({
    required this.port,
    required this.url,
    required this.isReachable,
    this.statusCode,
    this.statusReason,
    this.contentType,
    this.serverHeader,
    this.contentLength,
    required this.latencyMs,
    required this.headers,
    required this.timestamp,
    this.error,
  });

  String get formattedStatus {
    if (!isReachable) return 'OFFLINE';
    if (statusCode != null) return '$statusCode ${statusReason ?? ''}'.trim();
    return 'LISTENING';
  }

  bool get isHttpSuccess =>
      statusCode != null && statusCode! >= 200 && statusCode! < 400;
}

/// Reactive background service that monitors and detects active local listening
/// sockets (e.g. 3000, 5173, 8000, 8080) for instant in-app web previewing.
class PortMonitorService {
  static final PortMonitorService _instance = PortMonitorService._internal();
  factory PortMonitorService() => _instance;
  PortMonitorService._internal();

  /// Default common dev server ports to check.
  static const List<int> defaultCandidatePorts = [
    3000, // Node.js / React / Next.js / Express
    5173, // Vite
    8000, // Python http.server / Django
    8080, // Webpack / Tomcat / http-server
    5000, // Flask / serve
    4200, // Angular
    8888, // Jupyter / generic dev
    3001, // Secondary Node
    3002, // Tertiary Node
  ];

  final Set<int> _customPorts = {};
  List<int> _activePorts = [];
  Timer? _autoScanTimer;
  bool _isScanning = false;

  final StreamController<List<int>> _portsStreamController =
      StreamController<List<int>>.broadcast();

  Stream<List<int>> get activePortsStream => _portsStreamController.stream;
  List<int> get activePorts => List.unmodifiable(_activePorts);
  bool get hasActiveServer => _activePorts.isNotEmpty;

  // Testing overrides
  static List<int>? mockActivePorts;
  static PortInspectionResult? mockInspectionResult;

  static void resetForTesting() {
    mockActivePorts = null;
    mockInspectionResult = null;
  }

  /// Adds a custom port to monitor (e.g. from user input or config).
  void registerPort(int port) {
    if (port > 0 && port <= 65535) {
      _customPorts.add(port);
    }
  }

  /// Removes a custom port.
  void unregisterPort(int port) {
    _customPorts.remove(port);
  }

  /// Starts automatic background port polling.
  void startAutoScan({Duration interval = const Duration(seconds: 3)}) {
    _autoScanTimer?.cancel();
    if (Platform.environment.containsKey('FLUTTER_TEST') && mockActivePorts == null) {
      return;
    }
    // Run an immediate scan
    triggerScan();
    _autoScanTimer = Timer.periodic(interval, (_) => triggerScan());
  }

  /// Stops automatic background polling.
  void stopAutoScan() {
    _autoScanTimer?.cancel();
    _autoScanTimer = null;
  }

  /// Triggers an immediate asynchronous scan of candidate ports.
  Future<List<int>> triggerScan() async {
    if (_isScanning) return _activePorts;
    _isScanning = true;

    try {
      if (mockActivePorts != null) {
        _activePorts = List.from(mockActivePorts!);
        _portsStreamController.add(_activePorts);
        return _activePorts;
      }

      final candidatePorts = <int>{
        ...defaultCandidatePorts,
        ..._customPorts,
      };

      // Also incorporate ports from active DevServerService instances
      try {
        final servers = DevServerService().lastKnownServers;
        for (final s in servers) {
          if (s.isAlive && s.detectedPort != null) {
            candidatePorts.add(s.detectedPort!);
          }
        }
      } catch (_) {}

      final newlyActive = <int>[];

      // Probe each port with a short socket timeout
      await Future.wait(
        candidatePorts.map((port) async {
          final isOpen = await _checkSocket(port);
          if (isOpen) {
            newlyActive.add(port);
          }
        }),
      );

      // Sort discovered ports numerically
      newlyActive.sort();

      // Check if active ports list changed
      final hasChanged = newlyActive.length != _activePorts.length ||
          !listEquals(newlyActive, _activePorts);

      _activePorts = newlyActive;
      if (hasChanged) {
        _portsStreamController.add(_activePorts);
      }

      return _activePorts;
    } finally {
      _isScanning = false;
    }
  }

  /// Checks if a socket connection succeeds to 127.0.0.1:[port].
  Future<bool> _checkSocket(int port, {int timeoutMs = 300}) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// Performs full HTTP diagnostics and header inspection on an active port.
  Future<PortInspectionResult> inspectPort(
    int port, {
    String path = '/',
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (mockInspectionResult != null) {
      return mockInspectionResult!;
    }

    final cleanPath = path.startsWith('/') ? path : '/$path';
    final url = 'http://127.0.0.1:$port$cleanPath';
    final uri = Uri.parse(url);
    final stopwatch = Stopwatch()..start();

    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = timeout;

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      stopwatch.stop();

      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name] = values.join(', ');
      });

      return PortInspectionResult(
        port: port,
        url: url,
        isReachable: true,
        statusCode: response.statusCode,
        statusReason: response.reasonPhrase,
        contentType: response.headers.contentType?.toString(),
        serverHeader: headers['server'],
        contentLength: response.contentLength >= 0 ? response.contentLength : null,
        latencyMs: stopwatch.elapsedMilliseconds,
        headers: headers,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      stopwatch.stop();
      return PortInspectionResult(
        port: port,
        url: url,
        isReachable: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        headers: const {},
        timestamp: DateTime.now(),
        error: e.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }
}
