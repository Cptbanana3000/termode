import 'dart:io';

import 'native_command_service.dart';
import 'runtime_bootstrap_service.dart';
import 'terminal_session_service.dart';
import 'workspace_service.dart';

class RuntimeProbeResult {
  final bool shellOk;
  final bool toyboxOk;
  final bool appHomeOk;
  final bool appUsrOk;
  final bool scriptsViaShOk;
  final String directAppBinExec;
  final bool nativeBridgeOk;
  final bool workspaceCwdOk;
  final Map<String, String> details;

  RuntimeProbeResult({
    required this.shellOk,
    required this.toyboxOk,
    required this.appHomeOk,
    required this.appUsrOk,
    required this.scriptsViaShOk,
    required this.directAppBinExec,
    required this.nativeBridgeOk,
    required this.workspaceCwdOk,
    required this.details,
  });

  String get overall {
    final requiredOk =
        shellOk &&
        toyboxOk &&
        appHomeOk &&
        appUsrOk &&
        scriptsViaShOk &&
        nativeBridgeOk &&
        workspaceCwdOk;
    if (!requiredOk) return 'UNHEALTHY';
    return directAppBinExec == 'allowed' ? 'HEALTHY' : 'LIMITED';
  }
}

class RuntimeCapabilityService {
  final NativeCommandService _native;
  final RuntimeBootstrapService _runtime;
  final WorkspaceService _workspace;

  RuntimeCapabilityService({
    NativeCommandService? native,
    RuntimeBootstrapService? runtime,
    WorkspaceService? workspace,
  }) : _native = native ?? NativeCommandService(),
       _runtime = runtime ?? RuntimeBootstrapService(),
       _workspace = workspace ?? WorkspaceService();

  Future<RuntimeProbeResult> probe(String sessionId) async {
    await _runtime.init();
    final paths = await _runtime.getPaths();
    final home = Directory(paths['home']!);
    final usr = Directory(paths['usr']!);
    final bin = Directory(paths['bin']!);
    final workspacePaths = await _workspace.paths();
    final projectsRoot = Directory(workspacePaths['projectsRoot']!);

    final details = <String, String>{};
    final shell = await _native.execute(
      '/system/bin/sh -c "echo shell-ok"',
      sessionId,
      timeoutMs: 5000,
    );
    details['shell'] = _formatNativeDetail(shell);

    final toybox = await _native.execute(
      '/system/bin/toybox echo toybox-ok',
      sessionId,
      timeoutMs: 5000,
    );
    details['toybox'] = _formatNativeDetail(toybox);

    final proofScript = File('${bin.path}/runtime-exec-proof');
    await proofScript.parent.create(recursive: true);
    await proofScript.writeAsString(
      '#!/system/bin/sh\nprintf "script-ok\\n"\n',
    );

    final viaSh = await _native.execute(
      '/system/bin/sh "${proofScript.path}"',
      sessionId,
      timeoutMs: 5000,
    );
    details['scriptViaSh'] = _formatNativeDetail(viaSh);

    final direct = await _native.execute(
      '"${proofScript.path}"',
      sessionId,
      timeoutMs: 5000,
    );
    details['directAppBinExec'] = _formatNativeDetail(direct);

    final diagnostics = await _native.getDiagnostics();
    details['nativeBridge'] = diagnostics == null ? 'missing' : 'native-ok';
    details['abi'] = diagnostics?['abi']?.toString() ?? 'unknown';
    details['pid'] = diagnostics?['pid']?.toString() ?? 'unknown';
    details['nativeCwd'] =
        diagnostics?['cwd']?.toString() ??
        diagnostics?['userDir']?.toString() ??
        'unknown';
    details['appHomePath'] = home.path;
    details['appUsrPath'] = usr.path;
    details['appBinPath'] = bin.path;
    details['workspaceRoot'] = projectsRoot.path;
    details['trackedCwd'] = _workspace.trackedWorkingDirectory();

    final session = TerminalSessionService().activeSession;
    final preferred = session.preferredWorkingDirectory;
    final cwdOk =
        projectsRoot.existsSync() &&
        (preferred == null ||
            _workspace.isInside(preferred, home.path) ||
            _workspace.isInside(preferred, projectsRoot.path));

    return RuntimeProbeResult(
      shellOk: shell.exitCode == 0 && shell.stdout.contains('shell-ok'),
      toyboxOk: toybox.exitCode == 0 && toybox.stdout.contains('toybox-ok'),
      appHomeOk: home.existsSync(),
      appUsrOk: usr.existsSync() && bin.existsSync(),
      scriptsViaShOk: viaSh.exitCode == 0 && viaSh.stdout.contains('script-ok'),
      directAppBinExec: _directExecStatus(direct),
      nativeBridgeOk: diagnostics != null,
      workspaceCwdOk: cwdOk,
      details: details,
    );
  }

  Future<String> doctor(String sessionId, {bool verbose = false}) async {
    final report = await probe(sessionId);
    final sb = StringBuffer();
    sb.writeln('=== Runtime Doctor ===');
    sb.writeln('Shell: ${_ok(report.shellOk)}');
    sb.writeln('Toybox: ${_ok(report.toyboxOk)}');
    sb.writeln('App HOME: ${_ok(report.appHomeOk)}');
    sb.writeln('App USR: ${_ok(report.appUsrOk)}');
    sb.writeln('Scripts via sh: ${_ok(report.scriptsViaShOk)}');
    sb.writeln('Direct app-bin exec: ${report.directAppBinExec}');
    sb.writeln('Native bridge: ${_ok(report.nativeBridgeOk)}');
    sb.writeln(
      'Bundled proof: ${report.nativeBridgeOk ? 'PROOF READY' : 'UNAVAILABLE'}',
    );
    sb.writeln('Workspace cwd: ${_ok(report.workspaceCwdOk)}');
    if (verbose) {
      sb.writeln();
      sb.writeln('Probe details:');
      sb.writeln('  App HOME path: ${report.details['appHomePath']}');
      sb.writeln('  App USR path: ${report.details['appUsrPath']}');
      sb.writeln('  App BIN path: ${report.details['appBinPath']}');
      sb.writeln('  Workspace root: ${report.details['workspaceRoot']}');
      sb.writeln('  Tracked cwd: ${report.details['trackedCwd']}');
      sb.writeln('  Shell probe: ${report.details['shell']}');
      sb.writeln('  Toybox probe: ${report.details['toybox']}');
      sb.writeln('  Script via sh probe: ${report.details['scriptViaSh']}');
      sb.writeln(
        '  Direct app-bin probe: ${report.details['directAppBinExec']}',
      );
      sb.writeln('  Native bridge probe: ${report.details['nativeBridge']}');
      sb.writeln('  ABI: ${report.details['abi']}');
      sb.writeln('  Native pid: ${report.details['pid']}');
      sb.writeln('  Native cwd: ${report.details['nativeCwd']}');
    }
    sb.write('Overall: ${report.overall}');
    return sb.toString();
  }

  Future<String> execTest(String sessionId, {bool verbose = false}) async {
    final report = await probe(sessionId);
    final sb = StringBuffer();
    sb.writeln('=== Runtime Exec Test ===');
    sb.writeln('/system/bin/sh: ${_pass(report.shellOk)}');
    sb.writeln('/system/bin/toybox: ${_pass(report.toyboxOk)}');
    sb.writeln('script via /system/bin/sh: ${_pass(report.scriptsViaShOk)}');
    sb.writeln('direct app-bin exec: ${report.directAppBinExec}');
    sb.writeln('workspace cwd probe: ${_pass(report.workspaceCwdOk)}');
    sb.writeln('native bridge probe: ${_pass(report.nativeBridgeOk)}');
    sb.writeln('bundled native proof: ${_pass(report.nativeBridgeOk)}');
    if (verbose) {
      sb.writeln();
      sb.writeln('Details:');
      for (final entry in report.details.entries) {
        sb.writeln('  ${entry.key}: ${entry.value}');
      }
    }
    sb.write('Overall: ${report.overall}');
    return sb.toString();
  }

  String capabilities() {
    return '=== Runtime Capabilities ===\n'
        'Supported:\n'
        '  - REAL PTY shell sessions\n'
        '  - Android system shell commands via /system/bin/sh\n'
        '  - Toybox/system tools\n'
        '  - Script packages through /system/bin/sh\n'
        '  - Remote script packages after repo trust/source checks\n'
        '  - Workspace folders under files/home/projects\n'
        '  - Localhost diagnostics for ports, HTTP checks, and preview URLs\n'
        '  - Bundled native bridge proof (v0.28)\n\n'
        'Not supported yet:\n'
        '  - Native binary packages\n'
        '  - Node.js\n'
        '  - npm\n'
        '  - Python\n'
        '  - Git\n\n'
        'Bundled runtime: native bridge proof available. Node.js not included.\n'
        'Next runtime phase: tiny native tool proof.';
  }

  String plan() {
    return '=== Runtime Plan ===\n'
        '1. Script packages - keep package helpers reliable and source-locked.\n'
        '2. Runtime diagnostics - keep shell, Toybox, and script probes visible.\n'
        '3. Localhost/preview workflow - prove dev server readiness and preview URLs without Node yet.\n'
        '4. Bundled native proof - tiny JNI/native bridge proof inside the APK (v0.28), no Node.\n'
        '5. Tiny native tool proof - add one tiny audited native tool later.\n'
        '6. Node proof later - test ABI, extraction, and execution constraints.\n'
        '7. npm proof later - prove package install/cache behavior in app storage.\n'
        '8. Vite proof later - run a minimal dev server inside the sandbox.\n'
        '9. CalypsoIDE integration later - wire editor workflows after runtime proof.';
  }

  String _directExecStatus(NativeCommandResult result) {
    final combined = '${result.stdout}\n${result.stderr}'.toLowerCase();
    if (result.exitCode == 0 && result.stdout.contains('script-ok')) {
      return 'allowed';
    }
    if (result.exitCode == 126 || combined.contains('permission denied')) {
      return 'blocked';
    }
    return 'unknown';
  }

  String _formatNativeDetail(NativeCommandResult result) {
    final out = result.stdout.trim();
    final err = result.stderr.trim();
    final parts = <String>['exit=${result.exitCode}'];
    if (out.isNotEmpty) parts.add('stdout=$out');
    if (err.isNotEmpty) parts.add('stderr=$err');
    return parts.join(' ');
  }

  String _ok(bool value) => value ? 'OK' : 'MISSING';

  String _pass(bool value) => value ? 'PASS' : 'FAIL';
}
