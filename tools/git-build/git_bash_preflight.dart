import 'dart:io';
import 'path_translation.dart';
import 'check_build_env.dart';

void main(List<String> args) {
  final idx = args.indexOf('--project-root');
  final rootPath = (idx != -1 && idx + 1 < args.length) ? args[idx + 1] : Directory.current.path;
  final root = Directory(rootPath).absolute;

  stdout.writeln('=== Git Bash Build Preflight ===');

  final gitBashPath = _checkGitBash();
  if (gitBashPath == null) {
    stdout.writeln('Git Bash: missing');
    stdout.writeln('Overall: NOT READY');
    stdout.writeln('Next: Install Git Bash on the host.');
    exitCode = 1;
    return;
  }

  stdout.writeln('Git Bash: found ($gitBashPath)');

  final report = detectGitBuildEnvironment(projectRoot: root.path);

  // 1. Project path check
  final posixRoot = translateToPosixPath(root.path);
  final projectOk = _runBashTest(gitBashPath, 'test -d $posixRoot');
  stdout.writeln('Project path: ${projectOk ? 'READY' : 'MISSING'}');

  // 2. Git source check
  final gitSourcePath = '${root.path}/tools/git-build/sources/git-2.44.0.tar.xz';
  final posixGitSource = translateToPosixPath(gitSourcePath);
  final gitSourceOk = _runBashTest(gitBashPath, 'test -f $posixGitSource');
  stdout.writeln('Git source: ${gitSourceOk ? 'READY' : 'MISSING'}');

  // 3. zlib output check
  final zlibPath = '${root.path}/tools/git-build/output/arm64-v8a/zlib/lib/libz.a';
  final posixZlib = translateToPosixPath(zlibPath);
  final zlibOk = _runBashTest(gitBashPath, 'test -f $posixZlib');
  stdout.writeln('zlib output: ${zlibOk ? 'READY' : 'MISSING'}');

  // 4. Perl check
  final perlOk = _runBashTest(gitBashPath, 'perl --version');
  stdout.writeln('Perl: ${perlOk ? 'READY' : 'MISSING'}');

  // 5. POSIX sh check
  final shOk = _runBashTest(gitBashPath, 'sh -c "echo ok"');
  stdout.writeln('POSIX sh: ${shOk ? 'READY' : 'MISSING'}');

  // 6. uname check
  final unameOk = _runBashTest(gitBashPath, 'uname');
  stdout.writeln('uname: ${unameOk ? 'READY' : 'MISSING'}');

  // 7. sed check
  final sedOk = _runBashTest(gitBashPath, 'sed --version');
  stdout.writeln('sed: ${sedOk ? 'READY' : 'MISSING'}');

  // 8. NDK compiler check
  bool compilerOk = false;
  if (report.compiler != null) {
    final posixCompiler = translateToPosixPath(report.compiler!);
    compilerOk = _runBashTest(gitBashPath, '$posixCompiler --version');
  }
  stdout.writeln('NDK compiler: ${compilerOk ? 'READY' : 'MISSING'}');

  final overallReady = projectOk && gitSourceOk && zlibOk && perlOk && shOk && unameOk && sedOk && compilerOk;

  stdout.writeln('Overall: ${overallReady ? 'READY' : 'NOT READY'}');
  if (overallReady) {
    stdout.writeln('Next: run Git Bash build command to compile Git under Git Bash.');
  } else {
    final blockers = <String>[];
    if (!projectOk) blockers.add('Project path inaccessible');
    if (!gitSourceOk) blockers.add('Git source missing');
    if (!zlibOk) blockers.add('zlib output missing');
    if (!perlOk) blockers.add('Perl missing/broken');
    if (!shOk) blockers.add('POSIX sh missing/broken');
    if (!unameOk) blockers.add('uname missing/broken');
    if (!sedOk) blockers.add('sed missing/broken');
    if (!compilerOk) blockers.add('NDK compiler missing/broken');
    stdout.writeln('Next: Resolve blockers: ${blockers.join(', ')}');
    exitCode = 1;
  }
}

bool _runBashTest(String gitBashPath, String command) {
  try {
    final result = Process.runSync(gitBashPath, ['-c', command]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
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
