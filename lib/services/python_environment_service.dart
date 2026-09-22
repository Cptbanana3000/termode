import 'dart:io';

import 'native_command_service.dart';
import 'runtime_prefix_service.dart';

/// Diagnostic report for the Python runtime environment.
class PythonDoctorReport {
  final bool pythonAvailable;
  final String pythonStatus;
  final String? pythonVersion;
  final String? pythonExecutablePath;
  final String abi;
  final String pythonHome;
  final String pythonUserBase;
  final String pythonUserBin;
  final bool pythonUserBinExists;
  final bool pythonUserBinInPath;
  final String pythonSitePackages;
  final String pythonLib;
  final String workingDirectory;
  final String pipStatus;
  final List<String> bionicDependencies;
  final String milestone;

  const PythonDoctorReport({
    required this.pythonAvailable,
    required this.pythonStatus,
    this.pythonVersion,
    this.pythonExecutablePath,
    required this.abi,
    required this.pythonHome,
    required this.pythonUserBase,
    required this.pythonUserBin,
    required this.pythonUserBinExists,
    required this.pythonUserBinInPath,
    required this.pythonSitePackages,
    required this.pythonLib,
    required this.workingDirectory,
    required this.pipStatus,
    required this.bionicDependencies,
    required this.milestone,
  });

  String formatOutput() {
    final sb = StringBuffer();
    sb.writeln('=== Python Environment Doctor ===');
    sb.writeln('Milestone:           $milestone');
    sb.writeln('Engine Status:       $pythonStatus');
    sb.writeln(
        'Python Executable:   ${pythonExecutablePath ?? "usr/bin/python3"} (${pythonAvailable ? "AVAILABLE" : "NOT INSTALLED"})');
    sb.writeln('Target ABI:          $abi (Bionic libc)');
    sb.writeln('PYTHONHOME:          $pythonHome');
    sb.writeln('PYTHONUSERBASE:      $pythonUserBase');
    sb.writeln(
        'User Bin Dir:        $pythonUserBin (${pythonUserBinExists ? "INITIALIZED" : "PENDING"}, in PATH: ${pythonUserBinInPath ? "YES" : "NO"})');
    sb.writeln('User Site-Packages:  $pythonSitePackages');
    sb.writeln('Prefix Library:      $pythonLib');
    sb.writeln('Pip Status:          $pipStatus');
    sb.writeln('Bionic Dependencies: ${bionicDependencies.join(", ")}');
    sb.writeln(
        'OSINT Target Tools:  Sherlock, Maigret -> user bin (~/.local/bin) in PATH: ${pythonUserBinInPath ? "YES" : "NO"}');
    sb.writeln(
        'Status:              ${pythonAvailable ? "READY" : "PROTOTYPE READY (Awaiting arm64 CPython binary acquisition)"}');
    return sb.toString().trimRight();
  }
}

/// Service managing Termode's Python runtime architecture, environment, and diagnostics.
class PythonEnvironmentService {
  static final PythonEnvironmentService _instance =
      PythonEnvironmentService._internal();
  factory PythonEnvironmentService() => _instance;
  PythonEnvironmentService._internal();

  final RuntimePrefixService _prefix = RuntimePrefixService();

  /// Test hook allowing unit tests to simulate an authentic Python execution.
  static Future<NativeCommandResult> Function(
    List<String> arguments, {
    String? workingDirectory,
  })? pythonExecutorForTesting;

  static const String pythonVersionTarget = '3.14.6';
  static const String pythonAbiTarget = 'arm64-v8a';
  static const List<String> requiredBionicLibraries = [
    'libc.so',
    'libm.so',
    'libdl.so',
    'libssl.so.3',
    'libcrypto.so.3',
    'libz.so.1',
    'libsqlite3.so',
    'libandroid-support.so',
    'libffi.so',
  ];

  /// Checks if Python executable is available and verified.
  Future<bool> isPythonAvailable() async {
    if (pythonExecutorForTesting != null) return true;
    if (Platform.isAndroid) {
      final paths = await NativeCommandService().getExecutablePaths();
      if (paths != null && paths['pythonExecutableExists'] == true) {
        return true;
      }
    }
    final paths = await _prefix.paths();
    final pythonBin = File('${paths['prefix']}/bin/python3');
    if (pythonBin.existsSync()) return true;
    final jniPython = File('android/app/src/main/jniLibs/arm64-v8a/libtermode_python_exec.so');
    if (jniPython.existsSync()) return true;
    return false;
  }

  /// Returns user-site base directory ($HOME/.local).
  Future<String> userBaseDir() async {
    final paths = await _prefix.paths();
    return paths['pythonUserBase'] ?? '${paths['home']}/.local';
  }

  /// Returns user-site bin directory ($HOME/.local/bin).
  Future<String> userBinDir() async {
    final paths = await _prefix.paths();
    return paths['pythonUserBin'] ?? '${paths['home']}/.local/bin';
  }

  /// Returns user-site packages directory ($HOME/.local/lib/python3.14/site-packages).
  Future<String> userSitePackagesDir() async {
    final paths = await _prefix.paths();
    return paths['pythonUserLib'] ??
        '${paths['home']}/.local/lib/python3.14/site-packages';
  }

  /// Returns standard prefix library directory ($TERMODE_PREFIX/usr/lib/python3.14).
  Future<String> prefixLibDir() async {
    final paths = await _prefix.paths();
    return paths['pythonLib'] ?? '${paths['prefix']}/lib/python3.14';
  }

  /// Verifies whether the user bin directory is present in the active PATH entries.
  Future<bool> isUserBinInPath() async {
    final pathEntries = await _prefix.pathEntries();
    final targetBin = await userBinDir();
    return pathEntries.contains(targetBin);
  }

  /// Compiles a comprehensive diagnostic report of the Python environment.
  Future<PythonDoctorReport> doctor({String? workingDirectory}) async {
    final paths = await _prefix.paths();
    final cwd = workingDirectory ?? paths['workspaces']!;
    final available = await isPythonAvailable();
    final userBin = await userBinDir();
    final userBinDirEntity = Directory(userBin);
    final inPath = await isUserBinInPath();
    final userSite = await userSitePackagesDir();
    final pyLib = await prefixLibDir();

    String execPath = '${paths['prefix']}/bin/python3';
    if (Platform.isAndroid) {
      final execPaths = await NativeCommandService().getExecutablePaths();
      if (execPaths != null && execPaths['pythonExecutable'] != null) {
        execPath = execPaths['pythonExecutable'].toString();
      }
    }

    final status = available
        ? 'AVAILABLE (CPython v$pythonVersionTarget)'
        : 'PROTOTYPE_CANDIDATE ($pythonAbiTarget)';

    return PythonDoctorReport(
      pythonAvailable: available,
      pythonStatus: status,
      pythonVersion: available ? pythonVersionTarget : null,
      pythonExecutablePath: execPath,
      abi: pythonAbiTarget,
      pythonHome: paths['prefix']!,
      pythonUserBase: paths['pythonUserBase']!,
      pythonUserBin: userBin,
      pythonUserBinExists: userBinDirEntity.existsSync(),
      pythonUserBinInPath: inPath,
      pythonSitePackages: userSite,
      pythonLib: pyLib,
      workingDirectory: cwd,
      pipStatus: 'PLANNED (v0.76+ user-site installer)',
      bionicDependencies: requiredBionicLibraries,
      milestone:
          'v0.75 (Python arm64 Binary Acquisition & Packaging)',
    );
  }

  /// Formats environment variables and configuration summary for the CLI.
  Future<String> formatEnvReport({String? workingDirectory}) async {
    final paths = await _prefix.paths();
    final env = await _prefix.envMap();
    final userBin = await userBinDir();
    final inPath = await isUserBinInPath();
    final userSite = await userSitePackagesDir();
    final pyLib = await prefixLibDir();

    final sb = StringBuffer();
    sb.writeln('=== Python Environment Configuration ===');
    sb.writeln('PYTHONHOME:        ${env['PYTHONHOME'] ?? paths['prefix']}');
    sb.writeln('PYTHONUSERBASE:    ${env['PYTHONUSERBASE'] ?? paths['pythonUserBase']}');
    sb.writeln('PYTHONPATH:        ${env['PYTHONPATH']}');
    sb.writeln('User Bin (PATH):   $userBin (in PATH: ${inPath ? "YES" : "NO"})');
    sb.writeln('User Site-Packages:$userSite');
    sb.writeln('Prefix Library:    $pyLib');
    sb.writeln('Executables:       python, python3');
    sb.writeln('Target OSINT Tools:sherlock, maigret, pytest, black, flake8');
    return sb.toString().trimRight();
  }

  /// Executes a Python command through the authentic binary or testing hook.
  Future<NativeCommandResult> executePython(
    List<String> arguments, {
    String? workingDirectory,
    int timeoutMs = 30000,
  }) async {
    if (pythonExecutorForTesting != null) {
      return pythonExecutorForTesting!(
        arguments,
        workingDirectory: workingDirectory,
      );
    }

    final available = await isPythonAvailable();
    if (!available) {
      return NativeCommandResult(
        stdout: '',
        stderr:
            'termode: python3: command not found\n'
            'CPython 3 runtime environment is not installed.\n'
            'Run: python-doctor',
        exitCode: 127,
      );
    }

    if (Platform.isAndroid) {
      return NativeCommandService().executeBundledPython(
        arguments,
        workingDirectory: workingDirectory,
        timeoutMs: timeoutMs,
      );
    }

    // Host fallback for testing/desktop
    final paths = await _prefix.paths();
    final pythonBin = '${paths['prefix']}/bin/python3';
    return NativeCommandService().execute(
      '$pythonBin ${arguments.join(' ')}',
      'python-session',
      timeoutMs: timeoutMs,
    );
  }
}
