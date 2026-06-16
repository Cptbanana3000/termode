import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'runtime_bootstrap_service.dart';

class PackageOperationResult {
  final String output;
  final bool isError;
  final bool changedHelpers;
  final String? executable;

  const PackageOperationResult({
    required this.output,
    this.isError = false,
    this.changedHelpers = false,
    this.executable,
  });
}

class _MetadataReadResult {
  final Map<String, dynamic> data;
  final bool exists;
  final bool isCorrupt;
  final String? error;

  const _MetadataReadResult({
    required this.data,
    required this.exists,
    this.isCorrupt = false,
    this.error,
  });
}

class PackageManagerService {
  static final PackageManagerService _instance =
      PackageManagerService._internal();
  factory PackageManagerService() => _instance;
  PackageManagerService._internal();

  static const int schemaVersion = 2;
  static const String managedBy = 'TermodePackageManager';
  static const String helperReloadCommand =
      '[ -f "\$TERMODE_USR/termode-shell-helpers.sh" ] && . "\$TERMODE_USR/termode-shell-helpers.sh"';

  static const Map<String, Map<String, dynamic>> localIndex = {
    'hello': {
      'name': 'hello',
      'version': '1.0.0',
      'type': 'script',
      'description': 'Prints a hello message from Termode package manager.',
      'executable': 'hello',
      'files': {
        'usr/bin/hello':
            '#!/system/bin/sh\necho "Hello from Termode package manager!"\n',
      },
    },
    'cowsay-lite': {
      'name': 'cowsay-lite',
      'version': '1.0.0',
      'type': 'script',
      'description': 'Prints text in a simple ASCII speech bubble.',
      'executable': 'cowsay-lite',
      'files': {
        'usr/bin/cowsay-lite':
            '#!/system/bin/sh\n'
            'if [ \$# -eq 0 ]; then\n'
            '  msg="Moo"\n'
            'else\n'
            '  msg="\$*"\n'
            'fi\n'
            'echo " ____________________"\n'
            'echo "< \$msg >"\n'
            'echo " --------------------"\n'
            'echo \'        \\   ^__^\'\n'
            'echo \'         \\  (oo)\\_______\'\n'
            'echo \'            (__)\\       )\\/\\\'\n'
            'echo \'                ||----w |\'\n'
            'echo \'                ||     ||\'\n',
      },
    },
    'sysinfo-lite': {
      'name': 'sysinfo-lite',
      'version': '1.0.0',
      'type': 'script',
      'description':
          'Prints basic Android/system information using shell commands.',
      'executable': 'sysinfo-lite',
      'files': {
        'usr/bin/sysinfo-lite':
            '#!/system/bin/sh\n'
            'echo "=== Termode System Information ==="\n'
            'echo "OS: \$(uname -o 2>/dev/null || echo Android)"\n'
            'echo "Kernel: \$(uname -r)"\n'
            'echo "Uptime: \$(uptime)"\n'
            'echo "Device Model: \$(getprop ro.product.model 2>/dev/null || echo Unknown)"\n'
            'echo "Brand: \$(getprop ro.product.brand 2>/dev/null || echo Unknown)"\n'
            'echo "Android Version: \$(getprop ro.build.version.release 2>/dev/null || echo Unknown)"\n'
            'echo "CPU Architecture: \$(getprop ro.product.cpu.abi 2>/dev/null || echo Unknown)"\n',
      },
    },
  };

  String _calculateFnv1a(String content) {
    final bytes = utf8.encode(content);
    int hash = 2166136261;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Map<String, dynamic> _emptyMetadata() {
    return {'schemaVersion': schemaVersion, 'packages': <String, dynamic>{}};
  }

  Future<Map<String, String>> _paths() async {
    final paths = await RuntimeBootstrapService().getPaths();
    final filesDir = '${paths['home']!}/..';
    return {'files': filesDir, 'usr': paths['usr']!, 'bin': paths['bin']!};
  }

  File _metadataFile(String usrDir) => File('$usrDir/termode-packages.json');

  String _normalizePath(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    final result = <String>[];
    for (final part in parts) {
      if (part.isEmpty || part == '.') {
        continue;
      }
      if (part == '..') {
        if (result.isNotEmpty) {
          result.removeLast();
        }
      } else {
        result.add(part);
      }
    }
    final prefix = path.startsWith('/') || path.contains(':') ? '' : '/';
    return '$prefix${result.join('/')}';
  }

  bool _isSafePackageName(String name) {
    return name.isNotEmpty &&
        !name.contains('/') &&
        !name.contains('\\') &&
        !name.contains('..');
  }

  bool _isSafeManagedRelPath(String relPath) {
    if (relPath.isEmpty ||
        relPath.contains('..') ||
        relPath.startsWith('/') ||
        relPath.contains('\\') ||
        !relPath.startsWith('usr/bin/')) {
      return false;
    }
    final segments = relPath.split('/');
    return segments.every((segment) => segment.isNotEmpty && segment != '.');
  }

  File? _resolveManagedFile(String filesDir, String relPath) {
    if (!_isSafeManagedRelPath(relPath)) {
      return null;
    }

    final target = File('$filesDir/$relPath');
    final normalizedTarget = _normalizePath(target.path);
    final normalizedBin = _normalizePath('$filesDir/usr/bin');
    if (normalizedTarget == normalizedBin ||
        normalizedTarget.startsWith('$normalizedBin/')) {
      return target;
    }
    return null;
  }

  Future<_MetadataReadResult> _readMetadata({bool missingOk = true}) async {
    final paths = await _paths();
    final file = _metadataFile(paths['usr']!);
    if (!await file.exists()) {
      if (missingOk) {
        return _MetadataReadResult(data: _emptyMetadata(), exists: false);
      }
      return _MetadataReadResult(
        data: _emptyMetadata(),
        exists: false,
        isCorrupt: true,
        error: 'metadata missing',
      );
    }

    try {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      data['schemaVersion'] = data['schemaVersion'] ?? 1;
      data['packages'] ??= <String, dynamic>{};
      if (data['packages'] is! Map) {
        return _MetadataReadResult(
          data: _emptyMetadata(),
          exists: true,
          isCorrupt: true,
          error: 'packages field is not an object',
        );
      }
      return _MetadataReadResult(data: data, exists: true);
    } catch (e) {
      return _MetadataReadResult(
        data: _emptyMetadata(),
        exists: true,
        isCorrupt: true,
        error: e.toString(),
      );
    }
  }

  Future<void> _writeMetadata(Map<String, dynamic> data) async {
    final paths = await _paths();
    final file = _metadataFile(paths['usr']!);
    data['schemaVersion'] = schemaVersion;
    data['packages'] ??= <String, dynamic>{};
    await file.writeAsString(jsonEncode(data));
  }

  Map<String, dynamic> _packageMetadata(
    String pkgName,
    Map<String, dynamic> pkg,
    List<String> installedFiles,
    Map<String, String> checksums, {
    String? installedAt,
  }) {
    final now = DateTime.now().toIso8601String();
    return {
      'name': pkg['name'] ?? pkgName,
      'version': pkg['version'],
      'type': pkg['type'],
      'description': pkg['description'],
      'executable': pkg['executable'],
      'installedAt': installedAt ?? now,
      'updatedAt': now,
      'source': 'local',
      'files': installedFiles,
      'checksums': checksums,
      'managedBy': managedBy,
    };
  }

  Future<String?> _writePackageFiles(
    String filesDir,
    Map<String, dynamic> pkg,
    List<String> installedFiles,
    Map<String, String> checksums,
  ) async {
    final filesMap = pkg['files'] as Map;
    for (final entry in filesMap.entries) {
      final relPath = entry.key.toString();
      final fileContent = entry.value.toString();
      final file = _resolveManagedFile(filesDir, relPath);
      if (file == null) {
        return 'Error: path traversal detected';
      }

      await file.parent.create(recursive: true);
      await file.writeAsString(fileContent);
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['+x', file.path]);
        } catch (e) {
          debugPrint('Chmod failed: $e');
        }
      }
      installedFiles.add(relPath);
      checksums[relPath] = _calculateFnv1a(fileContent);
    }
    return null;
  }

  Future<PackageOperationResult> _installPackageIntoMetadata(
    String pkgName,
    Map<String, dynamic> data, {
    String? installedAt,
    required String successVerb,
  }) async {
    if (!_isSafePackageName(pkgName)) {
      return const PackageOperationResult(
        output: 'Error: invalid package name',
        isError: true,
      );
    }

    final paths = await _paths();
    final pkg = localIndex[pkgName];
    if (pkg == null) {
      return PackageOperationResult(
        output: 'Error: package not found: $pkgName',
        isError: true,
      );
    }

    final installedFiles = <String>[];
    final checksums = <String, String>{};
    final writeError = await _writePackageFiles(
      paths['files']!,
      pkg,
      installedFiles,
      checksums,
    );
    if (writeError != null) {
      return PackageOperationResult(output: writeError, isError: true);
    }

    final packages = data['packages'] as Map;
    packages[pkgName] = _packageMetadata(
      pkgName,
      pkg,
      installedFiles,
      checksums,
      installedAt: installedAt,
    );

    await _writeMetadata(data);
    await updateShellHelpers();

    return PackageOperationResult(
      output: '$successVerb package $pkgName',
      changedHelpers: true,
      executable: pkg['executable'] as String? ?? pkgName,
    );
  }

  Future<void> _deleteManagedFiles(
    String filesDir,
    Map<dynamic, dynamic> pkgInfo,
  ) async {
    final filesList = pkgInfo['files'] as List? ?? [];
    for (final fileObj in filesList) {
      final relPath = fileObj.toString();
      final file = _resolveManagedFile(filesDir, relPath);
      if (file != null && await file.exists()) {
        await file.delete();
      }
    }
  }

  int _compareVersions(String a, String b) {
    final left = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final right = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final len = left.length > right.length ? left.length : right.length;
    for (int i = 0; i < len; i++) {
      final lv = i < left.length ? left[i] : 0;
      final rv = i < right.length ? right[i] : 0;
      if (lv != rv) {
        return lv.compareTo(rv);
      }
    }
    return 0;
  }

  bool _isExecutableMode(FileStat stat) {
    if (Platform.isWindows) {
      return true;
    }
    return (stat.mode & 0x49) != 0;
  }

  Future<bool> _helperHasExecutable(String executable) async {
    final paths = await _paths();
    final helpersFile = File('${paths['usr']}/termode-shell-helpers.sh');
    if (!await helpersFile.exists()) {
      return false;
    }
    final content = await helpersFile.readAsString();
    return content.contains('$executable() {') ||
        content.contains('alias $executable=');
  }

  Future<Map<String, dynamic>> updateIndex() async {
    return {
      'success': true,
      'message': 'Loaded local Termode package index.',
      'count': localIndex.length,
    };
  }

  Future<PackageOperationResult> installPackage(String pkgName) async {
    try {
      final meta = await _readMetadata();
      if (meta.isCorrupt) {
        return const PackageOperationResult(
          output: 'Error: metadata corrupted',
          isError: true,
        );
      }
      final packages = meta.data['packages'] as Map;
      if (packages.containsKey(pkgName)) {
        return PackageOperationResult(
          output: 'Error: package already installed: $pkgName',
          isError: true,
        );
      }
      return _installPackageIntoMetadata(
        pkgName,
        meta.data,
        successVerb: 'Success: Installed',
      );
    } catch (e) {
      return PackageOperationResult(
        output: 'Error: install failed: $e',
        isError: true,
      );
    }
  }

  Future<PackageOperationResult> removePackage(String pkgName) async {
    try {
      final meta = await _readMetadata();
      if (meta.isCorrupt) {
        return const PackageOperationResult(
          output: 'Error: metadata corrupted',
          isError: true,
        );
      }
      final packages = meta.data['packages'] as Map;
      if (!packages.containsKey(pkgName)) {
        return PackageOperationResult(
          output: 'Error: package not installed: $pkgName',
          isError: true,
        );
      }

      final paths = await _paths();
      final pkgInfo = Map<dynamic, dynamic>.from(packages[pkgName] as Map);
      await _deleteManagedFiles(paths['files']!, pkgInfo);
      packages.remove(pkgName);
      await _writeMetadata(meta.data);
      await updateShellHelpers();

      final executable =
          pkgInfo['executable'] as String? ??
          localIndex[pkgName]?['executable'] as String? ??
          pkgName;
      return PackageOperationResult(
        output: 'Success: Removed package $pkgName',
        changedHelpers: true,
        executable: executable,
      );
    } catch (e) {
      return PackageOperationResult(
        output: 'Error: remove failed: $e',
        isError: true,
      );
    }
  }

  Future<PackageOperationResult> reinstallPackage(String pkgName) async {
    try {
      final meta = await _readMetadata();
      if (meta.isCorrupt) {
        return const PackageOperationResult(
          output: 'Error: metadata corrupted',
          isError: true,
        );
      }
      final packages = meta.data['packages'] as Map;
      final existing = packages[pkgName];
      if (existing != null) {
        final paths = await _paths();
        final pkgInfo = Map<dynamic, dynamic>.from(existing as Map);
        await _deleteManagedFiles(paths['files']!, pkgInfo);
        packages.remove(pkgName);
        return _installPackageIntoMetadata(
          pkgName,
          meta.data,
          installedAt: pkgInfo['installedAt'] as String?,
          successVerb: 'Reinstalled',
        );
      }
      return _installPackageIntoMetadata(
        pkgName,
        meta.data,
        successVerb: 'Success: Installed',
      );
    } catch (e) {
      return PackageOperationResult(
        output: 'Error: reinstall failed: $e',
        isError: true,
      );
    }
  }

  Future<PackageOperationResult> upgradePackages() async {
    try {
      final meta = await _readMetadata();
      if (meta.isCorrupt) {
        return const PackageOperationResult(
          output: 'Error: metadata corrupted',
          isError: true,
        );
      }

      final packages = meta.data['packages'] as Map;
      final upgraded = <String>[];
      final skipped = <String>[];
      final paths = await _paths();

      for (final entry in packages.entries.toList()) {
        final pkgName = entry.key.toString();
        final installed = Map<dynamic, dynamic>.from(entry.value as Map);
        final local = localIndex[pkgName];
        if (local == null) {
          skipped.add(pkgName);
          continue;
        }
        final installedVersion = installed['version']?.toString() ?? '0.0.0';
        final localVersion = local['version']?.toString() ?? '0.0.0';
        if (_compareVersions(installedVersion, localVersion) < 0) {
          await _deleteManagedFiles(paths['files']!, installed);
          packages.remove(pkgName);
          final result = await _installPackageIntoMetadata(
            pkgName,
            meta.data,
            installedAt: installed['installedAt'] as String?,
            successVerb: 'Upgraded',
          );
          if (result.isError) {
            return result;
          }
          upgraded.add('$pkgName $installedVersion -> $localVersion');
        }
      }

      if (upgraded.isEmpty) {
        final suffix = skipped.isEmpty
            ? ''
            : '\nSkipped packages no longer in local index: ${skipped.join(", ")}';
        return PackageOperationResult(
          output: 'All packages are up to date.$suffix',
        );
      }

      await updateShellHelpers();
      return PackageOperationResult(
        output:
            'Upgraded packages:\n${upgraded.map((p) => '  - $p').join('\n')}',
        changedHelpers: true,
      );
    } catch (e) {
      return PackageOperationResult(
        output: 'Error: upgrade failed: $e',
        isError: true,
      );
    }
  }

  Future<PackageOperationResult> repairPackages() async {
    try {
      final meta = await _readMetadata();
      if (meta.isCorrupt) {
        return PackageOperationResult(
          output:
              'Error: metadata corrupted. Cannot repair safely: ${meta.error}',
          isError: true,
        );
      }

      final packages = meta.data['packages'] as Map;
      final paths = await _paths();
      final fixedFiles = <String>[];
      final missingPackages = <String>[];

      for (final entry in packages.entries.toList()) {
        final pkgName = entry.key.toString();
        final local = localIndex[pkgName];
        if (local == null) {
          packages.remove(pkgName);
          missingPackages.add(pkgName);
          continue;
        }

        final installed = Map<dynamic, dynamic>.from(entry.value as Map);
        final filesMap = local['files'] as Map;
        final installedFiles = <String>[];
        final checksums = <String, String>{};
        for (final fileEntry in filesMap.entries) {
          final relPath = fileEntry.key.toString();
          final expectedContent = fileEntry.value.toString();
          final file = _resolveManagedFile(paths['files']!, relPath);
          if (file == null) {
            continue;
          }
          final expectedChecksum = _calculateFnv1a(expectedContent);
          final exists = await file.exists();
          String? actualChecksum;
          if (exists) {
            actualChecksum = _calculateFnv1a(await file.readAsString());
          }
          if (!exists || actualChecksum != expectedChecksum) {
            await file.parent.create(recursive: true);
            await file.writeAsString(expectedContent);
            if (!Platform.isWindows) {
              try {
                await Process.run('chmod', ['+x', file.path]);
              } catch (e) {
                debugPrint('Chmod failed: $e');
              }
            }
            fixedFiles.add(relPath);
          }
          installedFiles.add(relPath);
          checksums[relPath] = expectedChecksum;
        }

        packages[pkgName] = _packageMetadata(
          pkgName,
          local,
          installedFiles,
          checksums,
          installedAt: installed['installedAt'] as String?,
        );
      }

      await _writeMetadata(meta.data);
      await updateShellHelpers();

      final doctor = await checkDoctor();
      final isHealthy = doctor['repairRecommended'] != true;
      final buf = StringBuffer();
      buf.writeln('=== Package Repair ===');
      buf.writeln(
        'Fixed Files: ${fixedFiles.isEmpty ? "None" : fixedFiles.join(", ")}',
      );
      buf.writeln(
        'Missing Packages Removed From Metadata: ${missingPackages.isEmpty ? "None" : missingPackages.join(", ")}',
      );
      buf.writeln('Helper Regeneration: OK');
      buf.write(
        'Final Health: ${isHealthy ? "HEALTHY" : "REPAIR RECOMMENDED"}',
      );

      return PackageOperationResult(
        output: buf.toString(),
        changedHelpers: true,
      );
    } catch (e) {
      return PackageOperationResult(
        output: 'Error: repair failed: $e',
        isError: true,
      );
    }
  }

  Future<PackageOperationResult> cleanPackages() async {
    try {
      final meta = await _readMetadata();
      if (meta.isCorrupt) {
        return const PackageOperationResult(
          output:
              'Error: metadata corrupted. Run pkg repair after fixing metadata.',
          isError: true,
        );
      }

      final paths = await _paths();
      final usrDir = paths['usr']!;
      final cleaned = <String>[];
      final controlledFiles = [
        File('$usrDir/termode-packages.json.tmp'),
        File('$usrDir/termode-packages.json.bak'),
        File('$usrDir/termode-shell-helpers.sh.tmp'),
        File('$usrDir/termode-shell-helpers.sh.bak'),
      ];

      for (final file in controlledFiles) {
        if (await file.exists()) {
          await file.delete();
          cleaned.add(file.path.split(Platform.pathSeparator).last);
        }
      }

      await updateShellHelpers();
      final buf = StringBuffer();
      buf.writeln('=== Package Clean ===');
      buf.writeln(
        'Cleaned: ${cleaned.isEmpty ? "Nothing to clean" : cleaned.join(", ")}',
      );
      buf.writeln('Unmanaged files: preserved');
      buf.write('Scope: files/usr package metadata and helper backups only');
      return PackageOperationResult(
        output: buf.toString(),
        changedHelpers: cleaned.isNotEmpty,
      );
    } catch (e) {
      return PackageOperationResult(
        output: 'Error: clean failed: $e',
        isError: true,
      );
    }
  }

  Future<PackageOperationResult> packageFiles(String pkgName) async {
    final meta = await _readMetadata();
    if (meta.isCorrupt) {
      return const PackageOperationResult(
        output: 'Error: metadata corrupted',
        isError: true,
      );
    }
    final packages = meta.data['packages'] as Map;
    if (!packages.containsKey(pkgName)) {
      return PackageOperationResult(
        output: 'Error: package not installed: $pkgName',
        isError: true,
      );
    }

    final paths = await _paths();
    final pkgInfo = Map<dynamic, dynamic>.from(packages[pkgName] as Map);
    final files = pkgInfo['files'] as List? ?? [];
    final checksums = Map<dynamic, dynamic>.from(
      pkgInfo['checksums'] as Map? ?? {},
    );
    final sb = StringBuffer();
    sb.writeln('=== Package Files: $pkgName ===');
    for (final fileObj in files) {
      final relPath = fileObj.toString();
      final file = _resolveManagedFile(paths['files']!, relPath);
      final exists = file != null && await file.exists();
      final executable = exists ? _isExecutableMode(await file.stat()) : false;
      sb.writeln(relPath);
      sb.writeln('  checksum: ${checksums[relPath] ?? "missing"}');
      sb.writeln('  exists: ${exists ? "YES" : "NO"}');
      sb.writeln('  managed: ${file != null ? "YES" : "NO"}');
      sb.writeln('  chmod executable: ${executable ? "YES" : "NO"}');
      sb.writeln(
        '  direct Android exec may be blocked: ${Platform.isAndroid ? "YES" : "UNKNOWN"}',
      );
    }
    return PackageOperationResult(output: sb.toString().trimRight());
  }

  Future<PackageOperationResult> verifyPackage(String pkgName) async {
    final meta = await _readMetadata();
    if (meta.isCorrupt) {
      return const PackageOperationResult(
        output: 'Error: metadata corrupted',
        isError: true,
      );
    }
    final packages = meta.data['packages'] as Map;
    if (!packages.containsKey(pkgName)) {
      return PackageOperationResult(
        output: 'FAIL: package not installed: $pkgName',
        isError: true,
      );
    }

    final paths = await _paths();
    final pkgInfo = Map<dynamic, dynamic>.from(packages[pkgName] as Map);
    final files = pkgInfo['files'] as List? ?? [];
    final checksums = Map<dynamic, dynamic>.from(
      pkgInfo['checksums'] as Map? ?? {},
    );
    final executable = pkgInfo['executable'] as String? ?? pkgName;
    final issues = <String>[];

    for (final fileObj in files) {
      final relPath = fileObj.toString();
      final file = _resolveManagedFile(paths['files']!, relPath);
      if (file == null) {
        issues.add('$relPath is not a safe managed path');
        continue;
      }
      if (!await file.exists()) {
        issues.add('$relPath is missing');
        continue;
      }
      final expected = checksums[relPath]?.toString();
      final actual = _calculateFnv1a(await file.readAsString());
      if (expected == null || expected != actual) {
        issues.add('$relPath checksum mismatch');
      }
    }

    if (!await _helperHasExecutable(executable)) {
      issues.add('helper function missing for $executable');
    }

    final sb = StringBuffer();
    sb.writeln('=== Package Verify: $pkgName ===');
    if (issues.isEmpty) {
      sb.write('Result: PASS');
      return PackageOperationResult(output: sb.toString());
    }

    sb.writeln('Result: FAIL');
    for (final issue in issues) {
      sb.writeln('  - $issue');
    }
    return PackageOperationResult(
      output: sb.toString().trimRight(),
      isError: true,
    );
  }

  Future<Map<String, dynamic>> checkDoctor() async {
    final paths = await _paths();
    final binDir = paths['bin']!;
    final usrDir = paths['usr']!;
    final filesDir = paths['files']!;

    final pkgsMetaFile = _metadataFile(usrDir);
    final helpersFile = File('$usrDir/termode-shell-helpers.sh');

    int installedCount = 0;
    int brokenPackageCount = 0;
    final List<String> missingFiles = [];
    bool hasHelpers = await helpersFile.exists();
    bool hasMeta = await pkgsMetaFile.exists();
    bool helpersGenerated = false;
    int helperFunctionCount = 0;
    String? metadataError;

    final meta = await _readMetadata();
    if (meta.isCorrupt) {
      metadataError = meta.error ?? 'metadata corrupted';
    } else {
      final packages = meta.data['packages'] as Map;
      installedCount = packages.length;
      for (final pkgEntry in packages.entries) {
        bool packageBroken = false;
        final pkg = Map<dynamic, dynamic>.from(pkgEntry.value as Map);
        final files = pkg['files'] as List? ?? [];
        for (final f in files) {
          final relPath = f.toString();
          final file = _resolveManagedFile(filesDir, relPath);
          if (file == null || !await file.exists()) {
            missingFiles.add(relPath);
            packageBroken = true;
          }
        }
        if (!localIndex.containsKey(pkgEntry.key.toString())) {
          packageBroken = true;
        }
        if (packageBroken) {
          brokenPackageCount++;
        }
      }
    }

    if (hasHelpers) {
      try {
        final content = await helpersFile.readAsString();
        helperFunctionCount = RegExp(r'\(\)\s*\{').allMatches(content).length;
        helpersGenerated =
            helperFunctionCount > 0 ||
            content.contains('unalias ') ||
            content.contains('unset -f ');
      } catch (_) {}
    }

    final repairRecommended =
        metadataError != null ||
        brokenPackageCount > 0 ||
        missingFiles.isNotEmpty ||
        (installedCount > 0 && !hasHelpers);

    return {
      'metadataPath': pkgsMetaFile.path,
      'binPath': binDir,
      'helperPath': helpersFile.path,
      'installedCount': installedCount,
      'brokenPackageCount': brokenPackageCount,
      'missingFileCount': missingFiles.length,
      'helperExists': hasHelpers,
      'metadataExists': hasMeta,
      'metadataError': metadataError,
      'missingFiles': missingFiles,
      'helpersGenerated': helpersGenerated,
      'helperFunctionCount': helperFunctionCount,
      'helperReloadCommand': helperReloadCommand,
      'mayNeedReload': hasHelpers,
      'repairRecommended': repairRecommended,
    };
  }

  static Future<void> updateShellHelpers() async {
    final service = PackageManagerService();
    final paths = await service._paths();
    final usrDir = paths['usr']!;

    final sb = StringBuffer();
    sb.writeln('# Termode runtime shell helpers and aliases');
    sb.writeln('# Generated automatically. Do not edit manually.');
    sb.writeln();
    sb.writeln(
      '# Clear stale helpers before defining the currently installed set.',
    );
    sb.writeln('unalias hello-termode 2>/dev/null');
    for (final pkg in localIndex.values) {
      final execName = pkg['executable'] as String?;
      if (execName != null && execName.isNotEmpty) {
        sb.writeln('unset -f $execName 2>/dev/null');
      }
    }
    sb.writeln('hash -r 2>/dev/null');
    sb.writeln();

    final toolsMetaFile = File('$usrDir/termode-tools.json');
    if (await toolsMetaFile.exists()) {
      try {
        final content = await toolsMetaFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final List<dynamic>? tools = data['installedTools'] as List<dynamic>?;
        if (tools != null && tools.contains('hello-termode')) {
          sb.writeln(
            'alias hello-termode=\'sh "\$TERMODE_BIN/hello-termode"\'',
          );
        }
      } catch (_) {}
    }

    final meta = await service._readMetadata();
    if (!meta.isCorrupt) {
      final packages = meta.data['packages'] as Map;
      if (packages.isNotEmpty) {
        for (final pkgEntry in packages.values) {
          final pkg = Map<dynamic, dynamic>.from(pkgEntry as Map);
          final execName = pkg['executable'] as String?;
          if (execName != null && execName.isNotEmpty) {
            sb.writeln();
            sb.writeln('$execName() {');
            sb.writeln('  /system/bin/sh "\$TERMODE_BIN/$execName" "\$@"');
            sb.writeln('}');
          }
        }
      }
    }

    final helpersFile = File('$usrDir/termode-shell-helpers.sh');
    await helpersFile.writeAsString(sb.toString());
  }
}
