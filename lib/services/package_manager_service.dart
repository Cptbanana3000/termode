import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'runtime_bootstrap_service.dart';

class PackageManagerService {
  static final PackageManagerService _instance =
      PackageManagerService._internal();
  factory PackageManagerService() => _instance;
  PackageManagerService._internal();

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

  Future<Map<String, dynamic>> updateIndex() async {
    return {
      'success': true,
      'message': 'Loaded local Termode package index.',
      'count': localIndex.length,
    };
  }

  Future<String> installPackage(String pkgName) async {
    try {
      final paths = await RuntimeBootstrapService().getPaths();
      final usrDir = paths['usr']!;
      final baseDir = '${paths['home']!}/..'; // files/ dir

      final pkg = localIndex[pkgName];
      if (pkg == null) {
        return 'Error: package not found: $pkgName';
      }

      final pkgsMetaFile = File('$usrDir/termode-packages.json');
      Map<String, dynamic> installedData = {'packages': <String, dynamic>{}};
      if (await pkgsMetaFile.exists()) {
        try {
          final content = await pkgsMetaFile.readAsString();
          installedData = jsonDecode(content) as Map<String, dynamic>;
          installedData['packages'] ??= <String, dynamic>{};
        } catch (_) {
          return 'Error: metadata corrupted';
        }
      }

      final packages = installedData['packages'] as Map;
      if (packages.containsKey(pkgName)) {
        return 'Error: package already installed: $pkgName';
      }

      // Write package script files
      final filesMap = pkg['files'] as Map;
      final List<String> installedFiles = [];
      final Map<String, String> checksums = {};

      for (final entry in filesMap.entries) {
        final relPath = entry.key; // e.g. usr/bin/hello
        final fileContent = entry.value;

        // Safety check: block path traversals
        if (relPath.contains('..') ||
            relPath.startsWith('/') ||
            relPath.contains('\\')) {
          return 'Error: path traversal detected';
        }

        final file = File('$baseDir/$relPath');
        // Create parent directories if missing
        await file.parent.create(recursive: true);
        await file.writeAsString(fileContent);

        // Chmod +x if Unix
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

      // Record installed package metadata
      final now = DateTime.now().toIso8601String();
      packages[pkgName] = {
        'name': pkg['name'],
        'version': pkg['version'],
        'type': pkg['type'],
        'description': pkg['description'],
        'executable': pkg['executable'],
        'installedAt': now,
        'files': installedFiles,
        'checksums': checksums,
        'managedBy': 'TermodePackageManager',
      };

      await pkgsMetaFile.writeAsString(jsonEncode(installedData));

      // Regenerate helper functions inside termode-shell-helpers.sh
      await updateShellHelpers();

      return 'Success: Installed package $pkgName';
    } catch (e) {
      return 'Error: install failed: $e';
    }
  }

  Future<String> removePackage(String pkgName) async {
    try {
      final paths = await RuntimeBootstrapService().getPaths();
      final usrDir = paths['usr']!;
      final baseDir = '${paths['home']!}/..'; // files/ dir

      final pkgsMetaFile = File('$usrDir/termode-packages.json');
      if (!await pkgsMetaFile.exists()) {
        return 'Error: package not installed: $pkgName';
      }

      Map<String, dynamic> installedData;
      try {
        final content = await pkgsMetaFile.readAsString();
        installedData = jsonDecode(content) as Map<String, dynamic>;
        installedData['packages'] ??= <String, dynamic>{};
      } catch (_) {
        return 'Error: metadata corrupted';
      }

      final packages = installedData['packages'] as Map;
      if (!packages.containsKey(pkgName)) {
        return 'Error: package not installed: $pkgName';
      }

      final pkgInfo = packages[pkgName] as Map;
      final filesList = pkgInfo['files'] as List;

      // Delete only registered files
      for (final fileObj in filesList) {
        final relPath = fileObj.toString();

        // Safety check: block path traversals and restrict to Termode usr/bin
        if (relPath.contains('..') ||
            relPath.startsWith('/') ||
            relPath.contains('\\') ||
            !relPath.startsWith('usr/bin/')) {
          continue;
        }

        final file = File('$baseDir/$relPath');
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Remove metadata entry
      packages.remove(pkgName);
      await pkgsMetaFile.writeAsString(jsonEncode(installedData));

      // Regenerate helper functions inside termode-shell-helpers.sh
      await updateShellHelpers();

      return 'Success: Removed package $pkgName';
    } catch (e) {
      return 'Error: remove failed: $e';
    }
  }

  Future<Map<String, dynamic>> checkDoctor() async {
    final paths = await RuntimeBootstrapService().getPaths();
    final binDir = paths['bin']!;
    final usrDir = paths['usr']!;

    final pkgsMetaFile = File('$usrDir/termode-packages.json');
    final helpersFile = File('$usrDir/termode-shell-helpers.sh');

    int installedCount = 0;
    final List<String> missingFiles = [];
    bool hasHelpers = await helpersFile.exists();
    bool hasMeta = await pkgsMetaFile.exists();
    bool helpersGenerated = false;
    int helperFunctionCount = 0;

    if (hasMeta) {
      try {
        final content = await pkgsMetaFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final packages = data['packages'] as Map?;
        if (packages != null) {
          installedCount = packages.length;
          final baseDir = '${paths['home']!}/..';
          for (final pkgEntry in packages.values) {
            final pkg = pkgEntry as Map;
            final files = pkg['files'] as List?;
            if (files != null) {
              for (final f in files) {
                final file = File('$baseDir/${f.toString()}');
                if (!await file.exists()) {
                  missingFiles.add(f.toString());
                }
              }
            }
          }
        }
      } catch (_) {}
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

    return {
      'metadataPath': pkgsMetaFile.path,
      'binPath': binDir,
      'helperPath': helpersFile.path,
      'installedCount': installedCount,
      'helperExists': hasHelpers,
      'metadataExists': hasMeta,
      'missingFiles': missingFiles,
      'helpersGenerated': helpersGenerated,
      'helperFunctionCount': helperFunctionCount,
      'helperReloadCommand':
          '[ -f "\$TERMODE_USR/termode-shell-helpers.sh" ] && . "\$TERMODE_USR/termode-shell-helpers.sh"',
      'mayNeedReload': hasHelpers,
    };
  }

  static Future<void> updateShellHelpers() async {
    final paths = await RuntimeBootstrapService().getPaths();
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

    // 1. Check tools metadata for hello-termode
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

    // 2. Check packages metadata for shell functions
    final pkgsMetaFile = File('$usrDir/termode-packages.json');
    if (await pkgsMetaFile.exists()) {
      try {
        final content = await pkgsMetaFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final packages = data['packages'] as Map?;
        if (packages != null && packages.isNotEmpty) {
          for (final pkgEntry in packages.values) {
            final pkg = pkgEntry as Map;
            final execName = pkg['executable'] as String?;
            if (execName != null && execName.isNotEmpty) {
              sb.writeln();
              sb.writeln('$execName() {');
              sb.writeln('  /system/bin/sh "\$TERMODE_BIN/$execName" "\$@"');
              sb.writeln('}');
            }
          }
        }
      } catch (_) {}
    }

    final helpersFile = File('$usrDir/termode-shell-helpers.sh');
    await helpersFile.writeAsString(sb.toString());
  }
}
