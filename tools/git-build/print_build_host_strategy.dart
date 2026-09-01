import 'dart:io';

void main() {
  final gitBashPath = _checkGitBash();
  final msysPath = _checkMsys();
  final hasWsl = _checkWsl();

  stdout.writeln('=== Git Build Host Strategy ===');
  stdout.writeln('Windows-native shell: blocked for Git Makefile');
  stdout.writeln('Git Bash: ${gitBashPath != null ? 'found' : 'missing'}');
  stdout.writeln('MSYS2 bash: ${msysPath != null ? 'found' : 'missing'}');
  stdout.writeln('WSL: ${hasWsl ? 'found' : 'missing'}');

  String strategy = 'none';
  String reason = 'No POSIX-compatible shell found on Windows host.';
  String nextAction = 'Install Git Bash or MSYS2 manually.';

  if (gitBashPath != null) {
    strategy = 'git-bash';
    reason = 'Git Bash is available and provides POSIX shell tools required by Git Makefile.';
    nextAction = 'run Git Bash build preflight.';
  } else if (msysPath != null) {
    strategy = 'msys2';
    reason = 'MSYS2 bash is available and provides POSIX shell tools.';
    nextAction = 'run MSYS2 build preflight.';
  } else if (hasWsl) {
    strategy = 'wsl';
    reason = 'WSL is available and provides a full Linux environment.';
    nextAction = 'run WSL build preflight.';
  }

  stdout.writeln('Selected strategy: $strategy');
  stdout.writeln('Reason: $reason');
  stdout.writeln('Next: $nextAction');
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

String? _checkMsys() {
  final candidates = [
    'C:\\msys64\\usr\\bin\\bash.exe',
    'C:\\msys64\\bin\\bash.exe',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
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
