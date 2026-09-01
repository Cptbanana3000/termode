import 'dart:io';

import 'check_build_env.dart';
import 'path_translation.dart';
import 'sha256_helper.dart';

void main(List<String> args) {
  final isBuild = args.contains('--build');
  final isDryRun = args.contains('--dry-run') || !isBuild;
  final isMinimalLocal = args.contains('--minimal-local');
  final rootPath = _projectRoot(args);
  final root = Directory(rootPath ?? Directory.current.path).absolute;

  final report = detectGitBuildEnvironment(projectRoot: root.path);

  String shellArg = 'auto';
  for (final arg in args) {
    if (arg.startsWith('--shell=')) {
      shellArg = arg.substring('--shell='.length).toLowerCase();
    }
  }

  final gitBashPath = _detectGitBashPath();
  final hasWsl = _detectWsl();

  // Resolve selected shell
  String selectedShell = 'powershell';
  if (shellArg == 'git-bash') {
    selectedShell = 'git-bash';
  } else if (shellArg == 'wsl') {
    selectedShell = 'wsl';
  } else if (shellArg == 'powershell') {
    selectedShell = 'powershell';
  } else {
    // auto
    if (gitBashPath != null) {
      selectedShell = 'git-bash';
    } else if (hasWsl) {
      selectedShell = 'wsl';
    } else {
      selectedShell = 'powershell';
    }
  }

  // Check preflight status for selected shell
  bool preflightOk = false;
  String preflightReason = '';

  if (selectedShell == 'git-bash') {
    if (gitBashPath == null) {
      preflightOk = false;
      preflightReason = 'Git Bash not found on host.';
    } else {
      final gitBashOk = _checkGitBashPreflight(gitBashPath, root.path, report);
      if (gitBashOk) {
        preflightOk = true;
        preflightReason = 'Git Bash is available and provides required POSIX shell tools.';
      } else {
        preflightOk = false;
        preflightReason = 'Git Bash found but failed preflight checks (missing POSIX tools or compiler).';
      }
    }
  } else if (selectedShell == 'wsl') {
    preflightOk = false;
    preflightReason = 'WSL strategy is planned but not fully implemented (deferred to WSL/MSYS2 path).';
  } else {
    // powershell
    preflightOk = false;
    preflightReason = 'Windows-native PowerShell/cmd is blocked (impractical for Git Makefile).';
  }

  if (isDryRun) {
    stdout.writeln('=== Git arm64-v8a Build Preflight ===');
    stdout.writeln('Running dry-run check...');
    stdout.writeln('Selected shell: $selectedShell');
    stdout.writeln('Minimal local: $isMinimalLocal');
    stdout.writeln('Shell preflight status: ${preflightOk ? 'READY' : 'NOT READY'}');
    if (!preflightOk) {
      stderr.writeln('Reason: $preflightReason');
      exitCode = 1;
      return;
    }
    stdout.writeln('Next: run dart tools/git-build/build_git_arm64.dart --build --shell=$selectedShell --minimal-local to attempt the real build.');
    return;
  }

  // Build mode
  stdout.writeln('=== Git arm64-v8a Build Attempt ===');
  stdout.writeln('Selected shell: $selectedShell');
  stdout.writeln('Shell preflight status: ${preflightOk ? 'READY' : 'NOT READY'}');

  if (!preflightOk) {
    stderr.writeln('Cannot start Git arm64 build.');
    stderr.writeln('Reason: $preflightReason');
    exitCode = 1;
    return;
  }

  if (selectedShell == 'git-bash') {
    stdout.writeln('Staging environment is verified.');
    stdout.writeln('Starting controlled arm64-v8a build under Git Bash...');

    // Setup directories
    final workDir = Directory('${root.path}/tools/git-build/work');
    final outputDir = Directory('${root.path}/tools/git-build/output');
    final logsDir = Directory('${root.path}/tools/git-build/logs');
    final gitOutputDir = Directory('${root.path}/tools/git-build/output/arm64-v8a/git');
    final zlibOutputDir = Directory('${root.path}/tools/git-build/output/arm64-v8a/zlib');

    workDir.createSync(recursive: true);
    outputDir.createSync(recursive: true);
    logsDir.createSync(recursive: true);
    gitOutputDir.createSync(recursive: true);
    zlibOutputDir.createSync(recursive: true);

    final gitLogFile = File('${logsDir.path}/git-arm64-build.log');
    gitLogFile.writeAsStringSync('=== Git 2.44.0 Build under Git Bash Log ===\n');

    // Verify Git SHA-256
    final gitArchive = File('${root.path}/tools/git-build/sources/git-2.44.0.tar.xz');
    if (!gitArchive.existsSync()) {
      stderr.writeln('Git source archive not found at ${gitArchive.path}');
      exitCode = 1;
      return;
    }
    final gitExpectedHash = 'e358738dcb5b5ea340ce900a0015c03ae86e804e7ff64e47aa4631ddee681de3';
    stdout.writeln('Verifying git-2.44.0.tar.xz checksum...');
    final gitBytes = gitArchive.readAsBytesSync();
    final gitActualHash = calculateSha256(gitBytes);
    if (gitActualHash.toLowerCase() != gitExpectedHash.toLowerCase()) {
      stderr.writeln('Git SHA-256 mismatch! Expected $gitExpectedHash, got $gitActualHash');
      exitCode = 1;
      return;
    }

    // Extract Git
    stdout.writeln('Extracting Git source...');
    final gitWorkspace = Directory('${workDir.path}/git');
    if (gitWorkspace.existsSync()) gitWorkspace.deleteSync(recursive: true);
    gitWorkspace.createSync(recursive: true);

    final posixGitArchive = translateToPosixPath(gitArchive.path);
    final posixGitWorkspace = translateToPosixPath(gitWorkspace.path);

    final gitExtractResult = Process.runSync(
      gitBashPath!,
      ['-c', 'tar -xf $posixGitArchive -C $posixGitWorkspace'],
    );
    gitLogFile.writeAsStringSync(
      'Extraction stdout:\n${gitExtractResult.stdout}\nExtraction stderr:\n${gitExtractResult.stderr}\n',
      mode: FileMode.append,
    );

    if (gitExtractResult.exitCode != 0) {
      stderr.writeln('Git extraction failed.');
      exitCode = 1;
      return;
    }

    // Attempt to build Git under Git Bash
    stdout.writeln('Attempting Git build for Android arm64-v8a under Git Bash...');
    final gitSrcDir = '${gitWorkspace.path}/git-2.44.0';
    final sysroot = '${report.androidNdk}/toolchains/llvm/prebuilt/windows-x86_64/sysroot';

    final posixGitSrcDir = translateToPosixPath(gitSrcDir);
    // Strip .cmd, check if compiler wrapper bash script is chosen
    final compilerClean = report.compiler!.replaceAll('.cmd', '').replaceAll('android21', 'android24');
    final posixCompiler = translateToPosixPath(compilerClean);
    final posixSysroot = translateToPosixPath(sysroot);
    final posixZlibInclude = translateToPosixPath('${zlibOutputDir.path}/include');
    final posixZlibLib = translateToPosixPath('${zlibOutputDir.path}/lib');
    final posixMake = translateToPosixPath(report.make!);

    String compileCmd = 'cd $posixGitSrcDir && $posixMake clean && $posixMake '
        'prefix=/usr/local '
        'uname_S=Linux '
        'CC="$posixCompiler" '
        'CFLAGS="--sysroot=$posixSysroot -target aarch64-linux-android24 -I$posixZlibInclude" '
        'LDFLAGS="-L$posixZlibLib"';

    if (isMinimalLocal) {
      compileCmd += ' NO_OPENSSL=YesPlease NO_CURL=YesPlease NO_EXPAT=YesPlease NO_GETTEXT=YesPlease NO_ICONV=YesPlease NO_PTHREADS=YesPlease HAVE_SYNC_FILE_RANGE= NEEDS_LIBRT=';
    }

    compileCmd += ' git';

    gitLogFile.writeAsStringSync('Running command: $compileCmd\n', mode: FileMode.append);

    final makeResult = Process.runSync(
      gitBashPath,
      ['-c', compileCmd],
    );

    final combinedLogs = '=== Make Build stdout ===\n${makeResult.stdout}\n=== Make Build stderr ===\n${makeResult.stderr}\n';
    gitLogFile.writeAsStringSync(combinedLogs, mode: FileMode.append);

    if (makeResult.exitCode == 0) {
      final compiledGitFile = File('$gitSrcDir/git');
      if (compiledGitFile.existsSync()) {
        final destBinDir = Directory('${gitOutputDir.path}/bin');
        destBinDir.createSync(recursive: true);
        final destGitFile = File('${destBinDir.path}/git');
        compiledGitFile.copySync(destGitFile.path);

        final destBytes = destGitFile.readAsBytesSync();
        final destHash = calculateSha256(destBytes);

        stdout.writeln('Git build succeeded.');
        stdout.writeln('Output: tools/git-build/output/arm64-v8a/git/bin/git');
        stdout.writeln('SHA-256: $destHash');
        stdout.writeln('Runtime Package Status: UNAVAILABLE');
        stdout.writeln('Next: v0.63 Git Artifact Packaging / Install QA');
        return;
      }
    }

    final failureCategory = _classifyFailure(combinedLogs);
    stderr.writeln('Git build failed.');
    stderr.writeln('Failure Category: $failureCategory');
    stderr.writeln('For full logs, see: tools/git-build/logs/git-arm64-build.log');
    exitCode = 1;
  } else {
    stderr.writeln('Real build not supported for shell strategy: $selectedShell');
    exitCode = 1;
  }
}

String _classifyFailure(String output) {
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

bool _checkGitBashPreflight(String gitBashPath, String rootPath, GitBuildEnvironment report) {
  final posixRoot = translateToPosixPath(rootPath);
  final projectOk = _runBashTest(gitBashPath, 'test -d $posixRoot');
  final gitSourcePath = '$rootPath/tools/git-build/sources/git-2.44.0.tar.xz';
  final posixGitSource = translateToPosixPath(gitSourcePath);
  final gitSourceOk = _runBashTest(gitBashPath, 'test -f $posixGitSource');
  final zlibPath = '$rootPath/tools/git-build/output/arm64-v8a/zlib/lib/libz.a';
  final posixZlib = translateToPosixPath(zlibPath);
  final zlibOk = _runBashTest(gitBashPath, 'test -f $posixZlib');
  final perlOk = _runBashTest(gitBashPath, 'perl --version');
  final shOk = _runBashTest(gitBashPath, 'sh -c "echo ok"');
  final unameOk = _runBashTest(gitBashPath, 'uname');
  final sedOk = _runBashTest(gitBashPath, 'sed --version');

  bool compilerOk = false;
  if (report.compiler != null) {
    final posixCompiler = translateToPosixPath(report.compiler!.replaceAll('.cmd', '').replaceAll('android21', 'android24'));
    compilerOk = _runBashTest(gitBashPath, '$posixCompiler --version');
  }

  return projectOk && gitSourceOk && zlibOk && perlOk && shOk && unameOk && sedOk && compilerOk;
}

bool _runBashTest(String gitBashPath, String command) {
  try {
    final result = Process.runSync(gitBashPath, ['-c', command]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

String? _detectGitBashPath() {
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

bool _detectWsl() {
  final wslFile = File('C:\\Windows\\System32\\wsl.exe');
  if (wslFile.existsSync()) return true;
  try {
    final result = Process.runSync('wsl', ['--status']);
    return result.exitCode == 0;
  } catch (_) {}
  return false;
}

String? _projectRoot(List<String> args) {
  final idx = args.indexOf('--project-root');
  if (idx != -1 && idx + 1 < args.length) return args[idx + 1];
  return null;
}
