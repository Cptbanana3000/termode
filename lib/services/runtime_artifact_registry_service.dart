import 'native_command_service.dart';

/// Safe registry for real runtime artifacts (v0.46), starting with Git.
///
/// This is the trust boundary for installing real native tools. For v0.46 the
/// registry is a **local/bundled contract only**: it answers whether a
/// verified, ABI-matched artifact is present in this build. There is NO runtime
/// internet download and NO arbitrary user-selected archive import.
///
/// Honest result for this build: no Git artifact is bundled, so Git is reported
/// UNAVAILABLE everywhere. Termode never fakes Git.
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

  /// Whether a verified Git artifact is bundled in this build.
  /// Always false for v0.46 (no bundled binary, no download). Honest.
  bool bundledGitArtifactExists() => false;

  /// The bundled Git manifest, if any. None in this build.
  Map<String, dynamic>? bundledGitManifest() => null;

  Future<String> currentAbi() async {
    final diagnostics = await NativeCommandService().getDiagnostics();
    final abi = diagnostics?['abi']?.toString();
    return (abi == null || abi.isEmpty) ? 'unknown' : abi;
  }

  /// Git artifact status for the current device ABI.
  Future<GitArtifactStatus> gitArtifactStatus() async {
    final abi = await currentAbi();
    if (!bundledGitArtifactExists()) {
      return GitArtifactStatus(
        available: false,
        installable: false,
        abi: abi,
        source: 'unavailable',
        reason: 'No verified Git artifact is bundled in this build.',
        status: 'UNAVAILABLE',
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
      );
    }
    return GitArtifactStatus(
      available: true,
      installable: true,
      abi: abi,
      source: manifest['source']?.toString() ?? 'bundled',
      reason: 'Verified Git artifact available.',
      status: 'AVAILABLE',
    );
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
    if (!trustedSources.contains(source)) errors.add('unknown/untrusted source');
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
  final String status; // AVAILABLE / UNAVAILABLE / INVALID / INCOMPATIBLE

  const GitArtifactStatus({
    required this.available,
    required this.installable,
    required this.abi,
    required this.source,
    required this.reason,
    required this.status,
  });
}
