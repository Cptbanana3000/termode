import 'dart:convert';
import 'dart:io';

import 'sha256_helper.dart';

const _abi = 'arm64-v8a';
const _gitVersion = '2.44.0';
const _zlibVersion = '1.3.1';
const _expectedGitBytes = 5463168;
const _expectedGitSha =
    '4a4883d3e0b18dc082ac99cdb3da5d80e2b988e2a801b418b0bebfe855a467e1';
const _executablePackageName = 'libtermode_git_exec.so';
const _gitSourceSha =
    'e358738dcb5b5ea340ce900a0015c03ae86e804e7ff64e47aa4631ddee681de3';
const _zlibSourceSha =
    '38ef96b8dfe510d42707d9c781877914792541133e1870841463bfa73f883e32';
const _zlibOutputSha =
    'a24daf30f67d09b7e9c080cf87c8e36ba5056ade11f0609e4883e657d13d277a';

Never _fail(String message) {
  stderr.writeln('=== Git Runtime Artifact Packaging ===');
  stderr.writeln('Build output: INVALID');
  stderr.writeln('Reason: $message');
  stderr.writeln('Runtime artifact: UNAVAILABLE');
  exitCode = 1;
  throw const FormatException('packaging refused');
}

void main(List<String> arguments) {
  final sourcePath = arguments.isEmpty
      ? 'tools/git-build/output/arm64-v8a/git/bin/git'
      : arguments.first;
  final artifactRoot = arguments.length < 2
      ? 'tools/runtime-artifacts/git/arm64-v8a'
      : arguments[1];
  final nativeExecutablePath = arguments.length >= 3
      ? arguments[2]
      : (arguments.isEmpty
            ? 'android/app/src/main/jniLibs/arm64-v8a/$_executablePackageName'
            : '$artifactRoot/android-native/arm64-v8a/$_executablePackageName');
  final source = File(sourcePath);
  try {
    if (!source.existsSync()) _fail('Git binary is missing: $sourcePath');
    final bytes = source.readAsBytesSync();
    if (bytes.isEmpty) _fail('Git binary is zero bytes.');
    if (bytes.length != _expectedGitBytes) {
      _fail('Git binary byte count mismatch.');
    }
    final sha = calculateSha256(bytes);
    if (sha != _expectedGitSha) _fail('Git binary checksum mismatch ($sha).');
    if (bytes.length < 4 ||
        bytes[0] != 0x7f ||
        bytes[1] != 0x45 ||
        bytes[2] != 0x4c ||
        bytes[3] != 0x46) {
      _fail('Git output is not an ELF executable (scripts are refused).');
    }

    final destination = File('$artifactRoot/files/usr/bin/git');
    destination.parent.createSync(recursive: true);
    source.copySync(destination.path);
    final copied = destination.readAsBytesSync();
    if (copied.length != _expectedGitBytes ||
        calculateSha256(copied) != _expectedGitSha) {
      destination.deleteSync();
      _fail('Copied artifact failed byte-count/checksum verification.');
    }

    final nativeExecutable = File(nativeExecutablePath);
    nativeExecutable.parent.createSync(recursive: true);
    source.copySync(nativeExecutable.path);
    final nativeBytes = nativeExecutable.readAsBytesSync();
    if (nativeBytes.length != _expectedGitBytes ||
        calculateSha256(nativeBytes) != _expectedGitSha) {
      nativeExecutable.deleteSync();
      _fail('Packaged native executable failed checksum verification.');
    }

    final manifest = <String, dynamic>{
      'name': 'git',
      'version': _gitVersion,
      'termode_milestone': 'v0.64',
      'kind': 'native-tool',
      'abi': _abi,
      'command': 'git',
      'entrypoint': 'usr/bin/git',
      'install_target': 'usr/bin/git',
      'logical_install_path': 'usr/bin/git',
      'executable_strategy': 'native-library-dir',
      'executable_package_name': _executablePackageName,
      'original_binary_sha256': _expectedGitSha,
      'packaged_executable_sha256': _expectedGitSha,
      'execution_policy_note':
          'Logical prefix mapping only; execute the immutable APK payload from applicationInfo.nativeLibraryDir.',
      'local_only': true,
      'remote_features_deferred': true,
      'source': 'termode-built',
      'source_url':
          'https://mirrors.edge.kernel.org/pub/software/scm/git/git-2.44.0.tar.xz',
      'source_git_version': _gitVersion,
      'source_archive_sha256': _gitSourceSha,
      'zlib_version': _zlibVersion,
      'zlib_archive_sha256': _zlibSourceSha,
      'zlib_output_sha256': _zlibOutputSha,
      'build_mode': 'minimal-local',
      'build_method': 'reproducible-android-ndk-git-bash-build',
      'license': 'GPL-2.0-only',
      'created_by': 'Termode host build pipeline',
      'trusted_by': 'local developer verification',
      'candidate': false,
      'template_only': false,
      'disabled_or_deferred_features': [
        'OpenSSL',
        'curl',
        'HTTPS remotes',
        'SSH remotes',
        'credential helpers',
        'Git LFS',
        'submodules',
      ],
      'supported_initial_commands': ['git --version', 'git init', 'git status'],
      'verification_command': 'git --version',
      'smoke_tests': ['git --version', 'git init', 'git status'],
      'dependencies': [
        {
          'name': 'zlib',
          'version': _zlibVersion,
          'linkage': 'static',
          'sha256': _zlibOutputSha,
        },
      ],
      'created_at': '2026-09-01T00:00:00Z',
      'files': [
        {
          'path': 'usr/bin/git',
          'sha256': _expectedGitSha,
          'bytes': _expectedGitBytes,
        },
      ],
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(manifest);
    File('$artifactRoot/manifest.json').writeAsStringSync('$encoded\n');

    stdout.writeln('=== Git Runtime Artifact Packaging ===');
    stdout.writeln('Build output: VERIFIED');
    stdout.writeln('ABI: $_abi');
    stdout.writeln('Package: git');
    stdout.writeln('Version: $_gitVersion');
    stdout.writeln('Manifest: written');
    stdout.writeln('Files: copied');
    stdout.writeln('Executable strategy: native-library-dir');
    stdout.writeln('Native executable: $nativeExecutablePath');
    stdout.writeln('Runtime artifact: AVAILABLE');
    stdout.writeln('Install status: not installed');
    stdout.writeln(
      'Next: install with runtime-pkg and run on-device smoke tests.',
    );
  } on FormatException catch (error) {
    if (error.message != 'packaging refused') rethrow;
  }
}
