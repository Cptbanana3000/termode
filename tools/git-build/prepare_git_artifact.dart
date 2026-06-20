import 'dart:convert';
import 'dart:io';

import 'sha256_helper.dart';

String filesRootPath(String abi) => 'tools/runtime-artifacts/git/$abi/files';

String candidateManifestPath(String abi) =>
    'tools/runtime-artifacts/git/$abi/manifest.candidate.json';

void main(List<String> args) {
  final abi = args.isNotEmpty ? args[0] : 'arm64-v8a';
  final stagedOutput = args.length > 1 ? Directory(args[1]) : null;
  final filesRoot = Directory(filesRootPath(abi));
  if (stagedOutput != null) {
    final stagedFiles = _validatedStagedFiles(stagedOutput);
    if (stagedFiles == null) return;
    filesRoot.createSync(recursive: true);
    for (final staged in stagedFiles) {
      final relative = _relativePath(stagedOutput, staged);
      final destination = File('${filesRoot.path}/$relative');
      if (destination.existsSync() &&
          calculateSha256(destination.readAsBytesSync()) !=
              calculateSha256(staged.readAsBytesSync())) {
        stderr.writeln(
          'Refusing to overwrite different artifact payload: $relative',
        );
        exitCode = 73;
        return;
      }
      destination.parent.createSync(recursive: true);
      staged.copySync(destination.path);
    }
  } else if (!filesRoot.existsSync()) {
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
    'version':
        Platform.environment['TERMODE_GIT_VERSION'] ??
        'REPLACE_WITH_REAL_GIT_VERSION',
    'kind': 'native-tool',
    'abi': abi,
    'command': 'git',
    'entrypoint': 'bin/git',
    'files': files,
    'source': 'termode-built',
    'source_note':
        Platform.environment['TERMODE_GIT_SOURCE_NOTE'] ??
        'REPLACE_WITH_AUDITABLE_SOURCE_AND_CHECKSUM',
    'build_method':
        Platform.environment['TERMODE_GIT_BUILD_METHOD'] ??
        'REPLACE_WITH_REPRODUCIBLE_BUILD_NOTES',
    'license': 'GPL-2.0-only',
    'trusted_by': 'Termode',
    'verification_command': 'git --version',
    'smoke_tests': ['git --version', 'git init', 'git status'],
    'dependencies': (Platform.environment['TERMODE_GIT_DEPENDENCIES'] ?? '')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(),
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(manifest));
  if (files.isEmpty) {
    stderr.writeln(
      'No artifact payload files found. Add real bin/, lib/, libexec/, or '
      'share/ contents before treating this manifest as installable.',
    );
    exitCode = 1;
    return;
  }
  if (stagedOutput != null) {
    final candidate = File(candidateManifestPath(abi));
    candidate.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
    stdout.writeln('Wrote non-installable candidate: ${candidate.path}');
    stdout.writeln(
      'Review metadata, then promote to manifest.json only after validation.',
    );
  }
}

List<File>? _validatedStagedFiles(Directory stagedOutput) {
  if (!stagedOutput.existsSync()) {
    stderr.writeln('Missing staged build output: ${stagedOutput.path}');
    exitCode = 66;
    return null;
  }
  final entities = stagedOutput.listSync(recursive: true);
  if (entities.any((entity) => entity is Link)) {
    stderr.writeln('Rejected symbolic link in staged build output.');
    exitCode = 65;
    return null;
  }
  final files = entities.whereType<File>().toList();
  if (files.isEmpty) {
    stderr.writeln(
      'Staged build output contains no files: ${stagedOutput.path}',
    );
    exitCode = 66;
    return null;
  }
  for (final file in files) {
    final relative = _relativePath(stagedOutput, file);
    if (!_isSafeArtifactPayloadPath(relative)) {
      stderr.writeln('Rejected unsafe or unsupported staged path: $relative');
      exitCode = 65;
      return null;
    }
    if (file.lengthSync() <= 0) {
      stderr.writeln('Rejected zero-byte staged payload: $relative');
      exitCode = 65;
      return null;
    }
  }
  return files;
}

String _relativePath(Directory root, File file) => file.absolute.path
    .substring(root.absolute.path.length + 1)
    .replaceAll('\\', '/');

bool _isSafeArtifactPayloadPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.isEmpty || normalized.startsWith('/')) return false;
  if (RegExp(r'^[A-Za-z]:').hasMatch(normalized)) return false;
  final segments = normalized.split('/');
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    return false;
  }
  if (segments.any(
    (segment) => !RegExp(r'^[A-Za-z0-9._+@-]+$').hasMatch(segment),
  )) {
    return false;
  }
  return _isArtifactPayloadPath(normalized);
}

bool _isArtifactPayloadPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.startsWith('bin/') ||
      normalized.startsWith('lib/') ||
      normalized.startsWith('libexec/') ||
      normalized.startsWith('share/');
}
