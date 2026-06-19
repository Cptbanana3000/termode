import 'dart:convert';
import 'dart:io';

import 'sha256_helper.dart';

String filesRootPath(String abi) => 'tools/runtime-artifacts/git/$abi/files';

void main(List<String> args) {
  final abi = args.isNotEmpty ? args[0] : 'arm64-v8a';
  final filesRoot = Directory(filesRootPath(abi));
  if (!filesRoot.existsSync()) {
    stderr.writeln('Missing files directory: ${filesRoot.path}');
    exitCode = 66;
    return;
  }
  final files = <Map<String, Object>>[];
  for (final entity in filesRoot.listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = entity.path
        .substring(filesRoot.path.length + 1)
        .replaceAll('\\', '/');
    if (!_isArtifactPayloadPath(rel)) continue;
    if (entity.lengthSync() <= 0) {
      stderr.writeln('Skipping zero-byte payload candidate: $rel');
      continue;
    }
    files.add({
      'path': rel,
      'sha256': calculateSha256(entity.readAsBytesSync()),
      'bytes': entity.lengthSync(),
    });
  }
  files.sort((a, b) => a['path'].toString().compareTo(b['path'].toString()));
  final manifest = {
    'name': 'git',
    'version': 'REPLACE_WITH_REAL_GIT_VERSION',
    'kind': 'native-tool',
    'abi': abi,
    'command': 'git',
    'entrypoint': 'bin/git',
    'files': files,
    'source': 'termode-built',
    'source_note': 'REPLACE_WITH_AUDITABLE_SOURCE_AND_CHECKSUM',
    'build_method': 'REPLACE_WITH_REPRODUCIBLE_BUILD_NOTES',
    'license': 'GPL-2.0-only',
    'trusted_by': 'Termode',
    'verification_command': 'git --version',
    'smoke_tests': ['git --version', 'git init', 'git status'],
    'dependencies': <String>[],
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(manifest));
  if (files.isEmpty) {
    stderr.writeln(
      'No artifact payload files found. Add real bin/, lib/, libexec/, or '
      'share/ contents before treating this manifest as installable.',
    );
    exitCode = 1;
  }
}

bool _isArtifactPayloadPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.startsWith('bin/') ||
      normalized.startsWith('lib/') ||
      normalized.startsWith('libexec/') ||
      normalized.startsWith('share/');
}
