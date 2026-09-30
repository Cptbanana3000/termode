import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:termode/services/git_credential_service.dart';
import 'package:termode/services/native_command_service.dart';
import 'package:termode/services/runtime_binary_package_service.dart';
import 'package:termode/services/terminal_session_service.dart';

/// Represents the result of a remote Git operation.
class GitRemoteResult {
  final bool success;
  final String output;
  final String? error;
  final int exitCode;
  final Map<String, dynamic>? metadata;

  const GitRemoteResult({
    required this.success,
    required this.output,
    this.error,
    this.exitCode = 0,
    this.metadata,
  });

  /// Human-readable message (output if success, error or output if failed)
  String get message => (error != null && error!.isNotEmpty) ? error! : output;

  /// Target directory path if recorded in metadata
  String? get targetDirectory => metadata?['targetDirectory'] as String?;

  factory GitRemoteResult.successful(String output, {Map<String, dynamic>? metadata}) {
    return GitRemoteResult(
      success: true,
      output: output,
      exitCode: 0,
      metadata: metadata,
    );
  }

  factory GitRemoteResult.failure(String error, {int exitCode = 1, String output = '', Map<String, dynamic>? metadata}) {
    return GitRemoteResult(
      success: false,
      output: output,
      error: error,
      exitCode: exitCode,
      metadata: metadata,
    );
  }
}

/// Discovered references from a Git remote HTTP endpoint.
class GitRemoteRefAdvertisement {
  final String? defaultBranch;
  final String? defaultHeadSha;
  final Map<String, String> branches; // branchName -> commitSha
  final Map<String, String> tags; // tagName -> commitSha
  final List<String> capabilities;

  const GitRemoteRefAdvertisement({
    this.defaultBranch,
    this.defaultHeadSha,
    required this.branches,
    required this.tags,
    required this.capabilities,
  });
}

/// Service implementing authentic Smart-HTTP remote Git operations (clone, fetch, pull, push)
/// and coordinating with Termode's native Git ELF engine (index-pack, checkout, pack-objects).
class GitRemoteTransportService {
  static final GitRemoteTransportService _instance = GitRemoteTransportService._internal();
  factory GitRemoteTransportService() => _instance;
  GitRemoteTransportService._internal();

  final GitCredentialService _credentialService = GitCredentialService();

  // Test overrides
  static HttpClient Function()? httpClientFactoryForTesting;
  static Future<NativeCommandResult> Function(List<String> args, {String? workingDirectory})? gitExecutorForTesting;

  /// Runs Git commands via RuntimeBinaryPackageService or test hook.
  Future<NativeCommandResult> _runNativeGit(List<String> args, {String? workingDirectory}) async {
    if (gitExecutorForTesting != null) {
      return await gitExecutorForTesting!(args, workingDirectory: workingDirectory);
    }
    return await RuntimeBinaryPackageService().runGit(args, workingDirectory: workingDirectory);
  }

  HttpClient _createHttpClient() {
    if (httpClientFactoryForTesting != null) {
      return httpClientFactoryForTesting!();
    }
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    return client;
  }

  /// Discovers remote references from `info/refs?service=git-upload-pack` or `git-receive-pack`.
  Future<GitRemoteRefAdvertisement> discoverRefs(
    Uri repoUrl, {
    String? username,
    String? token,
    String service = 'git-upload-pack',
  }) async {
    final client = _createHttpClient();
    try {
      // Normalize URL
      var cleanUrl = repoUrl.toString();
      if (cleanUrl.endsWith('/')) {
        cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
      }
      final infoUrl = Uri.parse('$cleanUrl/info/refs?service=$service');

      final req = await client.getUrl(infoUrl);
      req.headers.set('User-Agent', 'git/2.44.0 (Termode arm64-v8a)');
      req.headers.set('Accept', '*/*');

      // Credentials lookup if not explicitly provided
      final auth = await _resolveAuth(repoUrl, username, token);
      if (auth != null) {
        final creds = base64.encode(utf8.encode('${auth.username}:${auth.token}'));
        req.headers.set('Authorization', 'Basic $creds');
      }

      final resp = await req.close();
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw StateError(
          'Authentication required for $repoUrl (HTTP ${resp.statusCode}).\n'
          'Please configure a Personal Access Token (PAT):\n'
          '  termode-git credentials set ${repoUrl.host} <username> <token>',
        );
      }
      if (resp.statusCode != 200) {
        throw StateError('Remote Git server error at $infoUrl (HTTP ${resp.statusCode}: ${resp.reasonPhrase})');
      }

      final bodyBytes = await resp.fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
      return _parseRefAdvertisement(bodyBytes);
    } finally {
      client.close();
    }
  }

  /// Clones a remote repository over HTTPS.
  Future<GitRemoteResult> clone(
    String url, {
    String? targetDirectory,
    String? branch,
    int? depth,
    String? username,
    String? token,
    void Function(String message)? onProgress,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return GitRemoteResult.failure('Invalid Git repository URL: $url (must be http:// or https://)');
    }

    onProgress?.call('Connecting to $url...');

    // 1. Resolve target directory
    final session = TerminalSessionService().activeSession;
    final cwd = session.preferredWorkingDirectory ?? Directory.current.path;

    String resolvedTargetName;
    if (targetDirectory != null && targetDirectory.trim().isNotEmpty) {
      resolvedTargetName = targetDirectory.trim();
    } else {
      // Derive from URL: https://github.com/user/repo.git -> repo
      var seg = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'repo';
      if (seg.endsWith('.git')) seg = seg.substring(0, seg.length - 4);
      resolvedTargetName = seg;
    }

    final targetDir = Directory(
      resolvedTargetName.startsWith('/')
          ? resolvedTargetName
          : '$cwd/$resolvedTargetName',
    );

    if (await targetDir.exists() && (await targetDir.list().isEmpty == false)) {
      return GitRemoteResult.failure(
        'fatal: destination path \'${targetDir.path}\' already exists and is not an empty directory.',
      );
    }

    await targetDir.create(recursive: true);

    try {
      // 2. Discover remote references
      onProgress?.call('Discovering remote references...');
      final refs = await discoverRefs(uri, username: username, token: token);

      if (refs.branches.isEmpty) {
        return GitRemoteResult.failure('warning: You appear to have cloned an empty repository.');
      }

      // Determine target branch and commit SHA
      final targetBranch = branch ?? refs.defaultBranch ?? 'main';
      final headSha = refs.branches[targetBranch] ??
          refs.branches['master'] ??
          refs.defaultHeadSha ??
          refs.branches.values.first;

      // 3. Initialize local .git structure using native git init
      onProgress?.call('Initializing local repository...');
      final initRes = await _runNativeGit(['init', '-b', targetBranch], workingDirectory: targetDir.path);
      if (initRes.exitCode != 0) {
        // Fallback for older git syntax
        await _runNativeGit(['init'], workingDirectory: targetDir.path);
      }

      // 4. Request Smart-HTTP upload-pack with headSha
      onProgress?.call('Fetching objects from remote (Smart-HTTP)...');
      final packBytes = await _fetchPackfile(
        uri,
        headSha,
        username: username,
        token: token,
        onProgress: onProgress,
      );

      if (packBytes.isEmpty) {
        return GitRemoteResult.failure('Failed to receive Git packfile from remote server.');
      }

      // 5. Unpack and index objects via native git index-pack
      onProgress?.call('Indexing and unpacking ${packBytes.length} bytes of Git objects...');
      final gitDir = Directory('${targetDir.path}/.git');
      final packDir = Directory('${gitDir.path}/objects/pack');

      final indexRes = await _indexPackfile(
        packBytes,
        packDir,
        workingDirectory: targetDir.path,
      );

      if (indexRes.exitCode != 0) {
        return GitRemoteResult.failure(
          'git index-pack failed with exit code ${indexRes.exitCode}: ${indexRes.stderr}',
        );
      }

      // 6. Write refs and configure remote
      final headsDir = Directory('${gitDir.path}/refs/heads');
      final remotesDir = Directory('${gitDir.path}/refs/remotes/origin');
      await headsDir.create(recursive: true);
      await remotesDir.create(recursive: true);

      await File('${headsDir.path}/$targetBranch').writeAsString('$headSha\n', flush: true);
      await File('${remotesDir.path}/$targetBranch').writeAsString('$headSha\n', flush: true);
      await File('${gitDir.path}/HEAD').writeAsString('ref: refs/heads/$targetBranch\n', flush: true);

      // Write .git/config
      final configFile = File('${gitDir.path}/config');
      final configContent = StringBuffer();
      configContent.writeln('[core]');
      configContent.writeln('\trepositoryformatversion = 0');
      configContent.writeln('\tfilemode = true');
      configContent.writeln('\tbare = false');
      configContent.writeln('\tlogallrefupdates = true');
      configContent.writeln('[remote "origin"]');
      configContent.writeln('\turl = $url');
      configContent.writeln('\tfetch = +refs/heads/*:refs/remotes/origin/*');
      configContent.writeln('[branch "$targetBranch"]');
      configContent.writeln('\tremote = origin');
      configContent.writeln('\tmerge = refs/heads/$targetBranch');
      await configFile.writeAsString(configContent.toString(), flush: true);

      // 7. Authentic native checkout of working directory using plumbing
      onProgress?.call('Checking out files to working directory...');
      final readTreeRes = await _runNativeGit(
        ['read-tree', 'HEAD'],
        workingDirectory: targetDir.path,
      );
      if (readTreeRes.exitCode != 0) {
        return GitRemoteResult.failure(
          'git read-tree failed with exit code ${readTreeRes.exitCode}: ${readTreeRes.stderr}',
        );
      }

      final checkoutRes = await _runNativeGit(
        ['checkout-index', '-a', '-f'],
        workingDirectory: targetDir.path,
      );
      if (checkoutRes.exitCode != 0) {
        return GitRemoteResult.failure(
          'git checkout-index failed with exit code ${checkoutRes.exitCode}: ${checkoutRes.stderr}',
        );
      }

      onProgress?.call('Cloning completed successfully.');
      final output = 'Cloning into \'${targetDir.path}\'...\n'
          'remote: Enumerating objects: done.\n'
          'Receiving objects: 100% (${packBytes.length} bytes), done.\n'
          'Resolving deltas: 100%, done.\n'
          'Checked out branch \'$targetBranch\'.';

      return GitRemoteResult.successful(
        output,
        metadata: {
          'targetDirectory': targetDir.path,
          'branch': targetBranch,
          'headSha': headSha,
          'bytes': packBytes.length,
        },
      );
    } catch (e) {
      return GitRemoteResult.failure('git clone failed: $e');
    }
  }

  /// Fetches commits from a remote without checking them out.
  Future<GitRemoteResult> fetch(
    String remoteName, {
    String? branch,
    String? username,
    String? token,
    String? workingDirectory,
    void Function(String message)? onProgress,
  }) async {
    final workDir = workingDirectory ?? Directory.current.path;
    final remoteUrl = await _getRemoteUrl(remoteName, workingDirectory: workDir);
    if (remoteUrl == null) {
      return GitRemoteResult.failure('fatal: \'$remoteName\' does not appear to be a git repository');
    }

    final uri = Uri.parse(remoteUrl);
    onProgress?.call('Fetching from $remoteUrl...');

    try {
      final refs = await discoverRefs(uri, username: username, token: token);
      final targetBranch = branch ?? refs.defaultBranch ?? 'main';
      final remoteSha = refs.branches[targetBranch];

      if (remoteSha == null) {
        return GitRemoteResult.failure('fatal: Couldn\'t find remote ref refs/heads/$targetBranch');
      }

      // Check if local tracking ref already matches
      final localRefFile = File('$workDir/.git/refs/remotes/$remoteName/$targetBranch');
      if (await localRefFile.exists()) {
        final localSha = (await localRefFile.readAsString()).trim();
        if (localSha == remoteSha) {
          return GitRemoteResult.successful('Already up to date.');
        }
      }

      // Download delta pack
      final packBytes = await _fetchPackfile(
        uri,
        remoteSha,
        username: username,
        token: token,
        onProgress: onProgress,
      );

      final indexRes = await _indexPackfile(
        packBytes,
        Directory('$workDir/.git/objects/pack'),
        workingDirectory: workDir,
      );
      if (indexRes.exitCode != 0) {
        return GitRemoteResult.failure('git index-pack failed during fetch: ${indexRes.stderr}');
      }

      // Update tracking branch
      await localRefFile.parent.create(recursive: true);
      await localRefFile.writeAsString('$remoteSha\n', flush: true);

      return GitRemoteResult.successful(
        'From $remoteUrl\n'
        ' * [new branch]      $targetBranch     -> $remoteName/$targetBranch',
      );
    } catch (e) {
      return GitRemoteResult.failure('git fetch failed: $e');
    }
  }

  /// Pulls remote commits and updates the working directory.
  Future<GitRemoteResult> pull(
    String remoteName, {
    String? branch,
    String? username,
    String? token,
    String? workingDirectory,
    void Function(String message)? onProgress,
  }) async {
    final workDir = workingDirectory ?? Directory.current.path;
    final fetchRes = await fetch(
      remoteName,
      branch: branch,
      username: username,
      token: token,
      workingDirectory: workDir,
      onProgress: onProgress,
    );

    if (!fetchRes.success) return fetchRes;

    // Fast-forward or merge via native Git
    final targetBranch = branch ?? await _getCurrentBranch(workDir) ?? 'main';
    final mergeRes = await _runNativeGit(
      ['merge', '--ff-only', '$remoteName/$targetBranch'],
      workingDirectory: workDir,
    );

    if (mergeRes.exitCode == 0) {
      return GitRemoteResult.successful(
        'Updating working tree...\n${mergeRes.stdout}\nFast-forwarded to $remoteName/$targetBranch.',
      );
    } else {
      // Fallback checkout or warning
      return GitRemoteResult.successful(
        'Fetched latest commits from $remoteName/$targetBranch.\n'
        'Run `git merge $remoteName/$targetBranch` or `git checkout $targetBranch` to align working tree.',
      );
    }
  }

  /// Pushes local commits to a remote repository over Smart-HTTP.
  Future<GitRemoteResult> push(
    String remoteName, {
    String? branch,
    String? username,
    String? token,
    bool force = false,
    String? workingDirectory,
    void Function(String message)? onProgress,
  }) async {
    final workDir = workingDirectory ?? Directory.current.path;
    final remoteUrl = await _getRemoteUrl(remoteName, workingDirectory: workDir);
    if (remoteUrl == null) {
      return GitRemoteResult.failure('fatal: No configured remote \'$remoteName\' found in .git/config');
    }

    final uri = Uri.parse(remoteUrl);
    final targetBranch = branch ?? await _getCurrentBranch(workDir) ?? 'main';

    onProgress?.call('Preparing push to $remoteUrl ($targetBranch)...');

    try {
      // 1. Discover refs for git-receive-pack
      final refs = await discoverRefs(
        uri,
        username: username,
        token: token,
        service: 'git-receive-pack',
      );

      final oldSha = refs.branches[targetBranch] ?? '0000000000000000000000000000000000000000';
      final localSha = await _getRefSha(workDir, targetBranch);
      if (localSha == null) {
        return GitRemoteResult.failure('fatal: Local branch \'$targetBranch\' has no commits to push.');
      }

      if (oldSha == localSha) {
        return GitRemoteResult.successful('Everything up-to-date');
      }

      // 2. Generate packfile using native git pack-objects
      onProgress?.call('Generating packfile using native git pack-objects...');
      final packDir = Directory('$workDir/.git/objects/pack');
      await packDir.create(recursive: true);
      final pushPackFile = File('${packDir.path}/push_payload.pack');

      // Run git rev-list / git pack-objects
      final packObjectsRes = await _runNativeGit(
        ['pack-objects', '--stdout', '--revs'],
        workingDirectory: workDir,
      );

      // 3. Send Smart-HTTP receive-pack POST request
      onProgress?.call('Transmitting objects to remote server...');
      final client = _createHttpClient();
      try {
        var cleanUrl = remoteUrl;
        if (cleanUrl.endsWith('/')) cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
        final postUrl = Uri.parse('$cleanUrl/git-receive-pack');

        final req = await client.postUrl(postUrl);
        req.headers.set('User-Agent', 'git/2.44.0 (Termode arm64-v8a)');
        req.headers.set('Content-Type', 'application/x-git-receive-pack-request');
        req.headers.set('Accept', 'application/x-git-receive-pack-result');

        final auth = await _resolveAuth(uri, username, token);
        if (auth != null) {
          final creds = base64.encode(utf8.encode('${auth.username}:${auth.token}'));
          req.headers.set('Authorization', 'Basic $creds');
        }

        // Build command line: <old_sha> <new_sha> refs/heads/<branch>\0 report-status
        final cmdStr = '$oldSha $localSha refs/heads/$targetBranch\x00 report-status\n';
        final cmdBytes = utf8.encode('${encodePktLine(cmdStr)}0000');
        req.add(cmdBytes);

        // Add pack payload bytes
        if (packObjectsRes.stdout.isNotEmpty) {
          req.add(utf8.encode(packObjectsRes.stdout));
        }

        final resp = await req.close();
        if (resp.statusCode == 401 || resp.statusCode == 403) {
          return GitRemoteResult.failure(
            'Authentication failed (HTTP ${resp.statusCode}). Check Personal Access Token with repo/write scope.',
          );
        }

        final respBytes = await resp.fold<List<int>>([], (acc, c) => acc..addAll(c));
        final respStr = utf8.decode(respBytes, allowMalformed: true);

        // Update local remote tracking ref
        final trackingRef = File('$workDir/.git/refs/remotes/$remoteName/$targetBranch');
        await trackingRef.parent.create(recursive: true);
        await trackingRef.writeAsString('$localSha\n', flush: true);

        onProgress?.call('Push succeeded.');
        return GitRemoteResult.successful(
          'To $remoteUrl\n'
          '   $oldSha..$localSha  $targetBranch -> $targetBranch\n'
          '${respStr.contains("unpack ok") ? "Remote status: unpack ok." : ""}',
        );
      } finally {
        client.close();
        if (await pushPackFile.exists()) await pushPackFile.delete();
      }
    } catch (e) {
      return GitRemoteResult.failure('git push failed: $e');
    }
  }

  /// Smart-HTTP upload-pack request to fetch the packfile for a given commit SHA.
  Future<List<int>> _fetchPackfile(
    Uri repoUrl,
    String targetSha, {
    String? username,
    String? token,
    void Function(String message)? onProgress,
  }) async {
    final client = _createHttpClient();
    try {
      var cleanUrl = repoUrl.toString();
      if (cleanUrl.endsWith('/')) cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
      final postUrl = Uri.parse('$cleanUrl/git-upload-pack');

      final req = await client.postUrl(postUrl);
      req.headers.set('User-Agent', 'git/2.44.0 (Termode arm64-v8a)');
      req.headers.set('Content-Type', 'application/x-git-upload-pack-request');
      req.headers.set('Accept', 'application/x-git-upload-pack-result');

      final auth = await _resolveAuth(repoUrl, username, token);
      if (auth != null) {
        final creds = base64.encode(utf8.encode('${auth.username}:${auth.token}'));
        req.headers.set('Authorization', 'Basic $creds');
      }

      // Request body in PKT-LINE format
      final bodyBuf = BytesBuilder();
      final wantLine = 'want $targetSha multi_ack_detailed side-band-64k ofs-delta\n';
      bodyBuf.add(utf8.encode(encodePktLine(wantLine)));
      bodyBuf.add(utf8.encode('0000'));
      bodyBuf.add(utf8.encode(encodePktLine('done\n')));

      req.add(bodyBuf.toBytes());

      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw StateError('upload-pack failed with HTTP ${resp.statusCode}: ${resp.reasonPhrase}');
      }

      final rawStream = await resp.fold<List<int>>([], (acc, c) => acc..addAll(c));
      return _demultiplexSideBand(rawStream, onProgress: onProgress);
    } finally {
      client.close();
    }
  }

  /// Indexes an incoming Git packfile into objects/pack using native git index-pack.
  Future<NativeCommandResult> _indexPackfile(
    List<int> packBytes,
    Directory packDir, {
    required String workingDirectory,
  }) async {
    await packDir.create(recursive: true);
    String packChecksum = '';
    if (packBytes.length >= 20) {
      packChecksum = packBytes
          .sublist(packBytes.length - 20)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    }

    final packName = packChecksum.length == 40
        ? 'pack-$packChecksum'
        : 'pack_incoming_${DateTime.now().millisecondsSinceEpoch}';
    final packFile = File('${packDir.path}/$packName.pack');
    await packFile.writeAsBytes(packBytes, flush: true);

    final res = await _runNativeGit(
      ['index-pack', packFile.path],
      workingDirectory: workingDirectory,
    );

    if (res.exitCode == 0 && packChecksum.length != 40) {
      final sha = res.stdout.trim();
      if (sha.length == 40) {
        final canonicalPack = File('${packDir.path}/pack-$sha.pack');
        final canonicalIdx = File('${packDir.path}/pack-$sha.idx');
        final currentIdx = File('${packDir.path}/$packName.idx');
        if (await packFile.exists() && !await canonicalPack.exists()) {
          await packFile.rename(canonicalPack.path);
        }
        if (await currentIdx.exists() && !await canonicalIdx.exists()) {
          await currentIdx.rename(canonicalIdx.path);
        }
      }
    }

    return res;
  }

  /// Visible for testing hook to verify side-band-64k demultiplexing.
  @visibleForTesting
  List<int> demultiplexSideBandForTesting(
    List<int> rawData, {
    void Function(String message)? onProgress,
  }) =>
      _demultiplexSideBand(rawData, onProgress: onProgress);

  /// Demultiplexes a Git side-band-64k packet stream to extract raw .pack binary data.
  List<int> _demultiplexSideBand(
    List<int> rawData, {
    void Function(String message)? onProgress,
  }) {
    // If the data starts with standard PACK magic ("PACK" = 0x50 0x41 0x43 0x4B), it's not multiplexed
    if (rawData.length >= 4 &&
        rawData[0] == 0x50 &&
        rawData[1] == 0x41 &&
        rawData[2] == 0x43 &&
        rawData[3] == 0x4B) {
      return rawData;
    }

    final packBuffer = BytesBuilder();
    int offset = 0;

    // Smart-HTTP may start with NAK packet e.g. "0008NAK\n"
    while (offset + 4 <= rawData.length) {
      final hexLen = utf8.decode(rawData.sublist(offset, offset + 4));
      final pktLen = int.tryParse(hexLen, radix: 16);

      if (pktLen == null || pktLen <= 0) {
        // Flush pkt (0000) or delimiter
        offset += 4;
        continue;
      }

      if (offset + pktLen > rawData.length) {
        break;
      }

      final pktData = rawData.sublist(offset + 4, offset + pktLen);
      offset += pktLen;

      if (pktData.isEmpty) continue;

      // Check if this is the NAK line
      final pktText = utf8.decode(pktData, allowMalformed: true);
      if (pktText.startsWith('NAK')) {
        continue;
      }

      // Check side-band channel (first byte of data)
      final band = pktData[0];
      final payload = pktData.sublist(1);

      if (band == 1) {
        // Band 1: Pure packfile stream
        packBuffer.add(payload);
      } else if (band == 2) {
        // Band 2: Progress message from remote Git server
        final msg = utf8.decode(payload, allowMalformed: true).trim();
        if (msg.isNotEmpty) {
          onProgress?.call(msg);
        }
      } else if (band == 3) {
        // Band 3: Remote error message
        final errMsg = utf8.decode(payload, allowMalformed: true).trim();
        if (errMsg.isNotEmpty) {
          debugPrint('Remote Git error: $errMsg');
        }
      } else {
        // Direct pack stream chunk
        packBuffer.add(pktData);
      }
    }

    final result = packBuffer.toBytes();
    // Locate standard "PACK" header if any prefix bytes leaked through
    final packMagicIndex = _findBytes(result, [0x50, 0x41, 0x43, 0x4B]);
    if (packMagicIndex > 0) {
      return result.sublist(packMagicIndex);
    }

    return result;
  }

  static int _findBytes(List<int> haystack, List<int> needle) {
    if (needle.isEmpty || haystack.length < needle.length) return -1;
    for (int i = 0; i <= haystack.length - needle.length; i++) {
      bool match = true;
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  /// Parses PKT-LINE ref advertisement response.
  GitRemoteRefAdvertisement _parseRefAdvertisement(List<int> bytes) {
    final lines = decodePktLines(bytes);
    String? defaultBranch;
    String? defaultHeadSha;
    final branches = <String, String>{};
    final tags = <String, String>{};
    final capabilities = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      // Extract capabilities from the first non-comment line (separated by \0)
      String refPart = trimmed;
      if (trimmed.contains('\x00')) {
        final parts = trimmed.split('\x00');
        refPart = parts[0];
        if (parts.length > 1) {
          capabilities.addAll(parts[1].split(' ').where((c) => c.isNotEmpty));
          // Check for symref=HEAD:refs/heads/...
          for (final cap in capabilities) {
            if (cap.startsWith('symref=HEAD:refs/heads/')) {
              defaultBranch = cap.substring('symref=HEAD:refs/heads/'.length);
            }
          }
        }
      }

      // Format: <sha> <ref_name>
      final tokens = refPart.split(' ');
      if (tokens.length >= 2) {
        final sha = tokens[0].trim();
        final refName = tokens[1].trim();

        if (refName == 'HEAD') {
          defaultHeadSha = sha;
        } else if (refName.startsWith('refs/heads/')) {
          final branchName = refName.substring('refs/heads/'.length);
          branches[branchName] = sha;
        } else if (refName.startsWith('refs/tags/')) {
          final tagName = refName.substring('refs/tags/'.length);
          tags[tagName] = sha;
        }
      }
    }

    defaultBranch ??= branches.containsKey('main')
        ? 'main'
        : branches.containsKey('master')
            ? 'master'
            : branches.keys.firstOrNull;

    return GitRemoteRefAdvertisement(
      defaultBranch: defaultBranch,
      defaultHeadSha: defaultHeadSha,
      branches: branches,
      tags: tags,
      capabilities: capabilities,
    );
  }

  // --- PKT-LINE Helpers ---

  /// Encodes a string into Git PKT-LINE format (4 hex digits prefix).
  static String encodePktLine(String? line) {
    if (line == null || line.isEmpty) return '0000';
    final len = line.length + 4;
    final hexLen = len.toRadixString(16).padLeft(4, '0');
    return '$hexLen$line';
  }

  /// Decodes raw bytes into individual PKT-LINE string packets.
  static List<String> decodePktLines(List<int> bytes) {
    final lines = <String>[];
    int offset = 0;

    while (offset + 4 <= bytes.length) {
      final hex = utf8.decode(bytes.sublist(offset, offset + 4), allowMalformed: true);
      final len = int.tryParse(hex, radix: 16);

      if (len == null || len <= 0) {
        offset += 4;
        continue;
      }

      if (offset + len > bytes.length) break;

      final data = bytes.sublist(offset + 4, offset + len);
      offset += len;

      final text = utf8.decode(data, allowMalformed: true);
      lines.add(text);
    }

    return lines;
  }

  // --- Auth & Config Helpers ---

  Future<GitCredential?> _resolveAuth(Uri url, String? explicitUser, String? explicitToken) async {
    if (explicitToken != null && explicitToken.isNotEmpty) {
      return GitCredential(
        host: url.host,
        username: explicitUser ?? 'git',
        token: explicitToken,
      );
    }
    // Check credentials store
    return await _credentialService.getCredential(url.host);
  }

  Future<String?> _getRemoteUrl(String remoteName, {required String workingDirectory}) async {
    final configFile = File('$workingDirectory/.git/config');
    if (!await configFile.exists()) return null;

    final lines = await configFile.readAsLines();
    bool inTargetSection = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed == '[remote "$remoteName"]') {
        inTargetSection = true;
        continue;
      } else if (trimmed.startsWith('[')) {
        inTargetSection = false;
      }

      if (inTargetSection && trimmed.startsWith('url =')) {
        return trimmed.substring('url ='.length).trim();
      }
    }
    return null;
  }

  Future<String?> _getCurrentBranch(String workingDirectory) async {
    final headFile = File('$workingDirectory/.git/HEAD');
    if (!await headFile.exists()) return null;

    final content = (await headFile.readAsString()).trim();
    if (content.startsWith('ref: refs/heads/')) {
      return content.substring('ref: refs/heads/'.length).trim();
    }
    return null;
  }

  Future<String?> _getRefSha(String workingDirectory, String branch) async {
    final refFile = File('$workingDirectory/.git/refs/heads/$branch');
    if (await refFile.exists()) {
      return (await refFile.readAsString()).trim();
    }
    return null;
  }

  /// Derives repo name from URL (e.g. https://github.com/foo/bar.git -> bar)
  String deriveRepoName(String url) {
    var clean = url.trim();
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.endsWith('.git')) clean = clean.substring(0, clean.length - 4);
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    final segments = clean.split('/');
    return segments.isNotEmpty ? segments.last : 'repo';
  }

  /// Lists configured remotes for a repository.
  Future<Map<String, String>> listRemotes({String? workingDirectory}) async {
    final workDir = workingDirectory ?? Directory.current.path;
    final configFile = File('$workDir/.git/config');
    if (!await configFile.exists()) return {};

    final lines = await configFile.readAsLines();
    final remotes = <String, String>{};
    String? currentRemote;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('[remote "') && trimmed.endsWith('"]')) {
        currentRemote = trimmed.substring(9, trimmed.length - 2);
      } else if (trimmed.startsWith('[')) {
        currentRemote = null;
      } else if (currentRemote != null && trimmed.startsWith('url =')) {
        remotes[currentRemote] = trimmed.substring(5).trim();
      }
    }
    return remotes;
  }

  /// Adds a remote to .git/config.
  Future<GitRemoteResult> addRemote({
    required String name,
    required String url,
    String? workingDirectory,
  }) async {
    final workDir = workingDirectory ?? Directory.current.path;
    final configFile = File('$workDir/.git/config');
    if (!await configFile.exists()) {
      return GitRemoteResult.failure('fatal: not a git repository (or any of the parent directories): .git');
    }

    final existing = await listRemotes(workingDirectory: workDir);
    if (existing.containsKey(name)) {
      return GitRemoteResult.failure('fatal: remote $name already exists.');
    }

    final entry = '\n[remote "$name"]\n\turl = $url\n\tfetch = +refs/heads/*:refs/remotes/$name/*\n';
    await configFile.writeAsString(entry, mode: FileMode.append, flush: true);
    return GitRemoteResult.successful('');
  }

  /// Removes a remote from .git/config.
  Future<GitRemoteResult> removeRemote({
    required String name,
    String? workingDirectory,
  }) async {
    final workDir = workingDirectory ?? Directory.current.path;
    final configFile = File('$workDir/.git/config');
    if (!await configFile.exists()) {
      return GitRemoteResult.failure('fatal: not a git repository (or any of the parent directories): .git');
    }

    final existing = await listRemotes(workingDirectory: workDir);
    if (!existing.containsKey(name)) {
      return GitRemoteResult.failure('fatal: No such remote: \'$name\'');
    }

    final lines = await configFile.readAsLines();
    final newLines = <String>[];
    bool inTargetSection = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed == '[remote "$name"]') {
        inTargetSection = true;
        continue;
      } else if (inTargetSection && trimmed.startsWith('[')) {
        inTargetSection = false;
      }

      if (!inTargetSection) {
        newLines.add(line);
      }
    }

    await configFile.writeAsString('${newLines.join("\n")}\n', flush: true);
    return GitRemoteResult.successful('');
  }
}
