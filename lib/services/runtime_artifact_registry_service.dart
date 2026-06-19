import 'dart:convert';
import 'dart:io';

import 'native_command_service.dart';

/// Safe registry for real runtime artifacts (v0.50), starting with Git.
///
/// This is the trust boundary for installing real native tools. For v0.50 the
/// registry knows about the arm64-v8a production artifact layout and host-side
/// production pipeline, but template-only and placeholder manifests are never
/// installable. There is NO runtime internet download and NO arbitrary
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
  static const String gitArtifactsRoot = 'tools/runtime-artifacts/git';

  static String gitProjectManifestPath(String abi) =>
      '$gitArtifactsRoot/$abi/manifest.json';

  static String gitProjectFilesRoot(String abi) =>
      '$gitArtifactsRoot/$abi/files';

  /// Whether a verified Git artifact is bundled in this build.
  /// Always false for v0.50 until a reviewed asset bundle is wired in.
  bool bundledGitArtifactExists() => false;

  /// The bundled Git manifest, if any. None in this build.
  Map<String, dynamic>? bundledGitManifest() => null;

  bool gitTemplateExists() => File(gitTemplatePath).existsSync();

  bool gitProjectManifestExists([String? abi]) {
    if (abi != null && abi.isNotEmpty) {
      return File(gitProjectManifestPath(abi)).existsSync();
    }
    return supportedGitAbis.any(
      (candidate) => File(gitProjectManifestPath(candidate)).existsSync(),
    );
  }

  Map<String, dynamic>? readGitTemplateManifest() =>
      _readJsonMap(gitTemplatePath);

  Map<String, dynamic>? readProjectGitManifest(String abi) =>
      _readJsonMap(gitProjectManifestPath(abi));

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
    final bundled = await bundledGitArtifactStatus();
    if (bundled.installable || bundled.status == 'INVALID') {
      return bundled;
    }
    return projectGitArtifactStatus();
  }

  Future<GitArtifactStatus> bundledGitArtifactStatus() async {
    final abi = await currentAbi();
    if (!bundledGitArtifactExists()) {
      return GitArtifactStatus(
        available: false,
        installable: false,
        abi: abi,
        source: 'bundled',
        reason: 'No verified Git artifact is bundled in this build.',
        status: 'UNAVAILABLE',
        templatePresent: gitTemplateExists(),
        manifestPresent: false,
        location: 'bundled',
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
        location: 'bundled',
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
        location: 'bundled',
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
        location: 'bundled',
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
      location: 'bundled',
    );
  }

  Future<GitArtifactStatus> projectGitArtifactStatus() async {
    final abi = await currentAbi();
    final manifestPath = gitProjectManifestPath(abi);
    final manifest = readProjectGitManifest(abi);
    if (manifest == null) {
      return GitArtifactStatus(
        available: false,
        installable: false,
        abi: abi,
        source: gitTemplateExists() ? 'template' : 'unavailable',
        reason: gitTemplateExists()
            ? 'Git artifact template exists, but no project Git payload is present.'
            : 'No project Git artifact manifest exists at $manifestPath.',
        status: gitTemplateExists() ? 'TEMPLATE_ONLY' : 'UNAVAILABLE',
        templatePresent: gitTemplateExists(),
        manifestPresent: false,
        location: 'project',
        manifestPath: manifestPath,
      );
    }
    final manifestAbi = manifest['abi']?.toString() ?? '';
    if (manifestAbi != 'all' && manifestAbi != abi) {
      return GitArtifactStatus(
        available: false,
        installable: false,
        abi: abi,
        source: manifest['source']?.toString() ?? 'project',
        reason:
            'Project artifact ABI ($manifestAbi) does not match device ($abi).',
        status: 'INCOMPATIBLE',
        templatePresent: gitTemplateExists(),
        manifestPresent: true,
        location: 'project',
        manifestPath: manifestPath,
      );
    }
    final validation = validateProjectGitArtifact(manifest, abi);
    if (validation.isNotEmpty) {
      return GitArtifactStatus(
        available: false,
        installable: false,
        abi: abi,
        source: manifest['source']?.toString() ?? 'project',
        reason: validation.first,
        status: 'INVALID',
        templatePresent: gitTemplateExists(),
        manifestPresent: true,
        location: 'project',
        manifestPath: manifestPath,
      );
    }
    return GitArtifactStatus(
      available: true,
      installable: true,
      abi: abi,
      source: manifest['source']?.toString() ?? 'project',
      reason: 'Verified project Git artifact available.',
      status: 'AVAILABLE',
      templatePresent: gitTemplateExists(),
      manifestPresent: true,
      location: 'project',
      manifestPath: manifestPath,
    );
  }

  List<String> validateProjectGitArtifact(
    Map<String, dynamic> manifest,
    String currentAbi,
  ) {
    final errors = validateGitManifest(manifest, currentAbi);
    if (errors.isNotEmpty) return errors;
    final abi = manifest['abi']?.toString() ?? currentAbi;
    final filesRoot = Directory(
      gitProjectFilesRoot(abi == 'all' ? currentAbi : abi),
    );
    final files = manifest['files'];
    if (files is! List) return const ['missing files'];
    final root = filesRoot.absolute.path.replaceAll('\\', '/');
    if (!filesRoot.existsSync()) {
      return ['artifact files directory missing: ${filesRoot.path}'];
    }
    for (final item in files) {
      if (item is! Map) return const ['invalid file entry'];
      final relPath = item['path']?.toString() ?? '';
      final expected = item['sha256']?.toString() ?? '';
      if (!_isSafeRelativePath(relPath)) return ['unsafe file path: $relPath'];
      final file = File('${filesRoot.path}/$relPath');
      final normalized = file.absolute.path.replaceAll('\\', '/');
      if (!normalized.startsWith('$root/')) {
        return ['unsafe file path: $relPath'];
      }
      if (!file.existsSync()) {
        return ['missing artifact file: $relPath'];
      }
      final expectedBytes = item['bytes'];
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

  List<String> validateGitTemplateManifest() {
    final manifest = readGitTemplateManifest();
    if (manifest == null) {
      return const ['template missing or invalid JSON'];
    }
    final abi = manifest['abi']?.toString() ?? 'arm64-v8a';
    final errors = validateGitManifest(manifest, abi)
        .where(
          (error) =>
              error != 'placeholder manifest is not installable' &&
              error != 'placeholder checksum' &&
              error != 'invalid file byte count',
        )
        .toList();
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
    final sourceNote = manifest['source_note']?.toString() ?? '';
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
    if (sourceUrl.trim().isEmpty && sourceNote.trim().isEmpty) {
      errors.add('missing source_url or source_note');
    }
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
        final bytes = item['bytes'];
        if (!_isSafeRelativePath(path)) errors.add('unsafe file path');
        if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha)) {
          errors.add('invalid checksum');
        }
        if (bytes is! int || bytes <= 0) errors.add('invalid file byte count');
        if (RegExp(r'^0{64}$').hasMatch(sha)) {
          errors.add('placeholder checksum');
        }
      }
    }
    if (version.toLowerCase().contains('template') ||
        createdAt == 'TEMPLATE_ONLY') {
      errors.add('placeholder manifest is not installable');
    }
    return errors.toSet().toList()..sort();
  }

  String calculateSha256(List<int> input) {
    final bytes = List<int>.from(input);
    final bitLength = bytes.length * 8;
    bytes.add(0x80);
    while ((bytes.length % 64) != 56) {
      bytes.add(0);
    }
    for (var shift = 56; shift >= 0; shift -= 8) {
      bytes.add((bitLength >> shift) & 0xff);
    }

    const k = <int>[
      0x428a2f98,
      0x71374491,
      0xb5c0fbcf,
      0xe9b5dba5,
      0x3956c25b,
      0x59f111f1,
      0x923f82a4,
      0xab1c5ed5,
      0xd807aa98,
      0x12835b01,
      0x243185be,
      0x550c7dc3,
      0x72be5d74,
      0x80deb1fe,
      0x9bdc06a7,
      0xc19bf174,
      0xe49b69c1,
      0xefbe4786,
      0x0fc19dc6,
      0x240ca1cc,
      0x2de92c6f,
      0x4a7484aa,
      0x5cb0a9dc,
      0x76f988da,
      0x983e5152,
      0xa831c66d,
      0xb00327c8,
      0xbf597fc7,
      0xc6e00bf3,
      0xd5a79147,
      0x06ca6351,
      0x14292967,
      0x27b70a85,
      0x2e1b2138,
      0x4d2c6dfc,
      0x53380d13,
      0x650a7354,
      0x766a0abb,
      0x81c2c92e,
      0x92722c85,
      0xa2bfe8a1,
      0xa81a664b,
      0xc24b8b70,
      0xc76c51a3,
      0xd192e819,
      0xd6990624,
      0xf40e3585,
      0x106aa070,
      0x19a4c116,
      0x1e376c08,
      0x2748774c,
      0x34b0bcb5,
      0x391c0cb3,
      0x4ed8aa4a,
      0x5b9cca4f,
      0x682e6ff3,
      0x748f82ee,
      0x78a5636f,
      0x84c87814,
      0x8cc70208,
      0x90befffa,
      0xa4506ceb,
      0xbef9a3f7,
      0xc67178f2,
    ];

    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;

    int rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;

    for (var offset = 0; offset < bytes.length; offset += 64) {
      final w = List<int>.filled(64, 0);
      for (var i = 0; i < 16; i++) {
        final j = offset + i * 4;
        w[i] =
            ((bytes[j] << 24) |
                (bytes[j + 1] << 16) |
                (bytes[j + 2] << 8) |
                bytes[j + 3]) &
            0xffffffff;
      }
      for (var i = 16; i < 64; i++) {
        final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }
      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;
      var f = h5;
      var g = h6;
      var h = h7;
      for (var i = 0; i < 64; i++) {
        final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        final ch = (e & f) ^ ((~e) & g);
        final temp1 = (h + s1 + ch + k[i] + w[i]) & 0xffffffff;
        final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;
        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }
      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }
    return [
      h0,
      h1,
      h2,
      h3,
      h4,
      h5,
      h6,
      h7,
    ].map((v) => v.toRadixString(16).padLeft(8, '0')).join();
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
  final String location;
  final String manifestPath;

  const GitArtifactStatus({
    required this.available,
    required this.installable,
    required this.abi,
    required this.source,
    required this.reason,
    required this.status,
    this.templatePresent = false,
    this.manifestPresent = false,
    this.location = 'unknown',
    this.manifestPath = '',
  });
}
