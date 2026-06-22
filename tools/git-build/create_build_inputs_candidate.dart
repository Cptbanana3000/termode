import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  stdout.writeln('=== Create Build Inputs Candidate ===');
  
  String? gitVersion;
  String? gitArchive;
  String? gitSha256;
  String? zlibVersion;
  String? zlibArchive;
  String? zlibSha256;
  String? trustedBy;

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--git-version' && i + 1 < args.length) gitVersion = args[++i];
    if (args[i] == '--git-archive' && i + 1 < args.length) gitArchive = args[++i];
    if (args[i] == '--git-sha256' && i + 1 < args.length) gitSha256 = args[++i];
    if (args[i] == '--zlib-version' && i + 1 < args.length) zlibVersion = args[++i];
    if (args[i] == '--zlib-archive' && i + 1 < args.length) zlibArchive = args[++i];
    if (args[i] == '--zlib-sha256' && i + 1 < args.length) zlibSha256 = args[++i];
    if (args[i] == '--trusted-by' && i + 1 < args.length) trustedBy = args[++i];
  }

  gitVersion ??= '2.44.0';
  gitArchive ??= 'tools/git-build/sources/git-2.44.0.tar.xz';
  zlibVersion ??= '1.3.1';
  zlibArchive ??= 'tools/git-build/sources/zlib-1.3.1.tar.xz';
  trustedBy ??= 'REPLACE_WITH_REVIEWER';

  if (gitSha256 == null || gitSha256.isEmpty || gitSha256 == '0' * 64) {
    stderr.writeln('Error: missing or placeholder --git-sha256 checksum');
    exitCode = 1;
    return;
  }
  if (zlibSha256 == null || zlibSha256.isEmpty || zlibSha256 == '0' * 64) {
    stderr.writeln('Error: missing or placeholder --zlib-sha256 checksum');
    exitCode = 1;
    return;
  }

  if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(gitSha256) ||
      !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(zlibSha256)) {
    stderr.writeln('Error: checksum must be a valid 64-character SHA-256 hex string');
    exitCode = 1;
    return;
  }

  if (!_isSafePath(gitArchive, 'tools/git-build/sources/')) {
    stderr.writeln('Error: unsafe git-archive path: $gitArchive');
    exitCode = 1;
    return;
  }

  if (!_isSafePath(zlibArchive, 'tools/git-build/sources/')) {
    stderr.writeln('Error: unsafe zlib-archive path: $zlibArchive');
    exitCode = 1;
    return;
  }

  final candidateData = {
    "template_only": false,
    "candidate": true,
    "selected_git_version": gitVersion,
    "source_archive": gitArchive,
    "source_tree": "tools/git-build/sources/git-$gitVersion/",
    "source_sha256": gitSha256,
    "source_license": "GPL-2.0-only",
    "source_provenance": "https://mirrors.edge.kernel.org/pub/software/scm/git/git-$gitVersion.tar.xz",
    "dependency_mode": "minimal-local-git",
    "required_now": ["perl", "android_ndk", "zlib"],
    "deferred_dependencies": ["curl", "openssl_or_tls", "expat", "pcre2"],
    "git": {
      "version": gitVersion,
      "source_type": "archive",
      "source_path": gitArchive,
      "source_url": "https://mirrors.edge.kernel.org/pub/software/scm/git/git-$gitVersion.tar.xz",
      "sha256": gitSha256,
      "license": "GPL-2.0-only",
      "trusted_by": trustedBy
    },
    "dependencies": [
      {
        "name": "zlib",
        "version": zlibVersion,
        "source_type": "archive",
        "source_path": zlibArchive,
        "source_url": "https://zlib.net/zlib-$zlibVersion.tar.xz",
        "sha256": zlibSha256,
        "license": "Zlib",
        "trusted_by": trustedBy,
        "required_for": "minimal-local-git"
      }
    ],
    "host_requirements": {
      "perl": "required",
      "android_ndk": "required",
      "cmake": "required",
      "make": "required",
      "archive_tool": "required"
    },
    "target": {
      "abi": "arm64-v8a",
      "min_android_api": 24
    },
    "output": {
      "staging_dir": "tools/runtime-artifacts/git/arm64-v8a/files/",
      "artifact_dir": "tools/runtime-artifacts/git/arm64-v8a/"
    },
    "trust": {
      "source": "termode-built",
      "trusted_by": trustedBy,
      "notes": "Verify build outputs with sha256 checksums."
    },
    "build_mode": "minimal-local-git",
    "build_method": "reproducible-ndk-make-build",
    "acquired_at": DateTime.now().toUtc().toIso8601String()
  };

  final file = File('tools/git-build/build-inputs.candidate.json');
  if (!file.parent.existsSync()) {
    file.parent.createSync(recursive: true);
  }
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(candidateData)}\n');
  
  stdout.writeln('Success: wrote candidate manifest to ${file.path}');
  stdout.writeln('HUMAN REVIEW REQUIRED: please review the candidate file and promote to build-inputs.json only after verification.');
}

bool _isSafePath(String path, String allowedRoot) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.isEmpty || normalized.startsWith('/')) return false;
  if (RegExp(r'^[A-Za-z]:').hasMatch(normalized)) return false;
  final parts = normalized.split('/');
  if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    return false;
  }
  return normalized.startsWith(allowedRoot);
}
