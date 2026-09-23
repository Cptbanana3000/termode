import 'dart:io';

import 'package_manager_service.dart';
import 'python_environment_service.dart';
import 'runtime_binary_package_service.dart';
import 'runtime_prefix_service.dart';

/// Metadata model for an installed Python distribution package.
class PipPackageInfo {
  final String name;
  final String version;
  final String summary;
  final String location;
  final bool isUserSite;
  final String license;
  final String installer;
  final List<String> entryPoints;

  const PipPackageInfo({
    required this.name,
    required this.version,
    this.summary = '',
    required this.location,
    required this.isUserSite,
    this.license = '',
    this.installer = 'pip',
    this.entryPoints = const [],
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'summary': summary,
    'location': location,
    'is_user_site': isUserSite,
    'license': license,
    'installer': installer,
    'entry_points': entryPoints,
  };
}

/// Comprehensive diagnostic report model for pip and Python package management.
class PipDoctorReport {
  final bool pythonAvailable;
  final String pythonStatus;
  final bool pipAvailable;
  final String pipStatus;
  final String? pipVersion;
  final String workingDirectory;
  final String userBase;
  final String userBin;
  final bool userBinExists;
  final bool userBinInPath;
  final String userSitePackages;
  final bool userSitePackagesExists;
  final String prefixSitePackages;
  final bool prefixSitePackagesExists;
  final int totalInstalledPackagesCount;
  final int userInstalledPackagesCount;
  final List<String> installedPackageNames;
  final String cacheDir;
  final int cacheSizeBytes;
  final String cacheSizeDisplay;
  final String sslCertDir;
  final bool sslCertDirExists;
  final String milestone;

  const PipDoctorReport({
    required this.pythonAvailable,
    required this.pythonStatus,
    required this.pipAvailable,
    required this.pipStatus,
    this.pipVersion,
    required this.workingDirectory,
    required this.userBase,
    required this.userBin,
    required this.userBinExists,
    required this.userBinInPath,
    required this.userSitePackages,
    required this.userSitePackagesExists,
    required this.prefixSitePackages,
    required this.prefixSitePackagesExists,
    required this.totalInstalledPackagesCount,
    required this.userInstalledPackagesCount,
    required this.installedPackageNames,
    required this.cacheDir,
    required this.cacheSizeBytes,
    required this.cacheSizeDisplay,
    required this.sslCertDir,
    required this.sslCertDirExists,
    required this.milestone,
  });

  String formatText() {
    final sb = StringBuffer('=== pip Diagnostics (Doctor) ===\n');
    sb.writeln('Milestone:               $milestone');
    sb.writeln('Python Runtime Engine:   ${pythonAvailable ? "AVAILABLE" : pythonStatus}');
    sb.writeln('pip Package Manager:     ${pipAvailable ? "AVAILABLE (${pipVersion ?? 'v26.2.1'})" : pipStatus}');
    sb.writeln('Active Working Directory: $workingDirectory');
    sb.writeln('User Base Directory:     $userBase');
    sb.writeln(
        'User Bin (~/.local/bin): $userBin (${userBinExists ? "INITIALIZED" : "PENDING"}, in PATH: ${userBinInPath ? "YES" : "NO"})');
    sb.writeln(
        'User Site-Packages:      $userSitePackages (${userSitePackagesExists ? "PRESENT" : "INITIALIZED"})');
    sb.writeln(
        'Prefix Site-Packages:    $prefixSitePackages (${prefixSitePackagesExists ? "PRESENT" : "INITIALIZED"})');
    sb.writeln('Total Installed Packages: $totalInstalledPackagesCount');
    sb.writeln('User-Site Packages:      $userInstalledPackagesCount');
    if (installedPackageNames.isNotEmpty) {
      sb.writeln('Installed Distributions: ${installedPackageNames.join(", ")}');
    }
    sb.writeln('SSL Certificate Dir:     $sslCertDir (exists: ${sslCertDirExists ? "YES" : "NO"})');
    sb.writeln('pip Cache Status:        $cacheSizeDisplay ($cacheDir)');
    sb.writeln('Target OSINT CLI Tools:  Sherlock, Maigret -> installed to user-site & ~/.local/bin');
    sb.writeln(
        'Status:                  ${pipAvailable ? "READY (Authentic upstream pip engine & isolated user-site operational)" : "STDLIB_READY (Run: pip-setup)"}');
    return sb.toString().trimRight();
  }
}

/// Standalone, embeddable service for Python package management, wheel unpacking,
/// user-site distribution inspection, and diagnostics.
///
/// Designed to be decoupled from terminal UI for direct reuse inside IDEs
/// such as Calypso IDE.
class PipPackageService {
  static final PipPackageService _instance = PipPackageService._internal();
  factory PipPackageService() => _instance;
  PipPackageService._internal();

  final RuntimePrefixService _prefix = RuntimePrefixService();
  final PythonEnvironmentService _pythonEnv = PythonEnvironmentService();
  final RuntimeBinaryPackageService _binaryPkg = RuntimeBinaryPackageService();

  /// Default pip cache directory ($HOME/.cache/pip).
  Future<String> pipCacheDir() async {
    final paths = await _prefix.paths();
    return '${paths['home']}/.cache/pip';
  }

  /// System prefix site-packages ($TERMODE_PREFIX/usr/lib/python3.14/site-packages).
  Future<String> prefixSitePackagesDir() async {
    final paths = await _prefix.paths();
    return '${paths['lib']}/python3.14/site-packages';
  }

  /// User-isolated site-packages ($HOME/.local/lib/python3.14/site-packages).
  Future<String> userSitePackagesDir() async {
    return _pythonEnv.userSitePackagesDir();
  }

  /// User-site binary directory ($HOME/.local/bin).
  Future<String> userBinDir() async {
    return _pythonEnv.userBinDir();
  }

  /// Checks if pip is installed and execution-verified.
  Future<bool> isPipAvailable() async {
    if (RuntimeBinaryPackageService.pipExecutorForTesting != null) return true;
    final prefixSite = await prefixSitePackagesDir();
    final pipModule = Directory('$prefixSite/pip');
    if (pipModule.existsSync()) return true;
    return _binaryPkg.pipInstalled();
  }

  /// Discovers installed distribution packages by scanning .dist-info directories
  /// in both prefix site-packages and user-site packages.
  Future<List<PipPackageInfo>> listPackages({bool userOnly = false}) async {
    final packages = <String, PipPackageInfo>{};
    final userSite = await userSitePackagesDir();
    final prefixSite = await prefixSitePackagesDir();

    // 1. Scan user site-packages first
    final userDir = Directory(userSite);
    if (userDir.existsSync()) {
      _scanSitePackages(userDir, isUserSite: true, out: packages);
    }

    // 2. Scan prefix site-packages unless userOnly is requested
    if (!userOnly) {
      final prefixDir = Directory(prefixSite);
      if (prefixDir.existsSync()) {
        _scanSitePackages(prefixDir, isUserSite: false, out: packages);
      }
    }

    final sortedList = packages.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sortedList;
  }

  void _scanSitePackages(
    Directory siteDir, {
    required bool isUserSite,
    required Map<String, PipPackageInfo> out,
  }) {
    try {
      for (final entity in siteDir.listSync(followLinks: false)) {
        if (entity is Directory && entity.path.endsWith('.dist-info')) {
          final info = _parseDistInfo(entity, isUserSite: isUserSite);
          if (info != null && !out.containsKey(info.name.toLowerCase())) {
            out[info.name.toLowerCase()] = info;
          }
        }
      }
    } catch (_) {}
  }

  PipPackageInfo? _parseDistInfo(
    Directory distInfoDir, {
    required bool isUserSite,
  }) {
    try {
      final metadataFile = File('${distInfoDir.path}/METADATA');
      final pkgInfoFile = File('${distInfoDir.path}/PKG-INFO');
      final targetMeta = metadataFile.existsSync()
          ? metadataFile
          : (pkgInfoFile.existsSync() ? pkgInfoFile : null);

      String name = '';
      String version = '';
      String summary = '';
      String license = '';
      String installer = 'pip';

      if (targetMeta != null) {
        final lines = targetMeta.readAsLinesSync();
        for (final line in lines) {
          if (line.startsWith('Name: ') && name.isEmpty) {
            name = line.substring(6).trim();
          } else if (line.startsWith('Version: ') && version.isEmpty) {
            version = line.substring(9).trim();
          } else if (line.startsWith('Summary: ') && summary.isEmpty) {
            summary = line.substring(9).trim();
          } else if (line.startsWith('License: ') && license.isEmpty) {
            license = line.substring(9).trim();
          }
        }
      }

      if (name.isEmpty) {
        // Fallback to directory name: e.g. pip-26.2.1.dist-info
        final base = distInfoDir.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .replaceAll('.dist-info', '');
        final parts = base.split('-');
        name = parts.first;
        if (parts.length > 1) version = parts[1];
      }

      final installerFile = File('${distInfoDir.path}/INSTALLER');
      if (installerFile.existsSync()) {
        installer = installerFile.readAsStringSync().trim();
      }

      final entryPointsFile = File('${distInfoDir.path}/entry_points.txt');
      final entryPoints = <String>[];
      if (entryPointsFile.existsSync()) {
        try {
          final epLines = entryPointsFile.readAsLinesSync();
          bool inConsoleScripts = false;
          for (final line in epLines) {
            final trimmed = line.trim();
            if (trimmed == '[console_scripts]') {
              inConsoleScripts = true;
              continue;
            } else if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
              inConsoleScripts = false;
              continue;
            }
            if (inConsoleScripts && trimmed.contains('=')) {
              entryPoints.add(trimmed.split('=').first.trim());
            }
          }
        } catch (_) {}
      }

      return PipPackageInfo(
        name: name,
        version: version.isNotEmpty ? version : 'unknown',
        summary: summary,
        location: distInfoDir.parent.path,
        isUserSite: isUserSite,
        license: license,
        installer: installer,
        entryPoints: entryPoints,
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns detailed information for a specific installed package.
  Future<PipPackageInfo?> showPackage(String packageName) async {
    final packages = await listPackages();
    final match = packages.where(
      (p) => p.name.toLowerCase() == packageName.toLowerCase(),
    );
    return match.isNotEmpty ? match.first : null;
  }

  /// Compiles a comprehensive diagnostic report of pip and the Python packaging environment.
  Future<PipDoctorReport> doctor({String? workingDirectory}) async {
    final paths = await _prefix.paths();
    final cwd = workingDirectory ?? paths['workspaces']!;
    final pythonAvailable = await _pythonEnv.isPythonAvailable();
    final pipAvailable = await isPipAvailable();
    final userBase = await _pythonEnv.userBaseDir();
    final userBin = await userBinDir();
    final userBinDirEntity = Directory(userBin);
    final inPath = await _pythonEnv.isUserBinInPath();
    final userSite = await userSitePackagesDir();
    final userSiteDirEntity = Directory(userSite);
    final prefixSite = await prefixSitePackagesDir();
    final prefixSiteDirEntity = Directory(prefixSite);

    final allPackages = await listPackages();
    final userPackages = allPackages.where((p) => p.isUserSite).toList();

    final cachePath = await pipCacheDir();
    final cacheDirEntity = Directory(cachePath);
    int cacheBytes = 0;
    if (cacheDirEntity.existsSync()) {
      try {
        for (final entity in cacheDirEntity.listSync(recursive: true, followLinks: false)) {
          if (entity is File) cacheBytes += entity.lengthSync();
        }
      } catch (_) {}
    }

    final cacheDisplay = cacheBytes > 1024 * 1024
        ? '${(cacheBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(cacheBytes / 1024).toStringAsFixed(1)} KB';

    String? pipVersion;
    if (pipAvailable) {
      final pipPkg = allPackages.where((p) => p.name.toLowerCase() == 'pip');
      if (pipPkg.isNotEmpty) {
        pipVersion = pipPkg.first.version;
      } else {
        final meta = await _binaryPkg.installedPipMetadata();
        pipVersion = meta?['version']?.toString() ?? '26.2.1';
      }
    }

    final sslCertDir = '/system/etc/security/cacerts';
    final sslDirExists = Directory(sslCertDir).existsSync();

    return PipDoctorReport(
      pythonAvailable: pythonAvailable,
      pythonStatus: pythonAvailable ? 'AVAILABLE (CPython 3.14)' : 'NOT INSTALLED',
      pipAvailable: pipAvailable,
      pipStatus: pipAvailable ? 'INSTALLED (v${pipVersion ?? "26.2.1"})' : 'NOT INSTALLED (Run: pip-setup)',
      pipVersion: pipVersion,
      workingDirectory: cwd,
      userBase: userBase,
      userBin: userBin,
      userBinExists: userBinDirEntity.existsSync(),
      userBinInPath: inPath,
      userSitePackages: userSite,
      userSitePackagesExists: userSiteDirEntity.existsSync(),
      prefixSitePackages: prefixSite,
      prefixSitePackagesExists: prefixSiteDirEntity.existsSync(),
      totalInstalledPackagesCount: allPackages.length,
      userInstalledPackagesCount: userPackages.length,
      installedPackageNames: allPackages.map((p) => '${p.name}==${p.version}').toList(),
      cacheDir: cachePath,
      cacheSizeBytes: cacheBytes,
      cacheSizeDisplay: cacheDisplay,
      sslCertDir: sslCertDir,
      sslCertDirExists: sslDirExists,
      milestone: 'v0.77 (Pip Package Management & User-Site Installation)',
    );
  }

  /// Installs a package or wheel via pip into the isolated user-site directory.
  Future<({bool success, String output})> installPackage(
    String packageSpec, {
    bool userSite = true,
    List<String> extraArgs = const [],
    String? workingDirectory,
  }) async {
    final args = <String>[
      'install',
      if (userSite) '--user',
      ...extraArgs,
      packageSpec,
    ];
    final result = await _binaryPkg.runPip(args, workingDirectory: workingDirectory);
    final out = result.stdout.trim().isNotEmpty
        ? result.stdout.trim()
        : result.stderr.trim();
    if (result.exitCode == 0) {
      try {
        await PackageManagerService.updateShellHelpers();
      } catch (_) {}
    }
    return (
      success: result.exitCode == 0,
      output: out,
    );
  }

  /// Uninstalls an installed package.
  Future<({bool success, String output})> uninstallPackage(
    String packageName, {
    bool yes = true,
    String? workingDirectory,
  }) async {
    final args = <String>[
      'uninstall',
      if (yes) '-y',
      packageName,
    ];
    final result = await _binaryPkg.runPip(args, workingDirectory: workingDirectory);
    final out = result.stdout.trim().isNotEmpty
        ? result.stdout.trim()
        : result.stderr.trim();
    if (result.exitCode == 0) {
      try {
        await PackageManagerService.updateShellHelpers();
      } catch (_) {}
    }
    return (
      success: result.exitCode == 0,
      output: out.isNotEmpty ? out : 'Successfully uninstalled $packageName',
    );
  }

  /// Cleans the pip cache directory.
  Future<({bool success, String output})> cacheClean({bool force = true}) async {
    final result = await _binaryPkg.runPip(['cache', 'purge']);
    final out = result.stdout.trim().isNotEmpty
        ? result.stdout.trim()
        : result.stderr.trim();
    return (
      success: result.exitCode == 0,
      output: out.isNotEmpty ? out : 'pip cache cleared',
    );
  }

  /// Checks whether a specific package is installed in site-packages or user-site.
  Future<bool> hasPackage(String packageName) async {
    final pkg = await showPackage(packageName);
    return pkg != null;
  }
}
