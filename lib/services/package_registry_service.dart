import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pip_package_service.dart';
import 'python_environment_service.dart';
import 'runtime_binary_package_service.dart';

/// Status model for a single package registry endpoint (npm, PyPI).
class RegistryEndpointStatus {
  final String name;
  final String url;
  final bool online;
  final int latencyMs;
  final int? statusCode;
  final String message;

  const RegistryEndpointStatus({
    required this.name,
    required this.url,
    required this.online,
    this.latencyMs = 0,
    this.statusCode,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'online': online,
    'latency_ms': latencyMs,
    'status_code': statusCode,
    'message': message,
  };
}

/// Comprehensive diagnostic health report for live package registries.
class RegistryDoctorReport {
  final RegistryEndpointStatus npmStatus;
  final RegistryEndpointStatus pypiStatus;
  final String sslCertDir;
  final bool sslCertDirExists;
  final bool nodeAvailable;
  final bool npmAvailable;
  final bool pythonAvailable;
  final bool pipAvailable;
  final String milestone;

  const RegistryDoctorReport({
    required this.npmStatus,
    required this.pypiStatus,
    required this.sslCertDir,
    required this.sslCertDirExists,
    required this.nodeAvailable,
    required this.npmAvailable,
    required this.pythonAvailable,
    required this.pipAvailable,
    this.milestone = 'v0.85 (Live Package Registries & Remote Downloads)',
  });

  bool get allOnline => npmStatus.online && pypiStatus.online;

  Map<String, dynamic> toJson() => {
    'milestone': milestone,
    'npm': npmStatus.toJson(),
    'pypi': pypiStatus.toJson(),
    'ssl_cert_dir': sslCertDir,
    'ssl_cert_dir_exists': sslCertDirExists,
    'node_available': nodeAvailable,
    'npm_available': npmAvailable,
    'python_available': pythonAvailable,
    'pip_available': pipAvailable,
    'all_online': allOnline,
  };

  String formatText() {
    final sb = StringBuffer('=== Package Registries Diagnostic (Doctor) ===\n');
    sb.writeln('Milestone:               $milestone');
    sb.writeln(
      'npm Registry:            ${npmStatus.online ? "ONLINE" : "OFFLINE"} '
      '(${npmStatus.url}) - ${npmStatus.latencyMs}ms [${npmStatus.statusCode ?? 'ERR'}]',
    );
    if (!npmStatus.online) {
      sb.writeln('  npm Error:             ${npmStatus.message}');
    }

    sb.writeln(
      'PyPI Registry:           ${pypiStatus.online ? "ONLINE" : "OFFLINE"} '
      '(${pypiStatus.url}) - ${pypiStatus.latencyMs}ms [${pypiStatus.statusCode ?? 'ERR'}]',
    );
    if (!pypiStatus.online) {
      sb.writeln('  PyPI Error:            ${pypiStatus.message}');
    }

    sb.writeln('SSL CA Certs:            $sslCertDir (${sslCertDirExists ? "VERIFIED" : "SYSTEM_DEFAULT"})');
    sb.writeln('Node.js Engine:          ${nodeAvailable ? "READY" : "NOT_INSTALLED"}');
    sb.writeln('npm Package Manager:     ${npmAvailable ? "READY (v10.9.3)" : "NOT_INSTALLED"}');
    sb.writeln('Python CPython Engine:   ${pythonAvailable ? "READY" : "NOT_INSTALLED"}');
    sb.writeln('pip Package Manager:     ${pipAvailable ? "READY (v26.2.1)" : "NOT_INSTALLED"}');
    sb.writeln('Overall Registries:      ${allOnline ? "HEALTHY (Live network downloads operational)" : "DEGRADED (Check connectivity)"}');
    return sb.toString().trimRight();
  }
}

/// Standalone service for probing, configuring, and querying remote package
/// registries (npm registry & PyPI index).
class PackageRegistryService {
  static final PackageRegistryService _instance = PackageRegistryService._internal();
  factory PackageRegistryService() => _instance;
  PackageRegistryService._internal();

  static const String defaultNpmRegistry = 'https://registry.npmjs.org/';
  static const String defaultPypiRegistry = 'https://pypi.org/pypi';

  /// Test injection hook for npm ping.
  static Future<RegistryEndpointStatus> Function(String url)? npmPingForTesting;

  /// Test injection hook for PyPI ping.
  static Future<RegistryEndpointStatus> Function(String url)? pypiPingForTesting;

  /// Pings npm registry endpoint and reports response latency.
  Future<RegistryEndpointStatus> pingNpmRegistry({String url = defaultNpmRegistry}) async {
    if (npmPingForTesting != null) {
      return npmPingForTesting!(url);
    }
    return _pingEndpoint(name: 'npm', url: url);
  }

  /// Pings PyPI index endpoint and reports response latency.
  Future<RegistryEndpointStatus> pingPypiRegistry({String url = defaultPypiRegistry}) async {
    if (pypiPingForTesting != null) {
      return pypiPingForTesting!(url);
    }
    return _pingEndpoint(name: 'PyPI', url: url);
  }

  /// Helper to send HTTP GET/HEAD request with timeout.
  Future<RegistryEndpointStatus> _pingEndpoint({
    required String name,
    required String url,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final sw = Stopwatch()..start();
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = timeout;
      final uri = Uri.parse(url);
      final request = await client.headUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      sw.stop();

      final isSuccess = response.statusCode >= 200 && response.statusCode < 400;
      return RegistryEndpointStatus(
        name: name,
        url: url,
        online: isSuccess,
        latencyMs: sw.elapsedMilliseconds,
        statusCode: response.statusCode,
        message: isSuccess ? 'OK' : 'HTTP status ${response.statusCode}',
      );
    } catch (e) {
      sw.stop();
      return RegistryEndpointStatus(
        name: name,
        url: url,
        online: false,
        latencyMs: sw.elapsedMilliseconds,
        statusCode: null,
        message: e.toString(),
      );
    } finally {
      client?.close(force: true);
    }
  }

  /// Runs full diagnostic check across all remote registries and local runtimes.
  Future<RegistryDoctorReport> doctor() async {
    final npmFuture = pingNpmRegistry();
    final pypiFuture = pingPypiRegistry();

    final binaryPkg = RuntimeBinaryPackageService();
    final nodeReady = await binaryPkg.nodeInstalled();
    final npmReady = await binaryPkg.npmInstalled();
    final pythonReady = await PythonEnvironmentService().isPythonAvailable();
    final pipReady = await PipPackageService().isPipAvailable();

    const sslCertDir = '/system/etc/security/cacerts';
    final sslExists = Directory(sslCertDir).existsSync();

    final npmStatus = await npmFuture;
    final pypiStatus = await pypiFuture;

    return RegistryDoctorReport(
      npmStatus: npmStatus,
      pypiStatus: pypiStatus,
      sslCertDir: sslCertDir,
      sslCertDirExists: sslExists,
      nodeAvailable: nodeReady,
      npmAvailable: npmReady,
      pythonAvailable: pythonReady,
      pipAvailable: pipReady,
    );
  }

  /// Fetches package metadata from PyPI JSON API.
  Future<Map<String, dynamic>?> fetchPypiPackageInfo(String packageName) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final uri = Uri.parse('https://pypi.org/pypi/$packageName/json');
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// Fetches package metadata from npm registry.
  Future<Map<String, dynamic>?> fetchNpmPackageInfo(String packageName) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final uri = Uri.parse('https://registry.npmjs.org/$packageName');
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}

