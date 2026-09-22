import 'dart:convert';
import 'dart:io';

import 'runtime_binary_package_service.dart';

/// Metadata model for a parsed `package.json` file.
class PackageJsonMetadata {
  final String name;
  final String version;
  final String description;
  final String main;
  final Map<String, String> scripts;
  final Map<String, String> dependencies;
  final Map<String, String> devDependencies;
  final String rawContent;

  const PackageJsonMetadata({
    required this.name,
    required this.version,
    required this.description,
    required this.main,
    required this.scripts,
    required this.dependencies,
    required this.devDependencies,
    required this.rawContent,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'description': description,
    'main': main,
    'scripts': scripts,
    'dependencies': dependencies,
    'devDependencies': devDependencies,
  };
}

/// Inspection model for local workspace dependency tree.
class WorkspaceDependencyReport {
  final String workingDirectory;
  final bool hasPackageJson;
  final String? packageName;
  final String? packageVersion;
  final Map<String, String> declaredDependencies;
  final Map<String, String> declaredDevDependencies;
  final List<String> installedModules;
  final List<String> missingModules;

  const WorkspaceDependencyReport({
    required this.workingDirectory,
    required this.hasPackageJson,
    this.packageName,
    this.packageVersion,
    this.declaredDependencies = const {},
    this.declaredDevDependencies = const {},
    this.installedModules = const [],
    this.missingModules = const [],
  });
}

/// Diagnostic report model for npm.
class NpmDoctorReport {
  final bool nodeAvailable;
  final String nodeStatus;
  final bool npmAvailable;
  final String npmStatus;
  final String workingDirectory;
  final bool hasPackageJson;
  final String? packageName;
  final int scriptCount;
  final int dependencyCount;
  final int installedModuleCount;
  final String npmConfigCache;
  final String npmConfigPrefix;

  const NpmDoctorReport({
    required this.nodeAvailable,
    required this.nodeStatus,
    required this.npmAvailable,
    required this.npmStatus,
    required this.workingDirectory,
    required this.hasPackageJson,
    this.packageName,
    this.scriptCount = 0,
    this.dependencyCount = 0,
    this.installedModuleCount = 0,
    required this.npmConfigCache,
    required this.npmConfigPrefix,
  });

  String formatText() {
    final sb = StringBuffer('=== npm Diagnostics (Doctor) ===\n');
    sb.writeln('Node.js Runtime: ${nodeAvailable ? "AVAILABLE" : nodeStatus}');
    sb.writeln('npm Engine: ${npmAvailable ? "AVAILABLE" : npmStatus}');
    sb.writeln('Active Working Directory: $workingDirectory');
    sb.writeln('package.json: ${hasPackageJson ? "PRESENT ($packageName)" : "NOT FOUND"}');
    sb.writeln('Defined Scripts: $scriptCount');
    sb.writeln('Declared Dependencies: $dependencyCount');
    sb.writeln('Installed node_modules: $installedModuleCount');
    sb.writeln('NPM_CONFIG_CACHE: $npmConfigCache');
    sb.writeln('NPM_CONFIG_PREFIX: $npmConfigPrefix');
    sb.writeln('Milestone: v0.72 (npm Package Installation & Module Resolution)');
    return sb.toString().trimRight();
  }
}

/// Standalone, embeddable service for Node.js package management, `package.json`
/// creation/manipulation, script detection, and workspace dependency inspection.
///
/// Designed to be decoupled from terminal UI for direct reuse inside IDEs
/// such as Calypso IDE.
class NpmPackageService {
  static final NpmPackageService _instance = NpmPackageService._internal();
  factory NpmPackageService() => _instance;
  NpmPackageService._internal();

  /// Default npm environment directories relative to Termode sandbox.
  static String defaultNpmCacheDir(String homeDir) => '$homeDir/.npm';
  static String defaultNpmPrefixDir(String homeDir) => '$homeDir/.npm-global';

  /// Generates or initializes a clean, standard `package.json` inside [workingDirectory].
  ///
  /// If [overwrite] is false and `package.json` already exists, returns an error.
  Future<({bool success, String message, PackageJsonMetadata? metadata})>
  initPackageJson({
    required String workingDirectory,
    String? name,
    String? version,
    String? description,
    String? main,
    Map<String, String>? scripts,
    bool overwrite = false,
  }) async {
    final targetDir = Directory(workingDirectory);
    if (!targetDir.existsSync()) {
      return (
        success: false,
        message: 'Target directory does not exist: $workingDirectory',
        metadata: null,
      );
    }

    final targetFile = File('${targetDir.path}/package.json');
    if (targetFile.existsSync() && !overwrite) {
      return (
        success: false,
        message: 'package.json already exists in $workingDirectory. Use overwrite to replace.',
        metadata: await readPackageJson(workingDirectory),
      );
    }

    // Default package name to folder basename, sanitizing to valid npm name
    final folderName = targetDir.uri.pathSegments.where((s) => s.isNotEmpty).isNotEmpty
        ? targetDir.uri.pathSegments.where((s) => s.isNotEmpty).last
        : 'termode-project';
    final safeName = (name ?? folderName)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\-_.]'), '-');

    final effectiveVersion = version ?? '1.0.0';
    final effectiveDescription = description ?? 'Created with Termode npm package manager';
    final effectiveMain = main ?? 'index.js';
    final effectiveScripts = scripts ?? {
      'test': 'echo "Error: no test specified" && exit 1',
      'start': 'node $effectiveMain',
    };

    final map = {
      'name': safeName,
      'version': effectiveVersion,
      'description': effectiveDescription,
      'main': effectiveMain,
      'scripts': effectiveScripts,
      'keywords': <String>[],
      'author': '',
      'license': 'ISC',
      'dependencies': <String, String>{},
      'devDependencies': <String, String>{},
    };

    final jsonContent = const JsonEncoder.withIndent('  ').convert(map);
    targetFile.writeAsStringSync('$jsonContent\n');

    final metadata = PackageJsonMetadata(
      name: safeName,
      version: effectiveVersion,
      description: effectiveDescription,
      main: effectiveMain,
      scripts: effectiveScripts,
      dependencies: {},
      devDependencies: {},
      rawContent: jsonContent,
    );

    return (
      success: true,
      message: 'Wrote to ${targetFile.path}:\n$jsonContent',
      metadata: metadata,
    );
  }

  /// Parses `package.json` in [workingDirectory] if present.
  Future<PackageJsonMetadata?> readPackageJson(String workingDirectory) async {
    final file = File('$workingDirectory/package.json');
    if (!file.existsSync()) return null;

    try {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final name = decoded['name']?.toString() ?? '';
      final version = decoded['version']?.toString() ?? '1.0.0';
      final description = decoded['description']?.toString() ?? '';
      final main = decoded['main']?.toString() ?? 'index.js';

      final scriptsMap = <String, String>{};
      if (decoded['scripts'] is Map) {
        for (final entry in (decoded['scripts'] as Map).entries) {
          scriptsMap[entry.key.toString()] = entry.value.toString();
        }
      }

      final depsMap = <String, String>{};
      if (decoded['dependencies'] is Map) {
        for (final entry in (decoded['dependencies'] as Map).entries) {
          depsMap[entry.key.toString()] = entry.value.toString();
        }
      }

      final devDepsMap = <String, String>{};
      if (decoded['devDependencies'] is Map) {
        for (final entry in (decoded['devDependencies'] as Map).entries) {
          devDepsMap[entry.key.toString()] = entry.value.toString();
        }
      }

      return PackageJsonMetadata(
        name: name,
        version: version,
        description: description,
        main: main,
        scripts: scriptsMap,
        dependencies: depsMap,
        devDependencies: devDepsMap,
        rawContent: raw,
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns map of script targets in [workingDirectory].
  Future<Map<String, String>> getScripts(String workingDirectory) async {
    final metadata = await readPackageJson(workingDirectory);
    return metadata?.scripts ?? const {};
  }

  /// Inspects declared dependencies in `package.json` versus installed folders in `node_modules`.
  Future<WorkspaceDependencyReport> listDependencies(String workingDirectory) async {
    final metadata = await readPackageJson(workingDirectory);
    final nodeModulesDir = Directory('$workingDirectory/node_modules');

    final installed = <String>[];
    if (nodeModulesDir.existsSync()) {
      for (final entity in nodeModulesDir.listSync(followLinks: false)) {
        if (entity is Directory) {
          final base = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (base.startsWith('@')) {
            // Scoped packages: e.g. @types/node
            for (final sub in entity.listSync(followLinks: false)) {
              if (sub is Directory) {
                final subName = sub.uri.pathSegments.where((s) => s.isNotEmpty).last;
                installed.add('$base/$subName');
              }
            }
          } else if (!base.startsWith('.')) {
            installed.add(base);
          }
        }
      }
      installed.sort();
    }

    final missing = <String>[];
    if (metadata != null) {
      for (final dep in metadata.dependencies.keys) {
        if (!installed.contains(dep)) missing.add(dep);
      }
      for (final dep in metadata.devDependencies.keys) {
        if (!installed.contains(dep)) missing.add(dep);
      }
      missing.sort();
    }

    return WorkspaceDependencyReport(
      workingDirectory: workingDirectory,
      hasPackageJson: metadata != null,
      packageName: metadata?.name,
      packageVersion: metadata?.version,
      declaredDependencies: metadata?.dependencies ?? const {},
      declaredDevDependencies: metadata?.devDependencies ?? const {},
      installedModules: installed,
      missingModules: missing,
    );
  }

  /// Generates a diagnostic report for npm and the current workspace.
  Future<NpmDoctorReport> doctor({required String workingDirectory}) async {
    final binaryPkg = RuntimeBinaryPackageService();
    final nodeInstalled = await binaryPkg.nodeInstalled();
    final nodeVerified = await binaryPkg.nodeExecutionVerified();
    final npmInstalled = await binaryPkg.npmInstalled();

    final metadata = await readPackageJson(workingDirectory);
    final depReport = await listDependencies(workingDirectory);

    final homeDir = Directory(workingDirectory).parent.path;

    return NpmDoctorReport(
      nodeAvailable: nodeInstalled || RuntimeBinaryPackageService.nodeExecutorForTesting != null,
      nodeStatus: nodeVerified
          ? 'VERIFIED'
          : (nodeInstalled ? 'INSTALLED (unverified)' : 'NOT_INSTALLED'),
      npmAvailable: npmInstalled || RuntimeBinaryPackageService.npmExecutorForTesting != null,
      npmStatus: npmInstalled ? 'INSTALLED (v10.9.3)' : 'PLANNED (npm 10.9.3)',
      workingDirectory: workingDirectory,
      hasPackageJson: metadata != null,
      packageName: metadata != null ? '${metadata.name}@${metadata.version}' : null,
      scriptCount: metadata?.scripts.length ?? 0,
      dependencyCount:
          (metadata?.dependencies.length ?? 0) + (metadata?.devDependencies.length ?? 0),
      installedModuleCount: depReport.installedModules.length,
      npmConfigCache: defaultNpmCacheDir(homeDir),
      npmConfigPrefix: defaultNpmPrefixDir(homeDir),
    );
  }

  /// Formats dependency listing matching `npm ls` style.
  String formatDependencyTree(WorkspaceDependencyReport report) {
    if (!report.hasPackageJson) {
      return 'npm ERR! code ENOENT\n'
          'npm ERR! syscall open\n'
          'npm ERR! path ${report.workingDirectory}/package.json\n'
          'npm ERR! enoent: no such file or directory, open \'${report.workingDirectory}/package.json\'\n\n'
          'Tip: Run `npm init` or `npm init -y` to create a package.json file.';
    }

    final sb = StringBuffer('${report.packageName ?? "unnamed"}@${report.packageVersion ?? "1.0.0"} ${report.workingDirectory}\n');
    final totalDeclared = report.declaredDependencies.length + report.declaredDevDependencies.length;

    if (totalDeclared == 0 && report.installedModules.isEmpty) {
      sb.writeln('`-- (empty)');
      return sb.toString().trimRight();
    }

    final allEntries = <String, String>{
      ...report.declaredDependencies,
      ...report.declaredDevDependencies,
    };

    var count = 0;
    final total = allEntries.length;
    for (final entry in allEntries.entries) {
      count++;
      final isLast = count == total;
      final prefix = isLast ? '`-- ' : '+-- ';
      final isInstalled = report.installedModules.contains(entry.key);
      final statusSuffix = isInstalled ? ' (installed)' : ' (UNMET DEPENDENCY)';
      sb.writeln('$prefix${entry.key}@${entry.value}$statusSuffix');
    }

    if (report.missingModules.isNotEmpty) {
      sb.writeln('\nnpm WARN unmet dependencies: ${report.missingModules.join(", ")}');
      sb.writeln('npm info: In v0.67 prototype mode, run npm-doctor for environment checks.');
    }

    return sb.toString().trimRight();
  }
}
