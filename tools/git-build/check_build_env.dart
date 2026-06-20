import 'dart:io';

const gitBuildTargetAbi = 'arm64-v8a';

class GitBuildEnvironment {
  const GitBuildEnvironment({
    required this.hostOs,
    required this.androidSdk,
    required this.androidNdk,
    required this.ndkVersion,
    required this.shell,
    required this.compiler,
    required this.cmake,
    required this.make,
    required this.perl,
    required this.archiveTool,
    required this.gitSourcePresent,
    required this.dependenciesPresent,
    required this.outputWritable,
  });

  final String hostOs;
  final String? androidSdk;
  final String? androidNdk;
  final String ndkVersion;
  final String? shell;
  final String? compiler;
  final String? cmake;
  final String? make;
  final String? perl;
  final String? archiveTool;
  final bool gitSourcePresent;
  final bool dependenciesPresent;
  final bool outputWritable;

  bool get toolchainPresent => androidNdk != null && compiler != null;

  bool get ready =>
      androidSdk != null &&
      toolchainPresent &&
      shell != null &&
      make != null &&
      perl != null &&
      archiveTool != null &&
      gitSourcePresent &&
      dependenciesPresent &&
      outputWritable;

  String get overall {
    if (ready) return 'READY';
    if (androidSdk != null || androidNdk != null || compiler != null) {
      return 'PARTIAL';
    }
    return 'NOT READY';
  }

  List<String> get blockers {
    final result = <String>[];
    if (androidSdk == null) result.add('Android SDK');
    if (androidNdk == null) result.add('Android NDK');
    if (compiler == null) result.add('arm64 Android compiler');
    if (shell == null) result.add('host shell');
    if (make == null) result.add('make');
    if (perl == null) result.add('Perl');
    if (archiveTool == null) result.add('tar/unzip tool');
    if (!gitSourcePresent) result.add('trusted Git source');
    if (!dependenciesPresent) result.add('dependency sources');
    if (!outputWritable) result.add('writable output directory');
    return result;
  }

  String format() {
    String status(String? value) =>
        value == null ? 'missing' : 'found ($value)';
    return '=== Git Build Environment ===\n'
        'Host OS: $hostOs\n'
        'Android SDK: ${status(androidSdk)}\n'
        'Android NDK: ${status(androidNdk)}\n'
        'NDK version: $ndkVersion\n'
        'Target ABI: $gitBuildTargetAbi\n'
        'Shell: ${status(shell)}\n'
        'C compiler: ${status(compiler)}\n'
        'CMake: ${status(cmake)}\n'
        'Make: ${status(make)}\n'
        'Perl: ${status(perl)}\n'
        'Tar/unzip: ${status(archiveTool)}\n'
        'Git source: ${gitSourcePresent ? 'found' : 'missing'}\n'
        'Dependencies: ${dependenciesPresent ? 'found' : 'missing'}\n'
        'Output dir: ${outputWritable ? 'writable' : 'not writable'}\n'
        'Overall: $overall';
  }
}

GitBuildEnvironment detectGitBuildEnvironment({
  String? projectRoot,
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final root = Directory(projectRoot ?? Directory.current.path).absolute;
  final sdk = _findAndroidSdk(env);
  final ndk = _findAndroidNdk(env, sdk);
  final hostTag = Platform.isWindows
      ? 'windows-x86_64'
      : Platform.isMacOS
      ? 'darwin-x86_64'
      : 'linux-x86_64';
  final executableSuffix = Platform.isWindows ? '.exe' : '';
  final commandSuffix = Platform.isWindows ? '.cmd' : '';
  final ndkCompiler = ndk == null
      ? null
      : _firstExisting([
          for (var api = 21; api <= 35; api++)
            '${ndk.path}/toolchains/llvm/prebuilt/$hostTag/bin/'
                'aarch64-linux-android$api-clang$commandSuffix',
        ]);
  final ndkMake = ndk == null
      ? null
      : _firstExisting([
          '${ndk.path}/prebuilt/$hostTag/bin/make$executableSuffix',
        ]);
  final sdkCmake = sdk == null ? null : _findSdkCmake(sdk);
  final output = Directory('${root.path}/tools/git-build/output');

  return GitBuildEnvironment(
    hostOs: Platform.operatingSystem,
    androidSdk: sdk?.path,
    androidNdk: ndk?.path,
    ndkVersion: ndk == null ? 'unknown' : _ndkVersion(ndk),
    shell: _findExecutable(Platform.isWindows ? 'powershell' : 'sh', env),
    compiler: ndkCompiler ?? _findExecutable('clang', env),
    cmake: sdkCmake ?? _findExecutable('cmake', env),
    make: ndkMake ?? _findExecutable('make', env),
    perl: _findExecutable('perl', env),
    archiveTool: _findExecutable('tar', env) ?? _findExecutable('unzip', env),
    gitSourcePresent: _hasGitSource(
      Directory('${root.path}/tools/git-build/sources/git'),
    ),
    dependenciesPresent: _hasDependencySources(
      Directory('${root.path}/tools/git-build/deps'),
    ),
    outputWritable: _isWritable(output),
  );
}

Directory? _findAndroidSdk(Map<String, String> env) {
  final candidates = <String?>[
    env['ANDROID_SDK_ROOT'],
    env['ANDROID_HOME'],
    if (Platform.isWindows && env['LOCALAPPDATA'] != null)
      '${env['LOCALAPPDATA']}/Android/Sdk',
    if (Platform.isMacOS && env['HOME'] != null)
      '${env['HOME']}/Library/Android/sdk',
    if (!Platform.isWindows && !Platform.isMacOS && env['HOME'] != null)
      '${env['HOME']}/Android/Sdk',
  ];
  for (final candidate in candidates) {
    if (candidate == null || candidate.trim().isEmpty) continue;
    final directory = Directory(candidate);
    if (directory.existsSync()) return directory.absolute;
  }
  return null;
}

Directory? _findAndroidNdk(Map<String, String> env, Directory? sdk) {
  for (final key in ['ANDROID_NDK_ROOT', 'ANDROID_NDK_HOME']) {
    final value = env[key];
    if (value != null && Directory(value).existsSync()) {
      return Directory(value).absolute;
    }
  }
  if (sdk == null) return null;
  final ndkRoot = Directory('${sdk.path}/ndk');
  if (!ndkRoot.existsSync()) return null;
  final versions = ndkRoot.listSync().whereType<Directory>().toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  return versions.isEmpty ? null : versions.first.absolute;
}

String _ndkVersion(Directory ndk) {
  final properties = File('${ndk.path}/source.properties');
  if (properties.existsSync()) {
    final match = RegExp(
      r'^Pkg\.Revision\s*=\s*(.+)$',
      multiLine: true,
    ).firstMatch(properties.readAsStringSync());
    if (match != null) return match.group(1)!.trim();
  }
  return ndk.uri.pathSegments.where((part) => part.isNotEmpty).last;
}

String? _findSdkCmake(Directory sdk) {
  final root = Directory('${sdk.path}/cmake');
  if (!root.existsSync()) return null;
  final versions = root.listSync().whereType<Directory>().toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  for (final version in versions) {
    final candidate =
        '${version.path}/bin/cmake${Platform.isWindows ? '.exe' : ''}';
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}

String? _findExecutable(String name, Map<String, String> env) {
  final path = env['PATH'] ?? env['Path'] ?? '';
  final suffixes = Platform.isWindows ? ['', '.exe', '.cmd', '.bat'] : [''];
  for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
    if (directory.trim().isEmpty) continue;
    for (final suffix in suffixes) {
      final candidate = File('$directory/$name$suffix');
      if (candidate.existsSync()) return candidate.absolute.path;
    }
  }
  return null;
}

String? _firstExisting(List<String> candidates) {
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}

bool _hasGitSource(Directory directory) {
  return File('${directory.path}/Makefile').existsSync() &&
      File('${directory.path}/git.c').existsSync();
}

bool _hasDependencySources(Directory directory) {
  if (!directory.existsSync()) return false;
  return directory.listSync().any((entity) {
    final name = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
    return name.toLowerCase() != 'readme.md';
  });
}

bool _isWritable(Directory directory) {
  try {
    directory.createSync(recursive: true);
    final probe = File('${directory.path}/.termode-write-$pid.tmp');
    probe.writeAsStringSync('probe');
    probe.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

void main(List<String> args) {
  String? root;
  if (args.length == 2 && args[0] == '--project-root') root = args[1];
  final report = detectGitBuildEnvironment(projectRoot: root);
  stdout.writeln(report.format());
  if (!report.ready) {
    stdout.writeln('Missing: ${report.blockers.join(', ')}');
    exitCode = report.overall == 'PARTIAL' ? 2 : 1;
  }
}
