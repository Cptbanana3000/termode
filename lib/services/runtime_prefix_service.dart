import 'dart:io';

import 'runtime_bootstrap_service.dart';

/// Plans and manages Termode's own controlled runtime prefix.
///
/// This is the foundation for future real runtime/toolchain support
/// (v0.43+). It is NOT a full Linux distribution and does NOT install or
/// execute any external binaries. It only computes safe, app-private paths
/// under `TERMODE_HOME`, can create those directories idempotently, and
/// reports status. It never deletes user files and never escapes the home
/// directory.
///
/// The runtime prefix is intentionally separate from the script-package
/// directory (`files/usr`) used by the existing package manager, so this
/// architecture work cannot break packages.
class RuntimePrefixService {
  static final RuntimePrefixService _instance =
      RuntimePrefixService._internal();
  factory RuntimePrefixService() => _instance;
  RuntimePrefixService._internal();

  final RuntimeBootstrapService _bootstrap = RuntimeBootstrapService();

  Future<String> _homePath() async {
    final paths = await _bootstrap.getPaths();
    return paths['home']!;
  }

  /// Absolute Termode prefix paths. All values live under [home].
  Future<Map<String, String>> paths() async {
    final home = await _homePath();
    final prefix = '$home/usr';
    return {
      'home': home,
      'prefix': prefix,
      'bin': '$prefix/bin',
      'lib': '$prefix/lib',
      'share': '$prefix/share',
      'tmp': '$prefix/tmp',
      'var': '$prefix/var',
      'packages': '$prefix/packages',
      'runtime': '$prefix/runtime',
      'toolchains': '$prefix/toolchains',
      'toolchainsGit': '$prefix/toolchains/git',
      'toolchainsNode': '$prefix/toolchains/node',
      'toolchainsPython': '$prefix/toolchains/python',
      'workspaces': '$home/workspaces',
      'cache': '$home/cache',
      'config': '$home/config',
    };
  }

  /// Directory keys that [initPrefix] creates and [prefixDoctor] requires.
  static const List<String> _dirKeys = [
    'prefix',
    'bin',
    'lib',
    'share',
    'tmp',
    'var',
    'packages',
    'runtime',
    'toolchains',
    'toolchainsGit',
    'toolchainsNode',
    'toolchainsPython',
    'workspaces',
    'cache',
    'config',
  ];

  /// Collapses an app-private absolute path to a short, safe display form.
  String shortPath(String path) {
    final norm = path.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/files/');
    if (idx >= 0) {
      return '~${norm.substring(idx)}';
    }
    final parts = norm.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length > 3) {
      return '.../${parts.sublist(parts.length - 3).join('/')}';
    }
    return norm;
  }

  /// True when every required prefix directory exists.
  Future<bool> isInitialized() async {
    final p = await paths();
    for (final key in _dirKeys) {
      if (!Directory(p[key]!).existsSync()) {
        return false;
      }
    }
    return true;
  }

  bool _isInsideHome(String candidate, String home) {
    final c = candidate.replaceAll('\\', '/');
    final h = home.replaceAll('\\', '/');
    return c == h || c.startsWith('$h/');
  }

  Future<String> prefixInfo() async {
    final p = await paths();
    final initialized = await isInitialized();
    return '=== Termode Prefix ===\n'
        'Home: ${shortPath(p['home']!)}\n'
        'Prefix: ${shortPath(p['prefix']!)}\n'
        'Bin: ${shortPath(p['bin']!)}\n'
        'Lib: ${shortPath(p['lib']!)}\n'
        'Packages: ${shortPath(p['packages']!)}\n'
        'Toolchains: ${shortPath(p['toolchains']!)}\n'
        'Status: ${initialized ? 'initialized' : 'not initialized'}';
  }

  /// Creates the prefix directories. Idempotent; never deletes anything.
  Future<String> initPrefix() async {
    final p = await paths();
    final home = p['home']!;
    var created = 0;
    var existed = 0;
    final problems = <String>[];

    for (final key in _dirKeys) {
      final path = p[key]!;
      // Safety: never create anything outside Termode home.
      if (!_isInsideHome(path, home)) {
        problems.add(key);
        continue;
      }
      final dir = Directory(path);
      if (dir.existsSync()) {
        existed++;
      } else {
        try {
          dir.createSync(recursive: true);
          created++;
        } catch (_) {
          problems.add(key);
        }
      }
    }

    final sb = StringBuffer();
    sb.writeln('=== Termode Prefix Init ===');
    sb.writeln('Created: $created');
    sb.writeln('Already existed: $existed');
    if (problems.isNotEmpty) {
      sb.writeln('Failed: ${problems.length} (${problems.join(', ')})');
      sb.write('Status: incomplete');
      return sb.toString();
    }
    sb.writeln('User files: untouched');
    sb.write('Status: initialized');
    return sb.toString();
  }

  Future<String> prefixDoctor() async {
    final p = await paths();
    final home = p['home']!;

    var present = 0;
    final total = _dirKeys.length;
    var pathSafe = true;
    for (final key in _dirKeys) {
      final path = p[key]!;
      if (!_isInsideHome(path, home)) {
        pathSafe = false;
      }
      if (Directory(path).existsSync()) {
        present++;
      }
    }
    final initialized = present == total;

    String writeAccess = 'UNKNOWN';
    var writable = false;
    if (initialized) {
      try {
        final probe = File('${p['bin']}/.termode-prefix-probe');
        probe.writeAsStringSync('ok');
        writable = probe.readAsStringSync() == 'ok';
        probe.deleteSync();
        writeAccess = writable ? 'OK' : 'FAILED';
      } catch (_) {
        writeAccess = 'FAILED';
      }
    }

    String overall;
    if (!pathSafe) {
      overall = 'UNHEALTHY';
    } else if (!initialized) {
      overall = 'LIMITED';
    } else if (!writable) {
      overall = 'UNHEALTHY';
    } else {
      overall = 'HEALTHY';
    }

    return '=== Termode Prefix Doctor ===\n'
        'Prefix dirs: ${initialized ? 'OK' : 'INCOMPLETE'} ($present/$total)\n'
        'Path safety: ${pathSafe ? 'OK' : 'UNSAFE'}\n'
        'Write access: $writeAccess\n'
        'Tip: run prefix-init to create missing directories.\n'
        'Overall: $overall';
  }

  Future<String> pathInfo() async {
    final p = await paths();
    return '=== Termode PATH ===\n'
        'Future PATH order:\n'
        '  1. ${shortPath(p['bin']!)}\n'
        '  2. bundled helper scripts\n'
        '  3. Android/system shell paths\n'
        'Note: the live shell PATH is not modified yet. This is the planned\n'
        'order for the v0.43 Prefix / PATH / Environment System milestone.';
  }

  Future<String> envInfo() async {
    final p = await paths();
    return '=== Termode Environment (planned) ===\n'
        'TERMODE_HOME: ${shortPath(p['home']!)}\n'
        'TERMODE_PREFIX: ${shortPath(p['prefix']!)}\n'
        'TERMODE_BIN: ${shortPath(p['bin']!)}\n'
        'TERMODE_WORKSPACES: ${shortPath(p['workspaces']!)}\n'
        'PATH strategy: Termode bin first, then helpers, then system\n'
        'HOME strategy: TERMODE_HOME stays app-private\n'
        'TMPDIR strategy: TERMODE_PREFIX/tmp\n'
        'Note: these are planned values; live runtime env is unchanged.';
  }
}
