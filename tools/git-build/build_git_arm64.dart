import 'dart:io';

import 'build_inputs.dart';
import 'check_build_env.dart';
import 'sha256_helper.dart';

void main(List<String> args) {
  final isBuild = args.contains('--build');
  final isDryRun = args.contains('--dry-run') || !isBuild;
  final rootPath = _projectRoot(args);
  final root = Directory(rootPath ?? Directory.current.path).absolute;

  final report = detectGitBuildEnvironment(projectRoot: root.path);
  final inputs = loadAndValidateBuildInputs(projectRoot: root.path);

  if (isDryRun) {
    stdout.writeln('=== Git arm64-v8a Build Preflight ===');
    stdout.writeln('Running dry-run check...');
    if (!report.ready || !inputs.valid) {
      final blockers = <String>{...report.blockers, ...inputs.errors}.toList();
      stderr.writeln('Cannot start Git arm64 build.');
      stderr.writeln('Missing: ${blockers.join(', ')}');
      exitCode = 1;
      return;
    }
    stdout.writeln('Build prerequisites are ready.');
    stdout.writeln('Next: run dart tools/git-build/build_git_arm64.dart --build to attempt the real build.');
    return;
  }

  // Real build attempt
  stdout.writeln('=== Git arm64-v8a Build Attempt ===');
  
  final gitSourceReady = report.gitSourcePresent ? 'READY' : 'MISSING';
  final zlibReady = report.dependenciesPresent ? 'READY' : 'MISSING';
  final inputsReady = inputs.valid ? 'READY' : 'INVALID';
  final ndkReady = report.androidNdk != null ? 'READY' : 'MISSING';
  final perlReady = report.perl != null ? 'READY' : 'MISSING';

  stdout.writeln('Git source: $gitSourceReady');
  stdout.writeln('zlib: $zlibReady');
  stdout.writeln('build-inputs.json: $inputsReady');
  stdout.writeln('NDK: $ndkReady');
  stdout.writeln('Perl: $perlReady');

  if (!report.ready || !inputs.valid) {
    final blockers = <String>{...report.blockers, ...inputs.errors}.toList();
    stderr.writeln('Cannot start Git arm64 build.');
    stderr.writeln('Missing: ${blockers.join(', ')}');
    exitCode = 1;
    return;
  }

  stdout.writeln('Starting controlled arm64-v8a build...');

  // Setup directories
  final outputDir = Directory('${root.path}/tools/git-build/output');
  final logsDir = Directory('${root.path}/tools/git-build/logs');
  final workspaceDir = Directory('${root.path}/tools/git-build/output/workspace');
  final zlibOutputDir = Directory('${root.path}/tools/git-build/output/arm64-v8a/zlib');
  final gitOutputDir = Directory('${root.path}/tools/git-build/output/arm64-v8a/git');

  outputDir.createSync(recursive: true);
  logsDir.createSync(recursive: true);
  workspaceDir.createSync(recursive: true);
  zlibOutputDir.createSync(recursive: true);
  gitOutputDir.createSync(recursive: true);

  final zlibLogFile = File('${logsDir.path}/zlib-arm64-build.log');
  final gitLogFile = File('${logsDir.path}/git-arm64-build.log');

  zlibLogFile.writeAsStringSync('=== zlib 1.3.1 Build Log ===\n');
  gitLogFile.writeAsStringSync('=== Git 2.44.0 Build Log ===\n');

  // Verify zlib SHA-256
  final zlibArchive = File('${root.path}/tools/git-build/sources/zlib-1.3.1.tar.xz');
  final zlibExpectedHash = '38ef96b8dfe510d42707d9c781877914792541133e1870841463bfa73f883e32';
  stdout.writeln('Verifying zlib-1.3.1.tar.xz checksum...');
  final zlibBytes = zlibArchive.readAsBytesSync();
  final zlibActualHash = calculateSha256(zlibBytes);
  if (zlibActualHash.toLowerCase() != zlibExpectedHash.toLowerCase()) {
    stderr.writeln('zlib SHA-256 mismatch! Expected $zlibExpectedHash, got $zlibActualHash');
    exitCode = 1;
    return;
  }

  // Extract zlib
  stdout.writeln('Extracting zlib source...');
  final zlibWorkspace = Directory('${workspaceDir.path}/zlib');
  if (zlibWorkspace.existsSync()) zlibWorkspace.deleteSync(recursive: true);
  zlibWorkspace.createSync(recursive: true);

  final zlibExtractResult = Process.runSync(
    report.archiveTool!,
    ['-xf', zlibArchive.path, '-C', zlibWorkspace.path],
  );
  zlibLogFile.writeAsStringSync(
    'Extraction stdout:\n${zlibExtractResult.stdout}\nExtraction stderr:\n${zlibExtractResult.stderr}\n',
    mode: FileMode.append,
  );

  if (zlibExtractResult.exitCode != 0) {
    stderr.writeln('zlib extraction failed.');
    exitCode = 1;
    return;
  }

  // Build zlib using CMake
  stdout.writeln('Configuring and building zlib...');
  final zlibSrcDir = '${zlibWorkspace.path}/zlib-1.3.1';
  final zlibBuildDir = '${zlibWorkspace.path}/build';
  Directory(zlibBuildDir).createSync(recursive: true);

  final cmakeConfigResult = Process.runSync(
    report.cmake!,
    [
      '-S', zlibSrcDir,
      '-B', zlibBuildDir,
      '-DCMAKE_TOOLCHAIN_FILE=${report.androidNdk}/build/cmake/android.toolchain.cmake',
      '-DANDROID_ABI=arm64-v8a',
      '-DANDROID_PLATFORM=android-24',
      '-GUnix Makefiles',
      '-DCMAKE_MAKE_PROGRAM=${report.make}',
      '-DCMAKE_INSTALL_PREFIX=${zlibOutputDir.path}',
    ],
  );

  zlibLogFile.writeAsStringSync(
    '=== CMake Configure stdout ===\n${cmakeConfigResult.stdout}\n=== CMake Configure stderr ===\n${cmakeConfigResult.stderr}\n',
    mode: FileMode.append,
  );

  if (cmakeConfigResult.exitCode != 0) {
    stderr.writeln('zlib CMake configuration failed. Check ${zlibLogFile.path} for details.');
    exitCode = 1;
    return;
  }

  final cmakeBuildResult = Process.runSync(
    report.cmake!,
    [
      '--build', zlibBuildDir,
      '--target', 'install',
    ],
  );

  zlibLogFile.writeAsStringSync(
    '=== CMake Build stdout ===\n${cmakeBuildResult.stdout}\n=== CMake Build stderr ===\n${cmakeBuildResult.stderr}\n',
    mode: FileMode.append,
  );

  if (cmakeBuildResult.exitCode != 0) {
    stderr.writeln('zlib CMake build/install failed. Check ${zlibLogFile.path} for details.');
    exitCode = 1;
    return;
  }

  final libzPath = '${zlibOutputDir.path}/lib/libz.a';
  if (!File(libzPath).existsSync()) {
    stderr.writeln('zlib build succeeded but libz.a was not found at $libzPath');
    exitCode = 1;
    return;
  }
  stdout.writeln('zlib build succeeded. Output installed at: $libzPath');

  // Verify Git SHA-256
  final gitArchive = File('${root.path}/tools/git-build/sources/git-2.44.0.tar.xz');
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
  final gitWorkspace = Directory('${workspaceDir.path}/git');
  if (gitWorkspace.existsSync()) gitWorkspace.deleteSync(recursive: true);
  gitWorkspace.createSync(recursive: true);

  final gitExtractResult = Process.runSync(
    report.archiveTool!,
    ['-xf', gitArchive.path, '-C', gitWorkspace.path],
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

  // Attempt to build Git
  stdout.writeln('Attempting Git build for Android arm64-v8a...');
  final gitSrcDir = '${gitWorkspace.path}/git-2.44.0';
  final sysroot = '${report.androidNdk}/toolchains/llvm/prebuilt/windows-x86_64/sysroot';

  final makeResult = Process.runSync(
    report.make!,
    [
      '-C', gitSrcDir,
      'CC=${report.compiler}',
      'CFLAGS=--sysroot=$sysroot -target aarch64-linux-android24 -I${zlibOutputDir.path}/include',
      'LDFLAGS=-L${zlibOutputDir.path}/lib',
      'git',
    ],
  );

  final combinedLogs = '=== Make Build stdout ===\n${makeResult.stdout}\n=== Make Build stderr ===\n${makeResult.stderr}\n';
  gitLogFile.writeAsStringSync(combinedLogs, mode: FileMode.append);

  final failureCategory = _classifyFailure(combinedLogs);
  stderr.writeln('Git build failed as expected.');
  stderr.writeln('Failure Category: $failureCategory');
  stderr.writeln('For full logs, see: tools/git-build/logs/git-arm64-build.log');
  exitCode = 1;
}

String _classifyFailure(String output) {
  final lower = output.toLowerCase();
  if (lower.contains('configure: error') || lower.contains('configure failed')) {
    return 'configure failure';
  }
  if (lower.contains('clang: error') || lower.contains('compiler error') || (lower.contains('error:') && lower.contains('.c:'))) {
    return 'compiler failure';
  }
  if (lower.contains('ld: error') || lower.contains('linker error') || lower.contains('undefined reference')) {
    return 'linker failure';
  }
  if (lower.contains('fatal error:') && lower.contains('.h: no such file')) {
    return 'missing header/library';
  }
  if (lower.contains('zlib.h') || lower.contains('zlib integration')) {
    return 'zlib integration failure';
  }
  if (lower.contains('perl') && (lower.contains('not found') || lower.contains('error'))) {
    return 'Perl/build script failure';
  }
  if (lower.contains('unsupported target') || lower.contains('unsupported android')) {
    return 'unsupported Android target issue';
  }
  if (lower.contains('not recognized as an internal or external command') ||
      lower.contains('spawn') ||
      lower.contains('cannot find the path specified') ||
      lower.contains('/bin/sh') ||
      lower.contains('process_begin') ||
      lower.contains('missing separator') ||
      lower.contains('no such file or directory') ||
      lower.contains('target pattern contains no')) {
    return 'Windows shell/path issue';
  }
  return 'unknown failure';
}

String? _projectRoot(List<String> args) {
  final idx = args.indexOf('--project-root');
  if (idx != -1 && idx + 1 < args.length) return args[idx + 1];
  return null;
}
