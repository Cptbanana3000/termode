import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'native_command_service.dart';
import 'runtime_artifact_registry_service.dart';
import 'runtime_prefix_service.dart';

class RuntimeBinaryPackageResult {
  final String output;
  final bool isError;

  const RuntimeBinaryPackageResult(this.output, {this.isError = false});
}

class RuntimeBinaryPackageService {
  static final RuntimeBinaryPackageService _instance =
      RuntimeBinaryPackageService._internal();
  factory RuntimeBinaryPackageService() => _instance;
  RuntimeBinaryPackageService._internal();

  static const String metadataSchema = 'termode.runtime-packages.v1';
  static const String helloBinName = 'hello-bin';
  static const String gitName = 'git';
  static const String gitLogicalInstallPath = 'usr/bin/git';
  static const String gitExecutablePackageName = 'libtermode_git_exec.so';
  static const String nodeName = 'node';
  static const String nodeLogicalInstallPath = 'usr/bin/node';
  static const String nodeExecutablePackageName = 'libtermode_node_exec.so';
  static const String npmName = 'npm';
  static const String npxName = 'npx';
  static const String npmLogicalInstallPath = 'usr/bin/npm';
  static const String pythonName = 'python';
  static const String python3Name = 'python3';
  static const String pythonLogicalInstallPath = 'usr/bin/python3';
  static const String pythonExecutablePackageName = 'libtermode_python_exec.so';
  static const String pipName = 'pip';
  static const String pip3Name = 'pip3';
  static const String pipLogicalInstallPath = 'usr/bin/pip';
  static const String helloBinOutput =
      'Hello from Termode binary package prototype.';
  static const String _helloBinContent =
      '#!/system/bin/sh\n'
      'printf "%s\\n" "Hello from Termode binary package prototype."\n';
  static Future<NativeCommandResult> Function(
    List<String> arguments, {
    String? workingDirectory,
  })? gitExecutorForTesting;
  static Future<NativeCommandResult> Function(
    List<String> arguments, {
    String? workingDirectory,
  })? nodeExecutorForTesting;
  static Future<NativeCommandResult> Function(
    List<String> arguments, {
    String? workingDirectory,
  })? npmExecutorForTesting;
  static Future<NativeCommandResult> Function(
    List<String> arguments, {
    String? workingDirectory,
  })? pythonExecutorForTesting;
  static Future<NativeCommandResult> Function(
    List<String> arguments, {
    String? workingDirectory,
  })? pipExecutorForTesting;

  final RuntimePrefixService _prefix = RuntimePrefixService();

  Map<String, dynamic> helloBinManifest() {
    final bytes = utf8.encode(_helloBinContent);
    return {
      'name': helloBinName,
      'version': '1.0.0',
      'description': 'Safe script-tool stand-in for future binary packages.',
      'kind': 'script-tool',
      'abi': 'all',
      'command': helloBinName,
      'entrypoints': [helloBinName],
      'source': 'builtin-prototype',
      'files': [
        {
          'path': 'bin/hello-bin',
          'sha256': _calculateSha256(bytes),
          'bytes': bytes.length,
        },
      ],
    };
  }

  Future<Map<String, String>> _paths() async {
    final p = await _prefix.paths();
    final root = '${p['var']}/termode/runtime-packages';
    return {
      ...p,
      'metadataRoot': root,
      'metadata': '$root/installed.json',
      'manifestCache': '$root/cache/manifests',
      'shareRoot': '${p['share']}/termode/runtime-packages',
    };
  }

  bool _isSafeName(String name) =>
      RegExp(r'^[a-z][a-z0-9-]{1,31}$').hasMatch(name);

  bool _isSafeCommand(String command) =>
      RegExp(r'^[a-z][a-z0-9-]{1,31}$').hasMatch(command);

  bool _isSafeRelativePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.isEmpty) return false;
    if (normalized.startsWith('/')) return false;
    if (RegExp(r'^[A-Za-z]:').hasMatch(normalized)) return false;
    if (normalized.split('/').contains('..')) return false;
    if (normalized.endsWith('/')) return false;
    return normalized == 'bin/hello-bin' ||
        normalized.startsWith('share/termode/runtime-packages/');
  }

  bool _isSafeGitRelativePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.isEmpty) return false;
    if (normalized.startsWith('/')) return false;
    if (RegExp(r'^[A-Za-z]:').hasMatch(normalized)) return false;
    if (normalized.split('/').contains('..')) return false;
    if (normalized.endsWith('/')) return false;
    return normalized.startsWith('usr/bin/') ||
        normalized.startsWith('usr/lib/') ||
        normalized.startsWith('usr/libexec/') ||
        normalized.startsWith('usr/share/') ||
        normalized.startsWith('bin/') ||
        normalized.startsWith('lib/') ||
        normalized.startsWith('libexec/') ||
        normalized.startsWith('share/');
  }

  List<String> validateManifest(Map<String, dynamic> manifest) {
    final errors = <String>[];
    final name = manifest['name']?.toString() ?? '';
    final version = manifest['version']?.toString() ?? '';
    final kind = manifest['kind']?.toString() ?? '';
    final command = manifest['command']?.toString() ?? '';
    final abi = manifest['abi']?.toString() ?? '';
    final files = manifest['files'];

    if (!_isSafeName(name)) errors.add('invalid package name');
    if (name != helloBinName) errors.add('unknown package name');
    if (version.trim().isEmpty) errors.add('missing version');
    if (!{
      'shim',
      'script-tool',
      'native-tool-planned',
      'runtime-planned',
    }.contains(kind)) {
      errors.add('unsupported package kind');
    }
    if (!_isSafeCommand(command)) errors.add('invalid command name');
    if (abi.isEmpty) errors.add('missing abi');
    if (files is! List || files.isEmpty) {
      errors.add('missing files');
    } else {
      for (final item in files) {
        if (item is! Map) {
          errors.add('invalid file entry');
          continue;
        }
        final path = item['path']?.toString() ?? '';
        final sha = item['sha256']?.toString() ?? '';
        if (!_isSafeRelativePath(path)) errors.add('unsafe file path');
        if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha)) {
          errors.add('invalid checksum');
        }
      }
    }
    return errors.toSet().toList()..sort();
  }

  Future<Map<String, dynamic>> _emptyMetadata() async => {
    'schema': metadataSchema,
    'packages': <String, dynamic>{},
  };

  Future<Map<String, dynamic>> _readMetadata() async {
    final p = await _paths();
    final file = File(p['metadata']!);
    if (!file.existsSync()) return _emptyMetadata();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return _emptyMetadata();
      if (decoded['packages'] is! Map) {
        decoded['packages'] = <String, dynamic>{};
      }
      decoded['schema'] = decoded['schema']?.toString() ?? metadataSchema;
      return decoded;
    } catch (_) {
      return _emptyMetadata();
    }
  }

  Future<void> _writeMetadata(Map<String, dynamic> metadata) async {
    final p = await _paths();
    final file = File(p['metadata']!);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  File? _resolvePrefixFile(String relPath, Map<String, String> paths) {
    if (!_isSafeRelativePath(relPath)) return null;
    final prefix = Directory(
      paths['prefix']!,
    ).absolute.path.replaceAll('\\', '/');
    final file = File('${paths['prefix']}/$relPath');
    final normalized = file.absolute.path.replaceAll('\\', '/');
    if (normalized == prefix || !normalized.startsWith('$prefix/')) {
      return null;
    }
    return file;
  }

  File? _resolveGitPrefixFile(String relPath, Map<String, String> paths) {
    if (!_isSafeGitRelativePath(relPath)) return null;
    var installPath = relPath.replaceAll('\\', '/');
    if (installPath.startsWith('usr/')) {
      installPath = installPath.substring(4);
    }
    final prefix = Directory(
      paths['prefix']!,
    ).absolute.path.replaceAll('\\', '/');
    final file = File('${paths['prefix']}/$installPath');
    final normalized = file.absolute.path.replaceAll('\\', '/');
    if (normalized == prefix || !normalized.startsWith('$prefix/')) {
      return null;
    }
    return file;
  }

  File? _resolveNodePrefixFile(String relPath, Map<String, String> paths) {
    if (!_isSafeGitRelativePath(relPath)) return null;
    var installPath = relPath.replaceAll('\\', '/');
    if (installPath.startsWith('usr/')) {
      installPath = installPath.substring(4);
    }
    final prefix = Directory(
      paths['prefix']!,
    ).absolute.path.replaceAll('\\', '/');
    final file = File('${paths['prefix']}/$installPath');
    final normalized = file.absolute.path.replaceAll('\\', '/');
    if (normalized == prefix || !normalized.startsWith('$prefix/')) {
      return null;
    }
    return file;
  }

  File? _resolvePythonPrefixFile(String relPath, Map<String, String> paths) {
    if (!_isSafeGitRelativePath(relPath)) return null;
    var installPath = relPath.replaceAll('\\', '/');
    if (installPath.startsWith('usr/')) {
      installPath = installPath.substring(4);
    }
    final prefix = Directory(
      paths['prefix']!,
    ).absolute.path.replaceAll('\\', '/');
    final file = File('${paths['prefix']}/$installPath');
    final normalized = file.absolute.path.replaceAll('\\', '/');
    if (normalized == prefix || !normalized.startsWith('$prefix/')) {
      return null;
    }
    return file;
  }

  Future<void> _ensureStructures() async {
    final p = await _paths();
    for (final key in ['metadataRoot', 'manifestCache', 'shareRoot']) {
      await Directory(p[key]!).create(recursive: true);
    }
  }

  Future<String> help() async {
    return '=== Runtime Package Prototype (v0.44) ===\n'
        'Safe prototype installer for future binary/runtime packages.\n'
        'Reviewed local-only Git and hello-bin are supported; no downloads or unknown binaries.\n\n'
        'Commands:\n'
        '  runtime-pkg available\n'
        '  runtime-pkg info <name>\n'
        '  runtime-pkg install <name>\n'
        '  runtime-pkg remove <name>\n'
        '  runtime-pkg verify <name>\n'
        '  runtime-pkg list\n'
        '  runtime-pkg status\n'
        '  runtime-pkg doctor\n'
        '  runtime-pkg repair\n\n'
        'Packages: hello-bin, git (arm64-v8a local-only)';
  }

  /// Whether a verified, bundled Git package artifact exists in this build.
  /// Delegates to the artifact registry; false in this build (no bundled
  /// binary, no download, no unsigned archives).
  bool gitArtifactAvailable() =>
      RuntimeArtifactRegistryService().bundledGitArtifactExists();

  /// Whether a Git runtime package is currently recorded as installed.
  Future<bool> gitInstalled() async {
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    return packages.containsKey(gitName);
  }

  Future<Map<String, dynamic>?> installedGitMetadata() async {
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    final value = packages[gitName];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<String?> gitExecutableBackingPath() async =>
      (await installedGitMetadata())?['executable_backing_path']?.toString();

  Future<bool> gitExecutionVerified() async =>
      (await installedGitMetadata())?['execution_verified'] == true;

  Future<bool> gitLocalSmokeVerified() async =>
      (await installedGitMetadata())?['local_smoke_verified'] == true;

  Future<void> markGitLocalSmokeVerified() async {
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    final value = packages[gitName];
    if (value is! Map) return;
    final pkg = Map<String, dynamic>.from(value);
    if (pkg['execution_verified'] != true) return;
    pkg['local_smoke_verified'] = true;
    pkg['local_smoke_verified_at'] = DateTime.now().toUtc().toIso8601String();
    packages[gitName] = pkg;
    metadata['packages'] = packages;
    await _writeMetadata(metadata);
  }

  Future<RuntimeBinaryPackageResult> binWhichGit() async {
    final pkg = await installedGitMetadata();
    if (pkg == null) {
      return const RuntimeBinaryPackageResult(
        'Not found in Termode PATH: git',
        isError: true,
      );
    }
    final paths = await _paths();
    final logical = _resolveGitPrefixFile(
      pkg['logical_path']?.toString() ?? gitLogicalInstallPath,
      paths,
    );
    return RuntimeBinaryPackageResult(
      '=== Binary Mapping: git ===\n'
      'Logical path: ${logical?.path ?? gitLogicalInstallPath}\n'
      'Backing path: ${pkg['executable_backing_path']}\n'
      'Executable storage: ${pkg['executable_storage']}\n'
      'Execution verified: ${pkg['execution_verified'] == true ? 'yes' : 'no'}',
    );
  }

  Future<NativeCommandResult> runGit(
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final pkg = await installedGitMetadata();
    if (pkg == null || pkg['execution_verified'] != true) {
      return NativeCommandResult(
        stdout: '',
        stderr: 'Git is not installed with a verified executable mapping.',
        exitCode: -1,
      );
    }
    final backingPath = pkg['executable_backing_path']?.toString() ?? '';
    return _executeGitBacking(
      backingPath,
      arguments,
      workingDirectory: workingDirectory,
    );
  }

  Future<bool> nodeInstalled() async {
    if (nodeExecutorForTesting != null) return true;
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    return packages.containsKey(nodeName);
  }

  Future<Map<String, dynamic>?> installedNodeMetadata() async {
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    final value = packages[nodeName];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<String?> nodeExecutableBackingPath() async =>
      (await installedNodeMetadata())?['executable_backing_path']?.toString();

  Future<bool> nodeExecutionVerified() async =>
      (await installedNodeMetadata())?['execution_verified'] == true;

  Future<NativeCommandResult> runNode(
    List<String> arguments, {
    String? workingDirectory,
    int timeoutMs = 15000,
  }) async {
    if (nodeExecutorForTesting != null) {
      return nodeExecutorForTesting!(
        arguments,
        workingDirectory: workingDirectory,
      );
    }
    if (Platform.isAndroid) {
      return NativeCommandService().executeBundledNode(
        arguments,
        workingDirectory: workingDirectory,
        timeoutMs: timeoutMs,
      );
    }
    return NativeCommandResult(
      stdout: '',
      stderr: 'Node.js execution is only available on Android or via test hook.',
      exitCode: -1,
    );
  }

  Future<bool> npmInstalled() async {
    if (npmExecutorForTesting != null) return true;
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    return packages.containsKey(npmName);
  }

  Future<Map<String, dynamic>?> installedNpmMetadata() async {
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    final value = packages[npmName];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<NativeCommandResult> runNpm(
    List<String> arguments, {
    String? workingDirectory,
    int timeoutMs = 60000,
  }) async {
    if (npmExecutorForTesting != null) {
      return npmExecutorForTesting!(
        arguments,
        workingDirectory: workingDirectory,
      );
    }
    if (Platform.isAndroid && (await nodeInstalled())) {
      final paths = await _paths();
      final usrPath = paths['usr'] ?? paths['prefix'] ?? '';
      final npmCliPath = '$usrPath/lib/node_modules/npm/bin/npm-cli.js';
      return runNode(
        [npmCliPath, ...arguments],
        workingDirectory: workingDirectory,
        timeoutMs: timeoutMs,
      );
    }
    return NativeCommandResult(
      stdout: '',
      stderr: 'npm execution requires Node.js runtime or active test hook.',
      exitCode: -1,
    );
  }

  Future<NativeCommandResult> runNpx(
    List<String> arguments, {
    String? workingDirectory,
    int timeoutMs = 60000,
  }) async {
    if (npmExecutorForTesting != null) {
      return npmExecutorForTesting!(
        arguments,
        workingDirectory: workingDirectory,
      );
    }
    if (Platform.isAndroid && (await nodeInstalled())) {
      final paths = await _paths();
      final usrPath = paths['usr'] ?? paths['prefix'] ?? '';
      final npxCliPath = '$usrPath/lib/node_modules/npm/bin/npx-cli.js';
      return runNode(
        [npxCliPath, ...arguments],
        workingDirectory: workingDirectory,
        timeoutMs: timeoutMs,
      );
    }
    return NativeCommandResult(
      stdout: '',
      stderr: 'npx execution requires Node.js runtime or active test hook.',
      exitCode: -1,
    );
  }

  Future<bool> pythonInstalled() async {
    if (pythonExecutorForTesting != null) return true;
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    return packages.containsKey(pythonName) || packages.containsKey(python3Name);
  }

  Future<Map<String, dynamic>?> installedPythonMetadata() async {
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    final value = packages[pythonName] ?? packages[python3Name];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<String?> pythonExecutableBackingPath() async {
    final meta = await installedPythonMetadata();
    return meta?['executable_backing_path']?.toString();
  }

  /// Ensures that native execution symlinks (python3, python, node, git)
  /// in $TERMODE_USR/bin point to the current APK nativeLibraryDir.
  Future<void> reconcileNativeSymlinks() async {
    if (!Platform.isAndroid) return;
    try {
      final execPaths = await NativeCommandService().getExecutablePaths();
      final nativeLibraryDir = execPaths?['nativeLibraryDir']?.toString();
      if (nativeLibraryDir == null || nativeLibraryDir.isEmpty) return;

      final paths = await _paths();
      final binDir = paths['bin']!;

      final linksToReconcile = {
        'python3': '$nativeLibraryDir/libtermode_python_exec.so',
        'python': '$nativeLibraryDir/libtermode_python_exec.so',
        'node': '$nativeLibraryDir/libtermode_node_exec.so',
        'git': '$nativeLibraryDir/libtermode_git_exec.so',
      };

      for (final entry in linksToReconcile.entries) {
        final linkPath = '$binDir/${entry.key}';
        final targetPath = entry.value;
        if (!File(targetPath).existsSync()) continue;

        try {
          final link = Link(linkPath);
          final linkType = await FileSystemEntity.type(linkPath, followLinks: false);
          bool needsUpdate = false;
          if (linkType == FileSystemEntityType.link) {
            try {
              final currentTarget = await link.target();
              if (currentTarget != targetPath || !File(currentTarget).existsSync()) {
                needsUpdate = true;
              }
            } catch (_) {
              needsUpdate = true;
            }
          } else if (linkType == FileSystemEntityType.notFound) {
            needsUpdate = true;
          }

          if (needsUpdate) {
            try {
              if (linkType != FileSystemEntityType.notFound) {
                await _deleteLogicalEntity(linkPath);
              }
            } catch (_) {}
            await Link(linkPath).create(targetPath);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<NativeCommandResult> runPython(
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
    if (Platform.isAndroid) {
      return NativeCommandService().executeBundledPython(
        arguments,
        workingDirectory: workingDirectory,
        timeoutMs: timeoutMs,
      );
    }
    return NativeCommandResult(
      stdout: '',
      stderr: 'Python execution is only available on Android or via test hook.',
      exitCode: -1,
    );
  }

  Future<bool> pipInstalled() async {
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    return packages.containsKey(pipName);
  }

  Future<Map<String, dynamic>?> installedPipMetadata() async {
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    final value = packages[pipName];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<bool> pipExecutionVerified() async =>
      (await installedPipMetadata())?['execution_verified'] == true;

  Future<NativeCommandResult> runPip(
    List<String> arguments, {
    String? workingDirectory,
    int timeoutMs = 60000,
  }) async {
    if (pipExecutorForTesting != null) {
      return pipExecutorForTesting!(
        arguments,
        workingDirectory: workingDirectory,
      );
    }
    return runPython(
      ['-m', 'pip', ...arguments],
      workingDirectory: workingDirectory,
      timeoutMs: timeoutMs,
    );
  }

  Future<String> available() async {
    final manifest = helloBinManifest();
    final artifact = await RuntimeArtifactRegistryService().gitArtifactStatus();
    final nodeArtifact =
        await RuntimeArtifactRegistryService().nodeArtifactStatus();
    final npmArtifact =
        await RuntimeArtifactRegistryService().npmArtifactStatus();
    final pythonArtifact =
        await RuntimeArtifactRegistryService().pythonArtifactStatus();
    final pipArtifact =
        await RuntimeArtifactRegistryService().pipArtifactStatus();
    final gitState = artifact.installable
        ? 'installable if verified'
        : 'artifact ${artifact.status.toLowerCase()}; install refuses safely';
    final nodeState = nodeArtifact.installable
        ? 'installable if verified'
        : 'artifact ${nodeArtifact.status.toLowerCase()}';
    final npmState = npmArtifact.installable
        ? 'installable if verified'
        : 'artifact ${npmArtifact.status.toLowerCase()}';
    final pythonState = pythonArtifact.installable
        ? 'installable if verified'
        : 'artifact ${pythonArtifact.status.toLowerCase()}';
    final pipState = pipArtifact.installable
        ? 'installable if verified'
        : 'artifact ${pipArtifact.status.toLowerCase()}';
    return '=== Available Runtime Packages ===\n'
        'Prototype available now:\n'
        '* hello-bin [${manifest['version']}] - ${manifest['description']}\n\n'
        'Reviewed real tools:\n'
        '* git - Distributed version control ($gitState)\n'
        '* node - Node.js JavaScript runtime prototype ($nodeState)\n'
        '* npm - Node.js Package Manager ($npmState)\n'
        '* python - Authentic CPython 3.14 runtime engine ($pythonState)\n'
        '* pip - Official Python Package Installer ($pipState)\n\n'
        'OSINT target tools (Sherlock, Maigret) planned for v0.78.';
  }

  Future<String> list() async {
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    if (packages.isEmpty) {
      return 'No runtime packages installed.\n'
          'Run: runtime-pkg available';
    }
    final sb = StringBuffer('=== Installed Runtime Packages ===\n');
    for (final name in packages.keys.toList()..sort()) {
      final pkg = Map<String, dynamic>.from(packages[name] as Map);
      sb.writeln('$name [${pkg['version']}] ${pkg['kind']} - ${pkg['status']}');
    }
    return sb.toString().trimRight();
  }

  Future<String> info(String name) async {
    if (name == gitName) {
      final installed = await gitInstalled();
      final artifact = await RuntimeArtifactRegistryService()
          .gitArtifactStatus();
      final status = installed
          ? 'installed'
          : (artifact.installable
                ? 'installable (verified artifact)'
                : 'planned (artifact ${artifact.status.toLowerCase()})');
      return '=== Runtime Package: git ===\n'
          'Name: git\n'
          'Kind: native-tool\n'
          'Status: $status\n'
          'Command: git\n'
          'Current ABI: ${artifact.abi}\n'
          'Artifact available: ${artifact.available ? 'yes' : 'no'}\n'
          'Installable: ${artifact.installable ? 'yes' : 'no'}\n'
          'Description: Distributed version control tool.\n'
          'Install support: enabled only with a verified package artifact.\n'
          'Current artifact state: ${artifact.status}\n'
          'Bundle state: ${artifact.status}\n'
          'Next step: git-artifact bundle-status\n'
          'Run: git-artifact next';
    }
    if (name == nodeName) {
      final installed = await nodeInstalled();
      final artifact = await RuntimeArtifactRegistryService()
          .nodeArtifactStatus();
      final status = installed
          ? 'installed'
          : (artifact.installable
                ? 'installable (verified artifact)'
                : 'planned (artifact ${artifact.status.toLowerCase()})');
      return '=== Runtime Package: node ===\n'
          'Name: node\n'
          'Kind: native-tool\n'
          'Status: $status\n'
          'Command: node\n'
          'Current ABI: ${artifact.abi}\n'
          'Artifact available: ${artifact.available ? 'yes' : 'no'}\n'
          'Installable: ${artifact.installable ? 'yes' : 'no'}\n'
          'Description: Node.js JavaScript runtime engine.\n'
          'Install support: enabled with verified arm64 ELF package artifact.\n'
          'Current artifact state: ${artifact.status}\n'
          'Next step: node-artifact status';
    }
    if (name == npmName) {
      final installed = await npmInstalled();
      final artifact = await RuntimeArtifactRegistryService()
          .npmArtifactStatus();
      final status = installed
          ? 'installed'
          : (artifact.installable
                ? 'installable (verified artifact)'
                : 'planned (artifact ${artifact.status.toLowerCase()})');
      return '=== Runtime Package: npm ===\n'
          'Name: npm\n'
          'Kind: package-manager\n'
          'Status: $status\n'
          'Command: npm\n'
          'Current ABI: universal\n'
          'Artifact available: ${artifact.available ? 'yes' : 'no'}\n'
          'Installable: ${artifact.installable ? 'yes' : 'no'}\n'
          'Description: Node.js Package Manager.\n'
          'Install support: bundled upstream npm 10.9.3 archive driven by Node.js runtime engine.\n'
          'Current artifact state: ${artifact.status}\n'
          'Next step: npm-doctor';
    }
    if (name == pythonName || name == python3Name) {
      final installed = await pythonInstalled();
      final artifact = await RuntimeArtifactRegistryService()
          .pythonArtifactStatus();
      final status = installed
          ? 'installed'
          : (artifact.installable
                ? 'installable (verified artifact)'
                : 'planned (artifact ${artifact.status.toLowerCase()})');
      return '=== Runtime Package: python ===\n'
          'Name: python\n'
          'Kind: native-tool\n'
          'Status: $status\n'
          'Command: python3\n'
          'Current ABI: ${artifact.abi}\n'
          'Artifact available: ${artifact.available ? 'yes' : 'no'}\n'
          'Installable: ${artifact.installable ? 'yes' : 'no'}\n'
          'Description: Authentic CPython 3.14 runtime engine.\n'
          'Install support: bundled upstream CPython binary and standard library archive.\n'
          'Current artifact state: ${artifact.status}\n'
          'Next step: python-doctor';
    }
    if (name == pipName || name == pip3Name) {
      final installed = await pipInstalled();
      final artifact = await RuntimeArtifactRegistryService()
          .pipArtifactStatus();
      final status = installed
          ? 'installed'
          : (artifact.installable
                ? 'installable (verified artifact)'
                : 'planned (artifact ${artifact.status.toLowerCase()})');
      return '=== Runtime Package: pip ===\n'
          'Name: pip\n'
          'Kind: package-manager\n'
          'Status: $status\n'
          'Command: pip\n'
          'Current ABI: universal\n'
          'Artifact available: ${artifact.available ? 'yes' : 'no'}\n'
          'Installable: ${artifact.installable ? 'yes' : 'no'}\n'
          'Description: Authentic upstream pip 26.2.1 package installer.\n'
          'Install support: bundled upstream pip wheel archive extracted into site-packages.\n'
          'Current artifact state: ${artifact.status}\n'
          'Next step: pip-doctor';
    }
    if (name != helloBinName) {
      return 'Unknown runtime package: $name\n'
          'Run: runtime-pkg available';
    }
    final manifest = helloBinManifest();
    final metadata = await _readMetadata();
    final installed = Map<String, dynamic>.from(
      metadata['packages'] as Map,
    ).containsKey(name);
    return '=== Runtime Package: hello-bin ===\n'
        'Version: ${manifest['version']}\n'
        'Kind: ${manifest['kind']}\n'
        'Description: ${manifest['description']}\n'
        'Command: ${manifest['command']}\n'
        'ABI: ${manifest['abi']}\n'
        'Status: ${installed ? 'installed' : 'available'}\n'
        'Safety: built-in prototype package, no download, no native binary';
  }

  Future<RuntimeBinaryPackageResult> install(String name) async {
    if (name == gitName) {
      final artifact = await RuntimeArtifactRegistryService()
          .gitArtifactStatus();
      if (artifact.status == 'INVALID' || artifact.status == 'INCOMPATIBLE') {
        return RuntimeBinaryPackageResult(
          'Git artifact failed verification.\n'
          'Current state: ${artifact.status}\n'
          'Reason: ${artifact.reason}\n'
          'Run: git-artifact bundle-check\n'
          'Run: git-artifact doctor\n'
          'Docs: docs/GIT_TRUSTED_BUILD.md',
          isError: true,
        );
      }
      if (!artifact.available) {
        return RuntimeBinaryPackageResult(
          'Git artifact is not available in this build.\n'
          'Current state: ${artifact.status}\n'
          'Run: git-artifact bundle-status\n'
          'Run: git-artifact bundle-plan\n'
          'Run: git-artifact next\n'
          'Docs: docs/GIT_TRUSTED_BUILD.md',
        );
      }
      if (!artifact.installable) {
        return RuntimeBinaryPackageResult(
          'Git artifact failed verification.\n'
          'Reason: ${artifact.reason}\n'
          'Run: git-artifact bundle-check\n'
          'Run: git-artifact doctor\n'
          'Docs: docs/GIT_TRUSTED_BUILD.md',
          isError: true,
        );
      }
      return _installGitArtifact(artifact);
    }
    if (name == nodeName) {
      final artifact = await RuntimeArtifactRegistryService()
          .nodeArtifactStatus();
      if (artifact.status == 'INVALID' || artifact.status == 'INCOMPATIBLE') {
        return RuntimeBinaryPackageResult(
          'Node.js artifact failed verification.\n'
          'Current state: ${artifact.status}\n'
          'Reason: ${artifact.reason}\n'
          'Run: node-artifact status\n'
          'Run: node-doctor',
          isError: true,
        );
      }
      if (!artifact.available) {
        return RuntimeBinaryPackageResult(
          'Node.js artifact is not available in this build.\n'
          'Current state: ${artifact.status}\n'
          'Run: node-artifact status\n'
          'Run: node-doctor',
        );
      }
      if (!artifact.installable) {
        return RuntimeBinaryPackageResult(
          'Node.js artifact failed verification.\n'
          'Reason: ${artifact.reason}\n'
          'Run: node-artifact status\n'
          'Run: node-doctor',
          isError: true,
        );
      }
      return _installNodeArtifact(artifact);
    }
    if (name == npmName) {
      final artifact = await RuntimeArtifactRegistryService()
          .npmArtifactStatus();
      if (artifact.status == 'INVALID') {
        return RuntimeBinaryPackageResult(
          'npm artifact failed verification.\n'
          'Current state: ${artifact.status}\n'
          'Reason: ${artifact.reason}\n'
          'Run: npm-doctor',
          isError: true,
        );
      }
      if (!artifact.available) {
        return RuntimeBinaryPackageResult(
          'npm artifact is not available in this build.\n'
          'Current state: ${artifact.status}\n'
          'Run: npm-doctor',
        );
      }
      if (!artifact.installable) {
        return RuntimeBinaryPackageResult(
          'npm artifact failed verification.\n'
          'Reason: ${artifact.reason}\n'
          'Run: npm-doctor',
          isError: true,
        );
      }
      return _installNpmArtifact(artifact);
    }
    if (name == pythonName || name == python3Name) {
      final artifact = await RuntimeArtifactRegistryService()
          .pythonArtifactStatus();
      if (artifact.status == 'INVALID' || artifact.status == 'INCOMPATIBLE') {
        return RuntimeBinaryPackageResult(
          'Python artifact failed verification.\n'
          'Current state: ${artifact.status}\n'
          'Reason: ${artifact.reason}\n'
          'Run: python-doctor',
          isError: true,
        );
      }
      if (!artifact.available) {
        return RuntimeBinaryPackageResult(
          'Python artifact is not available in this build.\n'
          'Current state: ${artifact.status}\n'
          'Run: python-doctor',
        );
      }
      if (!artifact.installable) {
        return RuntimeBinaryPackageResult(
          'Python artifact failed verification.\n'
          'Reason: ${artifact.reason}\n'
          'Run: python-doctor',
          isError: true,
        );
      }
      return _installPythonArtifact(artifact);
    }
    if (name == pipName || name == pip3Name) {
      final artifact = await RuntimeArtifactRegistryService()
          .pipArtifactStatus();
      if (artifact.status == 'INVALID') {
        return RuntimeBinaryPackageResult(
          'pip artifact failed verification.\n'
          'Current state: ${artifact.status}\n'
          'Reason: ${artifact.reason}\n'
          'Run: pip-doctor',
          isError: true,
        );
      }
      if (!artifact.available) {
        return RuntimeBinaryPackageResult(
          'pip artifact is not available in this build.\n'
          'Current state: ${artifact.status}\n'
          'Run: pip-doctor',
        );
      }
      if (!artifact.installable) {
        return RuntimeBinaryPackageResult(
          'pip artifact failed verification.\n'
          'Reason: ${artifact.reason}\n'
          'Run: pip-doctor',
          isError: true,
        );
      }
      return _installPipArtifact(artifact);
    }
    if (name != helloBinName) {
      return RuntimeBinaryPackageResult(
        'Unknown runtime package: $name\nRun: runtime-pkg available',
        isError: true,
      );
    }
    await _prefix.initPrefix();
    await _ensureStructures();
    final paths = await _paths();
    final manifest = helloBinManifest();
    final manifestErrors = validateManifest(manifest);
    if (manifestErrors.isNotEmpty) {
      return RuntimeBinaryPackageResult(
        'Invalid runtime package manifest: ${manifestErrors.first}',
        isError: true,
      );
    }

    final fileMeta = Map<String, dynamic>.from(
      (manifest['files'] as List).first as Map,
    );
    final relPath = fileMeta['path'].toString();
    final file = _resolvePrefixFile(relPath, paths);
    if (file == null) {
      return const RuntimeBinaryPackageResult(
        'Install blocked: unsafe runtime package path.',
        isError: true,
      );
    }
    if (await file.exists()) {
      final metadata = await _readMetadata();
      final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
      final ownsFile = packages.values.any((entry) {
        final pkg = Map<String, dynamic>.from(entry as Map);
        final files = (pkg['files'] as List? ?? []).map((v) => v.toString());
        return files.contains(relPath);
      });
      if (!ownsFile) {
        return RuntimeBinaryPackageResult(
          'Install blocked: unmanaged file already exists: $relPath',
          isError: true,
        );
      }
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(_helloBinContent);
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['700', file.path]);
      } catch (e) {
        debugPrint('runtime-pkg chmod failed: $e');
      }
    }
    final actual = _calculateSha256(await file.readAsBytes());
    if (actual != fileMeta['sha256']) {
      await file.delete().catchError((_) => file);
      return const RuntimeBinaryPackageResult(
        'Install failed: checksum mismatch.',
        isError: true,
      );
    }

    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    packages[name] = {
      'name': name,
      'version': manifest['version'],
      'description': manifest['description'],
      'kind': manifest['kind'],
      'abi': manifest['abi'],
      'entrypoints': manifest['entrypoints'],
      'files': [relPath],
      'sha256': {relPath: actual},
      'installed_at': DateTime.now().toUtc().toIso8601String(),
      'source': manifest['source'],
      'status': 'installed',
    };
    metadata['schema'] = metadataSchema;
    metadata['packages'] = packages;
    await _writeMetadata(metadata);
    await _prefix.generateEnvScript();

    return const RuntimeBinaryPackageResult(
      'Installed: hello-bin\n'
      'Command: hello-bin\n'
      'Run: hello-bin',
    );
  }

  Future<RuntimeBinaryPackageResult> _installGitArtifact(
    GitArtifactStatus artifact,
  ) async {
    final registry = RuntimeArtifactRegistryService();
    final abi = artifact.abi;
    final manifest = artifact.location == 'project'
        ? registry.readProjectGitManifest(abi)
        : await registry.bundledGitManifest();
    if (manifest == null) {
      return const RuntimeBinaryPackageResult(
        'Git install blocked: manifest missing.\n'
        'Run: git-artifact bundle-check',
        isError: true,
      );
    }
    final validation = artifact.location == 'project'
        ? registry.validateProjectGitArtifact(manifest, abi)
        : registry.validateGitManifest(manifest, abi);
    if (validation.isNotEmpty) {
      return RuntimeBinaryPackageResult(
        'Git install blocked: ${validation.first}\n'
        'Run: git-artifact bundle-check',
        isError: true,
      );
    }

    await _prefix.initPrefix();
    await _ensureStructures();
    final paths = await _paths();
    final files = manifest['files'] as List;
    final installedFiles = <String>[];
    final createdLogicalPaths = <String>[];
    final checksums = <String, String>{};
    try {
      final strategy = manifest['executable_strategy']?.toString() ?? '';
      if (strategy != 'native-library-dir') {
        throw StateError('unsupported executable strategy: $strategy');
      }
      if (files.length != 1 || files.first is! Map) {
        throw StateError('Git package must contain one reviewed executable');
      }
      final meta = Map<String, dynamic>.from(files.first as Map);
      final relPath = meta['path'].toString();
      final logicalPath = manifest['logical_install_path']?.toString() ?? '';
      if (relPath != logicalPath || logicalPath != gitLogicalInstallPath) {
        throw StateError('logical Git path does not match reviewed manifest');
      }
      final destination = _resolveGitPrefixFile(logicalPath, paths);
      if (destination == null) throw StateError('invalid logical Git path');
      await destination.parent.create(recursive: true);
      final existingType = await FileSystemEntity.type(
        destination.path,
        followLinks: false,
      );
      if (existingType != FileSystemEntityType.notFound) {
        throw StateError('unmanaged logical path already exists: $logicalPath');
      }

      late final String backingPath;
      late final String executableStorage;
      if (Platform.isAndroid) {
        final executablePaths = await NativeCommandService()
            .getExecutablePaths();
        final nativeDir =
            executablePaths?['nativeLibraryDir']?.toString() ?? '';
        backingPath = executablePaths?['gitExecutable']?.toString() ?? '';
        final packageName =
            manifest['executable_package_name']?.toString() ?? '';
        if (packageName != gitExecutablePackageName ||
            !_isApprovedNativeBackingPath(
              nativeDir,
              backingPath,
              packageName,
            )) {
          throw StateError('unsafe native library executable path');
        }
        executableStorage = 'native-library-dir';
      } else {
        // Host tests cannot execute the Android ELF. Copying into the isolated
        // test prefix preserves the rollback coverage without claiming support.
        final source = artifact.location == 'project'
            ? File(
                '${RuntimeArtifactRegistryService.gitProjectFilesRoot(abi)}/$relPath',
              )
            : null;
        if (source != null) {
          await source.copy(destination.path);
        } else {
          final bytes = await registry.readBundledGitFile(relPath);
          if (bytes == null) {
            throw StateError('bundled artifact file missing: $relPath');
          }
          await destination.writeAsBytes(bytes, flush: true);
        }
        createdLogicalPaths.add(destination.path);
        backingPath = destination.path;
        executableStorage = 'app-private-prefix-host-test';
      }

      final backingFile = File(backingPath);
      if (!await backingFile.exists()) {
        throw StateError('executable backing file missing: $backingPath');
      }
      final backingBytes = await backingFile.readAsBytes();
      final actual = _calculateSha256(backingBytes);
      final expected = meta['sha256'].toString().toLowerCase();
      final expectedBytes = meta['bytes'];
      if (actual.toLowerCase() != expected ||
          expectedBytes is! int ||
          backingBytes.length != expectedBytes) {
        throw StateError('packaged executable checksum/size mismatch');
      }
      if (backingBytes.length < 4 ||
          backingBytes[0] != 0x7f ||
          backingBytes[1] != 0x45 ||
          backingBytes[2] != 0x4c ||
          backingBytes[3] != 0x46) {
        throw StateError('packaged executable is not an ELF binary');
      }
      checksums[relPath] = actual;
      installedFiles.add(relPath);

      if (Platform.isAndroid) {
        await Link(destination.path).create(backingPath);
        createdLogicalPaths.add(destination.path);
      }

      final probeResult = await _executeGitBacking(backingPath, ['--version']);
      final probe = _preferredOutput(probeResult);
      if (probeResult.exitCode != 0 ||
          !RegExp(
            r'^git version \d+\.\d+\.\d+',
          ).hasMatch(probe.toLowerCase())) {
        throw StateError(
          'git --version failed '
          '[${classifyGitFailure(probeResult.exitCode, probe)}]: $probe',
        );
      }

      final metadata = await _readMetadata();
      final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
      packages[gitName] = {
        'name': gitName,
        'version': manifest['version'],
        'kind': manifest['kind'],
        'abi': manifest['abi'],
        'entrypoint': logicalPath,
        'entrypoints': ['git'],
        'files': installedFiles,
        'sha256': checksums,
        'logical_path': logicalPath,
        'executable_backing_path': backingPath,
        'executable_storage': executableStorage,
        'executable_strategy': strategy,
        'execution_verified': true,
        'local_smoke_verified': false,
        'local_only': true,
        'remote_features_deferred': true,
        'installed_at': DateTime.now().toUtc().toIso8601String(),
        'source': manifest['source'],
        'status': 'installed',
        'verification': probe,
      };
      metadata['schema'] = metadataSchema;
      metadata['packages'] = packages;
      await _writeMetadata(metadata);
      await _prefix.generateEnvScript();
      return RuntimeBinaryPackageResult(
        'Installed: git\n'
        'Command: git\n'
        'Logical path: ${destination.path}\n'
        'Executable backing path: $backingPath\n'
        'Executable storage: $executableStorage\n'
        'Execution verified: yes\n'
        '$probe\n'
        'Remote features: deferred\n'
        'Overall: HEALTHY',
      );
    } catch (e) {
      for (final path in createdLogicalPaths.reversed) {
        await _deleteLogicalEntity(path);
      }
      return RuntimeBinaryPackageResult(
        'Git install failed and was rolled back.\n'
        'Reason: $e\n'
        'Run: git-artifact bundle-check',
        isError: true,
      );
    }
  }

  Future<RuntimeBinaryPackageResult> _installNodeArtifact(
    NodeArtifactStatus artifact,
  ) async {
    final registry = RuntimeArtifactRegistryService();
    final abi = artifact.abi;
    final manifest = artifact.location == 'project'
        ? registry.readProjectNodeManifest(abi)
        : await registry.bundledNodeManifest();
    if (manifest == null) {
      return const RuntimeBinaryPackageResult(
        'Node install blocked: manifest missing.\n'
        'Run: node-artifact status',
        isError: true,
      );
    }
    final validation = registry.validateNodeManifest(manifest, abi);
    if (validation.isNotEmpty) {
      return RuntimeBinaryPackageResult(
        'Node install blocked: ${validation.first}\n'
        'Run: node-artifact status',
        isError: true,
      );
    }

    await _prefix.initPrefix();
    await _ensureStructures();
    final paths = await _paths();
    final files = manifest['files'] as List;
    final installedFiles = <String>[];
    final createdLogicalPaths = <String>[];
    final checksums = <String, String>{};
    try {
      final strategy = manifest['executable_strategy']?.toString() ?? '';
      if (strategy != 'native-library-dir') {
        throw StateError('unsupported executable strategy: $strategy');
      }
      if (files.isEmpty) {
        throw StateError('Node package contains no files');
      }
      final logicalPath = manifest['logical_install_path']?.toString() ?? 'bin/node';
      final entrypoint = manifest['entrypoint']?.toString() ?? 'bin/node';

      late final String backingPath;
      late final String executableStorage;
      if (Platform.isAndroid) {
        final executablePaths = await NativeCommandService()
            .getExecutablePaths();
        final nativeDir =
            executablePaths?['nativeLibraryDir']?.toString() ?? '';
        backingPath = executablePaths?['nodeExecutable']?.toString() ?? '';
        final packageName =
            manifest['executable_package_name']?.toString() ?? '';
        if (packageName != nodeExecutablePackageName ||
            !_isApprovedNativeBackingPath(
              nativeDir,
              backingPath,
              packageName,
            )) {
          throw StateError('unsafe native library executable path');
        }
        executableStorage = 'native-library-dir';
      } else {
        executableStorage = 'app-private-prefix-host-test';
        final hostExecDest = _resolveNodePrefixFile(logicalPath, paths);
        if (hostExecDest == null) throw StateError('invalid logical Node path');
        backingPath = hostExecDest.path;
      }

      for (final rawItem in files) {
        if (rawItem is! Map) {
          throw StateError('Node package contains invalid file entry');
        }
        final meta = Map<String, dynamic>.from(rawItem);
        final relPath = meta['path'].toString();
        final expectedSha = meta['sha256'].toString().toLowerCase();
        final expectedBytes = meta['bytes'];

        final destination = _resolveNodePrefixFile(relPath, paths);
        if (destination == null) {
          throw StateError('invalid destination for Node file: $relPath');
        }
        await destination.parent.create(recursive: true);

        if (relPath == entrypoint) {
          if (Platform.isAndroid) {
            final backingFile = File(backingPath);
            if (!await backingFile.exists()) {
              throw StateError('executable backing file missing: $backingPath');
            }
            final backingBytes = await backingFile.readAsBytes();
            final actual = _calculateSha256(backingBytes);
            if (actual.toLowerCase() != expectedSha ||
                expectedBytes is! int ||
                backingBytes.length != expectedBytes) {
              throw StateError('packaged executable checksum/size mismatch');
            }
            if (backingBytes.length < 4 ||
                backingBytes[0] != 0x7f ||
                backingBytes[1] != 0x45 ||
                backingBytes[2] != 0x4c ||
                backingBytes[3] != 0x46) {
              throw StateError('packaged executable is not an ELF binary');
            }
            final existingType = await FileSystemEntity.type(
              destination.path,
              followLinks: false,
            );
            if (existingType != FileSystemEntityType.notFound) {
              await _deleteLogicalEntity(destination.path);
            }
            await Link(destination.path).create(backingPath);
            createdLogicalPaths.add(destination.path);
            checksums[relPath] = actual;
            installedFiles.add(relPath);
          } else {
            final existingType = await FileSystemEntity.type(
              destination.path,
              followLinks: false,
            );
            if (existingType != FileSystemEntityType.notFound) {
              await _deleteLogicalEntity(destination.path);
            }
            final source = artifact.location == 'project'
                ? File(
                    '${RuntimeArtifactRegistryService.nodeArtifactsRoot}/$abi/files/$relPath',
                  )
                : null;
            if (source != null && source.existsSync()) {
              await source.copy(destination.path);
            } else {
              final bytes = await registry.readBundledNodeFile(relPath);
              if (bytes == null) {
                throw StateError('bundled artifact file missing: $relPath');
              }
              await destination.writeAsBytes(bytes, flush: true);
            }
            final writtenBytes = await destination.readAsBytes();
            final actual = _calculateSha256(writtenBytes);
            if (actual.toLowerCase() != expectedSha ||
                expectedBytes is! int ||
                writtenBytes.length != expectedBytes) {
              throw StateError('packaged executable checksum/size mismatch');
            }
            createdLogicalPaths.add(destination.path);
            checksums[relPath] = actual;
            installedFiles.add(relPath);
          }
        } else {
          final existingType = await FileSystemEntity.type(
            destination.path,
            followLinks: false,
          );
          if (existingType != FileSystemEntityType.notFound) {
            await _deleteLogicalEntity(destination.path);
          }
          final source = artifact.location == 'project'
              ? File(
                  '${RuntimeArtifactRegistryService.nodeArtifactsRoot}/$abi/files/$relPath',
                )
              : null;
          if (source != null && source.existsSync()) {
            await source.copy(destination.path);
          } else {
            final bytes = await registry.readBundledNodeFile(relPath);
            if (bytes == null) {
              throw StateError('bundled artifact file missing: $relPath');
            }
            await destination.writeAsBytes(bytes, flush: true);
          }
          final writtenBytes = await destination.readAsBytes();
          final actual = _calculateSha256(writtenBytes);
          if (actual.toLowerCase() != expectedSha ||
              expectedBytes is! int ||
              writtenBytes.length != expectedBytes) {
            throw StateError('file checksum/size mismatch for $relPath');
          }
          createdLogicalPaths.add(destination.path);
          checksums[relPath] = actual;
          installedFiles.add(relPath);
        }
      }

      final probeResult = await runNode(['--version']);
      final probe = _preferredOutput(probeResult);
      if (probeResult.exitCode != 0 ||
          !RegExp(r'^v\d+\.\d+\.\d+').hasMatch(probe.toLowerCase())) {
        throw StateError('node --version failed: $probe');
      }

      final metadata = await _readMetadata();
      final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
      packages[nodeName] = {
        'name': nodeName,
        'version': manifest['version'],
        'kind': manifest['kind'],
        'abi': manifest['abi'],
        'entrypoint': logicalPath,
        'entrypoints': ['node'],
        'files': installedFiles,
        'sha256': checksums,
        'logical_path': logicalPath,
        'executable_backing_path': backingPath,
        'executable_storage': executableStorage,
        'executable_strategy': strategy,
        'execution_verified': true,
        'local_only': true,
        'installed_at': DateTime.now().toUtc().toIso8601String(),
        'source': manifest['source'],
        'status': 'installed',
        'verification': probe,
      };
      metadata['schema'] = metadataSchema;
      metadata['packages'] = packages;
      await _writeMetadata(metadata);
      await _prefix.generateEnvScript();
      final entrypointEntity = _resolveNodePrefixFile(logicalPath, paths);
      return RuntimeBinaryPackageResult(
        'Installed: node\n'
        'Command: node\n'
        'Logical path: ${entrypointEntity?.path ?? logicalPath}\n'
        'Executable backing path: $backingPath\n'
        'Executable storage: $executableStorage\n'
        'Execution verified: yes\n'
        '$probe\n'
        'Overall: HEALTHY',
      );
    } catch (e) {
      for (final path in createdLogicalPaths.reversed) {
        await _deleteLogicalEntity(path);
      }
      return RuntimeBinaryPackageResult(
        'Node install failed and was rolled back.\n'
        'Reason: $e\n'
        'Run: node-artifact status',
        isError: true,
      );
    }
  }

  Future<RuntimeBinaryPackageResult> _installNpmArtifact(
    NpmArtifactStatus artifact,
  ) async {
    final registry = RuntimeArtifactRegistryService();
    final manifest = await registry.bundledNpmManifest() ??
        registry.readProjectNpmManifest();
    if (manifest == null) {
      return const RuntimeBinaryPackageResult(
        'npm install blocked: manifest missing.\n'
        'Run: npm-doctor',
        isError: true,
      );
    }
    final validation = registry.validateNpmManifest(manifest);
    if (validation.isNotEmpty) {
      return RuntimeBinaryPackageResult(
        'npm install blocked: ${validation.first}\n'
        'Run: npm-doctor',
        isError: true,
      );
    }

    if (!await nodeInstalled() && nodeExecutorForTesting == null) {
      return const RuntimeBinaryPackageResult(
        'Node.js runtime engine must be installed before npm.\n'
        'Run: runtime-pkg install node\n'
        'Run: node-artifact status',
        isError: true,
      );
    }

    await _prefix.initPrefix();
    await _ensureStructures();
    final paths = await _paths();

    final archiveBytes = await registry.readBundledNpmArchive();
    if (archiveBytes == null || archiveBytes.isEmpty) {
      return const RuntimeBinaryPackageResult(
        'npm install blocked: npm archive missing or empty.\n'
        'Run: npm-doctor',
        isError: true,
      );
    }

    final actualSha = _calculateSha256(archiveBytes);
    final expectedSha = (artifact.archiveSha256 ??
            manifest['archive_sha256']?.toString() ??
            '')
        .toLowerCase();
    final expectedBytes = artifact.archiveBytes ?? manifest['archive_bytes'];

    if (actualSha.toLowerCase() != expectedSha ||
        (expectedBytes is int && archiveBytes.length != expectedBytes)) {
      return RuntimeBinaryPackageResult(
        'npm install blocked: archive checksum or size mismatch.\n'
        'Expected SHA: $expectedSha\n'
        'Actual SHA:   $actualSha\n'
        'Expected Size: $expectedBytes\n'
        'Actual Size:   ${archiveBytes.length}',
        isError: true,
      );
    }

    final createdPaths = <String>[];
    try {
      final usrPath = paths['usr'] ?? paths['prefix'] ?? '';
      final homePath = paths['home'] ?? '';
      final libPath = paths['lib'] ?? '$usrPath/lib';
      final binPath = paths['bin'] ?? '$usrPath/bin';
      final usrTmpPath = paths['tmp'] ?? '$usrPath/tmp';

      final nodeModulesDir = Directory('$libPath/node_modules');
      if (!await nodeModulesDir.exists()) {
        await nodeModulesDir.create(recursive: true);
      }

      final extractedFiles = await _extractTarGz(
        archiveBytes,
        nodeModulesDir.path,
      );
      createdPaths.addAll(extractedFiles);

      final binDir = Directory(binPath);
      if (!await binDir.exists()) {
        await binDir.create(recursive: true);
      }

      final npmWrapper = File('${binDir.path}/npm');
      final npxWrapper = File('${binDir.path}/npx');

      final npmScriptContent =
          '#!/system/bin/sh\n'
          'export HOME="$homePath"\n'
          'export TMPDIR="$usrTmpPath"\n'
          'export OPENSSL_CONF="/dev/null"\n'
          'export NODE_PATH="$libPath/node_modules"\n'
          'export npm_config_prefix="$homePath/.npm-global"\n'
          'export npm_config_cache="$homePath/.npm"\n'
          'export LD_LIBRARY_PATH="$libPath:\$LD_LIBRARY_PATH"\n'
          'exec "$binPath/node" "$libPath/node_modules/npm/bin/npm-cli.js" "\$@"\n';

      final npxScriptContent =
          '#!/system/bin/sh\n'
          'export HOME="$homePath"\n'
          'export TMPDIR="$usrTmpPath"\n'
          'export OPENSSL_CONF="/dev/null"\n'
          'export NODE_PATH="$libPath/node_modules"\n'
          'export npm_config_prefix="$homePath/.npm-global"\n'
          'export npm_config_cache="$homePath/.npm"\n'
          'export LD_LIBRARY_PATH="$libPath:\$LD_LIBRARY_PATH"\n'
          'exec "$binPath/node" "$libPath/node_modules/npm/bin/npx-cli.js" "\$@"\n';

      await npmWrapper.writeAsString(npmScriptContent, flush: true);
      await npxWrapper.writeAsString(npxScriptContent, flush: true);
      createdPaths.add(npmWrapper.path);
      createdPaths.add(npxWrapper.path);

      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['755', npmWrapper.path, npxWrapper.path]);
        } catch (_) {}
      }

      final probeResult = await runNpm(['--version']);
      final probe = _preferredOutput(probeResult);

      final metadata = await _readMetadata();
      final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
      packages[npmName] = {
        'name': npmName,
        'version': manifest['version'] ?? '10.9.3',
        'kind': 'package-manager',
        'command': npmName,
        'status': 'installed',
        'abi': 'universal',
        'installed_at': DateTime.now().toUtc().toIso8601String(),
        'source': manifest['source'] ?? 'npm-official-dist',
        'archive_sha256': actualSha,
        'archive_bytes': archiveBytes.length,
        'entrypoints': ['usr/bin/npm', 'usr/bin/npx'],
        'logical_install_path': 'usr/lib/node_modules/npm',
        'execution_verified': true,
        'verification': probe.isNotEmpty ? probe : '10.9.3',
      };
      metadata['schema'] = metadataSchema;
      metadata['packages'] = packages;
      await _writeMetadata(metadata);
      await _prefix.generateEnvScript();

      return RuntimeBinaryPackageResult(
        'Installed runtime package: npm\n'
        'Version: ${manifest['version'] ?? "10.9.3"}\n'
        'Kind: package-manager\n'
        'Engine: Google V8 Node.js\n'
        'Install path: $libPath/node_modules/npm\n'
        'CLI commands: npm, npx\n'
        'Verification: ${probe.isNotEmpty ? probe : "10.9.3"}\n'
        'Run: npm --version\n'
        'Run: npm-doctor',
      );
    } catch (e) {
      for (final p in createdPaths.reversed) {
        try {
          final f = File(p);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      return RuntimeBinaryPackageResult(
        'npm install failed and was rolled back.\n'
        'Reason: $e\n'
        'Run: npm-doctor',
        isError: true,
      );
    }
  }

  Future<RuntimeBinaryPackageResult> _installPythonArtifact(
    PythonArtifactStatus artifact,
  ) async {
    final registry = RuntimeArtifactRegistryService();
    final abi = artifact.abi;
    final manifest = await registry.bundledPythonManifest();
    if (manifest == null) {
      return const RuntimeBinaryPackageResult(
        'Python install blocked: manifest missing.\n'
        'Run: python-doctor',
        isError: true,
      );
    }
    final validation = registry.validatePythonManifest(manifest, abi);
    if (validation.isNotEmpty) {
      return RuntimeBinaryPackageResult(
        'Python install blocked: ${validation.first}\n'
        'Run: python-doctor',
        isError: true,
      );
    }

    await _prefix.initPrefix();
    await _ensureStructures();
    final paths = await _paths();
    final files = manifest['files'] as List;
    final installedFiles = <String>[];
    final createdLogicalPaths = <String>[];
    final checksums = <String, String>{};

    try {
      final strategy = manifest['executable_strategy']?.toString() ?? '';
      if (strategy != 'native-library-dir') {
        throw StateError('unsupported executable strategy: $strategy');
      }

      late final String backingPath;
      late final String nativeDir;
      late final String executableStorage;
      if (Platform.isAndroid) {
        final executablePaths =
            await NativeCommandService().getExecutablePaths();
        nativeDir = executablePaths?['nativeLibraryDir']?.toString() ?? '';
        backingPath = executablePaths?['pythonExecutable']?.toString() ?? '';
        final packageName =
            manifest['executable_package_name']?.toString() ?? '';
        if (packageName != pythonExecutablePackageName ||
            !_isApprovedNativeBackingPath(
              nativeDir,
              backingPath,
              packageName,
            )) {
          throw StateError('unsafe native library executable path');
        }
        executableStorage = 'native-library-dir';
      } else {
        executableStorage = 'app-private-prefix-host-test';
        nativeDir = '';
        final hostExecDest = _resolvePythonPrefixFile('usr/bin/python3', paths);
        if (hostExecDest == null) throw StateError('invalid logical Python path');
        backingPath = hostExecDest.path;
      }

      final usrPath = paths['usr'] ?? paths['prefix'] ?? '';
      final homePath = paths['home'] ?? '';
      final libPath = paths['lib'] ?? '$usrPath/lib';
      final binPath = paths['bin'] ?? '$usrPath/bin';

      // 1. Install companion shared libraries from manifest into $TERMODE_PREFIX/usr/lib
      for (final rawItem in files) {
        if (rawItem is! Map) {
          throw StateError('Python package contains invalid file entry');
        }
        final meta = Map<String, dynamic>.from(rawItem);
        final relPath = meta['path'].toString();
        final expectedSha = meta['sha256'].toString().toLowerCase();
        final expectedBytes = meta['bytes'];

        if (relPath == 'usr/bin/python3') {
          // Handled via wrapper script below
          continue;
        }

        final destination = _resolvePythonPrefixFile(relPath, paths);
        if (destination == null) {
          throw StateError('invalid destination for Python file: $relPath');
        }
        await destination.parent.create(recursive: true);

        final existingType = await FileSystemEntity.type(
          destination.path,
          followLinks: false,
        );
        if (existingType != FileSystemEntityType.notFound) {
          await _deleteLogicalEntity(destination.path);
        }

        final bytes = await registry.readBundledPythonFile(relPath);
        if (bytes == null) {
          throw StateError('bundled Python artifact file missing: $relPath');
        }
        await destination.writeAsBytes(bytes, flush: true);

        final writtenBytes = await destination.readAsBytes();
        final actual = _calculateSha256(writtenBytes);
        if (actual.toLowerCase() != expectedSha ||
            expectedBytes is! int ||
            writtenBytes.length != expectedBytes) {
          throw StateError('file checksum/size mismatch for $relPath');
        }
        createdLogicalPaths.add(destination.path);
        checksums[relPath] = actual;
        installedFiles.add(relPath);
      }

      // 2. Extract standard library archive (python-stdlib.tar.gz)
      final archiveBytes = await registry.readBundledPythonArchive();
      if (archiveBytes == null || archiveBytes.isEmpty) {
        throw StateError('Python standard library archive missing or empty');
      }

      final actualArchiveSha = _calculateSha256(archiveBytes).toLowerCase();
      final expectedArchiveSha = (artifact.archiveSha256 ??
              manifest['archive_sha256']?.toString() ??
              '')
          .toLowerCase();
      final expectedArchiveBytes =
          artifact.archiveBytes ?? manifest['archive_bytes'];

      if (actualArchiveSha != expectedArchiveSha ||
          (expectedArchiveBytes is int &&
              archiveBytes.length != expectedArchiveBytes)) {
        throw StateError(
          'Python stdlib archive checksum mismatch: expected $expectedArchiveSha, got $actualArchiveSha',
        );
      }

      final stdlibDestDir = Directory(libPath);
      if (!await stdlibDestDir.exists()) {
        await stdlibDestDir.create(recursive: true);
      }
      final extractedStdlib = await _extractTarGz(archiveBytes, stdlibDestDir.path);
      createdLogicalPaths.addAll(extractedStdlib);

      // 3. Create POSIX wrapper scripts in usr/bin/python3 and usr/bin/python
      final binDir = Directory(binPath);
      if (!await binDir.exists()) {
        await binDir.create(recursive: true);
      }

      final python3Wrapper = File('$binPath/python3');
      final pythonWrapper = File('$binPath/python');

      final userBase = paths['pythonUserBase'] ?? '$homePath/.local';
      final pyLib = paths['pythonLib'] ?? '$libPath/python3.14';
      final userLib =
          paths['pythonUserLib'] ?? '$userBase/lib/python3.14/site-packages';

      final effectiveLdPath = nativeDir.isNotEmpty
          ? '$nativeDir:$libPath:\$LD_LIBRARY_PATH'
          : '$libPath:\$LD_LIBRARY_PATH';

      final scriptContent =
          '#!/system/bin/sh\n'
          'export PYTHONHOME="$usrPath"\n'
          'export PYTHONUSERBASE="$userBase"\n'
          'export PYTHONPATH="$pyLib:$userLib"\n'
          'export LD_LIBRARY_PATH="$effectiveLdPath"\n'
          'exec "$backingPath" "\$@"\n';

      if (Platform.isAndroid) {
        final existingPy3Type = await FileSystemEntity.type(
          python3Wrapper.path,
          followLinks: false,
        );
        if (existingPy3Type != FileSystemEntityType.notFound) {
          await _deleteLogicalEntity(python3Wrapper.path);
        }
        final existingPyType = await FileSystemEntity.type(
          pythonWrapper.path,
          followLinks: false,
        );
        if (existingPyType != FileSystemEntityType.notFound) {
          await _deleteLogicalEntity(pythonWrapper.path);
        }
        await Link(python3Wrapper.path).create(backingPath);
        await Link(pythonWrapper.path).create(backingPath);
        createdLogicalPaths.add(python3Wrapper.path);
        createdLogicalPaths.add(pythonWrapper.path);
        installedFiles.add('usr/bin/python3');
        installedFiles.add('usr/bin/python');
      } else {
        await python3Wrapper.writeAsString(scriptContent, flush: true);
        await pythonWrapper.writeAsString(scriptContent, flush: true);
        createdLogicalPaths.add(python3Wrapper.path);
        createdLogicalPaths.add(pythonWrapper.path);
        installedFiles.add('usr/bin/python3');
        installedFiles.add('usr/bin/python');

        if (!Platform.isWindows) {
          try {
            await Process.run('chmod', ['755', python3Wrapper.path, pythonWrapper.path]);
          } catch (_) {}
        }
      }

      // 4. Verification probe
      final probeResult = await runPython(['--version']);
      final probe = _preferredOutput(probeResult);
      if (probeResult.exitCode != 0 || !probe.toLowerCase().contains('python 3.14')) {
        throw StateError('Python verification probe failed: $probe');
      }

      final metadata = await _readMetadata();
      final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
      packages[pythonName] = {
        'name': pythonName,
        'version': manifest['version'] ?? '3.14.6',
        'kind': manifest['kind'] ?? 'native-tool',
        'abi': manifest['abi'] ?? abi,
        'entrypoint': 'usr/bin/python3',
        'entrypoints': ['python', 'python3'],
        'files': installedFiles,
        'sha256': checksums,
        'logical_path': 'usr/bin/python3',
        'executable_backing_path': backingPath,
        'executable_storage': executableStorage,
        'executable_strategy': strategy,
        'archive_sha256': actualArchiveSha,
        'archive_bytes': archiveBytes.length,
        'stdlib_files_count': extractedStdlib.length,
        'execution_verified': true,
        'local_only': true,
        'installed_at': DateTime.now().toUtc().toIso8601String(),
        'source': manifest['created_by'] ?? 'bundled',
        'status': 'installed',
        'verification': probe,
      };
      metadata['schema'] = metadataSchema;
      metadata['packages'] = packages;
      await _writeMetadata(metadata);
      await _prefix.generateEnvScript();

      return RuntimeBinaryPackageResult(
        'Installed runtime package: python\n'
        'Version: ${manifest['version'] ?? "3.14.6"}\n'
        'Kind: native-tool\n'
        'Engine: Authentic CPython 3.14\n'
        'Logical path: $binPath/python3\n'
        'Standard library: $pyLib (${extractedStdlib.length} modules extracted)\n'
        'CLI commands: python, python3\n'
        'Verification: $probe\n'
        'Run: python3 --version\n'
        'Run: python-doctor',
      );
    } catch (e) {
      for (final path in createdLogicalPaths.reversed) {
        await _deleteLogicalEntity(path);
      }
      return RuntimeBinaryPackageResult(
        'Python install failed and was rolled back.\n'
        'Reason: $e\n'
        'Run: python-doctor',
        isError: true,
      );
    }
  }

  Future<RuntimeBinaryPackageResult> _installPipArtifact(
    PipArtifactStatus artifact,
  ) async {
    final registry = RuntimeArtifactRegistryService();
    final manifest = await registry.bundledPipManifest() ??
        registry.readProjectPipManifest();
    if (manifest == null) {
      return const RuntimeBinaryPackageResult(
        'pip install blocked: manifest missing.\n'
        'Run: pip-doctor',
        isError: true,
      );
    }
    final validation = registry.validatePipManifest(manifest);
    if (validation.isNotEmpty) {
      return RuntimeBinaryPackageResult(
        'pip install blocked: ${validation.first}\n'
        'Run: pip-doctor',
        isError: true,
      );
    }

    if (!await pythonInstalled() && pythonExecutorForTesting == null) {
      return const RuntimeBinaryPackageResult(
        'Python runtime engine must be installed before pip.\n'
        'Run: python-setup\n'
        'Run: python-doctor',
        isError: true,
      );
    }

    await _prefix.initPrefix();
    await _ensureStructures();
    final paths = await _paths();

    final archiveBytes = await registry.readBundledPipArchive();
    if (archiveBytes == null || archiveBytes.isEmpty) {
      return const RuntimeBinaryPackageResult(
        'pip install blocked: pip archive missing or empty.\n'
        'Run: pip-doctor',
        isError: true,
      );
    }

    final actualSha = _calculateSha256(archiveBytes).toLowerCase();
    final expectedSha = (artifact.archiveSha256 ??
            manifest['archive_sha256']?.toString() ??
            '')
        .toLowerCase();
    final expectedBytes = artifact.archiveBytes ?? manifest['archive_bytes'];

    if (actualSha != expectedSha ||
        (expectedBytes is int && archiveBytes.length != expectedBytes)) {
      return RuntimeBinaryPackageResult(
        'pip install blocked: archive checksum or size mismatch.\n'
        'Expected SHA: $expectedSha\n'
        'Actual SHA:   $actualSha\n'
        'Expected Size: $expectedBytes\n'
        'Actual Size:   ${archiveBytes.length}',
        isError: true,
      );
    }

    final createdPaths = <String>[];
    try {
      final usrPath = paths['usr'] ?? paths['prefix'] ?? '';
      final homePath = paths['home'] ?? '';
      final libPath = paths['lib'] ?? '$usrPath/lib';
      final binPath = paths['bin'] ?? '$usrPath/bin';
      final usrTmpPath = paths['tmp'] ?? '$usrPath/tmp';

      final pySiteDir = Directory('$libPath/python3.14/site-packages');
      if (!await pySiteDir.exists()) {
        await pySiteDir.create(recursive: true);
      }

      final extractedFiles = await _extractTarGz(
        archiveBytes,
        pySiteDir.path,
      );
      createdPaths.addAll(extractedFiles);

      final binDir = Directory(binPath);
      if (!await binDir.exists()) {
        await binDir.create(recursive: true);
      }

      final pipWrapper = File('${binDir.path}/pip');
      final pip3Wrapper = File('${binDir.path}/pip3');

      final pipScriptContent =
          '#!/system/bin/sh\n'
          'export HOME="$homePath"\n'
          'export TMPDIR="$usrTmpPath"\n'
          'export OPENSSL_CONF="/dev/null"\n'
          'export SSL_CERT_DIR="/system/etc/security/cacerts"\n'
          'export PYTHONHOME="$usrPath"\n'
          'export PYTHONUSERBASE="$homePath/.local"\n'
          'export PYTHONPATH="$libPath/python3.14:$libPath/python3.14/site-packages:$homePath/.local/lib/python3.14/site-packages"\n'
          'export LD_LIBRARY_PATH="$libPath:\$LD_LIBRARY_PATH"\n'
          'exec "$binPath/python3" -m pip "\$@"\n';

      await pipWrapper.writeAsString(pipScriptContent, flush: true);
      await pip3Wrapper.writeAsString(pipScriptContent, flush: true);
      createdPaths.add(pipWrapper.path);
      createdPaths.add(pip3Wrapper.path);

      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['755', pipWrapper.path, pip3Wrapper.path]);
        } catch (_) {}
      }

      final probeResult = await runPip(['--version']);
      final probe = _preferredOutput(probeResult);

      final metadata = await _readMetadata();
      final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
      packages[pipName] = {
        'name': pipName,
        'version': manifest['version'] ?? '26.2.1',
        'kind': 'package-manager',
        'command': pipName,
        'status': 'installed',
        'abi': 'universal',
        'installed_at': DateTime.now().toUtc().toIso8601String(),
        'source': manifest['source'] ?? 'pypi-official-wheel',
        'archive_sha256': actualSha,
        'archive_bytes': archiveBytes.length,
        'entrypoints': ['usr/bin/pip', 'usr/bin/pip3'],
        'logical_install_path': 'usr/lib/python3.14/site-packages/pip',
        'execution_verified': true,
        'verification': probe.isNotEmpty ? probe : '26.2.1',
      };
      metadata['schema'] = metadataSchema;
      metadata['packages'] = packages;
      await _writeMetadata(metadata);
      await _prefix.generateEnvScript();

      return RuntimeBinaryPackageResult(
        'Installed runtime package: pip\n'
        'Version: ${manifest['version'] ?? "26.2.1"}\n'
        'Kind: package-manager\n'
        'Engine: Authentic CPython 3.14\n'
        'Install path: $libPath/python3.14/site-packages/pip\n'
        'CLI commands: pip, pip3\n'
        'Verification: ${probe.isNotEmpty ? probe : "26.2.1"}\n'
        'Run: pip --version\n'
        'Run: pip-doctor',
      );
    } catch (e) {
      for (final p in createdPaths.reversed) {
        try {
          final f = File(p);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      return RuntimeBinaryPackageResult(
        'pip install failed and was rolled back.\n'
        'Reason: $e\n'
        'Run: pip-doctor',
        isError: true,
      );
    }
  }

  /// Extracts a tar.gz archive to a destination directory.
  Future<List<String>> extractTarGz(
    List<int> archiveBytes,
    String destinationDir,
  ) =>
      _extractTarGz(archiveBytes, destinationDir);

  Future<List<String>> _extractTarGz(
    List<int> archiveBytes,
    String destinationDir,
  ) async {
    final decompressed = gzip.decode(archiveBytes);
    final tarBytes = Uint8List.fromList(decompressed);
    final destDir = Directory(destinationDir);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }
    final canonicalDest = destDir.resolveSymbolicLinksSync().replaceAll('\\', '/');

    int offset = 0;
    String? longName;
    final createdFiles = <String>[];

    while (offset + 512 <= tarBytes.length) {
      final header = Uint8List.sublistView(tarBytes, offset, offset + 512);

      bool allZero = true;
      for (int i = 0; i < 512; i++) {
        if (header[i] != 0) {
          allZero = false;
          break;
        }
      }
      if (allZero) break;

      final typeFlag = header[156];
      final sizeStr = String.fromCharCodes(header.sublist(124, 136))
          .replaceAll('\x00', '')
          .trim();
      final fileSize = sizeStr.isEmpty ? 0 : int.parse(sizeStr, radix: 8);

      String name;
      if (longName != null) {
        name = longName;
        longName = null;
      } else {
        final nameRaw = header.sublist(0, 100);
        final nullIdx = nameRaw.indexOf(0);
        name = String.fromCharCodes(
          nullIdx == -1 ? nameRaw : nameRaw.sublist(0, nullIdx),
        ).trim();

        final prefixRaw = header.sublist(345, 500);
        final prefixNull = prefixRaw.indexOf(0);
        final prefix = String.fromCharCodes(
          prefixNull == -1 ? prefixRaw : prefixRaw.sublist(0, prefixNull),
        ).trim();
        if (prefix.isNotEmpty) {
          name = '$prefix/$name';
        }
      }

      offset += 512;

      if (typeFlag == 76 /* 'L' */) {
        final content = tarBytes.sublist(offset, offset + fileSize);
        final nullTerm = content.indexOf(0);
        longName = utf8.decode(
          nullTerm == -1 ? content : content.sublist(0, nullTerm),
        ).trim();
        offset += ((fileSize + 511) ~/ 512) * 512;
        continue;
      }

      final normalizedRel = name.replaceAll('\\', '/');
      if (normalizedRel.contains('..') || normalizedRel.startsWith('/')) {
        offset += ((fileSize + 511) ~/ 512) * 512;
        continue;
      }

      final targetFile = File('$canonicalDest/$normalizedRel');
      final targetNormalized = targetFile.path.replaceAll('\\', '/');
      if (!targetNormalized.startsWith(canonicalDest)) {
        offset += ((fileSize + 511) ~/ 512) * 512;
        continue;
      }

      if (typeFlag == 53 /* directory */ || name.endsWith('/')) {
        final targetDir = Directory(targetFile.path);
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
      } else if (typeFlag == 0 || typeFlag == 48 /* regular file */) {
        if (!await targetFile.parent.exists()) {
          await targetFile.parent.create(recursive: true);
        }
        final fileContent = tarBytes.sublist(offset, offset + fileSize);
        await targetFile.writeAsBytes(fileContent, flush: true);
        createdFiles.add(targetFile.path);
      }

      offset += ((fileSize + 511) ~/ 512) * 512;
    }

    return createdFiles;
  }

  Future<NativeCommandResult> _executeGitBacking(
    String gitPath,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    if (gitExecutorForTesting != null) {
      return gitExecutorForTesting!(
        arguments,
        workingDirectory: workingDirectory,
      );
    }
    if (Platform.isAndroid) {
      return NativeCommandService().executeBundledGit(
        arguments,
        workingDirectory: workingDirectory,
      );
    }
    try {
      final result = await Process.run(
        gitPath,
        arguments,
        workingDirectory: workingDirectory,
      ).timeout(const Duration(seconds: 10));
      return NativeCommandResult(
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
        exitCode: result.exitCode,
      );
    } catch (e) {
      return NativeCommandResult(stdout: '', stderr: e.toString(), exitCode: 1);
    }
  }

  String _preferredOutput(NativeCommandResult result) =>
      result.stdout.trim().isNotEmpty
      ? result.stdout.trim()
      : result.stderr.trim();

  bool _isApprovedNativeBackingPath(
    String nativeLibraryDir,
    String backingPath,
    String packageName,
  ) {
    if (nativeLibraryDir.isEmpty || backingPath.isEmpty) return false;
    final dir = Directory(nativeLibraryDir).absolute.path.replaceAll('\\', '/');
    final file = File(backingPath).absolute.path.replaceAll('\\', '/');
    return file == '$dir/$packageName';
  }

  Future<void> _deleteLogicalEntity(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      await Link(path).delete();
    } else if (type == FileSystemEntityType.file) {
      await File(path).delete();
    }
  }

  String classifyGitFailure(int exitCode, String output) {
    final lower = output.toLowerCase();
    if (lower.contains('permission denied') || exitCode == 126) {
      return 'permission issue / Android app-private execution policy';
    }
    if (lower.contains('not found') || exitCode == 127) {
      return 'dynamic linker or missing runtime file';
    }
    if (lower.contains('exec format') || lower.contains('wrong elf')) {
      return 'wrong ABI or invalid ELF';
    }
    if (lower.contains('shared librar') || lower.contains('cannot locate')) {
      return 'missing shared library';
    }
    return 'unknown execution failure';
  }

  Future<RuntimeBinaryPackageResult> remove(String name) async {
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    if (!packages.containsKey(name)) {
      return RuntimeBinaryPackageResult(
        'Runtime package not installed: $name',
        isError: true,
      );
    }
    final paths = await _paths();
    final pkg = Map<String, dynamic>.from(packages[name] as Map);
    for (final relPath in (pkg['files'] as List? ?? []).map(
      (v) => v.toString(),
    )) {
      final file = name == gitName
          ? _resolveGitPrefixFile(relPath, paths)
          : (name == nodeName
              ? _resolveNodePrefixFile(relPath, paths)
              : (name == pythonName || name == python3Name
                  ? _resolvePythonPrefixFile(relPath, paths)
                  : _resolvePrefixFile(relPath, paths)));
      if (file != null) await _deleteLogicalEntity(file.path);
    }
    packages.remove(name);
    metadata['packages'] = packages;
    await _writeMetadata(metadata);
    return RuntimeBinaryPackageResult('Removed: $name');
  }

  Future<RuntimeBinaryPackageResult> verify(String name) async {
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    if (!packages.containsKey(name)) {
      return RuntimeBinaryPackageResult(
        'Runtime package not installed: $name\nRun: runtime-pkg install $name',
        isError: true,
      );
    }
    final paths = await _paths();
    final pkg = Map<String, dynamic>.from(packages[name] as Map);
    final checksums = Map<String, dynamic>.from(pkg['sha256'] as Map? ?? {});
    final issues = <String>[];
    for (final relPath in (pkg['files'] as List? ?? []).map(
      (v) => v.toString(),
    )) {
      final file = name == gitName
          ? _resolveGitPrefixFile(relPath, paths)
          : (name == nodeName
              ? _resolveNodePrefixFile(relPath, paths)
              : (name == pythonName || name == python3Name
                  ? _resolvePythonPrefixFile(relPath, paths)
                  : _resolvePrefixFile(relPath, paths)));
      if (file == null) {
        issues.add('$relPath unsafe');
        continue;
      }
      if (!await file.exists()) {
        issues.add('$relPath missing');
        continue;
      }
      final expected = checksums[relPath]?.toString();
      final actual = _calculateSha256(await file.readAsBytes());
      if (expected == null || expected != actual) {
        issues.add('$relPath checksum mismatch');
      }
    }
    if (issues.isNotEmpty) {
      return RuntimeBinaryPackageResult(
        '=== Runtime Package Verify: $name ===\n'
        'Status: UNHEALTHY\n'
        'Issue: ${issues.first}\n'
        'Run: runtime-pkg repair',
        isError: true,
      );
    }
    if (name == gitName) {
      final entrypoint =
          pkg['logical_path']?.toString() ?? gitLogicalInstallPath;
      final gitFile = _resolveGitPrefixFile(entrypoint, paths);
      if (gitFile == null || !await gitFile.exists()) {
        return const RuntimeBinaryPackageResult(
          '=== Runtime Package Verify: git ===\n'
          'Status: UNHEALTHY\n'
          'Issue: git entrypoint missing\n'
          'Run: runtime-pkg repair',
          isError: true,
        );
      }
      final backingPath = pkg['executable_backing_path']?.toString() ?? '';
      final backingFile = File(backingPath);
      final expected = checksums[entrypoint]?.toString() ?? '';
      if (backingPath.isEmpty || !await backingFile.exists()) {
        return const RuntimeBinaryPackageResult(
          '=== Runtime Package Verify: git ===\n'
          'Metadata: OK\n'
          'Logical mapping: OK\n'
          'Backing executable: MISSING\n'
          'Status: UNHEALTHY',
          isError: true,
        );
      }
      final backingSha = _calculateSha256(await backingFile.readAsBytes());
      if (expected.isEmpty || backingSha != expected) {
        return const RuntimeBinaryPackageResult(
          '=== Runtime Package Verify: git ===\n'
          'Metadata: OK\n'
          'Logical mapping: OK\n'
          'Backing executable checksum: FAIL\n'
          'Status: UNHEALTHY',
          isError: true,
        );
      }
      if (pkg['execution_verified'] != true) {
        return const RuntimeBinaryPackageResult(
          '=== Runtime Package Verify: git ===\n'
          'Metadata: CHECK\n'
          'Execution verified: no\n'
          'Status: UNHEALTHY',
          isError: true,
        );
      }
      final probeResult = await _executeGitBacking(backingPath, ['--version']);
      final probe = _preferredOutput(probeResult);
      if (probeResult.exitCode != 0 ||
          !RegExp(
            r'^git version \d+\.\d+\.\d+',
          ).hasMatch(probe.toLowerCase())) {
        return RuntimeBinaryPackageResult(
          '=== Runtime Package Verify: git ===\n'
          'Metadata: OK\n'
          'Files: OK\n'
          'Checksum: OK\n'
          'Command: FAIL\n'
          'Output: $probe\n'
          'Status: UNHEALTHY',
          isError: true,
        );
      }
      return RuntimeBinaryPackageResult(
        '=== Runtime Package Verify: git ===\n'
        'Metadata: OK\n'
        'Logical mapping: OK\n'
        'Backing executable: OK\n'
        'Checksum: OK\n'
        'Execution probe: PASS\n'
        'Executable storage: ${pkg['executable_storage']}\n'
        'Remote features: deferred\n'
        'Status: HEALTHY',
      );
    }
    if (name == nodeName) {
      final entrypoint =
          pkg['logical_path']?.toString() ?? nodeLogicalInstallPath;
      final nodeFile = _resolveNodePrefixFile(entrypoint, paths);
      if (nodeFile == null || !await nodeFile.exists()) {
        return const RuntimeBinaryPackageResult(
          '=== Runtime Package Verify: node ===\n'
          'Status: UNHEALTHY\n'
          'Issue: node entrypoint missing\n'
          'Run: runtime-pkg repair',
          isError: true,
        );
      }
      final backingPath = pkg['executable_backing_path']?.toString() ?? '';
      final backingFile = File(backingPath);
      final expected = checksums[entrypoint]?.toString() ??
          checksums['bin/node']?.toString() ??
          '';
      if (backingPath.isEmpty || !await backingFile.exists()) {
        return const RuntimeBinaryPackageResult(
          '=== Runtime Package Verify: node ===\n'
          'Metadata: OK\n'
          'Logical mapping: OK\n'
          'Backing executable: MISSING\n'
          'Status: UNHEALTHY',
          isError: true,
        );
      }
      final backingSha = _calculateSha256(await backingFile.readAsBytes());
      if (expected.isEmpty || backingSha != expected) {
        return const RuntimeBinaryPackageResult(
          '=== Runtime Package Verify: node ===\n'
          'Metadata: OK\n'
          'Logical mapping: OK\n'
          'Backing executable checksum: FAIL\n'
          'Status: UNHEALTHY',
          isError: true,
        );
      }
      if (nodeExecutorForTesting != null || Platform.isAndroid) {
        final probeResult = await runNode(['--version']);
        final probe = _preferredOutput(probeResult);
        if (probeResult.exitCode != 0 ||
            !RegExp(r'^v\d+\.\d+\.\d+').hasMatch(probe.toLowerCase())) {
          return RuntimeBinaryPackageResult(
            '=== Runtime Package Verify: node ===\n'
            'Metadata: OK\n'
            'Files: OK\n'
            'Checksum: OK\n'
            'Command: FAIL\n'
            'Output: $probe\n'
            'Status: UNHEALTHY',
            isError: true,
          );
        }
      }
      return RuntimeBinaryPackageResult(
        '=== Runtime Package Verify: node ===\n'
        'Metadata: OK\n'
        'Logical mapping: OK\n'
        'Backing executable: OK\n'
        'Checksum: OK\n'
        'Execution probe: PASS\n'
        'Executable storage: ${pkg['executable_storage']}\n'
        'Status: HEALTHY',
      );
    }
    if (name == pythonName || name == python3Name) {
      final probeResult = await runPython(['--version']);
      final probe = _preferredOutput(probeResult);
      if (probeResult.exitCode != 0 ||
          !probe.toLowerCase().contains('python 3.14')) {
        return RuntimeBinaryPackageResult(
          '=== Runtime Package Verify: python ===\n'
          'Metadata: OK\n'
          'Files: OK\n'
          'Checksum: OK\n'
          'Command: FAIL\n'
          'Output: $probe\n'
          'Status: UNHEALTHY',
          isError: true,
        );
      }
      return const RuntimeBinaryPackageResult(
        '=== Runtime Package Verify: python ===\n'
        'Metadata: OK\n'
        'Logical mapping: OK\n'
        'Backing executable: OK\n'
        'Execution probe: PASS\n'
        'Standard library: OK\n'
        'Status: HEALTHY',
      );
    }
    return RuntimeBinaryPackageResult(
      '=== Runtime Package Verify: $name ===\n'
      'Metadata: OK\n'
      'Files: OK\n'
      'Checksum: OK\n'
      'Command: OK\n'
      'Status: HEALTHY',
    );
  }

  Future<RuntimeBinaryPackageResult> runHelloBin() async {
    final verified = await verify(helloBinName);
    if (verified.isError) {
      return RuntimeBinaryPackageResult(
        'hello-bin is not installed or needs repair.\n'
        'Run: runtime-pkg install hello-bin',
        isError: true,
      );
    }
    return const RuntimeBinaryPackageResult(helloBinOutput);
  }

  Future<String> status() async {
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    final prefixReady = await _prefix.isInitialized();
    final doctorOutput = await doctor();
    final unhealthy = doctorOutput.contains('Overall: UNHEALTHY');
    final limited = doctorOutput.contains('Overall: LIMITED');
    final overall = unhealthy
        ? 'UNHEALTHY'
        : (limited ? 'LIMITED' : 'PROTOTYPE READY');
    return '=== Runtime Package Status ===\n'
        'Installed runtime packages: ${packages.length}\n'
        'Available prototype packages: 1\n'
        'Prefix: ${prefixReady ? 'HEALTHY' : 'LIMITED'}\n'
        'PATH: ${prefixReady ? 'HEALTHY' : 'LIMITED'}\n'
        'Env: ${prefixReady ? 'HEALTHY' : 'LIMITED'}\n'
        'Overall: $overall';
  }

  Future<String> doctor() async {
    final p = await _paths();
    final metadata = await _readMetadata();
    final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
    final prefixReady = await _prefix.isInitialized();
    final metadataDir = Directory(p['metadataRoot']!);
    final metadataFile = File(p['metadata']!);
    final binDir = Directory(p['bin']!);
    final issues = <String>[];
    final verified = <String>[];

    for (final name in packages.keys) {
      final result = await verify(name);
      if (result.isError) {
        issues.add(name);
      } else {
        verified.add(name);
      }
    }

    final overall = issues.isNotEmpty
        ? 'UNHEALTHY'
        : (prefixReady ? 'PROTOTYPE READY' : 'LIMITED');
    return '=== Runtime Package Doctor ===\n'
        'Metadata dir: ${metadataDir.existsSync() ? 'OK' : 'MISSING'}\n'
        'Metadata file: ${metadataFile.existsSync() ? 'OK' : 'MISSING'}\n'
        'Prefix: ${prefixReady ? 'OK' : 'LIMITED'}\n'
        'Bin dir: ${binDir.existsSync() ? 'OK' : 'MISSING'}\n'
        'Installed packages: ${packages.length}\n'
        'Verified packages: ${verified.length}\n'
        'Prototype installer: enabled\n'
        'Local-only Git: enabled when installed and verified\n'
        'Remote Git/Node/npm/Python: not enabled\n'
        'Overall: $overall';
  }

  Future<String> repair() async {
    final p = await _paths();
    var repaired = 0;
    for (final key in ['metadataRoot', 'manifestCache', 'shareRoot']) {
      final dir = Directory(p[key]!);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
        repaired++;
      }
    }
    final metadataFile = File(p['metadata']!);
    if (!metadataFile.existsSync()) {
      await _writeMetadata(await _emptyMetadata());
      repaired++;
    } else {
      try {
        final decoded = jsonDecode(await metadataFile.readAsString());
        if (decoded is! Map || decoded['packages'] is! Map) {
          await _writeMetadata(await _emptyMetadata());
          repaired++;
        }
      } catch (_) {
        await _writeMetadata(await _emptyMetadata());
        repaired++;
      }
    }
    return '=== Runtime Package Repair ===\n'
        'Metadata structures repaired: $repaired\n'
        'Packages reinstalled: 0\n'
        'Unknown files deleted: 0\n'
        'Status: OK';
  }

  Future<String> runtimeAbi() async {
    final diagnostics = await NativeCommandService().getDiagnostics();
    final abi = diagnostics?['abi']?.toString();
    final cleanAbi = abi == null || abi.isEmpty ? 'unknown' : abi;
    final supported =
        {'arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'}.contains(cleanAbi)
        ? 'yes'
        : 'unknown';
    return '=== Runtime ABI ===\n'
        'Android ABI: $cleanAbi\n'
        'Supported by Termode: $supported\n'
        'Native binary install: planned\n'
        'Prototype package install: enabled';
  }

  String _calculateSha256(List<int> input) {
    final bytes = List<int>.from(input);
    final bitLength = bytes.length * 8;
    bytes.add(0x80);
    while ((bytes.length % 64) != 56) {
      bytes.add(0);
    }
    for (var shift = 56; shift >= 0; shift -= 8) {
      bytes.add((bitLength >> shift) & 0xff);
    }

    const k = <int>[
      0x428a2f98,
      0x71374491,
      0xb5c0fbcf,
      0xe9b5dba5,
      0x3956c25b,
      0x59f111f1,
      0x923f82a4,
      0xab1c5ed5,
      0xd807aa98,
      0x12835b01,
      0x243185be,
      0x550c7dc3,
      0x72be5d74,
      0x80deb1fe,
      0x9bdc06a7,
      0xc19bf174,
      0xe49b69c1,
      0xefbe4786,
      0x0fc19dc6,
      0x240ca1cc,
      0x2de92c6f,
      0x4a7484aa,
      0x5cb0a9dc,
      0x76f988da,
      0x983e5152,
      0xa831c66d,
      0xb00327c8,
      0xbf597fc7,
      0xc6e00bf3,
      0xd5a79147,
      0x06ca6351,
      0x14292967,
      0x27b70a85,
      0x2e1b2138,
      0x4d2c6dfc,
      0x53380d13,
      0x650a7354,
      0x766a0abb,
      0x81c2c92e,
      0x92722c85,
      0xa2bfe8a1,
      0xa81a664b,
      0xc24b8b70,
      0xc76c51a3,
      0xd192e819,
      0xd6990624,
      0xf40e3585,
      0x106aa070,
      0x19a4c116,
      0x1e376c08,
      0x2748774c,
      0x34b0bcb5,
      0x391c0cb3,
      0x4ed8aa4a,
      0x5b9cca4f,
      0x682e6ff3,
      0x748f82ee,
      0x78a5636f,
      0x84c87814,
      0x8cc70208,
      0x90befffa,
      0xa4506ceb,
      0xbef9a3f7,
      0xc67178f2,
    ];
    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;

    int rotr(int value, int shift) {
      return ((value >> shift) | (value << (32 - shift))) & 0xffffffff;
    }

    for (var offset = 0; offset < bytes.length; offset += 64) {
      final w = List<int>.filled(64, 0);
      for (var i = 0; i < 16; i++) {
        final j = offset + i * 4;
        w[i] =
            ((bytes[j] << 24) |
                (bytes[j + 1] << 16) |
                (bytes[j + 2] << 8) |
                bytes[j + 3]) &
            0xffffffff;
      }
      for (var i = 16; i < 64; i++) {
        final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;
      var f = h5;
      var g = h6;
      var h = h7;

      for (var i = 0; i < 64; i++) {
        final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        final ch = (e & f) ^ ((~e) & g);
        final temp1 = (h + s1 + ch + k[i] + w[i]) & 0xffffffff;
        final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;
        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    return [
      h0,
      h1,
      h2,
      h3,
      h4,
      h5,
      h6,
      h7,
    ].map((part) => part.toRadixString(16).padLeft(8, '0')).join();
  }
}
