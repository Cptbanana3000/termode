import 'package:flutter/services.dart';

/// Tiny Native Tool Proof (v0.29).
///
/// Exposes a small set of audited utilities implemented inside the bundled
/// native library and reached through the existing JNI/native bridge. These
/// tools spawn no shell, launch no external process, perform no network access,
/// and execute no app-writable binaries. They prove that Termode can safely
/// expose native utilities without a real runtime such as Node.js.
class NativeToolService {
  static final NativeToolService _instance = NativeToolService._internal();
  factory NativeToolService() => _instance;
  NativeToolService._internal();

  static const String channelName = 'com.termode/native_shell';

  /// Only these environment keys are ever surfaced; anything else is dropped.
  static const List<String> safeEnvKeys = [
    'HOME',
    'TMPDIR',
    'TERMODE_HOME',
    'TERMODE_USR',
    'TERMODE_BIN',
  ];

  static const String _unavailable =
      'Native tool bridge unavailable.\nRuntime remains limited.';

  static const List<String> subcommands = [
    'help',
    'info',
    'echo',
    'cwd',
    'pid',
    'abi',
    'hash',
    'time',
    'env',
    'doctor',
  ];

  Future<Map<String, dynamic>?> _call(
    String command, [
    String args = '',
  ]) async {
    try {
      final dynamic res = await const MethodChannel(
        channelName,
      ).invokeMethod('nativeTool', {'command': command, 'args': args});
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // --------------------------------------------------------------------------
  // Commands
  // --------------------------------------------------------------------------

  /// `native-tool` / `native-tool help`
  String help() {
    return '=== Native Tool ===\n'
        'Tiny audited utilities exposed through the JNI/native bridge.\n'
        'No shell, no external process, no app-writable binary execution.\n\n'
        'Subcommands:\n'
        '  native-tool info        - Show native bridge tool info\n'
        '  native-tool echo <text> - Echo text from native code\n'
        '  native-tool cwd         - Native current working directory\n'
        '  native-tool pid         - Native process id\n'
        '  native-tool abi         - Detected native ABI\n'
        '  native-tool hash <text> - SHA-256 of text (native)\n'
        '  native-tool time        - Native timestamp (epoch ms)\n'
        '  native-tool env         - Safe limited environment summary\n'
        '  native-tool doctor      - Diagnose the native tool bridge\n'
        '  native-tool help        - Show this help\n\n'
        'Node.js: not included.';
  }

  /// `native-tool info`
  Future<String> info() async {
    final r = await _call('info');
    if (r == null || r['ok'] != true) {
      return _unavailable;
    }
    final sb = StringBuffer();
    sb.writeln('=== Native Tool Info ===');
    sb.writeln('Native bridge: ${r['abi'] != null ? 'OK' : 'LIMITED'}');
    sb.writeln('ABI: ${r['abi'] ?? 'unknown'}');
    sb.writeln('PID: ${r['pid'] ?? -1}');
    sb.writeln('CWD: ${r['cwd'] ?? 'unknown'}');
    sb.writeln('Tools: echo, cwd, pid, abi, hash, time, env');
    sb.write('Node.js: not included');
    return sb.toString();
  }

  /// `native-tool echo <text>`
  Future<String> echo(String text) async {
    final r = await _call('echo', text);
    if (r == null || r['ok'] != true) {
      return _unavailable;
    }
    return r['value']?.toString() ?? '';
  }

  /// `native-tool cwd`
  Future<String> cwd() async {
    final r = await _call('cwd');
    if (r == null || r['ok'] != true) {
      return _unavailable;
    }
    return r['value']?.toString() ?? 'unknown';
  }

  /// `native-tool pid`
  Future<String> pid() async {
    final r = await _call('pid');
    if (r == null || r['ok'] != true) {
      return _unavailable;
    }
    return '${r['value'] ?? -1}';
  }

  /// `native-tool abi`
  Future<String> abi() async {
    final r = await _call('abi');
    if (r == null || r['ok'] != true) {
      return _unavailable;
    }
    return r['value']?.toString() ?? 'unknown';
  }

  /// `native-tool hash <text>`
  Future<String> hash(String text) async {
    final r = await _call('hash', text);
    if (r == null || r['ok'] != true) {
      return _unavailable;
    }
    final sb = StringBuffer();
    sb.writeln('=== Native Tool Hash ===');
    sb.writeln('Hash type: ${r['hashType'] ?? 'SHA-256'}');
    sb.write('Hash: ${r['value'] ?? ''}');
    return sb.toString();
  }

  /// `native-tool time`
  Future<String> time() async {
    final r = await _call('time');
    if (r == null || r['ok'] != true) {
      return _unavailable;
    }
    final raw = r['value'];
    final ms = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? -1;
    final sb = StringBuffer();
    sb.writeln('=== Native Tool Time ===');
    sb.writeln('Epoch ms: $ms');
    if (ms > 0) {
      sb.write(
        'ISO: ${DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String()}',
      );
    } else {
      sb.write('ISO: (unavailable)');
    }
    return sb.toString();
  }

  /// `native-tool env` — only the safe whitelist is ever shown.
  Future<String> env() async {
    final r = await _call('env');
    if (r == null || r['ok'] != true) {
      return _unavailable;
    }
    final rawEnv = r['env'];
    final envMap = rawEnv is Map
        ? Map<String, dynamic>.from(rawEnv)
        : <String, dynamic>{};
    final sb = StringBuffer();
    sb.writeln('=== Native Tool Env ===');
    for (var i = 0; i < safeEnvKeys.length; i++) {
      final key = safeEnvKeys[i];
      final value = envMap[key]?.toString();
      final line = '$key=${value == null || value.isEmpty ? '(unset)' : value}';
      if (i == safeEnvKeys.length - 1) {
        sb.write(line);
      } else {
        sb.writeln(line);
      }
    }
    return sb.toString();
  }

  /// `native-tool doctor`
  Future<String> doctor() async {
    final r = await _call('doctor');
    final bridgeOk = r != null && r['ok'] == true;
    final echoOk = bridgeOk && r['echoOk'] == true;
    final cwdOk = bridgeOk && (r['cwd']?.toString().isNotEmpty ?? false);
    final abiOk =
        bridgeOk &&
        (r['abi']?.toString().isNotEmpty ?? false) &&
        r['abi'] != 'unknown';
    final hashOk = bridgeOk && r['hashOk'] == true;

    final String overall;
    if (!bridgeOk) {
      overall = 'UNHEALTHY';
    } else if (echoOk && cwdOk && abiOk && hashOk) {
      overall = 'HEALTHY';
    } else {
      overall = 'LIMITED';
    }

    final sb = StringBuffer();
    sb.writeln('=== Native Tool Doctor ===');
    sb.writeln('Bridge: ${bridgeOk ? 'OK' : 'FAIL'}');
    sb.writeln('Echo: ${echoOk ? 'OK' : 'FAIL'}');
    sb.writeln('CWD: ${cwdOk ? 'OK' : 'FAIL'}');
    sb.writeln('ABI: ${abiOk ? 'OK' : 'FAIL'}');
    sb.writeln('Hash: ${hashOk ? 'OK' : 'FAIL'}');
    sb.writeln('Tiny JS proof: available via js-proof');
    sb.writeln('JS engine decision: available via js-engine-decision');
    sb.writeln('Runtime research: available via runtime-candidates');
    sb.writeln('Recommended next proof: runtime-next');
    sb.writeln('Node.js: not included');
    sb.write('Overall: $overall');
    return sb.toString();
  }
}
