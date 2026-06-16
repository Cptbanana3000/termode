import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'runtime_bootstrap_service.dart';
import 'package_manager_service.dart';

class RuntimeToolService {
  static final RuntimeToolService _instance = RuntimeToolService._internal();
  factory RuntimeToolService() => _instance;
  RuntimeToolService._internal();

  static const String helloTermodeScript = '#!/system/bin/sh\n'
      'echo "Hello from Termode runtime tools"\n';

  // Generate 32-bit FNV-1a checksum hash representation
  String _calculateFnv1a(String content) {
    final bytes = utf8.encode(content);
    int hash = 2166136261;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<bool> installTestTool() async {
    try {
      final paths = await RuntimeBootstrapService().getPaths();
      final binDir = paths['bin']!;
      final usrDir = paths['usr']!;

      // 1. Write hello-termode test tool
      final helloFile = File('$binDir/hello-termode');
      await helloFile.writeAsString(helloTermodeScript);

      // 2. Chmod +x hello-termode
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['+x', helloFile.path]);
        } catch (e) {
          debugPrint('Chmod failed: $e');
        }
      }

      // 3. Save metadata configuration first so updateShellHelpers sees it
      final metaFile = File('$usrDir/termode-tools.json');
      final checksum = _calculateFnv1a(helloTermodeScript);
      final now = DateTime.now().toIso8601String();

      final metadata = {
        'installedTools': ['hello-termode'],
        'version': '0.16.0',
        'installedAt': now,
        'managedBy': 'Termode',
        'checksums': {
          'hello-termode': checksum,
        }
      };

      await metaFile.writeAsString(jsonEncode(metadata));

      // 4. Update shell helpers using the centralized PackageManagerService function
      await PackageManagerService.updateShellHelpers();

      return true;
    } catch (e) {
      debugPrint('RuntimeToolService installTestTool error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> checkStatus() async {
    final paths = await RuntimeBootstrapService().getPaths();
    final binDir = paths['bin']!;
    final usrDir = paths['usr']!;

    final metaFile = File('$usrDir/termode-tools.json');
    final List<String> installed = [];
    final List<String> missing = [];
    final Map<String, String> chmodStatus = {};
    final Map<String, String> directExecStatus = {};
    final Map<String, String> interpreterStatus = {};
    String health = 'HEALTHY (no tools installed yet)';

    if (await metaFile.exists()) {
      try {
        final content = await metaFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final List<dynamic>? tools = data['installedTools'] as List<dynamic>?;
        if (tools != null && tools.isNotEmpty) {
          bool anyMissing = false;
          bool anyNonExecutableChmod = false;
          bool anyNonDirectExec = false;
          bool anyNonInterpreter = false;

          for (final toolNameObj in tools) {
            final toolName = toolNameObj.toString();
            final toolFile = File('$binDir/$toolName');

            if (await toolFile.exists()) {
              installed.add(toolName);
              
              // 1. Chmod executable bit
              bool isExec = true;
              if (!Platform.isWindows) {
                final stat = await toolFile.stat();
                isExec = (stat.mode & 0x49) != 0; // check user/group/others execute bit
              }
              chmodStatus[toolName] = isExec ? 'Yes' : 'No';
              if (!isExec) {
                anyNonExecutableChmod = true;
              }

              // 2. Android direct-exec supported
              bool directExec = true;
              if (Platform.isAndroid) {
                try {
                  final res = await Process.run(toolFile.path, []).timeout(const Duration(seconds: 2));
                  if (res.exitCode == 126 || res.stderr.toString().contains('Permission denied')) {
                    directExec = false;
                  }
                } catch (e) {
                  directExec = false;
                }
              }
              directExecStatus[toolName] = directExec ? 'Yes' : 'No';
              if (!directExec) {
                anyNonDirectExec = true;
              }

              // 3. Script interpreter runnable
              bool interpreterRunnable = false;
              try {
                final lines = await toolFile.readAsLines();
                if (lines.isNotEmpty && lines.first.startsWith('#!')) {
                  final interpreterPath = lines.first.substring(2).trim();
                  if (interpreterPath.isNotEmpty) {
                    final interpreterFile = File(interpreterPath);
                    if (await interpreterFile.exists()) {
                      interpreterRunnable = true;
                      if (!Platform.isWindows) {
                        final stat = await interpreterFile.stat();
                        interpreterRunnable = (stat.mode & 0x49) != 0;
                      }
                    }
                  }
                }
              } catch (_) {}
              interpreterStatus[toolName] = interpreterRunnable ? 'Yes' : 'No';
              if (!interpreterRunnable) {
                anyNonInterpreter = true;
              }
            } else {
              missing.add(toolName);
              anyMissing = true;
              chmodStatus[toolName] = 'Unknown';
              directExecStatus[toolName] = 'Unknown';
              interpreterStatus[toolName] = 'Unknown';
            }
          }

          if (anyMissing) {
            health = 'UNHEALTHY (missing tools: ${missing.join(", ")})';
          } else if (anyNonExecutableChmod || anyNonDirectExec || anyNonInterpreter) {
            final List<String> issues = [];
            if (anyNonExecutableChmod) issues.add('non-executable chmod');
            if (anyNonDirectExec) issues.add('direct exec blocked');
            if (anyNonInterpreter) issues.add('missing interpreter');
            health = 'UNHEALTHY (${issues.join(", ")})';
          } else {
            health = 'HEALTHY';
          }
        }
      } catch (e) {
        health = 'UNHEALTHY (corrupt metadata: $e)';
      }
    }

    return {
      'health': health,
      'binPath': binDir,
      'installedTools': installed,
      'missingTools': missing,
      'chmodStatus': chmodStatus,
      'directExecStatus': directExecStatus,
      'interpreterStatus': interpreterStatus,
    };
  }

  Future<bool> reset() async {
    try {
      final paths = await RuntimeBootstrapService().getPaths();
      final binDir = paths['bin']!;
      final usrDir = paths['usr']!;

      final metaFile = File('$usrDir/termode-tools.json');
      List<String> toolsToDelete = ['hello-termode'];

      if (await metaFile.exists()) {
        try {
          final content = await metaFile.readAsString();
          final data = jsonDecode(content) as Map<String, dynamic>;
          final List<dynamic>? tools = data['installedTools'] as List<dynamic>?;
          if (tools != null) {
            toolsToDelete = tools.map((e) => e.toString()).toList();
          }
        } catch (e) {
          debugPrint('Error reading metadata for reset: $e');
        }
      }

      // Delete installed tool files
      for (final toolName in toolsToDelete) {
        // Safety check: block path traversals
        if (toolName.contains('/') || toolName.contains('\\') || toolName.contains('..')) {
          continue;
        }
        final file = File('$binDir/$toolName');
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Delete metadata file first so updateShellHelpers knows it is gone
      if (await metaFile.exists()) {
        await metaFile.delete();
      }

      // Rebuild or delete helpers script file depending on package status
      await PackageManagerService.updateShellHelpers();

      return true;
    } catch (e) {
      debugPrint('RuntimeToolService reset error: $e');
      return false;
    }
  }
}
