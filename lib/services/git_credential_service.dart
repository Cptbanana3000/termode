import 'dart:convert';
import 'dart:io';

import 'runtime_prefix_service.dart';

/// Represents a stored Git credential for a remote host.
class GitCredential {
  final String protocol;
  final String host;
  final String username;
  final String token;

  const GitCredential({
    this.protocol = 'https',
    required this.host,
    required this.username,
    required this.token,
  });

  /// URL line formatted for Git credential-store (~/.git-credentials)
  String toStoreLine() {
    final encUser = Uri.encodeComponent(username);
    final encToken = Uri.encodeComponent(token);
    return '$protocol://$encUser:$encToken@$host';
  }

  /// Masked token for display in UI or logs (e.g. ghp_...3f2a)
  String get maskedToken {
    if (token.length <= 8) {
      return '********';
    }
    final prefix = token.substring(0, 4);
    final suffix = token.substring(token.length - 4);
    return '$prefix...$suffix';
  }

  /// Parses a line from ~/.git-credentials
  static GitCredential? parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;

    try {
      final uri = Uri.parse(trimmed);
      if (uri.userInfo.isEmpty) return null;

      final parts = uri.userInfo.split(':');
      if (parts.length < 2) return null;

      final username = Uri.decodeComponent(parts[0]);
      final token = Uri.decodeComponent(parts.sublist(1).join(':'));
      final host = uri.host.isNotEmpty ? uri.host : uri.path;

      return GitCredential(
        protocol: uri.scheme.isNotEmpty ? uri.scheme : 'https',
        host: host,
        username: username,
        token: token,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Service that manages Git credentials in $HOME/.git-credentials.
class GitCredentialService {
  static final GitCredentialService _instance = GitCredentialService._internal();
  factory GitCredentialService() => _instance;
  GitCredentialService._internal();

  final RuntimePrefixService _prefix = RuntimePrefixService();

  // Test override hook
  String? overrideHomeDir;

  Future<File> _getCredentialsFile() async {
    if (overrideHomeDir != null) {
      final homeDir = Directory(overrideHomeDir!);
      if (!homeDir.existsSync()) homeDir.createSync(recursive: true);
      return File('${homeDir.path}/.git-credentials');
    }
    final paths = await _prefix.paths();
    final home = paths['home']!;
    final homeDir = Directory(home);
    if (!homeDir.existsSync()) {
      await homeDir.create(recursive: true);
    }
    return File('$home/.git-credentials');
  }

  /// Retrieves stored credential for a given host (e.g. github.com, gitlab.com).
  Future<GitCredential?> getCredential(String host) async {
    final cleanHost = _normalizeHost(host);
    final all = await listCredentials();
    for (final cred in all) {
      if (_normalizeHost(cred.host) == cleanHost) {
        return cred;
      }
    }
    return null;
  }

  /// Named argument alias for getCredential.
  Future<GitCredential?> get({required String host}) => getCredential(host);

  /// Named argument alias for storeCredential.
  Future<void> store({
    required String host,
    required String username,
    required String token,
    String protocol = 'https',
  }) =>
      storeCredential(host, username, token, protocol: protocol);

  /// Named argument alias for deleteCredential.
  Future<bool> erase({required String host}) => deleteCredential(host);

  /// Stores or updates credential for a host.
  Future<void> storeCredential(
    String host,
    String username,
    String token, {
    String protocol = 'https',
  }) async {
    final file = await _getCredentialsFile();
    final cleanHost = _normalizeHost(host);
    final credentials = await listCredentials();

    // Remove existing for this host if present
    credentials.removeWhere((c) => _normalizeHost(c.host) == cleanHost);

    // Add new
    credentials.add(
      GitCredential(
        protocol: protocol,
        host: cleanHost,
        username: username.trim(),
        token: token.trim(),
      ),
    );

    // Save back to file
    final lines = credentials.map((c) => c.toStoreLine()).join('\n');
    await file.writeAsString(lines.isEmpty ? '' : '$lines\n', flush: true);
  }

  /// Deletes credential for a host.
  Future<bool> deleteCredential(String host) async {
    final file = await _getCredentialsFile();
    if (!await file.exists()) return false;

    final cleanHost = _normalizeHost(host);
    final credentials = await listCredentials();
    final initialCount = credentials.length;
    credentials.removeWhere((c) => _normalizeHost(c.host) == cleanHost);

    if (credentials.length != initialCount) {
      final lines = credentials.map((c) => c.toStoreLine()).join('\n');
      await file.writeAsString(lines.isEmpty ? '' : '$lines\n', flush: true);
      return true;
    }
    return false;
  }

  /// Lists all stored Git credentials.
  Future<List<GitCredential>> listCredentials() async {
    final file = await _getCredentialsFile();
    if (!await file.exists()) return [];

    try {
      final content = await file.readAsString();
      final lines = const LineSplitter().convert(content);
      final results = <GitCredential>[];
      for (final line in lines) {
        final cred = GitCredential.parseLine(line);
        if (cred != null) {
          results.add(cred);
        }
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  /// Clears all stored credentials.
  Future<void> clearAll() async {
    final file = await _getCredentialsFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _normalizeHost(String host) {
    var h = host.toLowerCase().trim();
    if (h.startsWith('https://')) h = h.substring(8);
    if (h.startsWith('http://')) h = h.substring(7);
    if (h.contains('/')) h = h.split('/').first;
    if (h.contains(':')) h = h.split(':').first;
    return h;
  }
}
