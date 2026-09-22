import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'localhost_service.dart';
import 'native_command_service.dart';
import 'preview_service.dart';

/// Represents an active or recent background dev server process in Termode.
class DevServerInfo {
  final String id;
  final int pid;
  final String command;
  final List<String> arguments;
  final String workingDirectory;
  final DateTime startTime;
  final bool isAlive;
  final int? detectedPort;
  final String recentStdout;
  final String recentStderr;

  const DevServerInfo({
    required this.id,
    required this.pid,
    required this.command,
    required this.arguments,
    required this.workingDirectory,
    required this.startTime,
    required this.isAlive,
    this.detectedPort,
    this.recentStdout = '',
    this.recentStderr = '',
  });

  Duration get uptime => DateTime.now().difference(startTime);

  String get formattedUptime {
    final secs = uptime.inSeconds;
    if (secs < 60) return '${secs}s';
    final mins = uptime.inMinutes;
    if (mins < 60) return '${mins}m ${secs % 60}s';
    final hours = uptime.inHours;
    return '${hours}h ${mins % 60}m';
  }

  int get effectivePort => detectedPort ?? 3000;

  String get previewUrl => 'http://127.0.0.1:$effectivePort';

  String get fullCommand => [command, ...arguments].join(' ');

  factory DevServerInfo.fromJson(Map<String, dynamic> json) {
    final startTimeRaw = json['startTime'];
    DateTime start;
    if (startTimeRaw is int) {
      start = DateTime.fromMillisecondsSinceEpoch(startTimeRaw);
    } else if (startTimeRaw is String) {
      start = DateTime.tryParse(startTimeRaw) ?? DateTime.now();
    } else {
      start = DateTime.now();
    }

    final rawArgs = json['arguments'];
    final args = rawArgs is List
        ? rawArgs.map((e) => e.toString()).toList()
        : <String>[];

    return DevServerInfo(
      id: json['id']?.toString() ?? '',
      pid: json['pid'] is int ? json['pid'] as int : int.tryParse(json['pid']?.toString() ?? '') ?? -1,
      command: json['command']?.toString() ?? 'node',
      arguments: args,
      workingDirectory: json['workingDirectory']?.toString() ?? '',
      startTime: start,
      isAlive: json['isAlive'] == true,
      detectedPort: json['detectedPort'] is int ? json['detectedPort'] as int : int.tryParse(json['detectedPort']?.toString() ?? ''),
      recentStdout: json['recentStdout']?.toString() ?? '',
      recentStderr: json['recentStderr']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pid': pid,
    'command': command,
    'arguments': arguments,
    'workingDirectory': workingDirectory,
    'startTime': startTime.millisecondsSinceEpoch,
    'isAlive': isAlive,
    'detectedPort': detectedPort,
    'recentStdout': recentStdout,
    'recentStderr': recentStderr,
  };
}

/// Diagnostic health report for background dev servers and socket binding.
class DevServerDoctorReport {
  final bool supervisorReady;
  final int activeServerCount;
  final List<int> activePorts;
  final bool socketHealth;
  final bool browserOpenAvailable;
  final List<DevServerInfo> servers;

  const DevServerDoctorReport({
    required this.supervisorReady,
    required this.activeServerCount,
    required this.activePorts,
    required this.socketHealth,
    required this.browserOpenAvailable,
    required this.servers,
  });

  String formatReport() {
    final sb = StringBuffer('=== Dev Server Doctor ===\n');
    sb.writeln('Supervisor: ${supervisorReady ? "ACTIVE" : "STANDBY"}');
    sb.writeln('Running servers: $activeServerCount');
    sb.writeln('Active ports: ${activePorts.isEmpty ? "none" : activePorts.join(", ")}');
    sb.writeln('Socket health: ${socketHealth ? "OK" : "CHECK_PORTS"}');
    sb.writeln('Browser open: ${browserOpenAvailable ? "AVAILABLE" : "RESTRICTED"}');

    if (servers.isNotEmpty) {
      sb.writeln('\nActive Daemons:');
      for (final s in servers) {
        sb.writeln('  - [${s.id}] PID ${s.pid} -> port ${s.detectedPort ?? "detecting..."} (${s.formattedUptime})');
        sb.writeln('    Cmd: ${s.fullCommand}');
        sb.writeln('    CWD: ${s.workingDirectory}');
      }
    }

    final healthy = supervisorReady && (activeServerCount == 0 || socketHealth);
    sb.writeln('Overall: ${healthy ? "HEALTHY" : "ATTENTION_NEEDED"}');
    return sb.toString().trimRight();
  }
}

/// Service providing developer server process supervision, status tracking,
/// port resolution, logs streaming, and graceful shutdown.
class DevServerService {
  static final DevServerService _instance = DevServerService._internal();
  factory DevServerService() => _instance;
  DevServerService._internal();

  final _serverStreamController = StreamController<List<DevServerInfo>>.broadcast();
  Stream<List<DevServerInfo>> get activeServersStream => _serverStreamController.stream;

  List<DevServerInfo> _lastKnownServers = [];
  List<DevServerInfo> get lastKnownServers => List.unmodifiable(_lastKnownServers);

  // Testing hooks
  static List<DevServerInfo>? serverListHookForTesting;
  static bool? stopServerHookForTesting;
  static String? serverLogsHookForTesting;
  static bool? openBrowserHookForTesting;

  static void resetForTesting() {
    serverListHookForTesting = null;
    stopServerHookForTesting = null;
    serverLogsHookForTesting = null;
    openBrowserHookForTesting = null;
  }

  /// Lists all active background dev servers.
  Future<List<DevServerInfo>> listServers({bool refresh = false}) async {
    if (serverListHookForTesting != null) {
      _lastKnownServers = List.from(serverListHookForTesting!);
      _serverStreamController.add(_lastKnownServers);
      return _lastKnownServers;
    }

    if (!Platform.isAndroid) {
      return _lastKnownServers;
    }

    try {
      final rawList = await NativeCommandService().listDevServers();
      final servers = rawList
          .map((item) => DevServerInfo.fromJson(item))
          .where((s) => s.isAlive)
          .toList();
      _lastKnownServers = servers;
      _serverStreamController.add(servers);
      return servers;
    } catch (e) {
      debugPrint('Error listing dev servers: $e');
      return _lastKnownServers;
    }
  }

  /// Stops a running dev server by ID, listening port, or PID.
  Future<bool> stopServer({
    String? id,
    int? port,
    int? pid,
    bool all = false,
  }) async {
    if (stopServerHookForTesting != null) {
      if (stopServerHookForTesting!) {
        if (all) {
          _lastKnownServers.clear();
        } else {
          _lastKnownServers.removeWhere((s) =>
              (id != null && s.id == id) ||
              (port != null && s.detectedPort == port) ||
              (pid != null && s.pid == pid));
        }
        _serverStreamController.add(_lastKnownServers);
      }
      return stopServerHookForTesting!;
    }

    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final res = await NativeCommandService().stopDevServer(
        id: id,
        port: port,
        pid: pid,
        all: all,
      );
      final success = res['success'] == true && (res['stoppedCount'] as int? ?? 0) > 0;
      await listServers(refresh: true);
      return success;
    } catch (e) {
      debugPrint('Error stopping dev server: $e');
      return false;
    }
  }

  /// Retrieves buffered stdout and stderr logs for a dev server.
  Future<String?> getServerLogs({String? id, int? port}) async {
    if (serverLogsHookForTesting != null) {
      return serverLogsHookForTesting;
    }

    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final res = await NativeCommandService().getDevServerLogs(id: id, port: port);
      if (res == null) return null;
      final stdout = res['stdout']?.toString() ?? '';
      final stderr = res['stderr']?.toString() ?? '';
      final sb = StringBuffer();
      if (stdout.trim().isNotEmpty) {
        sb.writeln(stdout.trim());
      }
      if (stderr.trim().isNotEmpty) {
        if (sb.isNotEmpty) sb.writeln();
        sb.writeln('[STDERR]');
        sb.writeln(stderr.trim());
      }
      return sb.toString().trim();
    } catch (e) {
      debugPrint('Error fetching server logs: $e');
      return null;
    }
  }

  /// Launches the device browser pointing to the server's preview URL.
  Future<bool> openInBrowser({int? port, String? url}) async {
    if (openBrowserHookForTesting != null) {
      return openBrowserHookForTesting!;
    }

    final targetUrl = url ?? 'http://127.0.0.1:${port ?? 3000}';
    final actionResult = await PreviewService().openExternally(targetUrl);
    return !actionResult.isError;
  }

  /// Runs comprehensive diagnostic checks on dev server supervision and socket health.
  Future<DevServerDoctorReport> runDoctor() async {
    final servers = await listServers();
    final activePorts = <int>[];
    var socketsHealthy = true;

    final localhost = LocalhostService();
    for (final s in servers) {
      if (s.detectedPort != null) {
        activePorts.add(s.detectedPort!);
        final check = await localhost.checkPort(s.detectedPort!);
        if (!check.isOpen) {
          socketsHealthy = false;
        }
      }
    }

    return DevServerDoctorReport(
      supervisorReady: true,
      activeServerCount: servers.length,
      activePorts: activePorts,
      socketHealth: socketsHealthy,
      browserOpenAvailable: true,
      servers: servers,
    );
  }
}
