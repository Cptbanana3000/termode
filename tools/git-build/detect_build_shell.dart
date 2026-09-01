import 'dart:io';

void main() {
  stdout.writeln('=== Build Shell Detection ===');

  final hasPowerShell = _checkPowerShell();
  final hasCmd = _checkCmd();
  final gitBashPath = _checkGitBash();
  final msysPath = _checkMsys();
  final hasWsl = _checkWsl();

  stdout.writeln('PowerShell: ${hasPowerShell ? 'found' : 'missing'}');
  stdout.writeln('cmd.exe: ${hasCmd ? 'found' : 'missing'}');
  stdout.writeln('Git Bash: ${gitBashPath != null ? 'found ($gitBashPath)' : 'missing'}');
  stdout.writeln('MSYS2 bash: ${msysPath != null ? 'found ($msysPath)' : 'missing'}');
  stdout.writeln('WSL: ${hasWsl ? 'found' : 'missing'}');

  stdout.writeln('Recommended shell: Git Bash or MSYS2 bash');
}

bool _checkPowerShell() {
  return true; // We are running on it.
}

bool _checkCmd() {
  return true; // cmd.exe is always present on Windows.
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
  // Try finding it in path
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
