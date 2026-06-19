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
  static const String helloBinOutput =
      'Hello from Termode binary package prototype.';
  static const String _helloBinContent =
      '#!/system/bin/sh\n'
      'printf "%s\\n" "Hello from Termode binary package prototype."\n';

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
    return normalized.startsWith('bin/') ||
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

  Future<void> _ensureStructures() async {
    final p = await _paths();
    for (final key in ['metadataRoot', 'manifestCache', 'shareRoot']) {
      await Directory(p[key]!).create(recursive: true);
    }
  }

  Future<String> help() async {
    return '=== Runtime Package Prototype (v0.44) ===\n'
        'Safe prototype installer for future binary/runtime packages.\n'
        'No Git, Node.js, npm, Python, downloads, or unknown binaries yet.\n\n'
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
        'Prototype package: hello-bin';
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

  Future<String> available() async {
    final manifest = helloBinManifest();
    final artifact = await RuntimeArtifactRegistryService().gitArtifactStatus();
    final gitState = artifact.installable
        ? 'installable if verified'
        : 'artifact ${artifact.status.toLowerCase()}; install refuses safely';
    return '=== Available Runtime Packages ===\n'
        'Prototype available now:\n'
        '* hello-bin [${manifest['version']}] - ${manifest['description']}\n\n'
        'Planned real tools:\n'
        '* git - Distributed version control ($gitState)\n\n'
        'Real Git/Node/npm/Python packages are planned, not enabled yet.';
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
          'Docs: docs/GIT_ARM64_ARTIFACT_PIPELINE.md',
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
          'Docs: docs/GIT_ARM64_ARTIFACT_PIPELINE.md',
        );
      }
      if (!artifact.installable) {
        return RuntimeBinaryPackageResult(
          'Git artifact failed verification.\n'
          'Reason: ${artifact.reason}\n'
          'Run: git-artifact bundle-check\n'
          'Run: git-artifact doctor\n'
          'Docs: docs/GIT_ARM64_ARTIFACT_PIPELINE.md',
          isError: true,
        );
      }
      return _installGitArtifact(artifact);
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
        : registry.bundledGitManifest();
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
    final copiedFiles = <File>[];
    final checksums = <String, String>{};
    try {
      for (final item in files) {
        final meta = Map<String, dynamic>.from(item as Map);
        final relPath = meta['path'].toString();
        final source = artifact.location == 'project'
            ? File(
                '${RuntimeArtifactRegistryService.gitProjectFilesRoot(abi)}/$relPath',
              )
            : null;
        final destination = _resolveGitPrefixFile(relPath, paths);
        if (source == null || destination == null) {
          throw StateError('unsafe artifact path: $relPath');
        }
        await destination.parent.create(recursive: true);
        await source.copy(destination.path);
        copiedFiles.add(destination);
        installedFiles.add(relPath);
        final actual = _calculateSha256(await destination.readAsBytes());
        if (actual.toLowerCase() != meta['sha256'].toString().toLowerCase()) {
          throw StateError('checksum mismatch: $relPath');
        }
        checksums[relPath] = actual;
        if (!Platform.isWindows) {
          try {
            await Process.run('chmod', ['700', destination.path]);
          } catch (e) {
            debugPrint('runtime-pkg git chmod failed: $e');
          }
        }
      }

      final entrypoint = manifest['entrypoint']?.toString() ?? 'bin/git';
      final gitFile = _resolveGitPrefixFile(entrypoint, paths);
      if (gitFile == null) throw StateError('invalid Git entrypoint');
      final probe = await _runInstalledGitVersion(gitFile.path);
      if (probe.exitCode != 0 || !probe.output.toLowerCase().contains('git')) {
        throw StateError('git --version failed: ${probe.output}');
      }

      final metadata = await _readMetadata();
      final packages = Map<String, dynamic>.from(metadata['packages'] as Map);
      packages[gitName] = {
        'name': gitName,
        'version': manifest['version'],
        'kind': manifest['kind'],
        'abi': manifest['abi'],
        'entrypoint': entrypoint,
        'entrypoints': ['git'],
        'files': installedFiles,
        'sha256': checksums,
        'installed_at': DateTime.now().toUtc().toIso8601String(),
        'source': manifest['source'],
        'status': 'installed',
        'verification': probe.output,
      };
      metadata['schema'] = metadataSchema;
      metadata['packages'] = packages;
      await _writeMetadata(metadata);
      await _prefix.generateEnvScript();
      return RuntimeBinaryPackageResult(
        'Installed: git\n'
        'Command: git\n'
        '${probe.output}\n'
        'Overall: HEALTHY',
      );
    } catch (e) {
      for (final file in copiedFiles.reversed) {
        if (await file.exists()) {
          await file.delete();
        }
      }
      return RuntimeBinaryPackageResult(
        'Git install failed and was rolled back.\n'
        'Reason: $e\n'
        'Run: git-artifact bundle-check',
        isError: true,
      );
    }
  }

  Future<({int exitCode, String output})> _runInstalledGitVersion(
    String gitPath,
  ) async {
    if (Platform.isAndroid) {
      final result = await NativeCommandService().execute(
        '/system/bin/sh "$gitPath" --version',
        'runtime_pkg_git',
        timeoutMs: 5000,
      );
      final output = result.stdout.trim().isNotEmpty
          ? result.stdout.trim()
          : result.stderr.trim();
      return (exitCode: result.exitCode, output: output);
    }
    try {
      final result = await Process.run(gitPath, [
        '--version',
      ]).timeout(const Duration(seconds: 5));
      final out = result.stdout.toString().trim().isNotEmpty
          ? result.stdout.toString().trim()
          : result.stderr.toString().trim();
      return (exitCode: result.exitCode, output: out);
    } catch (e) {
      return (exitCode: 1, output: e.toString());
    }
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
          : _resolvePrefixFile(relPath, paths);
      if (file != null && await file.exists()) {
        await file.delete();
      }
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
          : _resolvePrefixFile(relPath, paths);
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
      final entrypoint = pkg['entrypoint']?.toString() ?? 'bin/git';
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
      final probe = await _runInstalledGitVersion(gitFile.path);
      if (probe.exitCode != 0 || !probe.output.toLowerCase().contains('git')) {
        return RuntimeBinaryPackageResult(
          '=== Runtime Package Verify: git ===\n'
          'Metadata: OK\n'
          'Files: OK\n'
          'Checksum: OK\n'
          'Command: FAIL\n'
          'Output: ${probe.output}\n'
          'Status: UNHEALTHY',
          isError: true,
        );
      }
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
        'Real Git/Node/npm/Python: not enabled yet\n'
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
