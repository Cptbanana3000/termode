import 'dart:io';

import 'runtime_bootstrap_service.dart';

/// Manages Termode's controlled runtime prefix, PATH overlay, and environment.
///
/// v0.43 turns the v0.42 planning surface into a real, usable environment
/// layer for future toolchains. It still does NOT install, download, or
/// execute any external binary.
///
/// Design note: the runtime prefix is **unified with the existing package
/// prefix** (`TERMODE_USR` = the Termode `usr` directory). This keeps
/// `TERMODE_BIN` (= `usr/bin`) stable so installed packages and the silent
/// helper reload keep working, and means future runtime tools share the same
/// bin that is already first on PATH. The prefix and all managed directories
/// live inside the app's private `files/` sandbox; nothing escapes it.
class RuntimePrefixService {
  static final RuntimePrefixService _instance =
      RuntimePrefixService._internal();
  factory RuntimePrefixService() => _instance;
  RuntimePrefixService._internal();

  final RuntimeBootstrapService _bootstrap = RuntimeBootstrapService();

  /// Absolute Termode paths. All values live inside the `files/` sandbox.
  Future<Map<String, String>> paths() async {
    final p = await _bootstrap.getPaths();
    final home = p['home']!; // files/home
    final usr = p['usr']!; //  files/usr  (== TERMODE_PREFIX)
    final bin = p['bin']!; //  files/usr/bin
    final sandbox = Directory(home).parent.path; // files
    return {
      'sandbox': sandbox,
      'home': home,
      'prefix': usr,
      'bin': bin,
      'lib': '$usr/lib',
      'share': '$usr/share',
      'tmp': '$usr/tmp',
      'var': '$usr/var',
      'etc': '$usr/etc',
      'packages': '$usr/packages',
      'runtime': '$usr/runtime',
      'toolchains': '$usr/toolchains',
      'toolchainsGit': '$usr/toolchains/git',
      'toolchainsNode': '$usr/toolchains/node',
      'toolchainsPython': '$usr/toolchains/python',
      'workspaces': '$home/projects',
      'cache': '$home/cache',
      'config': '$home/config',
    };
  }

  /// Directory keys that [initPrefix] creates and [prefixDoctor] requires.
  static const List<String> _dirKeys = [
    'bin',
    'lib',
    'share',
    'tmp',
    'var',
    'etc',
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

  /// The canonical safe environment future runtimes (and REAL PTY) should use.
  Future<Map<String, String>> envMap() async {
    final p = await paths();
    final pathEnv =
        '${p['bin']}:/system/bin:/system/xbin:/vendor/bin:/product/bin';
    return {
      'TERMODE_HOME': p['home']!,
      'TERMODE_PREFIX': p['prefix']!,
      'TERMODE_BIN': p['bin']!,
      'TERMODE_WORKSPACES': p['workspaces']!,
      'TERMODE_TMPDIR': p['tmp']!,
      'TERMODE_CACHE': p['cache']!,
      'TERMODE_CONFIG': p['config']!,
      'PATH': pathEnv,
      'HOME': p['home']!,
      'TMPDIR': '${p['sandbox']}/tmp',
      'TERM': 'xterm-256color',
    };
  }

  /// Ordered PATH entries used by the overlay.
  Future<List<String>> pathEntries() async {
    final p = await paths();
    return [
      p['bin']!,
      '/system/bin',
      '/system/xbin',
      '/vendor/bin',
      '/product/bin',
    ];
  }

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

  bool _isInsideSandbox(String candidate, String sandbox) {
    final c = candidate.replaceAll('\\', '/');
    final s = sandbox.replaceAll('\\', '/');
    if (c.split('/').contains('..')) return false;
    return c == s || c.startsWith('$s/');
  }

  /// A PATH entry is safe if it is non-empty, absolute, has no traversal, and
  /// is not a world-writable external-storage location.
  bool _isSafePathEntry(String entry) {
    final normalized = entry.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return false;
    final isUnixAbsolute = normalized.startsWith('/');
    final isWindowsAbsolute = RegExp(r'^[A-Za-z]:/').hasMatch(normalized);
    if (!isUnixAbsolute && !isWindowsAbsolute) return false;
    if (normalized.split('/').contains('..')) return false;
    final lower = normalized.toLowerCase();
    if (lower.startsWith('/sdcard') ||
        lower.startsWith('/storage/emulated') ||
        lower.contains('/external')) {
      return false;
    }
    return true;
  }

  Future<bool> isInitialized() async {
    final p = await paths();
    for (final key in _dirKeys) {
      if (!Directory(p[key]!).existsSync()) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _isWritable(String dirPath) async {
    try {
      final probe = File('$dirPath/.termode-write-probe');
      probe.writeAsStringSync('ok');
      final ok = probe.readAsStringSync() == 'ok';
      probe.deleteSync();
      return ok;
    } catch (_) {
      return false;
    }
  }

  // --- prefix --------------------------------------------------------------

  Future<String> prefixInfo() async {
    final p = await paths();
    final initialized = await isInitialized();
    return '=== Termode Prefix ===\n'
        'Home: ${shortPath(p['home']!)}\n'
        'Prefix: ${shortPath(p['prefix']!)}\n'
        'Bin: ${shortPath(p['bin']!)}\n'
        'Lib: ${shortPath(p['lib']!)}\n'
        'Etc: ${shortPath(p['etc']!)}\n'
        'Packages: ${shortPath(p['packages']!)}\n'
        'Toolchains: ${shortPath(p['toolchains']!)}\n'
        'Status: ${initialized ? 'initialized' : 'not initialized'}';
  }

  Future<String> initPrefix() async {
    final p = await paths();
    final sandbox = p['sandbox']!;
    var created = 0;
    var existed = 0;
    final problems = <String>[];

    for (final key in _dirKeys) {
      final path = p[key]!;
      if (!_isInsideSandbox(path, sandbox)) {
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

    // Regenerate the env script alongside init.
    await generateEnvScript();

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
    final sandbox = p['sandbox']!;
    var present = 0;
    final total = _dirKeys.length;
    var pathSafe = true;
    for (final key in _dirKeys) {
      final path = p[key]!;
      if (!_isInsideSandbox(path, sandbox)) pathSafe = false;
      if (Directory(path).existsSync()) present++;
    }
    final initialized = present == total;

    String writeAccess = 'UNKNOWN';
    var writable = false;
    if (initialized) {
      writable = await _isWritable(p['bin']!);
      writeAccess = writable ? 'OK' : 'FAILED';
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

  Future<String> prefixStatus() async {
    final p = await paths();
    final initialized = await isInitialized();
    final writable = initialized ? await _isWritable(p['bin']!) : false;
    final overall = !initialized
        ? 'LIMITED'
        : (writable ? 'HEALTHY' : 'UNHEALTHY');
    return '=== Prefix Status ===\n'
        'Initialized: ${initialized ? 'yes' : 'no'}\n'
        'Writable: ${initialized ? (writable ? 'yes' : 'no') : 'unknown'}\n'
        'PATH overlay: ${initialized ? 'enabled' : 'planned'}\n'
        'Shell environment: ${initialized ? 'enabled' : 'planned'}\n'
        '${initialized ? 'Tip: ready for shell sessions.' : 'Run: prefix-init'}\n'
        'Overall: $overall';
  }

  // --- PATH ----------------------------------------------------------------

  Future<String> pathInfo() async {
    final p = await paths();
    return '=== Termode PATH ===\n'
        'Future PATH order:\n'
        '  1. ${shortPath(p['bin']!)}\n'
        '  2. Termode helper scripts\n'
        '  3. Android/system shell paths\n'
        'Note: REAL PTY already puts the prefix bin first. This is the planned\n'
        'overlay order.';
  }

  Future<String> pathPreview() async {
    final entries = await pathEntries();
    final sb = StringBuffer('=== PATH Preview ===\n');
    sb.writeln('1. ${shortPath(entries.first)}');
    sb.writeln('2. Termode helper scripts');
    for (var i = 1; i < entries.length; i++) {
      sb.writeln('${i + 2}. ${entries[i]}');
    }
    sb.write('Order: prefix bin first, then helpers, then system paths.');
    return sb.toString();
  }

  Future<String> pathStatus() async {
    final p = await paths();
    final prefixBinExists = Directory(p['bin']!).existsSync();
    final helperExists =
        File('${p['prefix']}/termode-shell-helpers.sh').existsSync() ||
        Directory(p['prefix']!).existsSync();
    final systemExists = Directory('/system/bin').existsSync();
    final overlayEnabled = prefixBinExists;
    final overall = (prefixBinExists && systemExists) ? 'HEALTHY' : 'LIMITED';
    return '=== PATH Status ===\n'
        'Prefix bin: ${prefixBinExists ? 'available' : 'missing'}\n'
        'Helper bin: ${helperExists ? 'available' : 'missing'}\n'
        'System paths: available\n'
        'Overlay enabled: ${overlayEnabled ? 'yes' : 'no'}\n'
        'Applied to REAL PTY: yes\n'
        'Overall: $overall';
  }

  Future<String> pathDoctor() async {
    final p = await paths();
    final entries = await pathEntries();
    final prefixBinExists = Directory(p['bin']!).existsSync();
    final helperExists = Directory(p['prefix']!).existsSync();
    final systemExists = Directory('/system/bin').existsSync();
    final seen = <String>{};
    var safe = true;
    var noEmpty = true;
    var noDup = true;
    for (final e in entries) {
      if (e.trim().isEmpty) noEmpty = false;
      if (!_isSafePathEntry(e)) safe = false;
      if (!seen.add(e)) noDup = false;
    }
    final healthy = prefixBinExists && systemExists && safe && noEmpty && noDup;
    return '=== PATH Doctor ===\n'
        'Prefix bin: ${prefixBinExists ? 'OK' : 'MISSING'}\n'
        'Helper scripts: ${helperExists ? 'OK' : 'MISSING'}\n'
        'System shell path: ${systemExists ? 'OK' : 'MISSING'}\n'
        'Entries safe: ${safe ? 'OK' : 'UNSAFE'}\n'
        'No empty entries: ${noEmpty ? 'OK' : 'CHECK'}\n'
        'No duplicate entries: ${noDup ? 'OK' : 'CHECK'}\n'
        'Overall: ${healthy ? 'HEALTHY' : 'LIMITED'}';
  }

  // --- environment ---------------------------------------------------------

  Future<String> envInfo() async {
    final p = await paths();
    return '=== Termode Environment ===\n'
        'TERMODE_HOME: ${shortPath(p['home']!)}\n'
        'TERMODE_PREFIX: ${shortPath(p['prefix']!)}\n'
        'TERMODE_BIN: ${shortPath(p['bin']!)}\n'
        'TERMODE_WORKSPACES: ${shortPath(p['workspaces']!)}\n'
        'PATH strategy: Termode bin first, then helpers, then system\n'
        'HOME strategy: TERMODE_HOME stays app-private\n'
        'TMPDIR strategy: app-private tmp\n'
        'Note: REAL PTY sessions receive these values.';
  }

  Future<String> envPreview() async {
    final env = await envMap();
    final entries = await pathEntries();
    final sb = StringBuffer('=== Env Preview ===\n');
    for (final key in [
      'TERMODE_HOME',
      'TERMODE_PREFIX',
      'TERMODE_BIN',
      'TERMODE_WORKSPACES',
      'TERMODE_TMPDIR',
      'TERMODE_CACHE',
      'TERMODE_CONFIG',
      'HOME',
      'TMPDIR',
      'TERM',
    ]) {
      final value = env[key]!;
      sb.writeln('$key=${key == 'TERM' ? value : shortPath(value)}');
    }
    sb.write('PATH=${shortPath(entries.first)}:...');
    return sb.toString();
  }

  Future<String> envStatus() async {
    final initialized = await isInitialized();
    final overall = initialized ? 'HEALTHY' : 'LIMITED';
    return '=== Env Status ===\n'
        'Termode variables: defined\n'
        'PATH overlay: ${initialized ? 'enabled' : 'planned'}\n'
        'Applied to REAL PTY: yes\n'
        'Prefix initialized: ${initialized ? 'yes' : 'no'}\n'
        '${initialized ? 'Tip: env-check verifies values.' : 'Run: prefix-init'}\n'
        'Overall: $overall';
  }

  Future<String> envDoctor() async {
    final p = await paths();
    final env = await envMap();
    final sandbox = p['sandbox']!;
    final initialized = await isInitialized();
    final homeSafe = _isInsideSandbox(env['TERMODE_HOME']!, sandbox);
    final prefixSafe = _isInsideSandbox(env['TERMODE_PREFIX']!, sandbox);
    final binSafe = _isInsideSandbox(env['TERMODE_BIN']!, sandbox);
    final tmpSafe = _isInsideSandbox(env['TMPDIR']!, sandbox);
    final tmpWritable = await _isWritable(
      env['TMPDIR']!,
    ).catchError((_) => false);
    final homeStrategyOk = env['HOME'] == env['TERMODE_HOME'];
    final pathOk = (await pathEntries()).every(_isSafePathEntry);
    final termOk = env['TERM'] == 'xterm-256color';
    final healthy =
        homeSafe &&
        prefixSafe &&
        binSafe &&
        tmpSafe &&
        homeStrategyOk &&
        pathOk &&
        termOk &&
        initialized;
    final overall = healthy
        ? 'HEALTHY'
        : (prefixSafe && binSafe ? 'LIMITED' : 'UNHEALTHY');
    return '=== Env Doctor ===\n'
        'TERMODE_HOME: ${homeSafe ? 'OK' : 'UNSAFE'}\n'
        'TERMODE_PREFIX: ${prefixSafe ? 'OK' : 'UNSAFE'}\n'
        'TERMODE_BIN: ${binSafe ? 'OK' : 'UNSAFE'}\n'
        'TMPDIR: ${tmpSafe ? (tmpWritable ? 'OK' : 'safe') : 'UNSAFE'}\n'
        'Prefix initialized: ${initialized ? 'yes' : 'no'}\n'
        'HOME strategy: ${homeStrategyOk ? 'OK' : 'CHECK'}\n'
        'PATH strategy: ${pathOk ? 'OK' : 'UNSAFE'}\n'
        'TERM: ${termOk ? 'OK (xterm-256color)' : env['TERM']}\n'
        'Overall: $overall';
  }

  Future<String> envCheck() async {
    final env = await envMap();
    final entries = await pathEntries();
    return '=== Env Check ===\n'
        'In a REAL PTY shell these should show:\n'
        '  echo \$TERMODE_PREFIX -> ${shortPath(env['TERMODE_PREFIX']!)}\n'
        '  echo \$TERMODE_BIN    -> ${shortPath(env['TERMODE_BIN']!)}\n'
        '  echo \$TMPDIR         -> ${shortPath(env['TMPDIR']!)}\n'
        '  echo \$PATH           -> ${shortPath(entries.first)}:...\n'
        '  echo \$TERM           -> ${env['TERM']}\n'
        'Run default-shell, then the echo commands above to verify.';
  }

  // --- env script ----------------------------------------------------------

  Future<String> envScriptPath() async {
    final p = await paths();
    return '${p['etc']}/termode_env.sh';
  }

  /// Single-quotes a value for safe inclusion in a POSIX shell script.
  String _shQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

  Future<bool> generateEnvScript() async {
    try {
      final p = await paths();
      final env = await envMap();
      final etc = Directory(p['etc']!);
      if (!etc.existsSync()) {
        // Only write the script if the etc dir can be created safely.
        if (!_isInsideSandbox(p['etc']!, p['sandbox']!)) return false;
        etc.createSync(recursive: true);
      }
      final sb = StringBuffer();
      sb.writeln('# Termode environment script (generated). Safe to source.');
      sb.writeln(
        '# Do not edit by hand; regenerated by prefix-init/env commands.',
      );
      for (final key in [
        'TERMODE_HOME',
        'TERMODE_PREFIX',
        'TERMODE_BIN',
        'TERMODE_WORKSPACES',
        'TERMODE_TMPDIR',
        'TERMODE_CACHE',
        'TERMODE_CONFIG',
        'HOME',
        'TMPDIR',
        'TERM',
      ]) {
        sb.writeln('export $key=${_shQuote(env[key]!)}');
      }
      sb.writeln('export PATH=${_shQuote(env['PATH']!)}');
      File(await envScriptPath()).writeAsStringSync(sb.toString());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> envScriptInfo() async {
    final scriptPath = await envScriptPath();
    final exists = File(scriptPath).existsSync();
    return '=== Termode Env Script ===\n'
        'Path: ${shortPath(scriptPath)}\n'
        'Status: ${exists ? 'exists' : 'missing'}\n'
        '${exists ? 'Safe to source in a POSIX shell.' : 'Run: prefix-init'}';
  }

  // --- bin discovery -------------------------------------------------------

  Future<List<String>> _binEntries() async {
    final p = await paths();
    final dir = Directory(p['bin']!);
    if (!dir.existsSync()) return const [];
    final names =
        dir
            .listSync()
            .map((e) => e.path.replaceAll('\\', '/').split('/').last)
            .where((n) => !n.startsWith('.'))
            .toList()
          ..sort();
    return names;
  }

  Future<String> binList() async {
    final names = await _binEntries();
    if (names.isEmpty) {
      return 'No runtime tools installed yet.\n'
          'Future tools: git, node, npm, python';
    }
    final sb = StringBuffer('=== Termode Bin ===\n');
    for (final n in names) {
      sb.writeln(n);
    }
    return sb.toString().trimRight();
  }

  Future<String> binWhich(String command) async {
    final name = command.trim();
    if (name.isEmpty || name.contains('/') || name.contains('..')) {
      return 'bin-which: invalid command name';
    }
    for (final dir in await pathEntries()) {
      if (!_isSafePathEntry(dir)) continue;
      final file = File('$dir/$name');
      if (file.existsSync()) {
        return shortPath(file.path);
      }
    }
    return 'Not found in Termode PATH.\n'
        'Planned tools can be checked with: toolchain-info $name';
  }

  Future<String> binDoctor() async {
    final p = await paths();
    final sandbox = p['sandbox']!;
    final binExists = Directory(p['bin']!).existsSync();
    final binSafe = _isInsideSandbox(p['bin']!, sandbox);
    final names = await _binEntries();
    final entriesSafe = names.every(
      (n) => !n.contains('..') && !n.contains('/'),
    );
    final healthy = binExists && binSafe && entriesSafe;
    return '=== Bin Doctor ===\n'
        'Prefix bin: ${binExists ? 'OK' : 'MISSING'}\n'
        'Path safety: ${binSafe ? 'OK' : 'UNSAFE'}\n'
        'Entries: ${entriesSafe ? 'OK' : 'CHECK'} (${names.length})\n'
        'Overall: ${healthy ? 'HEALTHY' : 'LIMITED'}';
  }

  // --- shims (planning) ----------------------------------------------------

  String shimInfo() {
    return '=== Runtime Shims (planning) ===\n'
        'Future runtime shims will live in \$TERMODE_PREFIX/bin.\n'
        'Shims will point to controlled runtime entrypoints.\n'
        'Shims will not execute unknown external code.\n'
        'Future examples: git, node, npm, python\n'
        'No runtime shims are created yet.';
  }

  Future<String> shimList() async {
    // No controlled runtime shims exist yet (real installs start in v0.45+).
    return 'No runtime shims installed yet.\n'
        'Planned shims: git, node, npm, python';
  }

  Future<String> shimDoctor() async {
    final p = await paths();
    final sandbox = p['sandbox']!;
    final binSafe = _isInsideSandbox(p['bin']!, sandbox);
    final binExists = Directory(p['bin']!).existsSync();
    return '=== Shim Doctor ===\n'
        'Shim directory: ${shortPath(p['bin']!)}\n'
        'Directory present: ${binExists ? 'OK' : 'NOT INITIALIZED'}\n'
        'Path safety: ${binSafe ? 'OK' : 'UNSAFE'}\n'
        'Installed shims: 0\n'
        'Overall: ARCHITECTURE PHASE';
  }
}
