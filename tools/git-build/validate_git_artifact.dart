import 'dart:convert';
import 'dart:io';

import 'sha256_helper.dart';

const supportedAbis = {'arm64-v8a', 'armeabi-v7a', 'x86_64'};
const trustedSources = {'termode-built', 'termode-vendored'};

String manifestPath(String abi) =>
    'tools/runtime-artifacts/git/$abi/manifest.json';

String filesRootPath(String abi) => 'tools/runtime-artifacts/git/$abi/files';

void main(List<String> args) {
  final abi = args.isNotEmpty ? args[0] : 'arm64-v8a';
  final manifestFile = File(manifestPath(abi));
  if (!manifestFile.existsSync()) {
    stderr.writeln('Missing manifest: ${manifestFile.path}');
    exitCode = 66;
    return;
  }
  final decoded = jsonDecode(manifestFile.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    stderr.writeln('Manifest is not a JSON object.');
    exitCode = 65;
    return;
  }
  final errors = validateProjectGitArtifact(decoded, abi);
  if (errors.isEmpty) {
    stdout.writeln('Git artifact candidate is valid for $abi.');
    return;
  }
  stderr.writeln('Git artifact candidate is invalid:');
  for (final error in errors) {
    stderr.writeln('- $error');
  }
  exitCode = 1;
}

List<String> validateProjectGitArtifact(
  Map<String, dynamic> manifest,
  String currentAbi,
) {
  final errors = validateGitManifest(manifest, currentAbi);
  if (errors.isNotEmpty) return errors;
  final abi = manifest['abi']?.toString() ?? currentAbi;
  final filesRoot = Directory(filesRootPath(abi == 'all' ? currentAbi : abi));
  if (!filesRoot.existsSync()) {
    return ['artifact files directory missing: ${filesRoot.path}'];
  }
  final root = filesRoot.absolute.path.replaceAll('\\', '/');
  for (final item in manifest['files'] as List) {
    final fileEntry = item as Map;
    final relPath = fileEntry['path'].toString();
    final expected = fileEntry['sha256'].toString();
    final file = File('${filesRoot.path}/$relPath');
    final normalized = file.absolute.path.replaceAll('\\', '/');
    if (!normalized.startsWith('$root/')) return ['unsafe file path: $relPath'];
    if (!file.existsSync()) return ['missing artifact file: $relPath'];
    final expectedBytes = fileEntry['bytes'];
    if (expectedBytes is int && file.lengthSync() != expectedBytes) {
      return ['byte count mismatch: $relPath'];
    }
    final actual = calculateSha256(file.readAsBytesSync());
    if (actual.toLowerCase() != expected.toLowerCase()) {
      return ['checksum mismatch: $relPath'];
    }
  }
  return const [];
}

List<String> validateGitManifest(
  Map<String, dynamic> manifest,
  String currentAbi,
) {
  final errors = <String>[];
  final abi = manifest['abi']?.toString() ?? '';
  final source = manifest['source']?.toString() ?? '';
  final sourceUrl = manifest['source_url']?.toString() ?? '';
  final sourceNote = manifest['source_note']?.toString() ?? '';
  final files = manifest['files'];
  if (manifest['name'] != 'git') errors.add('package name must be git');
  if (manifest['kind'] != 'native-tool') errors.add('kind must be native-tool');
  if (manifest['command'] != 'git') errors.add('command must be git');
  if (abi != 'all' && !supportedAbis.contains(abi)) {
    errors.add('unsupported abi');
  }
  if (abi != 'all' && abi != currentAbi) errors.add('abi mismatch');
  if (!trustedSources.contains(source)) errors.add('unknown/untrusted source');
  if (sourceUrl.trim().isEmpty && sourceNote.trim().isEmpty) {
    errors.add('missing source_url or source_note');
  }
  if (!_isSafeRelativePath(manifest['entrypoint']?.toString() ?? '')) {
    errors.add('invalid entrypoint');
  }
  if (files is! List || files.isEmpty) {
    errors.add('missing files');
  } else {
    for (final item in files) {
      if (item is! Map) {
        errors.add('invalid file entry');
        continue;
      }
      final path = item['path']?.toString() ?? '';
      final sha = item['sha256']?.toString() ?? '';
      final bytes = item['bytes'];
      if (!_isSafeRelativePath(path)) errors.add('unsafe file path');
      if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha)) {
        errors.add('invalid checksum');
      }
      if (RegExp(r'^0{64}$').hasMatch(sha)) errors.add('placeholder checksum');
      if (bytes is! int || bytes <= 0) errors.add('invalid file byte count');
    }
  }
  return errors.toSet().toList()..sort();
}

bool _isSafeRelativePath(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.isEmpty || normalized.startsWith('/')) return false;
  if (RegExp(r'^[A-Za-z]:').hasMatch(normalized)) return false;
  if (normalized.split('/').contains('..')) return false;
  return normalized.startsWith('bin/') ||
      normalized.startsWith('lib/') ||
      normalized.startsWith('libexec/') ||
      normalized.startsWith('share/');
}
