import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'virtual_filesystem.dart';
import 'native_command_service.dart';
import 'runtime_bootstrap_service.dart';
import 'storage_access_service.dart';
import 'terminal_session_service.dart';
import 'settings_service.dart';
import 'runtime_tool_service.dart';
import 'package_manager_service.dart';

class CommandResult {
  final String output;
  final bool isError;
  final bool shouldClear;
  final bool shouldReloadShellHelpers;
  final String? helperReloadSuccessMessage;
  final String? helperReloadFailureMessage;

  CommandResult({
    required this.output,
    this.isError = false,
    this.shouldClear = false,
    this.shouldReloadShellHelpers = false,
    this.helperReloadSuccessMessage,
    this.helperReloadFailureMessage,
  });
}

class CommandService {
  final VirtualFileSystem vfs;
  final String sessionId;

  CommandService(this.vfs, this.sessionId);

  String _formatStorageError(PlatformException e) {
    switch (e.code) {
      case 'NOT_LINKED':
        return 'Error: No storage folder is currently linked. Use "storage-link" to connect one.';
      case 'FILE_NOT_FOUND':
        return 'Error: File not found in linked storage.';
      case 'PERMISSION_REVOKED':
        return 'Error: Permission revoked or folder access denied.';
      case 'WRITE_FAILED':
        return 'Error: Write operation failed.';
      case 'UNSUPPORTED_FOLDER':
        return 'Error: Unsupported folder selected.';
      default:
        return 'Error: ${e.message ?? e.code}';
    }
  }

  String _normalizePath(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    final List<String> result = [];
    for (final part in parts) {
      if (part == '' || part == '.') {
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
    final prefix = path.startsWith('/') ? '/' : '';
    return prefix + result.join('/');
  }

  File? _resolveFileInHome(String inputPath, String homePath) {
    final combined = '$homePath/$inputPath';
    final normalized = _normalizePath(combined);
    final normalizedHome = _normalizePath(homePath);

    if (normalized == normalizedHome ||
        normalized.startsWith('$normalizedHome/')) {
      return File(normalized);
    }
    return null; // Path traversal detected!
  }

  // Parse arguments, supporting double-quoted string groupings
  List<String> _parseArgs(String input) {
    final List<String> args = [];
    final RegExp regex = RegExp(r'"([^"]*)"|([^\s]+)');
    final Iterable<RegExpMatch> matches = regex.allMatches(input);
    for (final match in matches) {
      if (match.group(1) != null) {
        args.add(match.group(1)!);
      } else if (match.group(2) != null) {
        args.add(match.group(2)!);
      }
    }
    return args;
  }

  Future<Map<String, dynamic>> _getInstalledPackages(String usrDir) async {
    final pkgsMetaFile = File('$usrDir/termode-packages.json');
    if (await pkgsMetaFile.exists()) {
      try {
        final content = await pkgsMetaFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        return Map<String, dynamic>.from(data['packages'] ?? {});
      } catch (_) {}
    }
    return {};
  }

  Future<CommandResult> execute(String input) async {
    final trimmedInput = input.trim();
    if (trimmedInput.isEmpty) {
      return CommandResult(output: '');
    }

    final parts = _parseArgs(trimmedInput);
    if (parts.isEmpty) {
      return CommandResult(output: '');
    }

    final command = parts[0].toLowerCase();
    final args = parts.sublist(1);

    switch (command) {
      case 'help':
        return CommandResult(
          output:
              'Termode runs in a true native REAL PTY shell by default.\n'
              'Most commands are executed directly in the Unix environment.\n'
              'Management commands like "pkg" are intercepted and run in the host app.\n\n'
              'Useful Prompt Commands:\n'
              '  normal-mode - Exit PTY interaction mode to return to classic Termode prompt\n'
              '  stop-shell  - Kill the PTY shell process and return to NORMAL mode\n'
              '  host-help   - Show list of intercepted app management commands\n'
              '  whereami    - View active sandbox directories\n\n'
              'Termode VFS Commands:\n'
              '  help        - Show VFS help\n'
              '  clear       - Clear screen\n'
              '  echo [text] - Print arguments\n'
              '  pwd         - Print VFS working directory\n'
              '  whoami      - Print active user\n'
              '  date        - Print current date/time\n'
              '  ls [path]   - List VFS directory\n'
              '  cd [path]   - Change VFS directory\n'
              '  mkdir [dir] - Create VFS directory\n'
              '  touch [fl]  - Create VFS file\n'
              '  cat [file]  - Display VFS file\n'
              '  rm [path]   - Remove VFS file/dir\n'
              '  cp [s] [d]  - Copy VFS file/dir\n'
              '  mv [s] [d]  - Move VFS file/dir\n'
              '  run-tool [t]- Execute a runtime tool script\n'
              '  pkg [cmd]   - Manage Termode packages',
        );
      case 'clear':
        return CommandResult(output: '', shouldClear: true);
      case 'echo':
        return CommandResult(output: args.join(' '));
      case 'pwd':
        return CommandResult(output: vfs.getAbsolutePath());
      case 'whoami':
        return CommandResult(output: 'user');
      case 'date':
        return CommandResult(output: DateTime.now().toString());

      case 'ls':
        final path = args.isNotEmpty ? args[0] : '';
        final result = vfs.ls(path);
        final isError = result.startsWith('ls:');
        return CommandResult(output: result, isError: isError);

      case 'cd':
        final path = args.isNotEmpty ? args[0] : '';
        final error = vfs.cd(path);
        return CommandResult(output: error ?? '', isError: error != null);

      case 'mkdir':
        if (args.isEmpty) {
          return CommandResult(output: 'mkdir: missing operand', isError: true);
        }
        final error = vfs.mkdir(args[0]);
        return CommandResult(output: error ?? '', isError: error != null);

      case 'touch':
        if (args.isEmpty) {
          return CommandResult(
            output: 'touch: missing file operand',
            isError: true,
          );
        }
        final path = args[0];
        final content = args.length > 1 ? args[1] : '';
        final error = vfs.touch(path, content);
        return CommandResult(output: error ?? '', isError: error != null);

      case 'cat':
        if (args.isEmpty) {
          return CommandResult(
            output: 'cat: missing file operand',
            isError: true,
          );
        }
        final result = vfs.cat(args[0]);
        final isError = result.startsWith('cat:');
        return CommandResult(output: result, isError: isError);

      case 'rm':
        if (args.isEmpty) {
          return CommandResult(output: 'rm: missing operand', isError: true);
        }
        bool recursive = false;
        String path = '';
        if (args[0] == '-r') {
          recursive = true;
          if (args.length < 2) {
            return CommandResult(output: 'rm: missing operand', isError: true);
          }
          path = args[1];
        } else {
          path = args[0];
        }
        final error = vfs.rm(path, recursive: recursive);
        return CommandResult(output: error ?? '', isError: error != null);

      case 'cp':
        if (args.isEmpty) {
          return CommandResult(
            output: 'cp: missing file operand',
            isError: true,
          );
        }
        bool recursive = false;
        String src = '';
        String dest = '';
        int argIdx = 0;

        if (args[0] == '-r') {
          recursive = true;
          argIdx = 1;
        }

        if (args.length < argIdx + 2) {
          return CommandResult(
            output:
                'cp: missing destination file operand after \'${args[args.length - 1]}\'',
            isError: true,
          );
        }
        src = args[argIdx];
        dest = args[argIdx + 1];

        final error = vfs.cp(src, dest, recursive: recursive);
        return CommandResult(output: error ?? '', isError: error != null);

      case 'mv':
        if (args.length < 2) {
          return CommandResult(
            output: args.isEmpty
                ? 'mv: missing file operand'
                : 'mv: missing destination file operand after \'${args[0]}\'',
            isError: true,
          );
        }
        final error = vfs.mv(args[0], args[1]);
        return CommandResult(output: error ?? '', isError: error != null);

      case 'android-shell':
        if (args.isEmpty) {
          return CommandResult(
            output:
                'android-shell: missing command operand\nUsage: android-shell <command>',
            isError: true,
          );
        }
        final cmdStr = args.join(' ');
        final nativeService = NativeCommandService();
        final nativeResult = await nativeService.execute(cmdStr, sessionId);

        String exitMsg = '';
        if (nativeResult.exitCode == 127) {
          exitMsg = 'android-shell: command not found';
        } else if (nativeResult.exitCode == 126) {
          exitMsg = 'android-shell: permission denied';
        } else if (nativeResult.exitCode != 0) {
          exitMsg =
              'Process exited with non-zero code ${nativeResult.exitCode}';
        }

        final outputBuilder = StringBuffer();
        if (nativeResult.stdout.isNotEmpty) {
          outputBuilder.write(nativeResult.stdout);
        }
        if (nativeResult.stderr.isNotEmpty) {
          if (outputBuilder.isNotEmpty) outputBuilder.write('\n');
          outputBuilder.write(nativeResult.stderr);
        }

        if (outputBuilder.isEmpty) {
          if (exitMsg.isNotEmpty) {
            outputBuilder.write(exitMsg);
          } else {
            outputBuilder.write(
              'Process exited with code ${nativeResult.exitCode}',
            );
          }
        } else {
          if (exitMsg.isNotEmpty) {
            outputBuilder.write('\n[$exitMsg]');
          }
        }

        return CommandResult(
          output: outputBuilder.toString(),
          isError: nativeResult.exitCode != 0,
        );

      case 'android-shell-diagnostics':
        final nativeService = NativeCommandService();
        final diag = await nativeService.getDiagnostics();
        if (diag == null) {
          return CommandResult(
            output:
                'android-shell-diagnostics: failed to retrieve native diagnostics.',
            isError: true,
          );
        }

        final userDir = diag['userDir'] as String? ?? 'Unknown';
        final pathEnv = diag['pathEnv'] as String? ?? 'Unknown';
        final uid = diag['uid'] as int? ?? -1;
        final testOutput = diag['testOutput'] as String? ?? 'Unknown';
        final fileChecks = diag['fileChecks'] as List<dynamic>? ?? [];
        final runtimeHome = diag['runtimeHome'] as String? ?? 'Unknown';
        final runtimePath = diag['runtimePath'] as String? ?? 'Unknown';

        final sb = StringBuffer();
        sb.writeln('=== Termode Native Diagnostics ===');
        sb.writeln('CWD: $userDir');
        sb.writeln('UID: $uid');
        sb.writeln('Runtime Home: $runtimeHome');
        sb.writeln('Runtime PATH: $runtimePath');
        sb.writeln('PATH env:');
        for (final p in pathEnv.split(':')) {
          if (p.trim().isNotEmpty) {
            sb.writeln('  - $p');
          }
        }
        sb.writeln('File checks (Exists / Read / Exec):');
        for (final check in fileChecks) {
          final map = Map<String, dynamic>.from(check as Map);
          final path = map['path'] as String;
          final exists = map['exists'] as bool? ?? false;
          final canRead = map['canRead'] as bool? ?? false;
          final canExecute = map['canExecute'] as bool? ?? false;

          final status = exists
              ? '[OK] r:${canRead ? "y" : "n"} x:${canExecute ? "y" : "n"}'
              : '[NOT FOUND]';
          sb.writeln('  - $path: $status');
        }
        sb.writeln('Test run (sh -c "echo shell-ok"): $testOutput');

        return CommandResult(output: sb.toString().trimRight());

      case 'android-shell-env':
        final nativeService = NativeCommandService();
        final env = await nativeService.getEnv();
        if (env == null) {
          return CommandResult(
            output: 'android-shell-env: failed to retrieve native environment.',
            isError: true,
          );
        }

        final sb = StringBuffer();
        sb.writeln('=== Effective Native Runtime Environment ===');
        sb.writeln('HOME:              ${env['HOME']}');
        sb.writeln('TERMODE_HOME:      ${env['TERMODE_HOME']}');
        sb.writeln('TERMODE_USR:       ${env['TERMODE_USR']}');
        sb.writeln('TERMODE_BIN:       ${env['TERMODE_BIN']}');
        sb.writeln('TMPDIR:            ${env['TMPDIR']}');
        sb.writeln('PATH:              ${env['PATH']}');
        sb.write('Working Directory: ${env['workingDirectory']}');
        return CommandResult(output: sb.toString());

      case 'termode-runtime':
        if (args.isEmpty) {
          return CommandResult(
            output:
                'termode-runtime: missing subcommand operand\nUsage: termode-runtime [status|path|reset]',
            isError: true,
          );
        }
        final subcmd = args[0].toLowerCase();
        final runtimeService = RuntimeBootstrapService();

        if (subcmd == 'status') {
          final status = await runtimeService.checkStatus();
          final sb = StringBuffer();
          sb.writeln('=== Termode Runtime Directory Status ===');
          var allOk = true;
          status.forEach((path, exists) {
            sb.writeln('  - $path: ${exists ? "[EXISTS]" : "[MISSING]"}');
            if (!exists) allOk = false;
          });
          sb.write('Overall status: ${allOk ? "HEALTHY" : "UNHEALTHY"}');
          return CommandResult(output: sb.toString(), isError: !allOk);
        } else if (subcmd == 'path') {
          final paths = await runtimeService.getPaths();
          final sb = StringBuffer();
          sb.writeln('=== Termode Runtime Paths ===');
          sb.writeln('Home:   ${paths['home']}');
          sb.writeln('Usr:    ${paths['usr']}');
          sb.writeln('Bin:    ${paths['bin']}');
          sb.writeln('UsrTmp: ${paths['usrTmp']}');
          sb.write('Tmp:    ${paths['tmp']}');
          return CommandResult(output: sb.toString());
        } else if (subcmd == 'reset') {
          await runtimeService.reset();
          return CommandResult(
            output: 'Runtime environment reset successfully.',
          );
        } else {
          return CommandResult(
            output:
                'termode-runtime: unknown subcommand: $subcmd\nUsage: termode-runtime [status|path|reset]',
            isError: true,
          );
        }

      case 'toybox':
        final nativeService = NativeCommandService();
        final cmdStr =
            '/system/bin/toybox${args.isNotEmpty ? " ${args.join(' ')}" : ""}';
        final result = await nativeService.execute(cmdStr, sessionId);

        final outputBuilder = StringBuffer();
        if (result.stdout.isNotEmpty) {
          outputBuilder.write(result.stdout);
        }
        if (result.stderr.isNotEmpty) {
          if (outputBuilder.isNotEmpty) outputBuilder.write('\n');
          outputBuilder.write(result.stderr);
        }
        if (outputBuilder.isEmpty && result.exitCode != 0) {
          outputBuilder.write(
            'Process exited with non-zero code ${result.exitCode}',
          );
        }
        return CommandResult(
          output: outputBuilder.toString().trimRight(),
          isError: result.exitCode != 0,
        );

      case 'toybox-list':
        final nativeService = NativeCommandService();
        final result = await nativeService.execute(
          '/system/bin/toybox',
          sessionId,
        );

        final outputBuilder = StringBuffer();
        if (result.stdout.isNotEmpty) {
          outputBuilder.write(result.stdout);
        }
        if (result.stderr.isNotEmpty) {
          if (outputBuilder.isNotEmpty) outputBuilder.write('\n');
          outputBuilder.write(result.stderr);
        }
        return CommandResult(
          output: outputBuilder.toString().trimRight(),
          isError: result.exitCode != 0,
        );

      case 'runtime-ls':
        final runtimeService = RuntimeBootstrapService();
        final paths = await runtimeService.getPaths();
        final homePath = paths['home']!;
        final dir = Directory(homePath);
        if (!await dir.exists()) {
          return CommandResult(
            output: 'runtime-ls: home directory not found',
            isError: true,
          );
        }
        try {
          final List<String> fileNames = [];
          await for (final entity in dir.list()) {
            final name = entity.path.replaceAll('\\', '/').split('/').last;
            fileNames.add(name);
          }
          if (fileNames.isEmpty) {
            return CommandResult(output: '(empty directory)');
          }
          return CommandResult(output: fileNames.join('\n'));
        } catch (e) {
          return CommandResult(
            output: 'runtime-ls: error listing directory: $e',
            isError: true,
          );
        }

      case 'runtime-pwd':
        final runtimeService = RuntimeBootstrapService();
        final paths = await runtimeService.getPaths();
        return CommandResult(output: paths['home']!);

      case 'runtime-cat':
        if (args.isEmpty) {
          return CommandResult(
            output: 'runtime-cat: missing file operand',
            isError: true,
          );
        }
        final runtimeService = RuntimeBootstrapService();
        final paths = await runtimeService.getPaths();
        final homePath = paths['home']!;
        final file = _resolveFileInHome(args[0], homePath);
        if (file == null) {
          return CommandResult(
            output: 'runtime-cat: path traversal detected or invalid path',
            isError: true,
          );
        }
        if (!await file.exists()) {
          return CommandResult(
            output: 'runtime-cat: ${args[0]}: No such file or directory',
            isError: true,
          );
        }
        try {
          final content = await file.readAsString();
          return CommandResult(output: content);
        } on FileSystemException {
          return CommandResult(
            output: 'runtime-cat: ${args[0]}: Permission denied or read error',
            isError: true,
          );
        } catch (e) {
          return CommandResult(
            output: 'runtime-cat: ${args[0]}: Error: $e',
            isError: true,
          );
        }

      case 'runtime-write':
        if (args.isEmpty) {
          return CommandResult(
            output: 'runtime-write: missing file operand',
            isError: true,
          );
        }
        if (args.length < 2) {
          return CommandResult(
            output: 'runtime-write: missing text operand',
            isError: true,
          );
        }
        final filename = args[0];
        final text = args.sublist(1).join(' ');

        final runtimeService = RuntimeBootstrapService();
        final paths = await runtimeService.getPaths();
        final homePath = paths['home']!;
        final file = _resolveFileInHome(filename, homePath);
        if (file == null) {
          return CommandResult(
            output: 'runtime-write: path traversal detected or invalid path',
            isError: true,
          );
        }

        try {
          await file.writeAsString(text);
          return CommandResult(
            output: 'Wrote ${text.length} characters to $filename.',
          );
        } on FileSystemException {
          return CommandResult(
            output:
                'runtime-write: $filename: Permission denied or write error',
            isError: true,
          );
        } catch (e) {
          return CommandResult(
            output: 'runtime-write: $filename: Error: $e',
            isError: true,
          );
        }

      case 'whereami':
        final runtimeService = RuntimeBootstrapService();
        final paths = await runtimeService.getPaths();
        final statusMap = await runtimeService.checkStatus();
        final isHealthy = statusMap.values.every((val) => val == true);

        final storageService = StorageAccessService();
        String storageStatusStr;
        try {
          final storageStatus = await storageService.getStatus();
          if (storageStatus != null) {
            final uri = storageStatus['uri'];
            final name = storageStatus['displayName'];
            final namePart = name != null ? ' (Name: $name)' : '';
            storageStatusStr = 'LINKED$namePart\n  Uri: $uri';
          } else {
            storageStatusStr = 'NOT LINKED';
          }
        } on PlatformException catch (e) {
          storageStatusStr = 'ERROR (${_formatStorageError(e)})';
        }

        final sb = StringBuffer();
        sb.writeln('=== Active Working Environments ===');
        sb.writeln('Dart Virtual Filesystem (VFS):');
        sb.writeln('  CWD: ${vfs.getAbsolutePath()}');
        sb.writeln('Native Sandbox Runtime:');
        sb.writeln('  Home: ${paths['home']}');
        sb.writeln('  Bin:  ${paths['bin']}');
        sb.writeln('  Tmp:  ${paths['tmp']}');
        sb.writeln(
          '  State: ${isHealthy ? "HEALTHY" : "UNHEALTHY (corrupted folders)"}',
        );
        sb.writeln('User-Linked Android Storage:');
        sb.writeln('  Status: $storageStatusStr');
        sb.write(
          'NOTE: Dart VFS, native runtime, and user-linked Android storage are currently separate.',
        );
        return CommandResult(output: sb.toString());

      case 'runtime-help':
        return CommandResult(
          output:
              'WARNING: Native sandbox commands operate directly on physical storage.\n\n'
              'Native Sandbox Commands:\n'
              '  android-shell [cmd]    - Run native shell command\n'
              '  android-shell-env      - Print environment config\n'
              '  android-shell-diag     - Run hardware diagnostics\n'
              '  termode-runtime status - Check runtime directory health\n'
              '  termode-runtime path   - Show native absolute paths\n'
              '  termode-runtime reset  - Wipe and rebuild sandbox layout\n'
              '  runtime-tools [cmd]    - Manage Termode runtime tools\n'
              '  run-tool [t] [args...] - Run a sandboxed tool script\n'
              '  pkg [cmd] [args...]    - Manage Termode script packages\n'
              '  toybox [args...]       - Run Toybox system command\n'
              '  toybox-list            - List all Toybox system utilities\n'
              '  runtime-pwd            - Print sandbox home directory\n'
              '  runtime-ls             - List sandbox home contents\n'
              '  runtime-cat [file]     - Read sandbox home file\n'
              '  runtime-write [fl] [t] - Write text to sandbox file\n\n'
              'Packages Guidance:\n'
              '  - Use "pkg list" to see available packages.\n'
              '  - Packages are installed to files/usr/bin and sourced via shell helpers.',
        );

      case 'storage-link':
        final storageService = StorageAccessService();
        try {
          final result = await storageService.linkFolder();
          if (result != null) {
            return CommandResult(output: 'Folder linked successfully: $result');
          } else {
            return CommandResult(
              output: 'Failed to link folder or linking cancelled.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-status':
        final storageService = StorageAccessService();
        try {
          final status = await storageService.getStatus();
          if (status != null) {
            final uri = status['uri'];
            final name = status['displayName'];
            final namePart = name != null ? ' (Name: $name)' : '';
            return CommandResult(
              output: 'Linked storage folder: $uri$namePart',
            );
          } else {
            return CommandResult(output: 'No folder is currently linked.');
          }
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-unlink':
        final storageService = StorageAccessService();
        try {
          await storageService.unlink();
          return CommandResult(output: 'Storage link removed successfully.');
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-list':
        final storageService = StorageAccessService();
        try {
          final files = await storageService.listFiles();
          if (files == null) {
            return CommandResult(
              output: 'storage-list: No linked storage or failed to query.',
              isError: true,
            );
          }
          if (files.isEmpty) {
            return CommandResult(output: '(empty directory)');
          }
          return CommandResult(output: files.join('\n'));
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-read':
        if (args.isEmpty) {
          return CommandResult(
            output: 'storage-read: missing file operand',
            isError: true,
          );
        }
        final filename = args.join(' ');
        final storageService = StorageAccessService();
        try {
          final content = await storageService.readFile(filename);
          if (content != null) {
            return CommandResult(output: content);
          } else {
            return CommandResult(
              output: 'storage-read: Failed to read file or file empty.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-write':
        if (args.isEmpty) {
          return CommandResult(
            output: 'storage-write: missing file operand',
            isError: true,
          );
        }
        if (args.length < 2) {
          return CommandResult(
            output: 'storage-write: missing text operand',
            isError: true,
          );
        }
        final filename = args[0];
        final text = args.sublist(1).join(' ');

        final storageService = StorageAccessService();
        try {
          final success = await storageService.writeFile(filename, text);
          if (success) {
            return CommandResult(
              output:
                  'Wrote ${text.length} characters to $filename inside linked folder.',
            );
          } else {
            return CommandResult(
              output: 'storage-write: Failed to write to file.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-delete':
        if (args.isEmpty) {
          return CommandResult(
            output: 'storage-delete: missing file operand',
            isError: true,
          );
        }
        final filename = args.join(' ');
        final storageService = StorageAccessService();
        try {
          final canDelete = await storageService.supportsDelete(filename);
          if (!canDelete) {
            return CommandResult(
              output:
                  'Error: Deletion not supported by provider for file "$filename".',
              isError: true,
            );
          }
          final success = await storageService.deleteFile(filename);
          if (success) {
            return CommandResult(
              output: 'Deleted file "$filename" from linked storage.',
            );
          } else {
            return CommandResult(
              output: 'Error: Failed to delete file "$filename".',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-mkdir':
        if (args.isEmpty) {
          return CommandResult(
            output: 'storage-mkdir: missing directory operand',
            isError: true,
          );
        }
        final folderName = args.join(' ');
        final storageService = StorageAccessService();
        try {
          final success = await storageService.createDirectory(folderName);
          if (success) {
            return CommandResult(
              output: 'Created directory "$folderName" inside linked storage.',
            );
          } else {
            return CommandResult(
              output: 'Error: Failed to create directory "$folderName".',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-test':
        final storageService = StorageAccessService();
        final sb = StringBuffer();
        sb.writeln('=== Starting Storage Integration Test ===');

        sb.write('1. Checking storage status... ');
        Map<String, String>? status;
        try {
          status = await storageService.getStatus();
        } on PlatformException catch (e) {
          sb.writeln('FAIL (${_formatStorageError(e)})');
          sb.writeln('=== Storage Integration Test Failed ===');
          sb.write('Result: FAIL');
          return CommandResult(output: sb.toString(), isError: true);
        }

        if (status == null || status['uri'] == null) {
          sb.writeln('FAIL (No folder is currently linked)');
          sb.writeln('=== Storage Integration Test Failed ===');
          sb.write('Result: FAIL');
          return CommandResult(output: sb.toString(), isError: true);
        }
        final folderDisplayName = status['displayName'] ?? status['uri']!;
        sb.writeln('PASS (Linked: $folderDisplayName)');

        final testFilename = 'termode_test_temp.txt';
        final testContent = 'Termode storage test content - ${DateTime.now()}';
        sb.write('2. Writing temporary test file ($testFilename)... ');
        try {
          final success = await storageService.writeFile(
            testFilename,
            testContent,
          );
          if (!success) {
            sb.writeln('FAIL (writeFile returned false)');
            sb.writeln('=== Storage Integration Test Failed ===');
            sb.write('Result: FAIL');
            return CommandResult(output: sb.toString(), isError: true);
          }
        } on PlatformException catch (e) {
          sb.writeln('FAIL (${_formatStorageError(e)})');
          sb.writeln('=== Storage Integration Test Failed ===');
          sb.write('Result: FAIL');
          return CommandResult(output: sb.toString(), isError: true);
        }
        sb.writeln('PASS');

        sb.write('3. Reading test file back... ');
        try {
          final readContent = await storageService.readFile(testFilename);
          if (readContent != testContent) {
            sb.writeln('FAIL (Content mismatch)');
            sb.writeln('=== Storage Integration Test Failed ===');
            sb.write('Result: FAIL');
            return CommandResult(output: sb.toString(), isError: true);
          }
        } on PlatformException catch (e) {
          sb.writeln('FAIL (${_formatStorageError(e)})');
          sb.writeln('=== Storage Integration Test Failed ===');
          sb.write('Result: FAIL');
          return CommandResult(output: sb.toString(), isError: true);
        }
        sb.writeln('PASS');

        sb.write('4. Checking deletion support... ');
        bool canDelete = false;
        try {
          canDelete = await storageService.supportsDelete(testFilename);
        } on PlatformException catch (e) {
          sb.writeln('FAIL (${_formatStorageError(e)})');
          sb.writeln('=== Storage Integration Test Failed ===');
          sb.write('Result: FAIL');
          return CommandResult(output: sb.toString(), isError: true);
        }

        if (canDelete) {
          sb.writeln('YES');
          sb.write('5. Deleting temporary test file... ');
          try {
            final success = await storageService.deleteFile(testFilename);
            if (!success) {
              sb.writeln('FAIL (deleteFile returned false)');
              sb.writeln('=== Storage Integration Test Failed ===');
              sb.write('Result: FAIL');
              return CommandResult(output: sb.toString(), isError: true);
            }
            sb.writeln('PASS');
          } on PlatformException catch (e) {
            sb.writeln('FAIL (${_formatStorageError(e)})');
            sb.writeln('=== Storage Integration Test Failed ===');
            sb.write('Result: FAIL');
            return CommandResult(output: sb.toString(), isError: true);
          }
        } else {
          sb.writeln('NO (Skipping delete test step)');
        }

        sb.writeln('=== Storage Integration Test Complete ===');
        sb.write('Result: PASS');
        return CommandResult(output: sb.toString());

      case 'storage-help':
        return CommandResult(
          output:
              '=== Termode User-Approved Storage Help ===\n\n'
              'Android security limits direct storage access. Termode uses the Android Storage Access Framework (SAF) to let you approve access to a specific folder.\n\n'
              'Commands:\n'
              '  storage-link       - Open picker to link an Android folder\n'
              '  storage-status     - Show whether a folder is currently linked\n'
              '  storage-unlink     - Unlink the folder (access revoked)\n'
              '  storage-list       - List files in the linked folder\n'
              '  storage-read [f]   - Read text file from the linked folder\n'
              '  storage-write [f] [t] - Write text file into the linked folder\n'
              '  storage-mkdir [d]  - Create a subdirectory in the linked folder\n'
              '  storage-delete [f] - Delete a file/directory from the linked folder\n'
              '  storage-test       - Run storage integration diagnostics test\n\n'
              'Limitations:\n'
              '  - You must select a folder. Android blocks access to root storage and some system folders.\n'
              '  - Termode only supports reading/writing plain text files here.\n'
              '  - Linked storage is separate from Dart VFS and native runtime.',
        );

      case 'shell-start':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? started = await channel.invokeMethod('ptyStart', {
            'sessionId': sessionId,
          });
          if (started == true) {
            TerminalSessionService().setShellActive(sessionId, true);
            return CommandResult(
              output:
                  'WARNING: Experimental Shell Mode is highly experimental and may behave unpredictably.\n'
                  'This is currently an interactive process bridge, not a full native PTY.\n'
                  'Use "shell-send <text>" to interact with the shell.\n'
                  'Shell process started successfully.',
            );
          } else {
            return CommandResult(
              output: 'Shell session is already running.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(
            output: 'Error starting shell: ${e.message}',
            isError: true,
          );
        }

      case 'shell-status':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final Map<dynamic, dynamic>? status = await channel.invokeMethod(
            'ptyStatus',
            {'sessionId': sessionId},
          );
          if (status != null && status['running'] == true) {
            final pid = status['pid'];
            return CommandResult(output: 'Shell Status: RUNNING (PID: $pid)');
          } else {
            return CommandResult(output: 'Shell Status: NOT RUNNING');
          }
        } on PlatformException catch (e) {
          return CommandResult(
            output: 'Error querying shell status: ${e.message}',
            isError: true,
          );
        }

      case 'shell-stop':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? stopped = await channel.invokeMethod('ptyStop', {
            'sessionId': sessionId,
          });
          if (stopped == true) {
            TerminalSessionService().setShellActive(sessionId, false);
            return CommandResult(output: 'Shell process stopped.');
          } else {
            return CommandResult(
              output: 'No active shell process to stop.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(
            output: 'Error stopping shell: ${e.message}',
            isError: true,
          );
        }

      case 'shell-send':
        if (args.isEmpty) {
          return CommandResult(
            output:
                'shell-send: missing command/text operand\nUsage: shell-send <text>',
            isError: true,
          );
        }
        final text = args.join(' ');
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex != -1) {
          sessionService.sessions[sessionIndex].lastSentPtyInput = text;
        }
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? success = await channel.invokeMethod('ptySend', {
            'sessionId': sessionId,
            'text': text,
          });
          if (success == true) {
            return CommandResult(
              output: '',
            ); // output will be streamed asynchronously!
          } else {
            return CommandResult(
              output: 'Error: Failed to send input to shell.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'NOT_RUNNING') {
            return CommandResult(
              output:
                  'Error: No active shell process. Start one with shell-start.',
              isError: true,
            );
          }
          return CommandResult(
            output: 'Error sending to shell: ${e.message}',
            isError: true,
          );
        }

      case 'shell-send-ctrl-c':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? success = await channel.invokeMethod('ptySendCtrlC', {
            'sessionId': sessionId,
          });
          if (success == true) {
            return CommandResult(
              output: 'Sent Ctrl-C (SIGINT) to shell process.',
            );
          } else {
            return CommandResult(
              output: 'Failed to send Ctrl-C.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'NOT_RUNNING') {
            return CommandResult(
              output: 'Error: No active shell process.',
              isError: true,
            );
          }
          return CommandResult(
            output: 'Error sending Ctrl-C: ${e.message}',
            isError: true,
          );
        }

      case 'shell-send-ctrl-d':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? success = await channel.invokeMethod('ptySendCtrlD', {
            'sessionId': sessionId,
          });
          if (success == true) {
            return CommandResult(output: 'Sent Ctrl-D (EOF) to shell process.');
          } else {
            return CommandResult(
              output: 'Failed to send Ctrl-D.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'NOT_RUNNING') {
            return CommandResult(
              output: 'Error: No active shell process.',
              isError: true,
            );
          }
          return CommandResult(
            output: 'Error sending Ctrl-D: ${e.message}',
            isError: true,
          );
        }

      case 'shell-help':
        return CommandResult(
          output:
              '=== Termode Experimental Shell Mode Help ===\n\n'
              'This mode runs an interactive shell (/system/bin/sh) inside the Termode sandbox.\n\n'
              'Note: This is currently an interactive process bridge and NOT a full native pseudo-terminal (PTY).\n'
              '- Simple shell commands (e.g. ls, echo, pwd) will work.\n'
              '- Fullscreen terminal programs (e.g. vim, top, nano, ssh) that expect raw PTY tty controls may not display or work correctly.\n\n'
              'Commands:\n'
              '  shell-start         - Start the interactive shell process\n'
              '  shell-status        - View if shell is running and print its PID\n'
              '  shell-send [text]   - Send text input to the shell process standard input\n'
              '  shell-send-ctrl-c   - Send Ctrl-C (SIGINT) to the process\n'
              '  shell-send-ctrl-d   - Send Ctrl-D (EOF) to the process\n'
              '  shell-stop          - Terminate the running shell process',
        );

      case 'real-pty-start':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? started = await channel.invokeMethod('realPtyStart', {
            'sessionId': sessionId,
          });
          if (started == true) {
            TerminalSessionService().setRealPtyActive(sessionId, true);
            return CommandResult(
              output:
                  'Warning: Experimental PTY prototype. Real PTY started.\n'
                  'Use enter-pty-mode or termode-shell to interact.',
            );
          } else {
            return CommandResult(
              output: 'Real PTY session is already running.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'LIMIT_EXCEEDED') {
            return CommandResult(output: 'Error: ${e.message}', isError: true);
          }
          return CommandResult(
            output: 'Error starting real PTY: ${e.message}',
            isError: true,
          );
        }

      case 'real-pty-status':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final Map<dynamic, dynamic>? status = await channel.invokeMethod(
            'realPtyStatus',
            {'sessionId': sessionId},
          );
          if (status != null && status['running'] == true) {
            final pid = status['pid'];
            return CommandResult(
              output: 'Real PTY Status: RUNNING (PID: $pid)',
            );
          } else {
            return CommandResult(output: 'Real PTY Status: NOT RUNNING');
          }
        } on PlatformException catch (e) {
          return CommandResult(
            output: 'Error querying real PTY status: ${e.message}',
            isError: true,
          );
        }

      case 'real-pty-send':
        if (args.isEmpty) {
          return CommandResult(
            output:
                'real-pty-send: missing command/text operand\nUsage: real-pty-send <text>',
            isError: true,
          );
        }
        final text = args.join(' ');
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex != -1) {
          sessionService.sessions[sessionIndex].lastSentRealPtyInput = text;
        }
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? success = await channel.invokeMethod('realPtySend', {
            'sessionId': sessionId,
            'text': text,
          });
          if (success == true) {
            return CommandResult(
              output: '',
            ); // output will be streamed asynchronously!
          } else {
            return CommandResult(
              output: 'Error: Failed to send input to real PTY.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'NOT_RUNNING') {
            return CommandResult(
              output:
                  'Error: No active real PTY process. Start one with real-pty-start.',
              isError: true,
            );
          }
          return CommandResult(
            output: 'Error sending to real PTY: ${e.message}',
            isError: true,
          );
        }

      case 'real-pty-stop':
        final sessionService = TerminalSessionService();
        sessionService.setRealPtyActive(sessionId, false);
        sessionService.setPtyInteractionActive(sessionId, false);
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? stopped = await channel.invokeMethod('realPtyStop', {
            'sessionId': sessionId,
          });
          if (stopped == true) {
            return CommandResult(
              output: 'Real PTY process stopped. Returned to NORMAL mode.',
            );
          } else {
            return CommandResult(
              output: 'Error: No active real PTY process to stop.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(
            output:
                'Error: Failed to stop real PTY: ${e.message}. Cleaned up local session state.',
            isError: true,
          );
        }

      case 'real-pty-send-ctrl-c':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? success = await channel.invokeMethod('realPtySendCtrlC', {
            'sessionId': sessionId,
          });
          if (success == true) {
            return CommandResult(
              output: 'Sent Ctrl-C (SIGINT) to real PTY process.',
            );
          } else {
            return CommandResult(
              output: 'Failed to send Ctrl-C.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'NOT_RUNNING') {
            return CommandResult(
              output: 'Error: No active real PTY process.',
              isError: true,
            );
          }
          return CommandResult(
            output: 'Error sending Ctrl-C to real PTY: ${e.message}',
            isError: true,
          );
        }

      case 'real-pty-send-ctrl-d':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? success = await channel.invokeMethod('realPtySendCtrlD', {
            'sessionId': sessionId,
          });
          if (success == true) {
            return CommandResult(
              output: 'Sent Ctrl-D (EOF) to real PTY process.',
            );
          } else {
            return CommandResult(
              output: 'Failed to send Ctrl-D.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'NOT_RUNNING') {
            return CommandResult(
              output: 'Error: No active real PTY process.',
              isError: true,
            );
          }
          return CommandResult(
            output: 'Error sending Ctrl-D to real PTY: ${e.message}',
            isError: true,
          );
        }

      case 'real-pty-resize':
        if (args.length < 2) {
          return CommandResult(
            output:
                'real-pty-resize: missing columns/rows operand\nUsage: real-pty-resize <cols> <rows>',
            isError: true,
          );
        }
        final cols = int.tryParse(args[0]);
        final rows = int.tryParse(args[1]);
        if (cols == null || rows == null || cols <= 0 || rows <= 0) {
          return CommandResult(
            output: 'Error: cols and rows must be positive integers.',
            isError: true,
          );
        }
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? success = await channel.invokeMethod('realPtyResize', {
            'sessionId': sessionId,
            'cols': cols,
            'rows': rows,
          });
          if (success == true) {
            try {
              final sessionService = TerminalSessionService();
              final session = sessionService.sessions.firstWhere(
                (s) => s.id == sessionId,
              );
              session.ansiBuffer.resize(cols, rows);
            } catch (_) {
              // Ignore if session not found or fails
            }
            return CommandResult(
              output: 'Resized real PTY to $cols cols x $rows rows.',
            );
          } else {
            return CommandResult(
              output: 'Error: Failed to resize real PTY.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'NOT_RUNNING') {
            return CommandResult(
              output: 'Error: No active real PTY process.',
              isError: true,
            );
          }
          return CommandResult(
            output: 'Error resizing real PTY: ${e.message}',
            isError: true,
          );
        }

      case 'real-pty-help':
        return CommandResult(
          output:
              '=== Termode Native PTY Prototype Help ===\n\n'
              'Termode runs in a native pseudo-terminal (PTY) attached to /system/bin/sh by default.\n'
              'This provides a command-line environment similar to Termux.\n\n'
              'Commands:\n'
              '  default-shell          - Start real PTY and enter interaction mode (Primary Shell Command)\n'
              '  normal-mode            - Exit PTY interaction mode, keeping it running in background\n'
              '  termode-shell          - Start real PTY and enter interaction mode automatically (Alias)\n'
              '  stop-shell             - Stop real PTY and exit interaction mode\n'
              '  shell-doctor           - Run diagnostics to verify state and troubleshoot shells\n'
              '  runtime-tools          - Manage Termode bundled runtime tools (status, install, reset)\n'
              '  pkg                    - Manage Termode script packages (list, install, remove, doctor)\n'
              '  host-help              - List all intercepted management commands\n'
              '  mode                   - Query active shell mode and interception state\n'
              '  enter-pty-mode         - Enter Real PTY Interaction Mode\n'
              '  exit-pty-mode          - Exit Real PTY Interaction Mode\n'
              '  real-pty-start         - Allocate and spawn a true native PTY shell\n'
              '  real-pty-stop          - Tear down terminal tty slave and close PTY\n'
              '  real-pty-status        - Show if real PTY is running and print its PID\n'
              '  real-pty-resize [c] [r] - Resize the virtual tty dimensions\n'
              '  real-pty-send-ctrl-c   - Send Ctrl-C (SIGINT) to the process\n'
              '  real-pty-send-ctrl-d   - Send Ctrl-D (EOF) to the process\n'
              '  real-pty-send [text]   - Write text to PTY master file descriptor\n'
              '  real-pty-mode-status   - Query PTY mode status\n'
              '  keyboard-help          - Show keyboard & shortcut helper\n\n'
              'Packages Notice:\n'
              '  - Packages installed via "pkg install" will automatically register shell helper functions\n'
              '    which can be invoked directly inside default-shell.\n'
              '  - "pkg" commands can be typed directly inside REAL PTY mode and are intercepted by the app.',
        );

      case 'enter-pty-mode':
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];
        if (!session.isRealPtyActive) {
          return CommandResult(
            output: 'Start real PTY first using real-pty-start.',
            isError: true,
          );
        }
        sessionService.setPtyInteractionActive(sessionId, true);
        return CommandResult(
          output:
              'Entered Real PTY Interaction Mode. All inputs are now routed to PTY.\n',
        );

      case 'exit-pty-mode':
        final sessionService = TerminalSessionService();
        sessionService.setPtyInteractionActive(sessionId, false);
        return CommandResult(
          output: 'Exited Real PTY Interaction Mode. Normal routing active.\n',
        );

      case 'default-shell':
      case 'termode-shell':
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];

        if (!session.isRealPtyActive) {
          final success = await sessionService.startRealPty(sessionId);
          if (success) {
            return CommandResult(
              output:
                  'Started Termode shell. Type normal-mode to return to commands.\n',
            );
          } else {
            sessionService.setRealPtyActive(sessionId, false);
            sessionService.setPtyInteractionActive(sessionId, false);
            return CommandResult(
              output:
                  'Error: Failed to start real PTY shell. Make sure native binary can execute.',
              isError: true,
            );
          }
        } else {
          if (!session.isPtyInteractionActive) {
            sessionService.setPtyInteractionActive(sessionId, true);
            return CommandResult(
              output: 'Entered Real PTY Interaction Mode.\n',
            );
          } else {
            return CommandResult(output: 'Already in real shell.');
          }
        }

      case 'normal-mode':
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];
        sessionService.setPtyInteractionActive(sessionId, false);
        if (session.isRealPtyActive) {
          return CommandResult(
            output: 'Returned to NORMAL mode. Real PTY is still running.',
          );
        } else {
          return CommandResult(output: 'Returned to NORMAL mode.');
        }

      case 'keyboard-help':
        return CommandResult(
          output:
              '=== Termode Keyboard & Input Help ===\n\n'
              'Special Keys in REAL PTY Mode:\n'
              '  ESC   - Sends escape code (\\u001B)\n'
              '  TAB   - Sends horizontal tab (\\t) for autocompletion\n'
              '  CTRL  - Toggles the CTRL state. Pressing CTRL then C/D sends Ctrl-C/D\n'
              '  HOME  - Sends cursor home (\\u001B[H)\n'
              '  END   - Sends cursor end (\\u001B[F)\n'
              '  Arrows- Send standard ANSI arrow sequences (up/down/left/right)\n\n'
              'Control Shortcuts:\n'
              '  CTRL+C - Sends SIGINT (interrupt current process)\n'
              '  CTRL+D - Sends EOF (closes input stream/exits shell)\n\n'
              'Limitations:\n'
              '  - Some complex full-screen programs (e.g. interactive text editors) may have display issues until the renderer matures.',
        );

      case 'stop-shell':
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];

        final wasRealPtyActive = session.isRealPtyActive;
        sessionService.setRealPtyActive(sessionId, false);
        sessionService.setPtyInteractionActive(sessionId, false);

        if (wasRealPtyActive) {
          final channel = const MethodChannel('com.termode/native_shell');
          try {
            await channel.invokeMethod('realPtyStop', {'sessionId': sessionId});
            return CommandResult(
              output: 'Real PTY shell stopped. Returned to NORMAL mode.',
            );
          } catch (e) {
            return CommandResult(
              output:
                  'Error: Failed to stop PTY: $e. Cleaned up local session state.',
              isError: true,
            );
          }
        } else {
          return CommandResult(output: 'No active real PTY shell is running.');
        }

      case 'shell-doctor':
        final sessionService = TerminalSessionService();
        final settings = SettingsService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];

        final mode = session.isPtyInteractionActive
            ? 'REAL PTY'
            : (session.isRealPtyActive ? 'PTY RUNNING' : 'NORMAL');
        final isRealPtyActive = session.isRealPtyActive;
        final isPtyInteractionActive = session.isPtyInteractionActive;
        final startInRealShell = settings.startInRealShell;

        bool nativeRunning = false;
        int nativePid = -1;
        try {
          final res = await const MethodChannel(
            'com.termode/native_shell',
          ).invokeMethod('realPtyStatus', {'sessionId': sessionId});
          if (res is Map) {
            nativeRunning = res['running'] as bool? ?? false;
            nativePid = res['pid'] as int? ?? -1;
          }
        } catch (e) {
          return CommandResult(
            output: 'Error: Native PTY status is unavailable: $e',
            isError: true,
          );
        }

        final List<String> mismatches = [];
        String suggestedFix =
            'No issues detected. Your shell environment is healthy.';

        if (isRealPtyActive != nativeRunning) {
          mismatches.add(
            'Session active flag ($isRealPtyActive) does not match native process status ($nativeRunning)',
          );
        }
        if (isPtyInteractionActive && !isRealPtyActive) {
          mismatches.add(
            'Session interaction flag is true but session active flag is false',
          );
        }

        if (mismatches.isNotEmpty) {
          suggestedFix =
              'Mismatch detected. Recommended actions:\n'
              '  - Run stop-shell to reset the session state.\n'
              '  - Or run default-shell to re-initialize the shell process.';
        }

        final buf = StringBuffer();
        buf.writeln('=== Termode Shell Doctor Diagnostics ===');
        buf.writeln('Session ID:             $sessionId');
        buf.writeln('Current Mode:           $mode');
        buf.writeln('isRealPtyActive:        $isRealPtyActive');
        buf.writeln('isPtyInteractionActive: $isPtyInteractionActive');
        buf.writeln('startInRealShell:       $startInRealShell');
        buf.writeln('Native PTY Running:     $nativeRunning (PID: $nativePid)');
        if (mismatches.isNotEmpty) {
          buf.writeln('\nMismatches Found:');
          for (final m in mismatches) {
            buf.writeln('  - $m');
          }
        }
        buf.writeln('\nSuggested Fix:');
        buf.writeln('  $suggestedFix');

        return CommandResult(output: buf.toString());

      case 'real-pty-mode-status':
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];
        if (session.isPtyInteractionActive) {
          return CommandResult(output: 'PTY Interaction Mode: ACTIVE');
        } else {
          return CommandResult(output: 'PTY Interaction Mode: INACTIVE');
        }

      case 'runtime-tools':
        if (args.isEmpty) {
          return CommandResult(
            output:
                'Usage: runtime-tools <status|install-test|test-run|reset|path|help>\n'
                'Type "runtime-tools help" for more information.',
            isError: true,
          );
        }
        final subcommand = args[0].toLowerCase();
        final runtimeService = RuntimeToolService();

        switch (subcommand) {
          case 'status':
            final status = await runtimeService.checkStatus();
            final installed = status['installedTools'] as List<String>;
            final missing = status['missingTools'] as List<String>;
            final chmodMap = status['chmodStatus'] as Map<String, String>;
            final directMap = status['directExecStatus'] as Map<String, String>;
            final interpreterMap =
                status['interpreterStatus'] as Map<String, String>;

            final buf = StringBuffer();
            buf.writeln('=== Termode Runtime Tools Status ===');
            buf.writeln('Health:               ${status['health']}');
            buf.writeln('Bin Path:             ${status['binPath']}');
            buf.writeln(
              'Installed Tools:      ${installed.isEmpty ? "None" : installed.join(", ")}',
            );
            buf.writeln(
              'Missing Tools:        ${missing.isEmpty ? "None" : missing.join(", ")}',
            );

            final chmodList = <String>[];
            chmodMap.forEach((k, v) => chmodList.add('$k: $v'));
            buf.writeln(
              'Chmod Executable:     ${chmodList.isEmpty ? "None" : chmodList.join(", ")}',
            );

            final directList = <String>[];
            directMap.forEach((k, v) => directList.add('$k: $v'));
            buf.writeln(
              'Direct Executable:    ${directList.isEmpty ? "None" : directList.join(", ")}',
            );

            final interpreterList = <String>[];
            interpreterMap.forEach((k, v) => interpreterList.add('$k: $v'));
            buf.writeln(
              'Interpreter Runnable: ${interpreterList.isEmpty ? "None" : interpreterList.join(", ")}',
            );

            return CommandResult(output: buf.toString());

          case 'install-test':
            final success = await runtimeService.installTestTool();
            if (success) {
              return CommandResult(
                output:
                    'Success: Installed hello-termode test tool into files/usr/bin.',
                shouldReloadShellHelpers: true,
                helperReloadSuccessMessage: 'Reloaded Termode shell helpers.',
                helperReloadFailureMessage:
                    'Runtime tool installed, but helper reload failed. Run: reload-helpers',
              );
            } else {
              return CommandResult(
                output: 'Error: Failed to install test tool.',
                isError: true,
              );
            }

          case 'test-run':
            final status = await runtimeService.checkStatus();
            final installed = status['installedTools'] as List<String>;
            if (!installed.contains('hello-termode')) {
              return CommandResult(
                output:
                    'Error: hello-termode test tool is not installed.\n'
                    'Run "runtime-tools install-test" first.',
                isError: true,
              );
            }
            final paths = await RuntimeBootstrapService().getPaths();
            final binDir = paths['bin']!;
            final toolFile = File('$binDir/hello-termode');

            final cmdStr = '/system/bin/sh "${toolFile.path}"';
            final nativeResult = await NativeCommandService().execute(
              cmdStr,
              sessionId,
            );
            final cleanOut = nativeResult.stdout.trim();
            final cleanErr = nativeResult.stderr.trim();

            final buf = StringBuffer();
            buf.writeln(
              'Executing /system/bin/sh \$TERMODE_BIN/hello-termode...',
            );
            if (cleanOut.isNotEmpty) {
              buf.writeln('Output: $cleanOut');
            }
            if (cleanErr.isNotEmpty) {
              buf.writeln('Error: $cleanErr');
            }
            buf.writeln('Exit code: ${nativeResult.exitCode}');

            final pass =
                nativeResult.exitCode == 0 &&
                cleanOut.contains('Hello from Termode runtime tools');
            buf.write('Result: ${pass ? "PASS" : "FAIL"}');

            return CommandResult(output: buf.toString(), isError: !pass);

          case 'reset':
            final success = await runtimeService.reset();
            if (success) {
              return CommandResult(
                output:
                    'Success: Cleaned up managed runtime tools and metadata.',
                shouldReloadShellHelpers: true,
                helperReloadSuccessMessage: 'Reloaded Termode shell helpers.',
                helperReloadFailureMessage:
                    'Runtime tools reset, but helper reload failed. Run: reload-helpers',
              );
            } else {
              return CommandResult(
                output: 'Error: Failed to reset runtime tools.',
                isError: true,
              );
            }

          case 'path':
            final paths = await RuntimeBootstrapService().getPaths();
            final buf = StringBuffer();
            buf.writeln('=== Termode Runtime Paths ===');
            buf.writeln('HOME:        ${paths['home']}');
            buf.writeln('TERMODE_USR: ${paths['usr']}');
            buf.writeln('TERMODE_BIN: ${paths['bin']}');
            buf.writeln(
              'PTY PATH:    ${paths['bin']}:/system/bin:/system/xbin:/vendor/bin:/product/bin',
            );
            return CommandResult(output: buf.toString());

          case 'help':
            return CommandResult(
              output:
                  '=== Termode Runtime Tools Help ===\n\n'
                  'Termode runtime tools allow installing and running local command-line tools.\n\n'
                  'Key Details:\n'
                  '  - Bundled runtime tools are experimental and run within the sandboxed files/usr/bin directory.\n'
                  '  - Files installed here are separate from the Android system commands.\n'
                  '  - Use pkg for installable script packages.\n'
                  '  - WARNING: Direct execution from files/usr/bin may fail on Android with "Permission denied" (exit code 126).\n'
                  '    Use: sh \$TERMODE_BIN/hello-termode\n'
                  '    Or use Termode NORMAL mode command: run-tool hello-termode\n\n'
                  'Subcommands:\n'
                  '  - runtime-tools status       - Display current installation status and health\n'
                  '  - runtime-tools install-test - Install the hello-termode test script\n'
                  '  - runtime-tools test-run     - Perform a test run of the hello-termode script\n'
                  '  - runtime-tools reset        - Uninstall and delete managed test tools\n'
                  '  - runtime-tools path         - Print shell environment directory paths\n'
                  '  - runtime-tools help         - Show this help reference',
            );

          default:
            return CommandResult(
              output:
                  'Unknown subcommand: $subcommand\n'
                  'Usage: runtime-tools <status|install-test|test-run|reset|path|help>',
              isError: true,
            );
        }

      case 'run-tool':
        if (args.isEmpty) {
          return CommandResult(
            output:
                'Usage: run-tool <tool-name> [args...]\n'
                'Type "runtime-tools help" for more information.',
            isError: true,
          );
        }
        final toolName = args[0];
        final paths = await RuntimeBootstrapService().getPaths();
        final binDir = paths['bin']!;

        // Safety check: block path traversals
        if (toolName.contains('/') ||
            toolName.contains('\\') ||
            toolName.contains('..')) {
          return CommandResult(
            output: 'run-tool: invalid tool name',
            isError: true,
          );
        }

        final toolFile = File('$binDir/$toolName');
        if (!await toolFile.exists()) {
          return CommandResult(
            output: 'run-tool: tool not found: $toolName',
            isError: true,
          );
        }

        final toolArgs = args
            .sublist(1)
            .map((arg) => arg.contains(' ') ? '"$arg"' : arg)
            .join(' ');
        final cmdStr =
            '/system/bin/sh "${toolFile.path}"${toolArgs.isNotEmpty ? " $toolArgs" : ""}';

        final nativeResult = await NativeCommandService().execute(
          cmdStr,
          sessionId,
        );
        final outputBuilder = StringBuffer();
        if (nativeResult.stdout.isNotEmpty) {
          outputBuilder.write(nativeResult.stdout);
        }
        if (nativeResult.stderr.isNotEmpty) {
          if (outputBuilder.isNotEmpty) outputBuilder.write('\n');
          outputBuilder.write(nativeResult.stderr);
        }
        if (outputBuilder.isEmpty && nativeResult.exitCode != 0) {
          outputBuilder.write(
            'Process exited with code ${nativeResult.exitCode}',
          );
        }
        return CommandResult(
          output: outputBuilder.toString().trimRight(),
          isError: nativeResult.exitCode != 0,
        );

      case 'pkg':
        if (args.isEmpty) {
          return execute('pkg help');
        }
        final subcommand = args[0].toLowerCase();
        final pmService = PackageManagerService();
        final bootstrapService = RuntimeBootstrapService();
        final pPaths = await bootstrapService.getPaths();
        final pUsrDir = pPaths['usr']!;

        switch (subcommand) {
          case 'help':
            return CommandResult(
              output:
                  '=== Termode Package Manager (pkg) ===\n'
                  'Manage script-based packages inside Termode.\n\n'
                  'Commands:\n'
                  '  pkg help                 - Show this help message\n'
                  '  pkg update               - Update local package index\n'
                  '  pkg list                 - List all packages in index with status\n'
                  '  pkg search <term>        - Search packages in index\n'
                  '  pkg info <name>          - Show detailed information for a package\n'
                  '  pkg install <name>       - Install a package\n'
                  '  pkg reinstall <name>     - Reinstall or install a package\n'
                  '  pkg upgrade              - Upgrade installed packages from local index\n'
                  '  pkg repair               - Repair missing package files and helpers\n'
                  '  pkg clean                - Clean package manager temp files\n'
                  '  pkg files <name>         - Show files managed by a package\n'
                  '  pkg verify <name>        - Verify files, checksums, and helper\n'
                  '  pkg remove <name>        - Uninstall a package\n'
                  '  pkg installed            - List all installed packages\n'
                  '  pkg doctor               - Audit package installation health',
            );

          case 'update':
            final res = await pmService.updateIndex();
            return CommandResult(
              output:
                  'Updating package index...\n'
                  '${res['message']}\n'
                  'Success: Index updated (${res['count']} packages available).',
            );

          case 'list':
            final installed = await _getInstalledPackages(pUsrDir);
            final sb = StringBuffer();
            sb.writeln('=== Termode Package Repository ===');
            for (final entry in PackageManagerService.localIndex.entries) {
              final name = entry.key;
              final pkg = entry.value;
              final status = installed.containsKey(name)
                  ? 'Installed'
                  : 'Not Installed';
              sb.writeln(
                '$name [${pkg['version']}] - ${pkg['description']} (Status: $status)',
              );
            }
            return CommandResult(output: sb.toString().trimRight());

          case 'search':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: pkg search <query>',
                isError: true,
              );
            }
            final query = args[1].toLowerCase();
            final installed = await _getInstalledPackages(pUsrDir);
            final sb = StringBuffer();
            sb.writeln('=== Search Results for "$query" ===');
            int count = 0;
            for (final entry in PackageManagerService.localIndex.entries) {
              final name = entry.key;
              final pkg = entry.value;
              final desc = (pkg['description'] as String).toLowerCase();
              if (name.toLowerCase().contains(query) || desc.contains(query)) {
                count++;
                final status = installed.containsKey(name)
                    ? 'Installed'
                    : 'Not Installed';
                sb.writeln(
                  '$name [${pkg['version']}] - ${pkg['description']} (Status: $status)',
                );
              }
            }
            if (count == 0) {
              sb.writeln('No matching packages found.');
            }
            return CommandResult(output: sb.toString().trimRight());

          case 'info':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: pkg info <package-name>',
                isError: true,
              );
            }
            final pkgName = args[1];
            final pkg = PackageManagerService.localIndex[pkgName];
            if (pkg == null) {
              return CommandResult(
                output: 'pkg info: Package "$pkgName" not found in index.',
                isError: true,
              );
            }
            final installed = await _getInstalledPackages(pUsrDir);
            final isInst = installed.containsKey(pkgName);
            final sb = StringBuffer();
            sb.writeln('Package:     ${pkg['name']}');
            sb.writeln('Version:     ${pkg['version']}');
            sb.writeln('Type:        ${pkg['type']}');
            sb.writeln(
              'Status:      ${isInst ? "Installed" : "Not Installed"}',
            );
            sb.writeln('Description: ${pkg['description']}');
            sb.writeln('Files:');
            final filesMap = pkg['files'] as Map<String, dynamic>;
            for (final f in filesMap.keys) {
              sb.writeln('  - $f');
            }
            return CommandResult(output: sb.toString().trimRight());

          case 'install':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: pkg install <package-name>',
                isError: true,
              );
            }
            final pkgName = args[1];
            final result = await pmService.installPackage(pkgName);
            if (result.isError) {
              return CommandResult(output: result.output, isError: true);
            }
            return CommandResult(
              output:
                  '${result.output}\nTip: Command is available now. Try: ${result.executable ?? pkgName}',
              shouldReloadShellHelpers: result.changedHelpers,
              helperReloadFailureMessage:
                  'Package installed, but helper reload failed. Run: reload-helpers',
            );

          case 'reinstall':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: pkg reinstall <package-name>',
                isError: true,
              );
            }
            final pkgName = args[1];
            final result = await pmService.reinstallPackage(pkgName);
            if (result.isError) {
              return CommandResult(output: result.output, isError: true);
            }
            return CommandResult(
              output:
                  '${result.output}\nTip: Command is available now. Try: ${result.executable ?? pkgName}',
              shouldReloadShellHelpers: result.changedHelpers,
              helperReloadFailureMessage:
                  'Package reinstalled, but helper reload failed. Run: reload-helpers',
            );

          case 'upgrade':
            final result = await pmService.upgradePackages();
            return CommandResult(
              output: result.output,
              isError: result.isError,
              shouldReloadShellHelpers: result.changedHelpers,
              helperReloadFailureMessage:
                  'Packages upgraded, but helper reload failed. Run: reload-helpers',
            );

          case 'repair':
            final result = await pmService.repairPackages();
            return CommandResult(
              output: result.output,
              isError: result.isError,
              shouldReloadShellHelpers: result.changedHelpers,
              helperReloadFailureMessage:
                  'Package repair completed, but helper reload failed. Run: reload-helpers',
            );

          case 'clean':
            final result = await pmService.cleanPackages();
            return CommandResult(
              output: result.output,
              isError: result.isError,
              shouldReloadShellHelpers: result.changedHelpers,
              helperReloadFailureMessage:
                  'Package clean completed, but helper reload failed. Run: reload-helpers',
            );

          case 'files':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: pkg files <package-name>',
                isError: true,
              );
            }
            final result = await pmService.packageFiles(args[1]);
            return CommandResult(
              output: result.output,
              isError: result.isError,
            );

          case 'verify':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: pkg verify <package-name>',
                isError: true,
              );
            }
            final result = await pmService.verifyPackage(args[1]);
            return CommandResult(
              output: result.output,
              isError: result.isError,
            );

          case 'remove':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: pkg remove <package-name>',
                isError: true,
              );
            }
            final pkgName = args[1];
            final pkg = PackageManagerService.localIndex[pkgName];
            final executable = pkg?['executable'] as String? ?? pkgName;
            final result = await pmService.removePackage(pkgName);
            if (result.isError) {
              return CommandResult(output: result.output, isError: true);
            }
            return CommandResult(
              output:
                  '${result.output}\n'
                  'Tip: Helper reload removes "$executable" from the current shell. '
                  'If it still appears cached, run: reload-helpers',
              shouldReloadShellHelpers: result.changedHelpers,
              helperReloadFailureMessage:
                  'Package removed, but helper reload failed. Run: reload-helpers',
            );

          case 'installed':
            final installed = await _getInstalledPackages(pUsrDir);
            if (installed.isEmpty) {
              return CommandResult(output: 'No packages currently installed.');
            }
            final sb = StringBuffer();
            sb.writeln('=== Installed Packages ===');
            for (final entry in installed.entries) {
              final name = entry.key;
              final data = entry.value as Map<String, dynamic>;
              sb.writeln(
                '$name [${data['version']}] - Installed at: ${data['installedAt']}',
              );
            }
            return CommandResult(output: sb.toString().trimRight());

          case 'doctor':
            final doc = await pmService.checkDoctor();
            final sb = StringBuffer();
            sb.writeln('=== Termode Package Manager Doctor ===');
            sb.writeln(
              'Metadata File:      ${doc['metadataExists'] ? "EXISTS" : "MISSING"} (${doc['metadataPath']})',
            );
            sb.writeln('Bin Directory:      ${doc['binPath']}');
            sb.writeln(
              'Helper Script:      ${doc['helperExists'] ? "EXISTS" : "MISSING"} (${doc['helperPath']})',
            );
            sb.writeln('Installed Packages: ${doc['installedCount']}');
            sb.writeln('Broken Packages:    ${doc['brokenPackageCount']}');
            sb.writeln('Missing File Count: ${doc['missingFileCount']}');
            sb.writeln('Helper Function Count: ${doc['helperFunctionCount']}');
            sb.writeln('Helper Reload Command: ${doc['helperReloadCommand']}');
            sb.writeln(
              'Current Shell May Need Reload: ${doc['mayNeedReload'] ? "YES" : "NO"}',
            );
            if (doc['metadataError'] != null) {
              sb.writeln('Metadata Error:     ${doc['metadataError']}');
            }

            final missing = doc['missingFiles'] as List<dynamic>;
            if (missing.isNotEmpty) {
              sb.writeln('Missing Package Files:');
              for (final f in missing) {
                sb.writeln('  - [MISSING] $f');
              }
            } else {
              sb.writeln('All registered files: Present');
            }

            sb.writeln(
              'Helper Functions:   ${doc['helpersGenerated'] ? "OK" : "NOT GENERATED"}',
            );

            bool isHealthy =
                doc['repairRecommended'] != true &&
                missing.isEmpty &&
                (!doc['metadataExists'] ||
                    doc['installedCount'] == 0 ||
                    doc['helperExists']);
            sb.writeln(
              'Repair Recommended: ${doc['repairRecommended'] ? "YES (run pkg repair)" : "NO"}',
            );
            sb.write(
              'Overall Status:     ${isHealthy ? "HEALTHY" : "UNHEALTHY"}',
            );
            return CommandResult(output: sb.toString(), isError: !isHealthy);

          default:
            return CommandResult(
              output:
                  'Unknown subcommand: $subcommand\n'
                  'Usage: pkg <help|update|list|search|info|install|reinstall|upgrade|repair|clean|files|verify|remove|installed|doctor>',
              isError: true,
            );
        }

      case 'mode':
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];
        final settings = SettingsService();

        final modeStr = session.isPtyInteractionActive
            ? 'REAL PTY'
            : (session.isRealPtyActive ? 'PTY RUNNING' : 'NORMAL');
        final interceptionStr = session.isPtyInteractionActive
            ? 'Active'
            : 'Inactive';
        final startInRealShellStr = settings.startInRealShell
            ? 'Enabled'
            : 'Disabled';

        final sb = StringBuffer();
        sb.writeln('=== Termode Mode Status ===');
        sb.writeln('Current Mode:                   $modeStr');
        sb.writeln('Host Command Interception:      $interceptionStr');
        sb.write('Start In Real Shell (Setting):  $startInRealShellStr');
        return CommandResult(output: sb.toString());

      case 'reload-helpers':
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];
        if (!session.isPtyInteractionActive || !session.isRealPtyActive) {
          return CommandResult(
            output:
                'Termode shell helpers are sourced inside REAL PTY shell sessions.\n'
                'Start or enter the shell with default-shell, then run reload-helpers.',
          );
        }

        final reloaded = await sessionService.reloadShellHelpersForSession(
          sessionId,
        );
        if (reloaded) {
          return CommandResult(output: 'Reloaded Termode shell helpers.');
        }
        return CommandResult(
          output:
              'Helper reload failed. Run reload-helpers after restarting the shell.',
          isError: true,
        );

      case 'host-help':
        final sb = StringBuffer();
        sb.writeln('=== Termode Host Command Interception ===');
        sb.writeln(
          'Termode runs in a real PTY shell by default, meaning most commands',
        );
        sb.writeln('are sent directly to the underlying Android system shell.');
        sb.writeln();
        sb.writeln(
          'However, Termode intercepts specific management commands to run',
        );
        sb.writeln('them inside the app environment:');
        sb.writeln();
        sb.writeln('Intercepted Host Commands:');
        sb.writeln(
          '  pkg            - Manage Termode packages (list, install, search, doctor, etc.)',
        );
        sb.writeln(
          '  runtime-tools  - Manage Termode runtime tools (status, install-test, test-run)',
        );
        sb.writeln(
          '  storage-*      - Access user-linked Android storage (storage-link, storage-list, etc.)',
        );
        sb.writeln(
          '  shell-doctor   - Audit PTY shell configuration and status',
        );
        sb.writeln('  keyboard-help  - Show keyboard shortcuts reference');
        sb.writeln('  real-pty-help  - Show PTY prototype help reference');
        sb.writeln(
          '  normal-mode    - Exit PTY interaction mode to return to classic Termode prompt',
        );
        sb.writeln(
          '  stop-shell     - Kill the PTY shell process and return to NORMAL mode',
        );
        sb.writeln(
          '  mode           - Display active mode and environment settings',
        );
        sb.writeln(
          '  whereami       - Show directory layouts of VFS, runtime, and linked storage',
        );
        sb.writeln(
          '  reload-helpers - Source package helper functions into the current shell',
        );
        sb.writeln(
          '  host-help      - Show this host interception help reference',
        );
        sb.writeln();
        sb.write(
          'Package Notes:\n'
          '  - pkg is handled by Termode host interception.\n'
          '  - Use pkg reinstall, pkg verify, and pkg repair to recover packages.\n'
          '  - Installed packages run inside the shell through helper functions.\n'
          '  - If a newly installed package does not work, run reload-helpers.',
        );
        return CommandResult(output: sb.toString());

      case 'pty-start':
        final res = await execute('shell-start');
        return CommandResult(
          output:
              'WARNING: "pty-start" is deprecated/experimental. Please use "shell-start" instead.\n${res.output}',
          isError: res.isError,
          shouldClear: res.shouldClear,
        );

      case 'pty-status':
        final res = await execute('shell-status');
        return CommandResult(
          output:
              'WARNING: "pty-status" is deprecated/experimental. Please use "shell-status" instead.\n${res.output}',
          isError: res.isError,
          shouldClear: res.shouldClear,
        );

      case 'pty-stop':
        final res = await execute('shell-stop');
        return CommandResult(
          output:
              'WARNING: "pty-stop" is deprecated/experimental. Please use "shell-stop" instead.\n${res.output}',
          isError: res.isError,
          shouldClear: res.shouldClear,
        );

      case 'pty-send':
        if (args.isEmpty) {
          return CommandResult(
            output:
                'pty-send: missing command/text operand\nUsage: pty-send <text>',
            isError: true,
          );
        }
        final res = await execute('shell-send ${args.join(' ')}');
        return CommandResult(
          output:
              'WARNING: "pty-send" is deprecated/experimental. Please use "shell-send" instead.\n${res.output}'
                  .trimRight(),
          isError: res.isError,
          shouldClear: res.shouldClear,
        );

      default:
        return CommandResult(
          output: 'termode: command not found: $command',
          isError: true,
        );
    }
  }
}
