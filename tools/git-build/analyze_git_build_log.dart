import 'dart:io';

void main(List<String> args) {
  final idx = args.indexOf('--project-root');
  final rootPath = (idx != -1 && idx + 1 < args.length) ? args[idx + 1] : Directory.current.path;
  final root = Directory(rootPath).absolute;

  final logFile = File('${root.path}/tools/git-build/logs/git-arm64-build.log');

  stdout.writeln('=== Git Build Log Diagnosis ===');
  stdout.writeln('Log: tools/git-build/logs/git-arm64-build.log');

  if (!logFile.existsSync()) {
    stdout.writeln('Failure category: unknown failure');
    stdout.writeln('Failing command: none (log file not found)');
    stdout.writeln('Relevant error lines:\n* Log file does not exist.');
    stdout.writeln('Recommended fix:\n* Rerun the build attempt to generate logs.');
    exitCode = 1;
    return;
  }

  final lines = logFile.readAsLinesSync();
  final errors = <String>[];
  String failingCommand = 'unknown';

  for (final line in lines) {
    final lower = line.toLowerCase();
    if (lower.contains('error') ||
        lower.contains('failed') ||
        lower.contains('not recognized') ||
        lower.contains('cannot find') ||
        lower.contains('pipe: no such file') ||
        lower.contains('missing separator') ||
        lower.contains('createprocess') ||
        lower.contains('make: ***')) {
      errors.add(line);
    }
    // Attempt to locate last failing make target or command
    if (line.contains('make: ***') || line.contains('CreateProcess')) {
      failingCommand = line.trim();
    }
  }

  final category = classifyFailure(lines.join('\n'));
  stdout.writeln('Failure category: $category');
  if (category == 'missing OpenSSL header') {
    stdout.writeln('Relevant error: openssl/ssl.h');
    stdout.writeln('Suggested action: try minimal local Git build with OpenSSL/curl/HTTPS disabled before staging OpenSSL.');
  }
  stdout.writeln('Failing command: $failingCommand');
  stdout.writeln('Relevant error lines:');
  if (errors.isEmpty) {
    stdout.writeln('* None detected.');
  } else {
    // Show last 5 unique errors
    final uniqueErrors = errors.toSet().toList();
    final toShow = uniqueErrors.length > 5 ? uniqueErrors.sublist(uniqueErrors.length - 5) : uniqueErrors;
    for (final err in toShow) {
      stdout.writeln('* $err');
    }
  }

  stdout.writeln('Recommended fix:');
  switch (category) {
    case 'missing OpenSSL header':
      stdout.writeln('* Suggest action: try minimal local Git build with OpenSSL/curl/HTTPS disabled before staging OpenSSL.');
      break;
    case 'missing header/library':
      stdout.writeln('* Verify that all required dependencies (like OpenSSL or curl) are staged, compiled, and their include/library paths are passed to Make.');
      break;
    case 'Makefile target failure':
      stdout.writeln('* The Unix Makefile requires POSIX shell utilities (/bin/sh, uname, sed, etc.).');
      final gitBashFound = _checkGitBash() != null;
      final wslFound = _checkWsl();
      if (gitBashFound) {
        stdout.writeln('Recommended strategy: git-bash');
      } else if (wslFound) {
        stdout.writeln('Recommended strategy: wsl');
      } else {
        stdout.writeln('Recommended strategy: install/configure POSIX-compatible build shell manually');
      }
      break;
    case 'Git Bash path translation issue':
      stdout.writeln('* Verify that POSIX path translation translates all Windows paths correctly and uses forward slashes.');
      break;
    case 'Git Bash environment issue':
      stdout.writeln('* Check the Git Bash environment setup and ensure essential CLI tools are in the PATH.');
      break;
    case 'compiler failure':
      stdout.writeln('* Check the compiler flags and ensure they match the Android NDK arm64 compiler requirements.');
      break;
    case 'linker failure':
      stdout.writeln('* Check the linker flags and make sure all library directories are referenced correctly.');
      break;
    case 'zlib integration failure':
      stdout.writeln('* Verify that zlib includes and static libraries are passed to the Git make process.');
      break;
    case 'Android target compatibility issue':
      stdout.writeln('* Ensure NDK target API version is configured correctly (e.g., API 24 wrapper).');
      break;
    default:
      stdout.writeln('* Troubleshoot the make process or try a different build shell environment.');
  }
}

String classifyFailure(String output) {
  final lower = output.toLowerCase();
  if (lower.contains('configure: error') || lower.contains('configure failed')) {
    return 'configure failure';
  }
  if (lower.contains('openssl/ssl.h') || lower.contains('openssl/crypto.h') || (lower.contains('openssl') && lower.contains('include'))) {
    return 'missing OpenSSL header';
  }
  if (lower.contains('fatal error:') && (lower.contains('no such file') || lower.contains('file not found') || lower.contains('.h:'))) {
    return 'missing header/library';
  }
  if (lower.contains('clang: error') || lower.contains('compiler error') || (lower.contains('error:') && lower.contains('.c:'))) {
    return 'compiler failure';
  }
  if (lower.contains('ld: error') || lower.contains('linker error') || lower.contains('undefined reference')) {
    return 'linker failure';
  }
  if (lower.contains('zlib.h') || lower.contains('zlib integration')) {
    return 'zlib integration failure';
  }
  if (lower.contains('perl') && (lower.contains('not found') || lower.contains('error'))) {
    return 'Perl/build script failure';
  }
  if (lower.contains('unsupported target') || lower.contains('unsupported android')) {
    return 'Android target compatibility issue';
  }
  if (lower.contains('path translation') || lower.contains('invalid drive') || (lower.contains('no such file or directory') && lower.contains('/c/'))) {
    return 'Git Bash path translation issue';
  }
  if (lower.contains('git bash') || (lower.contains('bash:') && (lower.contains('command not found') || lower.contains('environment')))) {
    return 'Git Bash environment issue';
  }
  if (lower.contains('not recognized as an internal or external command') ||
      lower.contains('spawn') ||
      lower.contains('cannot find the path specified') ||
      lower.contains('/bin/sh') ||
      lower.contains('process_begin') ||
      lower.contains('missing separator') ||
      lower.contains('target pattern contains no')) {
    return 'Makefile target failure';
  }
  return 'unknown failure';
}

String? _checkGitBash() {
  final candidates = [
    'C:\\Program Files\\Git\\bin\\bash.exe',
    'C:\\Program Files\\Git\\usr\\bin\\bash.exe',
    'C:\\Program Files (x86)\\Git\\bin\\bash.exe',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  try {
    final result = Process.runSync('where', ['bash']);
    if (result.exitCode == 0) {
      final line = result.stdout.toString().split('\n').first.trim();
      if (line.isNotEmpty && File(line).existsSync()) return line;
    }
  } catch (_) {}
  return null;
}

bool _checkWsl() {
  final wslFile = File('C:\\Windows\\System32\\wsl.exe');
  if (wslFile.existsSync()) return true;
  try {
    final result = Process.runSync('wsl', ['--status']);
    return result.exitCode == 0;
  } catch (_) {}
  return false;
}
