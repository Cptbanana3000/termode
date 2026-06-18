import 'dart:io';

import 'package:flutter/services.dart';

import 'runtime_bootstrap_service.dart';

/// Result of the bundled native runtime proof.
class BundledRuntimeProof {
  final bool bridgeOk;
  final bool tokenOk;
  final bool echoOk;
  final String token;
  final String echo;
  final String abi;
  final String cwd;
  final int pid;
  final String apkNativeLayer;
  final String? error;

  const BundledRuntimeProof({
    required this.bridgeOk,
    required this.tokenOk,
    required this.echoOk,
    required this.token,
    required this.echo,
    required this.abi,
    required this.cwd,
    required this.pid,
    required this.apkNativeLayer,
    this.error,
  });

  factory BundledRuntimeProof.unavailable(String? error) => BundledRuntimeProof(
    bridgeOk: false,
    tokenOk: false,
    echoOk: false,
    token: '',
    echo: '',
    abi: 'unknown',
    cwd: 'unknown',
    pid: -1,
    apkNativeLayer: 'unknown',
    error: error,
  );

  /// PROOF READY / LIMITED / UNAVAILABLE
  String get readiness {
    if (!bridgeOk) return 'UNAVAILABLE';
    if (tokenOk && echoOk) return 'PROOF READY';
    return 'LIMITED';
  }

  /// PASS / LIMITED / FAIL
  String get testResult {
    if (!bridgeOk) return 'FAIL';
    if (tokenOk && echoOk) return 'PASS';
    return 'LIMITED';
  }
}

/// Bundled Runtime Proof Strategy (v0.28).
///
/// Proves the safest future path for a real bundled runtime by exercising a
/// tiny native bridge proof shipped inside the APK's native library. It ships
/// **no** real runtime: no Node.js, npm, Python, or Git, and it downloads or
/// executes no app-writable binaries.
class BundledRuntimeService {
  static final BundledRuntimeService _instance =
      BundledRuntimeService._internal();
  factory BundledRuntimeService() => _instance;
  BundledRuntimeService._internal();

  static const String channelName = 'com.termode/native_shell';
  static const String nativeLibrary = 'libtermode_pty.so';
  static const String proofToken = 'termode-native-proof-ok';

  RuntimeBootstrapService _runtime = RuntimeBootstrapService();

  // Test hook to override the bootstrap service.
  set runtimeBootstrapService(RuntimeBootstrapService service) {
    _runtime = service;
  }

  Future<BundledRuntimeProof> proof() async {
    try {
      final dynamic res = await const MethodChannel(
        channelName,
      ).invokeMethod('bundledRuntimeProof');
      if (res is Map) {
        final token = res['token']?.toString() ?? '';
        final echo = res['echo']?.toString() ?? '';
        final bridge = res['nativeBridge'] == true || token == proofToken;
        return BundledRuntimeProof(
          bridgeOk: bridge,
          tokenOk: token == proofToken,
          echoOk: echo == 'hello',
          token: token,
          echo: echo,
          abi: res['abi']?.toString() ?? 'unknown',
          cwd: res['cwd']?.toString() ?? 'unknown',
          pid: res['pid'] is int
              ? res['pid'] as int
              : int.tryParse(res['pid']?.toString() ?? '') ?? -1,
          apkNativeLayer: res['apkNativeLayer']?.toString() ?? 'unknown',
        );
      }
      return BundledRuntimeProof.unavailable('native proof returned no data');
    } on PlatformException catch (e) {
      return BundledRuntimeProof.unavailable(e.message ?? e.code);
    } on MissingPluginException {
      return BundledRuntimeProof.unavailable('native bridge unavailable');
    } catch (e) {
      return BundledRuntimeProof.unavailable(e.toString());
    }
  }

  // --------------------------------------------------------------------------
  // Commands
  // --------------------------------------------------------------------------

  /// `bundled-runtime-info`
  Future<String> info() async {
    final p = await proof();
    final sb = StringBuffer();
    sb.writeln('=== Bundled Runtime Info ===');
    sb.writeln('ABI: ${p.abi}');
    sb.writeln('Native bridge: ${p.bridgeOk ? 'OK' : 'unavailable'}');
    sb.writeln(
      'APK native layer: ${p.bridgeOk ? p.apkNativeLayer : 'unknown'}',
    );
    sb.writeln('Executable strategy: bridge/native-lib proof');
    sb.writeln('Tiny native tool: available (bridge-exposed, not a package)');
    sb.writeln('Tiny JS proof: available via js-proof (not Node)');
    sb.writeln('JS engine decision: available via js-engine-decision');
    sb.writeln('QuickJS probe: limited/unavailable via quickjs');
    sb.writeln('Duktape probe: limited/unavailable via duktape');
    sb.writeln('Runtime candidate research: available');
    sb.writeln('Node.js: not included');
    sb.write('Overall: ${p.readiness}');
    return sb.toString();
  }

  /// `bundled-runtime-test`
  Future<String> test() async {
    final p = await proof();
    final sb = StringBuffer();
    sb.writeln('=== Bundled Runtime Test ===');
    sb.writeln('Native bridge call: ${p.bridgeOk ? 'OK' : 'FAIL'}');
    sb.writeln('ABI: ${p.abi}');
    sb.writeln('Native cwd: ${p.cwd}');
    sb.writeln('Native pid: ${p.pid}');
    sb.writeln('Echo proof: ${p.echoOk ? 'OK' : 'FAIL'}');
    sb.writeln('Tiny native tool: available');
    sb.writeln('Tiny JS proof: available');
    sb.writeln('JS engine decision/probe: available');
    sb.writeln('QuickJS probe command surface: available');
    sb.writeln('Duktape probe command surface: available');
    sb.writeln('Runtime candidate research: available');
    sb.write('Overall: ${p.testResult}');
    return sb.toString();
  }

  /// `bundled-runtime-doctor`
  Future<String> doctor({bool verbose = false}) async {
    final p = await proof();
    final sb = StringBuffer();
    sb.writeln('=== Bundled Runtime Doctor ===');
    sb.writeln('Native bridge: ${p.bridgeOk ? 'OK' : 'unavailable'}');
    sb.writeln('Native proof token: ${p.tokenOk ? 'OK' : 'MISSING'}');
    sb.writeln('Echo dispatcher: ${p.echoOk ? 'OK' : 'MISSING'}');
    sb.writeln('ABI: ${p.abi}');
    sb.writeln(
      'APK native layer: ${p.bridgeOk ? p.apkNativeLayer : 'unknown'}',
    );
    sb.writeln('Bundled executable: ${_bundledExecutableStatus()}');
    sb.writeln('Tiny native tool: available (bridge-exposed)');
    sb.writeln('Tiny JS proof: available (js-proof)');
    sb.writeln('JS engine decision: available (js-engine-decision)');
    sb.writeln('QuickJS probe: limited/unavailable (quickjs)');
    sb.writeln('Duktape probe: limited/unavailable (duktape)');
    sb.writeln(
      'Recommended next milestone: v0.36 Product Stabilization / Beta Readiness Pass',
    );
    sb.writeln('Node.js: not included');
    if (verbose) {
      sb.writeln();
      sb.writeln('Details:');
      sb.writeln('  Native library: $nativeLibrary');
      sb.writeln('  Native channel: $channelName (bundledRuntimeProof)');
      sb.writeln('  Token value: ${p.token.isEmpty ? '(none)' : p.token}');
      sb.writeln('  Echo value: ${p.echo.isEmpty ? '(none)' : p.echo}');
      sb.writeln('  Native cwd: ${p.cwd}');
      sb.writeln('  Native pid: ${p.pid}');
      if (p.error != null) {
        sb.writeln('  Error: ${p.error}');
      }
    }
    sb.write('Overall: ${p.readiness}');
    return sb.toString();
  }

  /// `bundled-runtime-paths`
  Future<String> paths() async {
    final p = await proof();
    final runtimePaths = await _runtime.getPaths();
    final sb = StringBuffer();
    sb.writeln('=== Bundled Runtime Paths ===');
    sb.writeln('Native library: $nativeLibrary');
    sb.writeln('Native bridge channel: $channelName');
    sb.writeln('Native cwd: ${p.cwd}');
    sb.writeln('App HOME: ${runtimePaths['home']}');
    sb.writeln('App USR: ${runtimePaths['usr']}');
    sb.writeln('App BIN: ${runtimePaths['bin']}');
    sb.writeln('APK native libs: managed by Android (per-ABI, read-only)');
    sb.write(
      'Note: app-writable usr/bin execution is blocked/limited on Android.',
    );
    return sb.toString();
  }

  /// `bundled-runtime-plan`
  String plan() {
    return '=== Bundled Runtime Plan ===\n'
        '1. Native bridge proof (v0.28) - prove JNI calls return a native token, ABI, pid, and cwd.\n'
        '2. Native echo dispatcher proof - prove native-side command handling without external code.\n'
        '3. Tiny native tool proof (v0.29) - audited native tools (native-tool) through the JNI bridge.\n'
        '4. Native runtime candidate research - study which runtimes can ship via the APK native layer.\n'
        '5. Tiny JS/runtime feasibility proof (v0.31) - controlled js-proof evaluator through the native bridge.\n'
        '6. Real embedded JS engine decision/probe (v0.32) - choose QuickJS/Duktape/no-engine-yet before engine code.\n'
        '7. QuickJS probe (v0.33) - command/bridge surface; engine source not integrated in this build.\n'
        '8. Duktape probe (v0.34) - fallback command/bridge surface; engine source not integrated in this build.\n'
        '9. Runtime decision freeze (v0.35) - frozen; keep js-proof active and defer real runtimes.\n'
        '10. Product stabilization (v0.36) - docs/help, onboarding, QA, package/workspace/terminal polish.\n'
        '11. Node as APK-shipped native component - investigate shipping Node in the APK native layer later.\n'
        '12. Node via native bridge control - drive a runtime through JNI rather than direct exec later.\n'
        '13. Standalone native executable - only if Android allows; app-private exec is blocked.\n'
        '14. Fallback - no Node until a safe strategy is proven.\n'
        'Node.js: not included.';
  }

  String _bundledExecutableStatus() {
    // Termode does not ship a standalone bundled executable. Android blocks
    // execution from app-writable paths, so direct app-bin execution is
    // treated as blocked on-device and unknown elsewhere.
    return Platform.isAndroid ? 'blocked' : 'unknown';
  }
}
