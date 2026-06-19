import 'dart:convert';
import 'dart:io';

import 'native_command_service.dart';

/// Safe registry for real runtime artifacts (v0.47), starting with Git.
///
/// This is the trust boundary for installing real native tools. For v0.47 the
/// registry also knows about the build-side artifact template, but template-only
/// is never installable. There is NO runtime internet download and NO arbitrary
/// user-selected archive import.
///
/// Honest result for this build: no Git artifact is bundled. A source checkout
/// may contain the manifest template, so Git can be reported TEMPLATE_ONLY, but
/// it remains not installable. Termode never fakes Git.
class RuntimeArtifactRegistryService {
  static final RuntimeArtifactRegistryService _instance =
      RuntimeArtifactRegistryService._internal();
  factory RuntimeArtifactRegistryService() => _instance;
  RuntimeArtifactRegistryService._internal();

  /// ABIs a future Git artifact may target.
  static const Set<String> supportedGitAbis = {
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
  };

  /// Sources Termode will trust for a bundled/local artifact.
  static const Set<String> trustedSources = {
    'termode-vendored',
    'termode-built',
  };

  static const String gitTemplatePath =
      'tools/runtime-artifacts/git/manifest.template.json';
  static const String gitManifestPath =
      'tools/runtime-artifacts/git/manifest.json';

  /// Whether a verified Git artifact is bundled in this build.
  /// Always false for v0.47 (no bundled binary, no download). Honest.
  bool bundledGitArtifactExists() => false;

  /// The bundled Git manifest, if any. None in this build.
  Map<String, dynamic>? bundledGitManifest() => null;

  bool gitTemplateExists() => File(gitTemplatePath).existsSync();

  bool gitProjectManifestExists() => File(gitManifestPath).existsSync();

  Map<String, dynamic>? readGitTemplateManifest() =>
      _readJsonMap(gitTemplatePath);

  Map<String, dynamic>? readProjectGitManifest() =>
      _readJsonMap(gitManifestPath);

  Map<String, dynamic>? _readJsonMap(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> currentAbi() async {
    final diagnostics = await NativeCommandService().getDiagnostics();
    final abi = diagnostics?['abi']?.toString();
    return (abi == null || abi.isEmpty) ? 'unknown' : abi;
  }

  /// Git artifact status for the current device ABI.
  Future<GitArtifactStatus> gitArtifactStatus() async {
    final abi = await currentAbi();
    if (!bundledGitArtifactExists()) {
      if (gitTemplateExists()) {
        return GitArtifactStatus(
          available: false,
          installable: false,
          abi: abi,
          source: 'template',
          reason:
              'Git artifact template exists, but no verified Git payload is bundled.',
          status: 'TEMPLATE_ONLY',
          templatePresent: true,
          manifestPresent: gitProjectManifestExists(),
        );
      }
      return GitArtifactStatus(
        available: false,
        installable: false,
        abi: abi,
        source: 'unavailable',
        reason: 'No verified Git artifact is bundled in this build.',
        status: 'UNAVAILABLE',
        templatePresent: false,
        manifestPresent: false,
      );
    }
    final manifest = bundledGitManifest();
    if (manifest == null) {
      return GitArtifactStatus(
        available: false,
        installable: false,
        abi: abi,
        source: 'bundled',
        reason: 'Git artifact manifest is missing.',
        status: 'INVALID',
        templatePresent: gitTemplateExists(),
        manifestPresent: false,
      );
    }
    final errors = validateGitManifest(manifest, abi);
    if (errors.isNotEmpty) {
      return GitArtifactStatus(
        available: true,
        installable: false,
        abi: abi,
        source: manifest['source']?.toString() ?? 'bundled',
        reason: 'Manifest invalid: ${errors.first}',
        status: 'INVALID',
        templatePresent: gitTemplateExists(),
        manifestPresent: true,
      );
    }
    final manifestAbi = manifest['abi']?.toString() ?? '';
    if (manifestAbi != 'all' && manifestAbi != abi) {
      return GitArtifactStatus(
        available: true,
        installable: false,
        abi: abi,
        source: manifest['source']?.toString() ?? 'bundled',
        reason: 'Artifact ABI ($manifestAbi) does not match device ($abi).',
        status: 'INCOMPATIBLE',
        templatePresent: gitTemplateExists(),
        manifestPresent: true,
      );
    }
    return GitArtifactStatus(
      available: true,
      installable: true,
      abi: abi,
      source: manifest['source']?.toString() ?? 'bundled',
      reason: 'Verified Git artifact available.',
      status: 'AVAILABLE',
      templatePresent: gitTemplateExists(),
      manifestPresent: true,
    );
  }

  List<String> validateGitTemplateManifest() {
    final manifest = readGitTemplateManifest();
    if (manifest == null) {
      return const ['template missing or invalid JSON'];
    }
    final abi = manifest['abi']?.toString() ?? 'arm64-v8a';
    final errors = validateGitManifest(manifest, abi);
    final version = manifest['version']?.toString() ?? '';
    final createdAt = manifest['created_at']?.toString() ?? '';
    if (!version.contains('template') && createdAt != 'TEMPLATE_ONLY') {
      errors.add('template is not marked template-only');
    }
    return errors.toSet().toList()..sort();
  }

  bool _isSafeRelativePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.isEmpty) return false;
    if (normalized.startsWith('/')) return false;
    if (RegExp(r'^[A-Za-z]:').hasMatch(normalized)) return false;
    if (normalized.split('/').contains('..')) return false;
    if (normalized.endsWith('/')) return false;
    return normalized.startsWith('bin/') ||
        normalized.startsWith('lib/') ||
        normalized.startsWith('libexec/') ||
        normalized.startsWith('share/');
  }

  /// Validates a real Git package manifest. Returns a sorted list of errors
  /// (empty = valid). Never throws on malformed input.
  List<String> validateGitManifest(
    Map<String, dynamic> manifest,
    String currentAbi,
  ) {
    final errors = <String>[];
    final name = manifest['name']?.toString() ?? '';
    final version = manifest['version']?.toString() ?? '';
    final kind = manifest['kind']?.toString() ?? '';
    final command = manifest['command']?.toString() ?? '';
    final abi = manifest['abi']?.toString() ?? '';
    final entrypoint = manifest['entrypoint']?.toString() ?? '';
    final source = manifest['source']?.toString() ?? '';
    final sourceUrl = manifest['source_url']?.toString() ?? '';
    final buildMethod = manifest['build_method']?.toString() ?? '';
    final license = manifest['license']?.toString() ?? '';
    final trustedBy = manifest['trusted_by']?.toString() ?? '';
    final verificationCommand =
        manifest['verification_command']?.toString() ?? '';
    final smokeTests = manifest['smoke_tests'];
    final dependencies = manifest['dependencies'];
    final createdAt = manifest['created_at']?.toString() ?? '';
    final files = manifest['files'];

    if (name != 'git') errors.add('package name must be git');
    if (version.trim().isEmpty) errors.add('missing version');
    if (kind != 'native-tool') errors.add('kind must be native-tool');
    if (command.trim().isEmpty) {
      errors.add('empty command');
    } else if (!RegExp(r'^[a-z][a-z0-9-]{0,31}$').hasMatch(command)) {
      errors.add('invalid command name');
    }
    if (abi.isEmpty) {
      errors.add('missing abi');
    } else if (abi != 'all' && !supportedGitAbis.contains(abi)) {
      errors.add('unsupported abi');
    }
    if (!_isSafeRelativePath(entrypoint)) errors.add('invalid entrypoint');
    if (!trustedSources.contains(source)) {
      errors.add('unknown/untrusted source');
    }
    if (sourceUrl.trim().isEmpty) errors.add('missing source_url');
    if (buildMethod.trim().isEmpty) errors.add('missing build_method');
    if (license.trim().isEmpty) errors.add('missing license');
    if (trustedBy.trim().isEmpty) errors.add('missing trusted_by');
    if (verificationCommand.trim().isEmpty) {
      errors.add('missing verification_command');
    }
    if (smokeTests is! List || smokeTests.isEmpty) {
      errors.add('missing smoke_tests');
    }
    if (dependencies is! List) errors.add('missing dependencies');
    if (createdAt.trim().isEmpty) errors.add('missing created_at');
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
        if (!_isSafeRelativePath(path)) errors.add('unsafe file path');
        if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha)) {
          errors.add('invalid checksum');
        }
      }
    }
    return errors.toSet().toList()..sort();
  }
}

class GitArtifactStatus {
  final bool available;
  final bool installable;
  final String abi;
  final String source;
  final String reason;
  final String status;
  // AVAILABLE / UNAVAILABLE / TEMPLATE_ONLY / INVALID / INCOMPATIBLE
  final bool templatePresent;
  final bool manifestPresent;

  const GitArtifactStatus({
    required this.available,
    required this.installable,
    required this.abi,
    required this.source,
    required this.reason,
    required this.status,
    this.templatePresent = false,
    this.manifestPresent = false,
  });
}
