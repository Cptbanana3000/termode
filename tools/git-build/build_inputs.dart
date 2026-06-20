import 'dart:convert';
import 'dart:io';

import 'sha256_helper.dart';

const buildInputsPath = 'tools/git-build/build-inputs.json';
const buildInputsExamplePath = 'tools/git-build/build-inputs.example.json';

class BuildInputsDocument {
  BuildInputsDocument({
    required this.projectRoot,
    required this.file,
    required this.exists,
    required this.data,
    required this.errors,
  });

  final Directory projectRoot;
  final File file;
  final bool exists;
  final Map<String, dynamic>? data;
  final List<String> errors;

  bool get valid => exists && data != null && errors.isEmpty;
  Map<String, dynamic>? get git => _map(data?['git']);
  List<Map<String, dynamic>> get dependencies =>
      (data?['dependencies'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
  String get targetAbi =>
      _map(data?['target'])?['abi']?.toString() ?? 'unknown';
}

BuildInputsDocument loadAndValidateBuildInputs({String? projectRoot}) {
  final root = Directory(projectRoot ?? Directory.current.path).absolute;
  final file = File('${root.path}/$buildInputsPath');
  if (!file.existsSync()) {
    return BuildInputsDocument(
      projectRoot: root,
      file: file,
      exists: false,
      data: null,
      errors: ['missing build-inputs.json'],
    );
  }

  Map<String, dynamic>? data;
  final errors = <String>[];
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map) {
      data = Map<String, dynamic>.from(decoded);
    } else {
      errors.add('build inputs must be a JSON object');
    }
  } catch (_) {
    errors.add('build inputs contain invalid JSON');
  }
  if (data != null) errors.addAll(validateBuildInputs(data, root));
  return BuildInputsDocument(
    projectRoot: root,
    file: file,
    exists: true,
    data: data,
    errors: errors.toSet().toList()..sort(),
  );
}

List<String> validateBuildInputs(
  Map<String, dynamic> data,
  Directory projectRoot,
) {
  final errors = <String>[];
  if (data['template_only'] == true) {
    errors.add('template-only inputs are not build-ready');
  }
  final git = _map(data['git']);
  if (git == null) {
    errors.add('missing git source entry');
  } else {
    errors.addAll(_validateSource(git, projectRoot, 'git', isGit: true));
  }

  final dependencies = data['dependencies'];
  if (dependencies is! List || dependencies.isEmpty) {
    errors.add('missing dependency entries');
  } else {
    for (final entry in dependencies) {
      if (entry is! Map) {
        errors.add('invalid dependency entry');
        continue;
      }
      final dependency = Map<String, dynamic>.from(entry);
      final name = dependency['name']?.toString().trim() ?? '';
      if (name.isEmpty) errors.add('dependency missing name');
      if ((dependency['required_for']?.toString().trim() ?? '').isEmpty) {
        errors.add(
          '${name.isEmpty ? 'dependency' : name} missing required_for',
        );
      }
      errors.addAll(
        _validateSource(
          dependency,
          projectRoot,
          name.isEmpty ? 'dependency' : name,
          isGit: false,
        ),
      );
    }
  }

  final host = _map(data['host_requirements']);
  for (final key in ['perl', 'android_ndk', 'cmake', 'make', 'archive_tool']) {
    if ((host?[key]?.toString().trim() ?? '').isEmpty) {
      errors.add('host requirements missing $key');
    }
  }
  final target = _map(data['target']);
  if (target?['abi'] != 'arm64-v8a') errors.add('target ABI must be arm64-v8a');
  final minApi = target?['min_android_api'];
  if (minApi is! int || minApi < 21) errors.add('invalid minimum Android API');
  if (!{
    'minimal-local-git',
    'git-with-https-later',
  }.contains(data['build_mode'])) {
    errors.add('invalid build mode');
  }
  for (final key in ['build_method', 'acquired_at']) {
    if ((data[key]?.toString().trim() ?? '').isEmpty) {
      errors.add('missing $key');
    }
  }
  return errors;
}

List<String> _validateSource(
  Map<String, dynamic> source,
  Directory root,
  String label, {
  required bool isGit,
}) {
  final errors = <String>[];
  for (final key in [
    'version',
    'source_type',
    'source_path',
    'source_url',
    'sha256',
    'license',
    'trusted_by',
  ]) {
    if ((source[key]?.toString().trim() ?? '').isEmpty) {
      errors.add('$label missing $key');
    }
  }
  final type = source['source_type']?.toString() ?? '';
  if (type != 'archive' && type != 'tree') {
    errors.add('$label invalid source_type');
  }
  final path = source['source_path']?.toString() ?? '';
  final allowedRoot = isGit
      ? 'tools/git-build/sources/'
      : 'tools/git-build/deps/';
  if (!isSafeBuildInputPath(path, allowedRoot)) {
    errors.add('$label unsafe source_path');
    return errors;
  }
  final entityPath = '${root.path}/$path';
  final entityExists = type == 'tree'
      ? Directory(entityPath).existsSync()
      : File(entityPath).existsSync();
  if (!entityExists) errors.add('$label source missing');

  final checksum = source['sha256']?.toString() ?? '';
  if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(checksum) ||
      RegExp(r'^0{64}$').hasMatch(checksum)) {
    errors.add('$label invalid or placeholder checksum');
  } else if (type == 'archive' && File(entityPath).existsSync()) {
    final actual = calculateSha256(File(entityPath).readAsBytesSync());
    if (actual.toLowerCase() != checksum.toLowerCase()) {
      errors.add('$label checksum mismatch');
    }
  }
  return errors;
}

bool isSafeBuildInputPath(String path, String allowedRoot) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.isEmpty || normalized.startsWith('/')) return false;
  if (RegExp(r'^[A-Za-z]:').hasMatch(normalized)) return false;
  final parts = normalized.split('/');
  if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    return false;
  }
  return normalized.startsWith(allowedRoot);
}

bool buildInputSourceExists(
  BuildInputsDocument document,
  Map<String, dynamic>? source, {
  required bool isGit,
}) {
  if (source == null) return false;
  final path = source['source_path']?.toString() ?? '';
  final allowedRoot = isGit
      ? 'tools/git-build/sources/'
      : 'tools/git-build/deps/';
  if (!isSafeBuildInputPath(path, allowedRoot)) return false;
  final resolved = '${document.projectRoot.path}/$path';
  return source['source_type'] == 'tree'
      ? Directory(resolved).existsSync()
      : File(resolved).existsSync();
}

Map<String, dynamic>? _map(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : null;
}
