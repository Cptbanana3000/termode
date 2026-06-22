import 'dart:convert';
import 'dart:io';

import 'sha256_helper.dart';

const buildInputsPath = 'tools/git-build/build-inputs.json';
const buildInputsExamplePath = 'tools/git-build/build-inputs.example.json';
const buildInputsCandidatePath = 'tools/git-build/build-inputs.candidate.json';
const selectedGitVersionTarget = '2.44.0';
const selectedGitArchivePath = 'tools/git-build/sources/git-2.44.0.tar.xz';
const selectedGitTreePath = 'tools/git-build/sources/git-2.44.0';
const minimalDependencyMode = 'minimal-local-git';

class BuildInputsDocument {
  BuildInputsDocument({
    required this.projectRoot,
    required this.file,
    required this.exists,
    required this.candidateExists,
    required this.isCandidate,
    required this.data,
    required this.errors,
  });

  final Directory projectRoot;
  final File file;
  final bool exists;
  final bool candidateExists;
  final bool isCandidate;
  final Map<String, dynamic>? data;
  final List<String> errors;

  bool get valid =>
      exists &&
      data != null &&
      errors.isEmpty &&
      !isCandidate &&
      data?['candidate'] != true &&
      data?['template_only'] != true;

  Map<String, dynamic>? get git => _map(data?['git']);
  List<Map<String, dynamic>> get dependencies =>
      (data?['dependencies'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
  String get targetAbi =>
      _map(data?['target'])?['abi']?.toString() ?? 'unknown';
  String get selectedVersion =>
      data?['selected_git_version']?.toString() ??
      git?['version']?.toString() ??
      'unknown';
}

BuildInputsDocument loadAndValidateBuildInputs({String? projectRoot}) {
  final root = Directory(projectRoot ?? Directory.current.path).absolute;
  var file = File('${root.path}/$buildInputsPath');
  final exists = file.existsSync();
  final candidateFile = File('${root.path}/$buildInputsCandidatePath');
  final candidateExists = candidateFile.existsSync();
  var isCandidate = false;

  if (!exists && candidateExists) {
    file = candidateFile;
    isCandidate = true;
  }

  if (!exists && !candidateExists) {
    return BuildInputsDocument(
      projectRoot: root,
      file: file,
      exists: false,
      candidateExists: false,
      isCandidate: false,
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
      if (isCandidate || data['candidate'] == true) {
        isCandidate = true;
      }
    } else {
      errors.add('build inputs must be a JSON object');
    }
  } catch (_) {
    errors.add('build inputs contain invalid JSON');
  }
  if (data != null) errors.addAll(validateBuildInputs(data, root));
  if (isCandidate) {
    errors.add('candidate inputs require human review before build');
  }
  return BuildInputsDocument(
    projectRoot: root,
    file: file,
    exists: exists,
    candidateExists: candidateExists,
    isCandidate: isCandidate,
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
  if (data['candidate'] == true) {
    errors.add('candidate inputs require human review before build');
  }
  final selectedVersion = data['selected_git_version']?.toString().trim();
  if (selectedVersion == null || selectedVersion.isEmpty) {
    errors.add('missing selected_git_version');
  } else if (selectedVersion != selectedGitVersionTarget) {
    errors.add('selected_git_version must be $selectedGitVersionTarget');
  }
  if ((data['source_archive']?.toString().trim() ?? '').isEmpty) {
    errors.add('missing source_archive');
  }
  if ((data['source_tree']?.toString().trim() ?? '').isEmpty) {
    errors.add('missing source_tree');
  }
  if ((data['source_license']?.toString().trim() ?? '').isEmpty) {
    errors.add('missing source_license');
  }
  if ((data['source_provenance']?.toString().trim() ?? '').isEmpty) {
    errors.add('missing source_provenance');
  }
  final sourceSha = data['source_sha256']?.toString().trim() ?? '';
  if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sourceSha) ||
      RegExp(r'^0{64}$').hasMatch(sourceSha)) {
    errors.add('invalid or placeholder source_sha256');
  }
  final dependencyMode = data['dependency_mode']?.toString().trim() ?? '';
  if (dependencyMode != minimalDependencyMode && dependencyMode != 'https-later') {
    errors.add('invalid dependency_mode');
  }
  if (data['required_now'] is! List || (data['required_now'] as List).isEmpty) {
    errors.add('missing required_now');
  }
  if (data['deferred_dependencies'] is! List) {
    errors.add('missing deferred_dependencies');
  }
  if (_map(data['output']) == null) errors.add('missing output');
  final trust = _map(data['trust']);
  if (trust == null) {
    errors.add('missing trust');
  } else {
    if ((trust['source']?.toString().trim() ?? '').isEmpty) {
      errors.add('trust missing source');
    }
    if ((trust['trusted_by']?.toString().trim() ?? '').isEmpty) {
      errors.add('trust missing trusted_by');
    }
  }
  final git = _map(data['git']);
  if (git == null) {
    errors.add('missing git source entry');
  } else {
    if (selectedVersion != null &&
        selectedVersion.isNotEmpty &&
        git['version']?.toString() != selectedVersion) {
      errors.add('git version must match selected_git_version');
    }
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
  final buildMode = data['build_mode']?.toString();
  if (buildMode != null &&
      !{
        'minimal-local-git',
        'git-with-https-later',
      }.contains(buildMode)) {
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
  final allowedRoot = 'tools/git-build/sources/';
  if (!isSafeBuildInputPath(path, allowedRoot)) {
    errors.add('$label unsafe source_path');
    return errors;
  }
  final entityPath = '${root.path}/$path';
  final entityExists = type == 'tree'
      ? Directory(entityPath).existsSync()
      : File(entityPath).existsSync();
  if (!entityExists) errors.add('$label source missing');
  if (type == 'tree' && Directory(entityPath).existsSync()) {
    final provenance = File('$entityPath/SOURCE_PROVENANCE.md');
    if (!provenance.existsSync()) {
      errors.add('$label tree missing SOURCE_PROVENANCE.md');
    }
  }

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
  final allowedRoot = 'tools/git-build/sources/';
  if (!isSafeBuildInputPath(path, allowedRoot)) return false;
  final resolved = '${document.projectRoot.path}/$path';
  return source['source_type'] == 'tree'
      ? Directory(resolved).existsSync()
      : File(resolved).existsSync();
}

Map<String, dynamic>? _map(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : null;
}
