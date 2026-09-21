import 'dart:io';

import 'sha256_helper.dart';

void main(List<String> args) {
  final idx = args.indexOf('--project-root');
  final rootPath = (idx != -1 && idx + 1 < args.length)
      ? args[idx + 1]
      : Directory.current.path;
  final root = Directory(rootPath).absolute;

  stdout.writeln('=== Git arm64 Build Output Verification ===');

  final zlibLibDir = Directory(
    '${root.path}/tools/git-build/output/arm64-v8a/zlib/lib',
  );
  final libzFile = File('${zlibLibDir.path}/libz.a');

  bool zlibOk = false;
  if (!libzFile.existsSync()) {
    stdout.writeln('zlib output: MISSING (libz.a not found)');
  } else {
    final bytes = libzFile.readAsBytesSync();
    if (bytes.isEmpty) {
      stdout.writeln('zlib output: INVALID (libz.a is empty)');
    } else {
      final contentStr = String.fromCharCodes(bytes.take(200));
      if (contentStr.contains('placeholder') || contentStr.contains('fake')) {
        stdout.writeln(
          'zlib output: REFUSED (placeholder or fake output detected)',
        );
      } else {
        final sha = calculateSha256(bytes);
        stdout.writeln('zlib output: VERIFIED');
        stdout.writeln(
          '  Path: tools/git-build/output/arm64-v8a/zlib/lib/libz.a',
        );
        stdout.writeln('  Size: ${bytes.length} bytes');
        stdout.writeln('  SHA-256: $sha');
        zlibOk = true;
      }
    }
  }

  // This verifier is read-only. Packaging is handled by package_git_artifact.
  final gitBinDir = Directory(
    '${root.path}/tools/git-build/output/arm64-v8a/git/bin',
  );
  final gitFile = File('${gitBinDir.path}/git');
  if (!gitFile.existsSync()) {
    stdout.writeln('Git output: MISSING (git binary not found)');
  } else {
    final bytes = gitFile.readAsBytesSync();
    final contentStr = String.fromCharCodes(bytes.take(200));
    if (contentStr.contains('placeholder') || contentStr.contains('fake')) {
      stdout.writeln(
        'Git output: REFUSED (placeholder or fake output detected)',
      );
    } else {
      final sha = calculateSha256(bytes);
      stdout.writeln('Git output: VERIFIED');
      stdout.writeln('  Path: tools/git-build/output/arm64-v8a/git/bin/git');
      stdout.writeln('  Size: ${bytes.length} bytes');
      stdout.writeln('  SHA-256: $sha');
    }
  }

  final manifest = File(
    '${root.path}/tools/runtime-artifacts/git/arm64-v8a/manifest.json',
  );
  stdout.writeln(
    'Runtime Artifact Status: ${manifest.existsSync() ? 'PACKAGED' : 'UNAVAILABLE'}',
  );
  stdout.writeln(
    'Note: Build-output verification is read-only; run package_git_artifact.dart '
    'to create or refresh the runtime artifact.',
  );

  if (!zlibOk) {
    exitCode = 1;
  }
}
