import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'runtime_bootstrap_service.dart';

typedef PackageHttpBytesFetcher = Future<List<int>> Function(Uri uri);

class PackageOperationResult {
  final String output;
  final bool isError;
  final bool changedHelpers;
  final String? executable;

  const PackageOperationResult({
    required this.output,
    this.isError = false,
    this.changedHelpers = false,
    this.executable,
  });
}

class _MetadataReadResult {
  final Map<String, dynamic> data;
  final bool exists;
  final bool isCorrupt;
  final String? error;

  const _MetadataReadResult({
    required this.data,
    required this.exists,
    this.isCorrupt = false,
    this.error,
  });
}

class _RepoConfig {
  final String repoUrl;
  final String? lastUpdatedAt;
  final String lastUpdateSource;
  final bool remoteEnabled;
  final bool fallbackToLocal;

  const _RepoConfig({
    required this.repoUrl,
    required this.lastUpdatedAt,
    required this.lastUpdateSource,
    required this.remoteEnabled,
    required this.fallbackToLocal,
  });

  factory _RepoConfig.defaults() {
    return const _RepoConfig(
      repoUrl: '',
      lastUpdatedAt: null,
      lastUpdateSource: 'local',
      remoteEnabled: false,
      fallbackToLocal: true,
    );
  }

  factory _RepoConfig.fromJson(Map<String, dynamic> json) {
    return _RepoConfig(
      repoUrl: json['repoUrl']?.toString() ?? '',
      lastUpdatedAt: json['lastUpdatedAt']?.toString(),
      lastUpdateSource: json['lastUpdateSource']?.toString() == 'remote'
          ? 'remote'
          : 'local',
      remoteEnabled: json['remoteEnabled'] == true,
      fallbackToLocal: json['fallbackToLocal'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'repoUrl': repoUrl,
      'lastUpdatedAt': lastUpdatedAt,
      'lastUpdateSource': lastUpdateSource,
      'remoteEnabled': remoteEnabled,
      'fallbackToLocal': fallbackToLocal,
    };
  }

  _RepoConfig copyWith({
    String? repoUrl,
    String? lastUpdatedAt,
    String? lastUpdateSource,
    bool? remoteEnabled,
    bool? fallbackToLocal,
  }) {
    return _RepoConfig(
      repoUrl: repoUrl ?? this.repoUrl,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      lastUpdateSource: lastUpdateSource ?? this.lastUpdateSource,
      remoteEnabled: remoteEnabled ?? this.remoteEnabled,
      fallbackToLocal: fallbackToLocal ?? this.fallbackToLocal,
    );
  }
}

class _PackageIndex {
  final Map<String, Map<String, dynamic>> packages;
  final String source;
  final String? repoUrl;

  const _PackageIndex({
    required this.packages,
    required this.source,
    this.repoUrl,
  });
}

class PackageManagerService {
  static final PackageManagerService _instance =
      PackageManagerService._internal();
  factory PackageManagerService() => _instance;
  PackageManagerService._internal();

  static const int schemaVersion = 2;
  static const String managedBy = 'TermodePackageManager';
  static const String helperReloadCommand =
      '[ -f "\$TERMODE_USR/termode-shell-helpers.sh" ] && . "\$TERMODE_USR/termode-shell-helpers.sh"';
  static PackageHttpBytesFetcher? httpBytesFetcherForTesting;

  static const Map<String, Map<String, dynamic>> localIndex = {
    'hello': {
      'name': 'hello',
      'version': '1.0.0',
      'type': 'script',
      'description': 'Prints a hello message from Termode package manager.',
      'executable': 'hello',
      'files': {
        'usr/bin/hello':
            '#!/system/bin/sh\necho "Hello from Termode package manager!"\n',
      },
    },
    'cowsay-lite': {
      'name': 'cowsay-lite',
      'version': '1.0.0',
      'type': 'script',
      'description': 'Prints text in a simple ASCII speech bubble.',
      'executable': 'cowsay-lite',
      'files': {
        'usr/bin/cowsay-lite':
            '#!/system/bin/sh\n'
            'if [ \$# -eq 0 ]; then\n'
            '  msg="Moo"\n'
            'else\n'
            '  msg="\$*"\n'
            'fi\n'
            'echo " ____________________"\n'
            'echo "< \$msg >"\n'
            'echo " --------------------"\n'
            'echo \'        \\   ^__^\'\n'
            'echo \'         \\  (oo)\\_______\'\n'
            'echo \'            (__)\\       )\\/\\\'\n'
            'echo \'                ||----w |\'\n'
            'echo \'                ||     ||\'\n',
      },
    },
    'sysinfo-lite': {
      'name': 'sysinfo-lite',
      'version': '1.0.0',
      'type': 'script',
      'description':
          'Prints basic Android/system information using shell commands.',
      'executable': 'sysinfo-lite',
      'files': {
        'usr/bin/sysinfo-lite':
            '#!/system/bin/sh\n'
            'echo "=== Termode System Information ==="\n'
            'echo "OS: \$(uname -o 2>/dev/null || echo Android)"\n'
            'echo "Kernel: \$(uname -r)"\n'
            'echo "Uptime: \$(uptime)"\n'
            'echo "Device Model: \$(getprop ro.product.model 2>/dev/null || echo Unknown)"\n'
            'echo "Brand: \$(getprop ro.product.brand 2>/dev/null || echo Unknown)"\n'
            'echo "Android Version: \$(getprop ro.build.version.release 2>/dev/null || echo Unknown)"\n'
            'echo "CPU Architecture: \$(getprop ro.product.cpu.abi 2>/dev/null || echo Unknown)"\n',
      },
    },
  };

  String _calculateFnv1a(String content) {
    final bytes = utf8.encode(content);
    int hash = 2166136261;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _calculateSha256(List<int> input) {
    final bytes = List<int>.from(input);
    final bitLength = bytes.length * 8;
    bytes.add(0x80);
    while ((bytes.length % 64) != 56) {
      bytes.add(0);
    }
    for (var shift = 56; shift >= 0; shift -= 8) {
      bytes.add((bitLength >> shift) & 0xff);
    }

    final k = <int>[
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

    int rotr(int value, int shift) {
      return ((value >> shift) | (value << (32 - shift))) & 0xffffffff;
    }

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
        final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
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
    ].map((part) => part.toRadixString(16).padLeft(8, '0')).join();
  }

  Map<String, dynamic> _emptyMetadata() {
    return {'schemaVersion': schemaVersion, 'packages': <String, dynamic>{}};
  }

  Future<Map<String, String>> _paths() async {
    final paths = await RuntimeBootstrapService().getPaths();
    final filesDir = '${paths['home']!}/..';
    return {'files': filesDir, 'usr': paths['usr']!, 'bin': paths['bin']!};
  }

  File _metadataFile(String usrDir) => File('$usrDir/termode-packages.json');
  File _repoConfigFile(String usrDir) => File('$usrDir/termode-repo.json');
  File _remoteIndexFile(String usrDir) =>
      File('$usrDir/termode-remote-index.json');

  Future<_RepoConfig> _readRepoConfig() async {
    final paths = await _paths();
    final file = _repoConfigFile(paths['usr']!);
    if (!await file.exists()) {
      return _RepoConfig.defaults();
    }
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return _RepoConfig.fromJson(data);
    } catch (_) {
      return _RepoConfig.defaults();
    }
  }

  Future<void> _writeRepoConfig(_RepoConfig config) async {
    final paths = await _paths();
    await _repoConfigFile(
      paths['usr']!,
    ).writeAsString(jsonEncode(config.toJson()));
  }

  bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  String? _validateRepoUrl(String value) {
    if (value.trim().isEmpty) {
      return 'repo URL missing';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      return 'invalid URL';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'unsupported URL scheme: ${uri.scheme}';
    }
    if (uri.host.isEmpty) {
      return 'invalid URL';
    }
    return null;
  }

  Future<List<int>> _fetchBytes(Uri uri) async {
    if (httpBytesFetcherForTesting != null) {
      return httpBytesFetcherForTesting!(uri);
    }
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  String _normalizePath(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    final result = <String>[];
    for (final part in parts) {
      if (part.isEmpty || part == '.') {
        continue;
      }
      if (part == '..') {
        if (result.isNotEmpty) {
          result.removeLast();
        }
      } else {
        result.add(part);
      }
    }
    final prefix = path.startsWith('/') || path.contains(':') ? '' : '/';
    return '$prefix${result.join('/')}';
  }

  bool _isSafePackageName(String name) {
    return name.isNotEmpty &&
        !name.contains('/') &&
        !name.contains('\\') &&
        !name.contains('..');
  }

  bool _isSafeManagedRelPath(String relPath) {
    if (relPath.isEmpty ||
        relPath.contains('..') ||
        relPath.startsWith('/') ||
        relPath.contains('\\') ||
        !relPath.startsWith('usr/bin/')) {
      return false;
    }
    final segments = relPath.split('/');
    return segments.every((segment) => segment.isNotEmpty && segment != '.');
  }

  File? _resolveManagedFile(String filesDir, String relPath) {
    if (!_isSafeManagedRelPath(relPath)) {
      return null;
    }

    final target = File('$filesDir/$relPath');
    final normalizedTarget = _normalizePath(target.path);
    final normalizedBin = _normalizePath('$filesDir/usr/bin');
    if (normalizedTarget == normalizedBin ||
        normalizedTarget.startsWith('$normalizedBin/')) {
      return target;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _readCachedRemoteIndexData() async {
    final paths = await _paths();
    final file = _remoteIndexFile(paths['usr']!);
    if (!await file.exists()) {
      return null;
    }
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Map<String, Map<String, dynamic>> _packagesFromRemoteIndex(
    Map<String, dynamic> data,
    String repoUrl,
  ) {
    final packages = <String, Map<String, dynamic>>{};
    final list = data['packages'] as List<dynamic>? ?? [];
    for (final item in list) {
      if (item is Map) {
        final pkg = Map<String, dynamic>.from(item);
        final name = pkg['name']?.toString();
        if (name != null && name.isNotEmpty) {
          pkg['source'] = 'remote';
          pkg['repoUrl'] = repoUrl;
          packages[name] = pkg;
        }
      }
    }
    return packages;
  }

  Future<_PackageIndex> _activePackageIndex() async {
    final config = await _readRepoConfig();
    if (config.lastUpdateSource == 'remote' && config.repoUrl.isNotEmpty) {
      final cached = await _readCachedRemoteIndexData();
      if (cached != null) {
        return _PackageIndex(
          packages: _packagesFromRemoteIndex(cached, config.repoUrl),
          source: 'remote',
          repoUrl: config.repoUrl,
        );
      }
    }
    return _PackageIndex(packages: localIndex, source: 'local');
  }

  Future<Map<String, dynamic>> _validateRemoteIndex(
    String content,
    String repoUrl,
  ) async {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('invalid index JSON');
    }
    if (!decoded.containsKey('schemaVersion')) {
      throw const FormatException('missing schemaVersion');
    }
    if (decoded['schemaVersion'] != 1) {
      throw const FormatException('unsupported schema');
    }
    final packages = decoded['packages'];
    if (packages is! List) {
      throw const FormatException('invalid index JSON');
    }

    for (final item in packages) {
      if (item is! Map) {
        throw const FormatException('invalid package entry');
      }
      final pkg = Map<String, dynamic>.from(item);
      final name = pkg['name']?.toString() ?? '';
      final executable = pkg['executable']?.toString() ?? '';
      if (!_isSafePackageName(name) || !_isSafePackageName(executable)) {
        throw const FormatException('invalid package name');
      }
      if (pkg['type']?.toString() != 'script') {
        throw const FormatException('only script packages are supported');
      }
      final files = pkg['files'];
      if (files is! List || files.isEmpty) {
        throw const FormatException('invalid package files');
      }
      for (final f in files) {
        if (f is! Map) {
          throw const FormatException('invalid package file');
        }
        final file = Map<String, dynamic>.from(f);
        final path = file['path']?.toString() ?? '';
        final url = file['url']?.toString() ?? '';
        final sha256 = file['sha256']?.toString() ?? '';
        if (!_isSafeManagedRelPath(path)) {
          throw const FormatException('unsafe package path');
        }
        if (sha256.isEmpty) {
          throw const FormatException('Remote package missing checksum.');
        }
        if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
          throw const FormatException('invalid checksum');
        }
        final resolved = Uri.parse(repoUrl).resolve(url);
        if (!_isHttpUrl(resolved.toString())) {
          throw const FormatException('unsupported URL scheme');
        }
      }
    }

    return decoded;
  }

  Future<_MetadataReadResult> _readMetadata({bool missingOk = true}) async {
    final paths = await _paths();
    final file = _metadataFile(paths['usr']!);
    if (!await file.exists()) {
      if (missingOk) {
        return _MetadataReadResult(data: _emptyMetadata(), exists: false);
      }
      return _MetadataReadResult(
        data: _emptyMetadata(),
        exists: false,
        isCorrupt: true,
        error: 'metadata missing',
      );
    }

    try {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      data['schemaVersion'] = data['schemaVersion'] ?? 1;
      data['packages'] ??= <String, dynamic>{};
      if (data['packages'] is! Map) {
        return _MetadataReadResult(
          data: _emptyMetadata(),
          exists: true,
          isCorrupt: true,
          error: 'packages field is not an object',
        );
      }
      return _MetadataReadResult(data: data, exists: true);
    } catch (e) {
      return _MetadataReadResult(
        data: _emptyMetadata(),
        exists: true,
        isCorrupt: true,
        error: e.toString(),
      );
    }
  }

  Future<void> _writeMetadata(Map<String, dynamic> data) async {
    final paths = await _paths();
    final file = _metadataFile(paths['usr']!);
    data['schemaVersion'] = schemaVersion;
    data['packages'] ??= <String, dynamic>{};
    await file.writeAsString(jsonEncode(data));
  }

  Map<String, dynamic> _packageMetadata(
    String pkgName,
    Map<String, dynamic> pkg,
    List<String> installedFiles,
    Map<String, String> checksums, {
    String? installedAt,
  }) {
    final now = DateTime.now().toIso8601String();
    return {
      'name': pkg['name'] ?? pkgName,
      'version': pkg['version'],
      'type': pkg['type'],
      'description': pkg['description'],
      'executable': pkg['executable'],
      'installedAt': installedAt ?? now,
      'updatedAt': now,
      'source': 'local',
      'files': installedFiles,
      'checksums': checksums,
      'managedBy': managedBy,
    };
  }

  Future<String?> _writePackageFiles(
    String filesDir,
    Map<String, dynamic> pkg,
    List<String> installedFiles,
    Map<String, String> checksums,
  ) async {
    final filesMap = pkg['files'] as Map;
    for (final entry in filesMap.entries) {
      final relPath = entry.key.toString();
      final fileContent = entry.value.toString();
      final file = _resolveManagedFile(filesDir, relPath);
      if (file == null) {
        return 'Error: path traversal detected';
      }

      await file.parent.create(recursive: true);
      await file.writeAsString(fileContent);
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['+x', file.path]);
        } catch (e) {
          debugPrint('Chmod failed: $e');
        }
      }
      installedFiles.add(relPath);
      checksums[relPath] = _calculateFnv1a(fileContent);
    }
    return null;
  }

  Future<PackageOperationResult> _installPackageIntoMetadata(
    String pkgName,
    Map<String, dynamic> data, {
    String? installedAt,
    required String successVerb,
  }) async {
    if (!_isSafePackageName(pkgName)) {
      return const PackageOperationResult(
        output: 'Error: invalid package name',
        isError: true,
      );
    }

    final paths = await _paths();
    final pkg = localIndex[pkgName];
    if (pkg == null) {
      return PackageOperationResult(
        output: 'Error: package not found: $pkgName',
        isError: true,
      );
    }

    final installedFiles = <String>[];
    final checksums = <String, String>{};
    final writeError = await _writePackageFiles(
      paths['files']!,
      pkg,
      installedFiles,
      checksums,
    );
    if (writeError != null) {
      return PackageOperationResult(output: writeError, isError: true);
    }

    final packages = data['packages'] as Map;
    packages[pkgName] = _packageMetadata(
      pkgName,
      pkg,
      installedFiles,
      checksums,
      installedAt: installedAt,
    );

    await _writeMetadata(data);
    await updateShellHelpers();

    return PackageOperationResult(
      output: '$successVerb package $pkgName',
      changedHelpers: true,
      executable: pkg['executable'] as String? ?? pkgName,
    );
  }

  Uri _resolvePackageFileUri(String repoUrl, String fileUrl) {
    return Uri.parse(repoUrl).resolve(fileUrl);
  }

  Future<PackageOperationResult> _installRemotePackageIntoMetadata(
    String pkgName,
    Map<String, dynamic> data,
    Map<String, dynamic> pkg, {
    String? installedAt,
    required String successVerb,
  }) async {
    if (!_isSafePackageName(pkgName)) {
      return const PackageOperationResult(
        output: 'Error: invalid package name',
        isError: true,
      );
    }
    final repoUrl = pkg['repoUrl']?.toString() ?? '';
    if (!_isHttpUrl(repoUrl)) {
      return const PackageOperationResult(
        output: 'Error: invalid remote repository URL',
        isError: true,
      );
    }
    final files = pkg['files'] as List<dynamic>? ?? [];
    final paths = await _paths();
    final packages = data['packages'] as Map;
    final writtenFiles = <File>[];
    final installedFiles = <String>[];
    final checksums = <String, String>{};
    final fileUrls = <String, String>{};

    Future<PackageOperationResult> failInstall(String output) async {
      for (final file in writtenFiles) {
        if (await file.exists()) {
          await file.delete();
        }
      }
      return PackageOperationResult(output: output, isError: true);
    }

    try {
      for (final item in files) {
        final fileMeta = Map<String, dynamic>.from(item as Map);
        final relPath = fileMeta['path']?.toString() ?? '';
        final sha256 = fileMeta['sha256']?.toString() ?? '';
        final url = fileMeta['url']?.toString() ?? '';
        if (!_isSafeManagedRelPath(relPath)) {
          return failInstall('Error: unsafe package path');
        }
        if (sha256.isEmpty) {
          return failInstall('Remote package missing checksum.');
        }
        final file = _resolveManagedFile(paths['files']!, relPath);
        if (file == null) {
          return failInstall('Error: unsafe package path');
        }
        if (await file.exists()) {
          final alreadyManaged = packages.values.any((value) {
            final info = Map<dynamic, dynamic>.from(value as Map);
            final managedFiles = info['files'] as List? ?? [];
            return managedFiles.map((f) => f.toString()).contains(relPath);
          });
          if (!alreadyManaged) {
            return failInstall(
              'Error: refusing to overwrite unmanaged file: $relPath',
            );
          }
        }

        final fileUri = _resolvePackageFileUri(repoUrl, url);
        if (!_isHttpUrl(fileUri.toString())) {
          return failInstall('Error: unsupported URL scheme');
        }
        final bytes = await _fetchBytes(fileUri);
        final actualSha = _calculateSha256(bytes);
        if (actualSha.toLowerCase() != sha256.toLowerCase()) {
          return failInstall('Error: checksum mismatch');
        }

        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        writtenFiles.add(file);
        if (!Platform.isWindows) {
          try {
            await Process.run('chmod', ['+x', file.path]);
          } catch (e) {
            debugPrint('Chmod failed: $e');
          }
        }
        installedFiles.add(relPath);
        checksums[relPath] = sha256.toLowerCase();
        fileUrls[relPath] = fileUri.toString();
      }

      final now = DateTime.now().toIso8601String();
      packages[pkgName] = {
        'name': pkg['name'] ?? pkgName,
        'version': pkg['version'],
        'type': pkg['type'],
        'description': pkg['description'],
        'executable': pkg['executable'],
        'installedAt': installedAt ?? now,
        'updatedAt': now,
        'source': 'remote',
        'repoUrl': repoUrl,
        'files': installedFiles,
        'checksums': checksums,
        'sha256': checksums,
        'fileUrls': fileUrls,
        'packageUrl': repoUrl,
        'managedBy': managedBy,
      };

      await _writeMetadata(data);
      await updateShellHelpers();
      return PackageOperationResult(
        output: '$successVerb package $pkgName',
        changedHelpers: true,
        executable: pkg['executable'] as String? ?? pkgName,
      );
    } catch (e) {
      return failInstall('Error: package file download failed: $e');
    }
  }

  Future<void> _deleteManagedFiles(
    String filesDir,
    Map<dynamic, dynamic> pkgInfo,
  ) async {
    final filesList = pkgInfo['files'] as List? ?? [];
    for (final fileObj in filesList) {
      final relPath = fileObj.toString();
      final file = _resolveManagedFile(filesDir, relPath);
      if (file != null && await file.exists()) {
        await file.delete();
      }
    }
  }

  int _compareVersions(String a, String b) {
    final left = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final right = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final len = left.length > right.length ? left.length : right.length;
    for (int i = 0; i < len; i++) {
      final lv = i < left.length ? left[i] : 0;
      final rv = i < right.length ? right[i] : 0;
      if (lv != rv) {
        return lv.compareTo(rv);
      }
    }
    return 0;
  }

  bool _isExecutableMode(FileStat stat) {
    if (Platform.isWindows) {
      return true;
    }
    return (stat.mode & 0x49) != 0;
  }

  Future<bool> _helperHasExecutable(String executable) async {
    final paths = await _paths();
    final helpersFile = File('${paths['usr']}/termode-shell-helpers.sh');
    if (!await helpersFile.exists()) {
      return false;
    }
    final content = await helpersFile.readAsString();
    return content.contains('$executable() {') ||
        content.contains('alias $executable=');
  }

  Future<Map<String, dynamic>> updateIndex() async {
    final config = await _readRepoConfig();
    if (config.remoteEnabled) {
      if (config.repoUrl.isEmpty) {
        return {
          'success': false,
          'message': 'Error: repo URL missing',
          'count': 0,
        };
      }
      try {
        final uri = Uri.parse(config.repoUrl);
        final bytes = await _fetchBytes(uri);
        final content = utf8.decode(bytes);
        final index = await _validateRemoteIndex(content, config.repoUrl);
        final paths = await _paths();
        await _remoteIndexFile(paths['usr']!).writeAsString(jsonEncode(index));
        await _writeRepoConfig(
          config.copyWith(
            lastUpdatedAt: DateTime.now().toIso8601String(),
            lastUpdateSource: 'remote',
          ),
        );
        final packages = index['packages'] as List<dynamic>;
        return {
          'success': true,
          'message': 'Fetched remote Termode package index.',
          'count': packages.length,
          'source': 'remote',
        };
      } catch (e) {
        if (config.fallbackToLocal) {
          await _writeRepoConfig(
            config.copyWith(
              lastUpdatedAt: DateTime.now().toIso8601String(),
              lastUpdateSource: 'local',
            ),
          );
          return {
            'success': true,
            'message':
                'Warning: Remote update failed. Falling back to local package index.',
            'count': localIndex.length,
            'source': 'local',
            'warning': e.toString(),
          };
        }
        return {
          'success': false,
          'message': 'Error: remote update failed: $e',
          'count': 0,
        };
      }
    }

    await _writeRepoConfig(
      config.copyWith(
        lastUpdatedAt: DateTime.now().toIso8601String(),
        lastUpdateSource: 'local',
      ),
    );
    return {
      'success': true,
      'message': 'Loaded local Termode package index.',
      'count': localIndex.length,
      'source': 'local',
    };
  }

  Future<PackageOperationResult> repoStatus() async {
    final config = await _readRepoConfig();
    final active = await _activePackageIndex();
    final cachedRemote = await _readCachedRemoteIndexData();
    final remoteCount = (cachedRemote?['packages'] as List<dynamic>?)?.length;
    final sb = StringBuffer();
    sb.writeln('=== Termode Package Repository Config ===');
    sb.writeln('Remote Enabled:     ${config.remoteEnabled ? "YES" : "NO"}');
    sb.writeln(
      'Repo URL:           ${config.repoUrl.isEmpty ? "(none)" : config.repoUrl}',
    );
    sb.writeln('Fallback To Local:  ${config.fallbackToLocal ? "YES" : "NO"}');
    sb.writeln('Last Updated:       ${config.lastUpdatedAt ?? "Never"}');
    sb.writeln('Active Index Source: ${active.source}');
    sb.writeln('Package Count:      ${active.packages.length}');
    sb.write('Cached Remote Count: ${remoteCount ?? 0}');
    return PackageOperationResult(output: sb.toString());
  }

  Future<PackageOperationResult> repoSet(String url) async {
    final trimmed = url.trim();
    final error = _validateRepoUrl(trimmed);
    if (error != null) {
      return PackageOperationResult(
        output:
            'Error: $error. Only http/https repository URLs are supported; https is recommended.',
        isError: true,
      );
    }
    final config = await _readRepoConfig();
    await _writeRepoConfig(config.copyWith(repoUrl: trimmed));
    return const PackageOperationResult(
      output: 'Repository URL saved. Run pkg update.',
    );
  }

  Future<PackageOperationResult> repoClear() async {
    final config = await _readRepoConfig();
    await _writeRepoConfig(
      config.copyWith(
        repoUrl: '',
        remoteEnabled: false,
        lastUpdateSource: 'local',
      ),
    );
    return const PackageOperationResult(
      output: 'Repository URL cleared. Remote disabled. Using local index.',
    );
  }

  Future<PackageOperationResult> repoEnable() async {
    final config = await _readRepoConfig();
    if (config.repoUrl.isEmpty) {
      return const PackageOperationResult(
        output: 'Error: repo URL missing. Run pkg repo set <url> first.',
        isError: true,
      );
    }
    await _writeRepoConfig(config.copyWith(remoteEnabled: true));
    return const PackageOperationResult(
      output: 'Remote package repository enabled. Run pkg update.',
    );
  }

  Future<PackageOperationResult> repoDisable() async {
    final config = await _readRepoConfig();
    await _writeRepoConfig(config.copyWith(remoteEnabled: false));
    return const PackageOperationResult(
      output:
          'Remote package repository disabled. pkg update will use local index.',
    );
  }

  Future<PackageOperationResult> sources() async {
    final config = await _readRepoConfig();
    final active = await _activePackageIndex();
    final cached = await _readCachedRemoteIndexData();
    final remoteCount = (cached?['packages'] as List<dynamic>?)?.length ?? 0;
    final sb = StringBuffer();
    sb.writeln('=== Termode Package Sources ===');
    sb.writeln('Local Index Packages:  ${localIndex.length}');
    sb.writeln('Cached Remote Packages: $remoteCount');
    sb.writeln('Active Source:         ${active.source}');
    sb.writeln('Remote Enabled:        ${config.remoteEnabled ? "YES" : "NO"}');
    sb.write('Fallback To Local:     ${config.fallbackToLocal ? "YES" : "NO"}');
    return PackageOperationResult(output: sb.toString());
  }

  Future<PackageOperationResult> cleanCache() async {
    final paths = await _paths();
    final file = _remoteIndexFile(paths['usr']!);
    var cleaned = false;
    if (await file.exists()) {
      await file.delete();
      cleaned = true;
    }
    return PackageOperationResult(
      output: cleaned
          ? 'Cleaned cached remote package index.'
          : 'No cached remote package index to clean.',
    );
  }

  Future<Map<String, Map<String, dynamic>>> availablePackages() async {
    return (await _activePackageIndex()).packages;
  }

  Future<String> activeIndexSource() async {
    return (await _activePackageIndex()).source;
  }

  Future<PackageOperationResult> installPackage(String pkgName) async {
    try {
      final meta = await _readMetadata();
      if (meta.isCorrupt) {
        return const PackageOperationResult(
          output: 'Error: metadata corrupted',
          isError: true,
        );
      }
      final packages = meta.data['packages'] as Map;
      if (packages.containsKey(pkgName)) {
        return PackageOperationResult(
          output: 'Error: package already installed: $pkgName',
          isError: true,
        );
      }
      final active = await _activePackageIndex();
      final remotePkg = active.packages[pkgName];
      if (remotePkg != null && remotePkg['source'] == 'remote') {
        return _installRemotePackageIntoMetadata(
          pkgName,
          meta.data,
          remotePkg,
          successVerb: 'Success: Installed',
        );
      }
      if (localIndex.containsKey(pkgName)) {
        return _installPackageIntoMetadata(
          pkgName,
          meta.data,
          successVerb: 'Success: Installed',
        );
      }
      return PackageOperationResult(
        output: 'Error: package not found: $pkgName',
        isError: true,
      );
    } catch (e) {
      return PackageOperationResult(
        output: 'Error: install failed: $e',
        isError: true,
      );
    }
  }

  Future<PackageOperationResult> removePackage(String pkgName) async {
    try {
      final meta = await _readMetadata();
      if (meta.isCorrupt) {
        return const PackageOperationResult(
          output: 'Error: metadata corrupted',
          isError: true,
        );
      }
      final packages = meta.data['packages'] as Map;
      if (!packages.containsKey(pkgName)) {
        return PackageOperationResult(
          output: 'Error: package not installed: $pkgName',
          isError: true,
        );
      }

      final paths = await _paths();
      final pkgInfo = Map<dynamic, dynamic>.from(packages[pkgName] as Map);
      await _deleteManagedFiles(paths['files']!, pkgInfo);
      packages.remove(pkgName);
      await _writeMetadata(meta.data);
      await updateShellHelpers();

      final executable =
          pkgInfo['executable'] as String? ??
          localIndex[pkgName]?['executable'] as String? ??
          pkgName;
      return PackageOperationResult(
        output: 'Success: Removed package $pkgName',
        changedHelpers: true,
        executable: executable,
      );
    } catch (e) {
      return PackageOperationResult(
        output: 'Error: remove failed: $e',
        isError: true,
      );
    }
  }

  Future<PackageOperationResult> reinstallPackage(String pkgName) async {
    try {
      final meta = await _readMetadata();
      if (meta.isCorrupt) {
        return const PackageOperationResult(
          output: 'Error: metadata corrupted',
          isError: true,
        );
      }
      final packages = meta.data['packages'] as Map;
      final existing = packages[pkgName];
      if (existing != null) {
        final paths = await _paths();
        final pkgInfo = Map<dynamic, dynamic>.from(existing as Map);
        await _deleteManagedFiles(paths['files']!, pkgInfo);
        packages.remove(pkgName);
        final active = await _activePackageIndex();
        final remotePkg = active.packages[pkgName];
        if (remotePkg != null && remotePkg['source'] == 'remote') {
          return _installRemotePackageIntoMetadata(
            pkgName,
            meta.data,
            remotePkg,
            installedAt: pkgInfo['installedAt'] as String?,
            successVerb: 'Reinstalled',
          );
        }
        return _installPackageIntoMetadata(
          pkgName,
          meta.data,
          installedAt: pkgInfo['installedAt'] as String?,
          successVerb: 'Reinstalled',
        );
      }
      return installPackage(pkgName);
    } catch (e) {
      return PackageOperationResult(
        output: 'Error: reinstall failed: $e',
        isError: true,
      );
    }
  }

  Future<PackageOperationResult> upgradePackages() async {
    try {
      final meta = await _readMetadata();
      if (meta.isCorrupt) {
        return const PackageOperationResult(
          output: 'Error: metadata corrupted',
          isError: true,
        );
      }

      final packages = meta.data['packages'] as Map;
      final upgraded = <String>[];
      final skipped = <String>[];
      final paths = await _paths();

      for (final entry in packages.entries.toList()) {
        final pkgName = entry.key.toString();
        final installed = Map<dynamic, dynamic>.from(entry.value as Map);
        if (installed['source'] == 'remote') {
          skipped.add(pkgName);
          continue;
        }
        final local = localIndex[pkgName];
        if (local == null) {
          skipped.add(pkgName);
          continue;
        }
        final installedVersion = installed['version']?.toString() ?? '0.0.0';
        final localVersion = local['version']?.toString() ?? '0.0.0';
        if (_compareVersions(installedVersion, localVersion) < 0) {
          await _deleteManagedFiles(paths['files']!, installed);
          packages.remove(pkgName);
          final result = await _installPackageIntoMetadata(
            pkgName,
            meta.data,
            installedAt: installed['installedAt'] as String?,
            successVerb: 'Upgraded',
          );
          if (result.isError) {
            return result;
          }
          upgraded.add('$pkgName $installedVersion -> $localVersion');
        }
      }

      if (upgraded.isEmpty) {
        final suffix = skipped.isEmpty
            ? ''
            : '\nSkipped packages no longer in local index: ${skipped.join(", ")}';
        return PackageOperationResult(
          output: 'All packages are up to date.$suffix',
        );
      }

      await updateShellHelpers();
      return PackageOperationResult(
        output:
            'Upgraded packages:\n${upgraded.map((p) => '  - $p').join('\n')}',
        changedHelpers: true,
      );
    } catch (e) {
      return PackageOperationResult(
        output: 'Error: upgrade failed: $e',
        isError: true,
      );
    }
  }

  Future<PackageOperationResult> repairPackages() async {
    try {
      final meta = await _readMetadata();
      if (meta.isCorrupt) {
        return PackageOperationResult(
          output:
              'Error: metadata corrupted. Cannot repair safely: ${meta.error}',
          isError: true,
        );
      }

      final packages = meta.data['packages'] as Map;
      final paths = await _paths();
      final fixedFiles = <String>[];
      final missingPackages = <String>[];

      for (final entry in packages.entries.toList()) {
        final pkgName = entry.key.toString();
        final installed = Map<dynamic, dynamic>.from(entry.value as Map);
        if (installed['source'] == 'remote') {
          continue;
        }
        final local = localIndex[pkgName];
        if (local == null) {
          packages.remove(pkgName);
          missingPackages.add(pkgName);
          continue;
        }

        final filesMap = local['files'] as Map;
        final installedFiles = <String>[];
        final checksums = <String, String>{};
        for (final fileEntry in filesMap.entries) {
          final relPath = fileEntry.key.toString();
          final expectedContent = fileEntry.value.toString();
          final file = _resolveManagedFile(paths['files']!, relPath);
          if (file == null) {
            continue;
          }
          final expectedChecksum = _calculateFnv1a(expectedContent);
          final exists = await file.exists();
          String? actualChecksum;
          if (exists) {
            actualChecksum = _calculateFnv1a(await file.readAsString());
          }
          if (!exists || actualChecksum != expectedChecksum) {
            await file.parent.create(recursive: true);
            await file.writeAsString(expectedContent);
            if (!Platform.isWindows) {
              try {
                await Process.run('chmod', ['+x', file.path]);
              } catch (e) {
                debugPrint('Chmod failed: $e');
              }
            }
            fixedFiles.add(relPath);
          }
          installedFiles.add(relPath);
          checksums[relPath] = expectedChecksum;
        }

        packages[pkgName] = _packageMetadata(
          pkgName,
          local,
          installedFiles,
          checksums,
          installedAt: installed['installedAt'] as String?,
        );
      }

      await _writeMetadata(meta.data);
      await updateShellHelpers();

      final doctor = await checkDoctor();
      final isHealthy = doctor['repairRecommended'] != true;
      final buf = StringBuffer();
      buf.writeln('=== Package Repair ===');
      buf.writeln(
        'Fixed Files: ${fixedFiles.isEmpty ? "None" : fixedFiles.join(", ")}',
      );
      buf.writeln(
        'Missing Packages Removed From Metadata: ${missingPackages.isEmpty ? "None" : missingPackages.join(", ")}',
      );
      buf.writeln('Helper Regeneration: OK');
      buf.write(
        'Final Health: ${isHealthy ? "HEALTHY" : "REPAIR RECOMMENDED"}',
      );

      return PackageOperationResult(
        output: buf.toString(),
        changedHelpers: true,
      );
    } catch (e) {
      return PackageOperationResult(
        output: 'Error: repair failed: $e',
        isError: true,
      );
    }
  }

  Future<PackageOperationResult> cleanPackages() async {
    try {
      final meta = await _readMetadata();
      if (meta.isCorrupt) {
        return const PackageOperationResult(
          output:
              'Error: metadata corrupted. Run pkg repair after fixing metadata.',
          isError: true,
        );
      }

      final paths = await _paths();
      final usrDir = paths['usr']!;
      final cleaned = <String>[];
      final controlledFiles = [
        File('$usrDir/termode-packages.json.tmp'),
        File('$usrDir/termode-packages.json.bak'),
        File('$usrDir/termode-shell-helpers.sh.tmp'),
        File('$usrDir/termode-shell-helpers.sh.bak'),
      ];

      for (final file in controlledFiles) {
        if (await file.exists()) {
          await file.delete();
          cleaned.add(file.path.split(Platform.pathSeparator).last);
        }
      }

      await updateShellHelpers();
      final buf = StringBuffer();
      buf.writeln('=== Package Clean ===');
      buf.writeln(
        'Cleaned: ${cleaned.isEmpty ? "Nothing to clean" : cleaned.join(", ")}',
      );
      buf.writeln('Unmanaged files: preserved');
      buf.write('Scope: files/usr package metadata and helper backups only');
      return PackageOperationResult(
        output: buf.toString(),
        changedHelpers: cleaned.isNotEmpty,
      );
    } catch (e) {
      return PackageOperationResult(
        output: 'Error: clean failed: $e',
        isError: true,
      );
    }
  }

  Future<PackageOperationResult> packageFiles(String pkgName) async {
    final meta = await _readMetadata();
    if (meta.isCorrupt) {
      return const PackageOperationResult(
        output: 'Error: metadata corrupted',
        isError: true,
      );
    }
    final packages = meta.data['packages'] as Map;
    if (!packages.containsKey(pkgName)) {
      return PackageOperationResult(
        output: 'Error: package not installed: $pkgName',
        isError: true,
      );
    }

    final paths = await _paths();
    final pkgInfo = Map<dynamic, dynamic>.from(packages[pkgName] as Map);
    final files = pkgInfo['files'] as List? ?? [];
    final checksums = Map<dynamic, dynamic>.from(
      pkgInfo['checksums'] as Map? ?? {},
    );
    final fileUrls = Map<dynamic, dynamic>.from(
      pkgInfo['fileUrls'] as Map? ?? {},
    );
    final sb = StringBuffer();
    sb.writeln('=== Package Files: $pkgName ===');
    sb.writeln('Source: ${pkgInfo['source'] ?? "local"}');
    if (pkgInfo['repoUrl'] != null) {
      sb.writeln('Repo URL: ${pkgInfo['repoUrl']}');
    }
    for (final fileObj in files) {
      final relPath = fileObj.toString();
      final file = _resolveManagedFile(paths['files']!, relPath);
      final exists = file != null && await file.exists();
      final executable = exists ? _isExecutableMode(await file.stat()) : false;
      sb.writeln(relPath);
      sb.writeln('  checksum: ${checksums[relPath] ?? "missing"}');
      if (fileUrls[relPath] != null) {
        sb.writeln('  file URL: ${fileUrls[relPath]}');
      }
      sb.writeln('  exists: ${exists ? "YES" : "NO"}');
      sb.writeln('  managed: ${file != null ? "YES" : "NO"}');
      sb.writeln('  chmod executable: ${executable ? "YES" : "NO"}');
      sb.writeln(
        '  direct Android exec may be blocked: ${Platform.isAndroid ? "YES" : "UNKNOWN"}',
      );
    }
    return PackageOperationResult(output: sb.toString().trimRight());
  }

  Future<PackageOperationResult> verifyPackage(String pkgName) async {
    final meta = await _readMetadata();
    if (meta.isCorrupt) {
      return const PackageOperationResult(
        output: 'Error: metadata corrupted',
        isError: true,
      );
    }
    final packages = meta.data['packages'] as Map;
    if (!packages.containsKey(pkgName)) {
      return PackageOperationResult(
        output: 'FAIL: package not installed: $pkgName',
        isError: true,
      );
    }

    final paths = await _paths();
    final pkgInfo = Map<dynamic, dynamic>.from(packages[pkgName] as Map);
    final files = pkgInfo['files'] as List? ?? [];
    final checksums = Map<dynamic, dynamic>.from(
      pkgInfo['checksums'] as Map? ?? {},
    );
    final source = pkgInfo['source']?.toString() ?? 'local';
    final executable = pkgInfo['executable'] as String? ?? pkgName;
    final issues = <String>[];

    for (final fileObj in files) {
      final relPath = fileObj.toString();
      final file = _resolveManagedFile(paths['files']!, relPath);
      if (file == null) {
        issues.add('$relPath is not a safe managed path');
        continue;
      }
      if (!await file.exists()) {
        issues.add('$relPath is missing');
        continue;
      }
      final expected = checksums[relPath]?.toString();
      final actual = source == 'remote'
          ? _calculateSha256(await file.readAsBytes())
          : _calculateFnv1a(await file.readAsString());
      if (expected == null || expected != actual) {
        issues.add('$relPath checksum mismatch');
      }
    }

    if (!await _helperHasExecutable(executable)) {
      issues.add('helper function missing for $executable');
    }

    final sb = StringBuffer();
    sb.writeln('=== Package Verify: $pkgName ===');
    sb.writeln('Source: $source');
    if (pkgInfo['repoUrl'] != null) {
      sb.writeln('Repo URL: ${pkgInfo['repoUrl']}');
    }
    if (issues.isEmpty) {
      sb.write('Result: PASS');
      return PackageOperationResult(output: sb.toString());
    }

    sb.writeln('Result: FAIL');
    for (final issue in issues) {
      sb.writeln('  - $issue');
    }
    return PackageOperationResult(
      output: sb.toString().trimRight(),
      isError: true,
    );
  }

  Future<Map<String, dynamic>> checkDoctor() async {
    final paths = await _paths();
    final binDir = paths['bin']!;
    final usrDir = paths['usr']!;
    final filesDir = paths['files']!;

    final pkgsMetaFile = _metadataFile(usrDir);
    final helpersFile = File('$usrDir/termode-shell-helpers.sh');

    int installedCount = 0;
    int brokenPackageCount = 0;
    int remoteInstalledCount = 0;
    final List<String> missingFiles = [];
    bool hasHelpers = await helpersFile.exists();
    bool hasMeta = await pkgsMetaFile.exists();
    bool helpersGenerated = false;
    int helperFunctionCount = 0;
    String? metadataError;

    final meta = await _readMetadata();
    if (meta.isCorrupt) {
      metadataError = meta.error ?? 'metadata corrupted';
    } else {
      final packages = meta.data['packages'] as Map;
      installedCount = packages.length;
      for (final pkgEntry in packages.entries) {
        bool packageBroken = false;
        final pkg = Map<dynamic, dynamic>.from(pkgEntry.value as Map);
        final source = pkg['source']?.toString() ?? 'local';
        if (source == 'remote') {
          remoteInstalledCount++;
        }
        final files = pkg['files'] as List? ?? [];
        for (final f in files) {
          final relPath = f.toString();
          final file = _resolveManagedFile(filesDir, relPath);
          if (file == null || !await file.exists()) {
            missingFiles.add(relPath);
            packageBroken = true;
          }
        }
        if (source != 'remote' &&
            !localIndex.containsKey(pkgEntry.key.toString())) {
          packageBroken = true;
        }
        if (packageBroken) {
          brokenPackageCount++;
        }
      }
    }

    if (hasHelpers) {
      try {
        final content = await helpersFile.readAsString();
        helperFunctionCount = RegExp(r'\(\)\s*\{').allMatches(content).length;
        helpersGenerated =
            helperFunctionCount > 0 ||
            content.contains('unalias ') ||
            content.contains('unset -f ');
      } catch (_) {}
    }

    final repairRecommended =
        metadataError != null ||
        brokenPackageCount > 0 ||
        missingFiles.isNotEmpty ||
        (installedCount > 0 && !hasHelpers);

    return {
      'metadataPath': pkgsMetaFile.path,
      'binPath': binDir,
      'helperPath': helpersFile.path,
      'installedCount': installedCount,
      'remoteInstalledCount': remoteInstalledCount,
      'brokenPackageCount': brokenPackageCount,
      'missingFileCount': missingFiles.length,
      'helperExists': hasHelpers,
      'metadataExists': hasMeta,
      'metadataError': metadataError,
      'missingFiles': missingFiles,
      'helpersGenerated': helpersGenerated,
      'helperFunctionCount': helperFunctionCount,
      'helperReloadCommand': helperReloadCommand,
      'mayNeedReload': hasHelpers,
      'repairRecommended': repairRecommended,
      'repoConfig': (await _readRepoConfig()).toJson(),
      'remoteIndexCached': await _readCachedRemoteIndexData() != null,
    };
  }

  static Future<void> updateShellHelpers() async {
    final service = PackageManagerService();
    final paths = await service._paths();
    final usrDir = paths['usr']!;

    final sb = StringBuffer();
    sb.writeln('# Termode runtime shell helpers and aliases');
    sb.writeln('# Generated automatically. Do not edit manually.');
    sb.writeln();
    sb.writeln(
      '# Clear stale helpers before defining the currently installed set.',
    );
    sb.writeln('unalias hello-termode 2>/dev/null');
    for (final pkg in localIndex.values) {
      final execName = pkg['executable'] as String?;
      if (execName != null && execName.isNotEmpty) {
        sb.writeln('unset -f $execName 2>/dev/null');
      }
    }
    sb.writeln('hash -r 2>/dev/null');
    sb.writeln();

    final toolsMetaFile = File('$usrDir/termode-tools.json');
    if (await toolsMetaFile.exists()) {
      try {
        final content = await toolsMetaFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final List<dynamic>? tools = data['installedTools'] as List<dynamic>?;
        if (tools != null && tools.contains('hello-termode')) {
          sb.writeln(
            'alias hello-termode=\'sh "\$TERMODE_BIN/hello-termode"\'',
          );
        }
      } catch (_) {}
    }

    final meta = await service._readMetadata();
    if (!meta.isCorrupt) {
      final packages = meta.data['packages'] as Map;
      if (packages.isNotEmpty) {
        for (final pkgEntry in packages.values) {
          final pkg = Map<dynamic, dynamic>.from(pkgEntry as Map);
          final execName = pkg['executable'] as String?;
          if (execName != null && execName.isNotEmpty) {
            sb.writeln();
            sb.writeln('$execName() {');
            sb.writeln('  /system/bin/sh "\$TERMODE_BIN/$execName" "\$@"');
            sb.writeln('}');
          }
        }
      }
    }

    final helpersFile = File('$usrDir/termode-shell-helpers.sh');
    await helpersFile.writeAsString(sb.toString());
  }
}
