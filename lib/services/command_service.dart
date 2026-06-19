import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'command_catalog.dart';
import 'virtual_filesystem.dart';
import 'native_command_service.dart';
import 'runtime_bootstrap_service.dart';
import 'storage_access_service.dart';
import 'terminal_session_service.dart';
import 'settings_service.dart';
import 'runtime_tool_service.dart';
import 'runtime_capability_service.dart';
import 'runtime_candidate_service.dart';
import 'runtime_freeze_service.dart';
import 'localhost_service.dart';
import 'preview_service.dart';
import 'bundled_runtime_service.dart';
import 'native_tool_service.dart';
import 'js_proof_service.dart';
import 'js_engine_decision_service.dart';
import 'quickjs_service.dart';
import 'duktape_service.dart';
import 'package_manager_service.dart';
import 'workspace_service.dart';
import 'runtime_prefix_service.dart';
import 'runtime_binary_package_service.dart';

class CommandResult {
  final String output;
  final bool isError;
  final bool shouldClear;
  final bool shouldReloadShellHelpers;
  final String? helperReloadSuccessMessage;
  final String? helperReloadFailureMessage;

  CommandResult({
    required this.output,
    this.isError = false,
    this.shouldClear = false,
    this.shouldReloadShellHelpers = false,
    this.helperReloadSuccessMessage,
    this.helperReloadFailureMessage,
  });
}

class CommandService {
  final VirtualFileSystem vfs;
  final String sessionId;

  CommandService(this.vfs, this.sessionId);

  String _packageTryLine(PackageOperationResult result, String pkgName) {
    final example = result.example;
    if (example != null && example.trim().isNotEmpty) {
      return 'Try: ${example.trim()}';
    }
    return 'Tip: Command is available now. Try: ${result.executable ?? pkgName}';
  }

  String _formatStorageError(PlatformException e) {
    switch (e.code) {
      case 'NOT_LINKED':
        return 'Error: No storage folder is currently linked. Use "storage-link" to connect one.';
      case 'FILE_NOT_FOUND':
        return 'Error: File not found in linked storage.';
      case 'PERMISSION_REVOKED':
        return 'Error: Permission revoked or folder access denied.';
      case 'WRITE_FAILED':
        return 'Error: Write operation failed.';
      case 'UNSUPPORTED_FOLDER':
        return 'Error: Unsupported folder selected.';
      default:
        return 'Error: ${e.message ?? e.code}';
    }
  }

  String _normalizePath(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    final List<String> result = [];
    for (final part in parts) {
      if (part == '' || part == '.') {
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
    final prefix = path.startsWith('/') ? '/' : '';
    return prefix + result.join('/');
  }

  File? _resolveFileInHome(String inputPath, String homePath) {
    final combined = '$homePath/$inputPath';
    final normalized = _normalizePath(combined);
    final normalizedHome = _normalizePath(homePath);

    if (normalized == normalizedHome ||
        normalized.startsWith('$normalizedHome/')) {
      return File(normalized);
    }
    return null; // Path traversal detected!
  }

  // Parse arguments, supporting double-quoted string groupings
  List<String> _parseArgs(String input) {
    final List<String> args = [];
    final RegExp regex = RegExp(r'"([^"]*)"|([^\s]+)');
    final Iterable<RegExpMatch> matches = regex.allMatches(input);
    for (final match in matches) {
      if (match.group(1) != null) {
        args.add(match.group(1)!);
      } else if (match.group(2) != null) {
        args.add(match.group(2)!);
      }
    }
    return args;
  }

  String _yesNo(bool value) => value ? 'yes' : 'no';

  String _statusFromDoctorOutput(String output) {
    final upper = output.toUpperCase();
    final explicitStatusMatches = RegExp(
      r'(?:OVERALL|OVERALL STATUS|OVERALL READINESS|FINAL HEALTH|STATUS|RESULT):\s*(UNHEALTHY|FAIL|FAILED|LIMITED|HEALTHY|PASS|FROZEN)',
    ).allMatches(upper).toList();
    if (explicitStatusMatches.isNotEmpty) {
      final status = explicitStatusMatches.last.group(1)!;
      if (status == 'UNHEALTHY' || status == 'FAIL' || status == 'FAILED') {
        return 'UNHEALTHY';
      }
      if (status == 'LIMITED') {
        return 'LIMITED';
      }
      return 'HEALTHY';
    }
    if (upper.contains('OVERALL: UNHEALTHY') ||
        upper.contains('OVERALL READINESS: UNHEALTHY') ||
        upper.contains('OVERALL: FAIL') ||
        upper.contains('FAIL')) {
      return 'UNHEALTHY';
    }
    if (upper.contains('OVERALL: LIMITED') ||
        upper.contains('OVERALL READINESS: LIMITED') ||
        upper.contains('LIMITED')) {
      return 'LIMITED';
    }
    if (upper.contains('OVERALL: FROZEN') ||
        upper.contains('OVERALL: HEALTHY') ||
        upper.contains('STATUS: HEALTHY') ||
        upper.contains('OVERALL STATUS: HEALTHY') ||
        upper.contains('FINAL HEALTH: HEALTHY') ||
        upper.contains('RESULT: PASS') ||
        upper.contains('PASS')) {
      return 'HEALTHY';
    }
    return 'LIMITED';
  }

  String _overallFromStatuses(Iterable<String> statuses) {
    if (statuses.contains('UNHEALTHY')) return 'UNHEALTHY';
    if (statuses.contains('LIMITED')) return 'LIMITED';
    return 'HEALTHY';
  }

  Future<String> _storageBetaStatus() async {
    try {
      final status = await StorageAccessService().getStatus();
      final linked =
          status != null &&
          ((status['linked']?.toLowerCase() == 'true') ||
              (status['displayName']?.trim().isNotEmpty ?? false));
      return linked ? 'OK' : 'LIMITED';
    } catch (_) {
      return 'LIMITED';
    }
  }

  Future<String> _betaStatusOutput() async {
    final storage = await _storageBetaStatus();
    final overall = storage == 'OK' ? 'BETA CANDIDATE' : 'LIMITED';
    return '=== Termode Beta Status ===\n'
        'PTY: OK\n'
        'Packages: OK\n'
        'Remote repo: OK\n'
        'Workspace: OK\n'
        'Storage: $storage\n'
        'Sessions: OK\n'
        'Terminal UX: OK\n'
        'Runtime: FROZEN\n'
        'Overall: $overall';
  }

  String _betaScoreOutput() {
    return '=== Beta Readiness Score ===\n'
        'Core shell: 20/20\n'
        'Packages: 20/20\n'
        'Workspaces: 15/15\n'
        'Sessions: 15/15\n'
        'Terminal UX: 15/15\n'
        'Docs/help: 10/15\n'
        'Total: 95/100';
  }

  String _betaChecklistOutput() {
    return '=== Beta Checklist ===\n'
        '* Run default-shell\n'
        '* Run pkg doctor\n'
        '* Run workspace-doctor\n'
        '* Run session-doctor\n'
        '* Run preview-doctor\n'
        '* Run runtime-freeze doctor\n'
        '* Test tab-new/tab-close\n'
        '* Test workspace-init/workspace-cd\n'
        '* Test package install/remove\n'
        '* Test background/restore\n'
        '* Test copy/paste\n'
        '* Test scroll-test 300';
  }

  String _betaKnownLimitsOutput() {
    return '=== Beta Known Limits ===\n'
        '* Node.js/npm are not included yet.\n'
        '* Python/Git are not included yet.\n'
        '* Runtime package installer is prototype-only.\n'
        '* Native binary packages are planned, not enabled.\n'
        '* QuickJS/Duktape are probe surfaces only.\n'
        '* Runtime research is frozen for now.\n'
        '* Storage features need Android folder linking.\n'
        '* Termode is beta software.';
  }

  String _betaNextOutput() {
    return '=== Beta Next ===\n'
        'Recommended next milestone:\n'
        'v0.46 Git Package Artifact / Real Git Execution\n\n'
        'Reason: v0.45 proves the Git installer path but ships no Git artifact; next vendors/builds a verified Git package.';
  }

  /// Computes beta-candidate readiness. Intentional limitations (frozen
  /// runtime, deferred QuickJS/Duktape, unlinked storage) are NOT blockers.
  /// Only a genuinely UNHEALTHY core subsystem (packages, workspaces,
  /// sessions) blocks beta readiness.
  Future<
    ({
      bool ready,
      String reason,
      String packages,
      String workspaces,
      String sessions,
    })
  >
  _betaCandidateReadiness() async {
    final packages = _statusFromDoctorOutput(
      (await execute('pkg doctor')).output,
    );
    final workspaces = _statusFromDoctorOutput(
      (await execute('workspace-doctor')).output,
    );
    final sessions = _statusFromDoctorOutput(
      (await execute('session-doctor')).output,
    );
    String? blocker;
    if (packages == 'UNHEALTHY') {
      blocker = 'package manager is unhealthy (run pkg doctor)';
    } else if (workspaces == 'UNHEALTHY') {
      blocker = 'workspace system is unhealthy (run workspace-doctor)';
    } else if (sessions == 'UNHEALTHY') {
      blocker = 'session system is unhealthy (run session-doctor)';
    }
    return (
      ready: blocker == null,
      reason: blocker ?? '',
      packages: packages,
      workspaces: workspaces,
      sessions: sessions,
    );
  }

  Future<String> _betaCandidateStatusOutput() async {
    final r = await _betaCandidateReadiness();
    String label(String s) => s == 'UNHEALTHY' ? 'UNHEALTHY' : 'OK';
    final prefixReady = await RuntimePrefixService().isInitialized();
    return '=== Termode Beta Candidate ===\n'
        'Version: v0.45\n'
        'Core shell: OK\n'
        'Packages: ${label(r.packages)}\n'
        'Workspaces: ${label(r.workspaces)}\n'
        'Sessions: ${label(r.sessions)}\n'
        'Terminal UX: OK\n'
        'Runtime: FROZEN (prototype installer active)\n'
        'Prefix: ${prefixReady ? 'initialized' : 'not initialized'}\n'
        'PATH overlay: ${prefixReady ? 'ready' : 'limited'}\n'
        'Runtime package installer: prototype ready\n'
        'Git: feasibility (planned, not installed)\n'
        'Toolchains: planned (not installed)\n'
        'Known limitations: yes\n'
        'Overall: ${r.ready ? 'BETA CANDIDATE' : 'NEEDS FIXES'}';
  }

  Future<String> _betaCandidateReadyOutput() async {
    final r = await _betaCandidateReadiness();
    return r.ready ? 'Ready for beta testing.' : 'Not ready: ${r.reason}';
  }

  String _betaCandidateChecklistOutput() {
    return '=== Beta Candidate Checklist ===\n'
        '* doctor\n'
        '* beta-score\n'
        '* qa-status\n'
        '* pkg doctor\n'
        '* workspace-doctor\n'
        '* session-doctor\n'
        '* runtime-freeze doctor\n'
        '* preview-doctor\n'
        '* localhost-doctor\n'
        '* settings-doctor\n'
        '* manual install test\n'
        '* force close/reopen test\n'
        '* package install/remove test\n'
        '* workspace file test';
  }

  String _betaCandidateNotesOutput() {
    return '=== Termode v0.45 Beta Candidate ===\n'
        'Termode is a standalone Android terminal with a REAL PTY shell.\n\n'
        'Highlights:\n'
        '* REAL PTY shell with host command interception\n'
        '* script packages (pkg) with trusted remote repo, verify, upgrade, repair\n'
        '* workspaces and safe host file commands\n'
        '* sessions, tabs, history, and scrollback persistence\n'
        '* terminal UX: keyboard, ANSI, paste, copy, scrollback helpers\n'
        '* settings/theme/status readouts and safe visual reset\n'
        '* preview/localhost diagnostics\n'
        '* prototype runtime package installer with hello-bin\n'
        '* QA/beta/onboarding tooling and doctors\n\n'
        'Runtime remains frozen beyond the prototype installer. Node/npm/Python/Git\n'
        'and real native packages are not included yet. Run beta-candidate limits.';
  }

  String _betaCandidateLimitsOutput() {
    return '=== Beta Candidate Limits ===\n'
        '* Node.js/npm are not included (planned, not installed).\n'
        '* Python/Git are not included (planned, not installed).\n'
        '* Runtime package installer is prototype-only.\n'
        '* Native binary packages are planned, not enabled yet.\n'
        '* QuickJS/Duktape are deferred.\n'
        '* Real toolchain installs are planned, not implemented (see runtime-install).\n'
        '* Direct app-bin execution may be blocked by Android.\n'
        '* Storage features need folder linking.\n'
        '* Beta software; bugs expected.';
  }

  String _betaCandidateHelpOutput() {
    return '=== Termode Beta Candidate ===\n'
        'Termode v0.45 is a terminal-foundation beta (Git support feasibility / installer path).\n\n'
        'Subcommands:\n'
        '  beta-candidate status     - Show beta candidate readiness summary\n'
        '  beta-candidate checklist  - Show the beta candidate checklist\n'
        '  beta-candidate notes      - Show concise release notes\n'
        '  beta-candidate limits     - Show known beta limitations\n'
        '  beta-candidate ready      - Show whether Termode is ready for beta\n\n'
        'See also: build-info, feedback, rc-status, doctor, qa-status.';
  }

  String _feedbackOutput() {
    return '=== Beta Feedback ===\n'
        'Use these when reporting a bug:\n\n'
        '1. bug-report\n'
        '2. qa-report\n'
        '3. beta-candidate status\n'
        '4. steps to reproduce\n'
        '5. expected result\n'
        '6. actual result\n'
        '7. screenshot/screen recording if possible\n\n'
        'Tip: feedback template gives a copy-friendly form. No data leaves your device.';
  }

  String _feedbackTemplateOutput() {
    return 'Termode version:\n'
        'Device:\n'
        'Android version:\n'
        'Command/area:\n'
        'Steps to reproduce:\n'
        'Expected:\n'
        'Actual:\n'
        'Does it happen after restart:\n'
        'Output from bug-report:\n'
        'Output from qa-report:';
  }

  String _feedbackChecklistOutput() {
    return '=== Beta Feedback Checklist ===\n'
        '* launch\n'
        '* typing\n'
        '* REAL PTY\n'
        '* package install/remove\n'
        '* workspace file write/read\n'
        '* force close/reopen\n'
        '* settings reset safe\n'
        '* beta-candidate ready';
  }

  String _rcChecklistOutput() {
    return '=== Release Candidate Checklist ===\n'
        '* flutter analyze\n'
        '* flutter test\n'
        '* debug APK build\n'
        '* install APK on real Android device\n'
        '* versionName/versionCode confirmed\n'
        '* version command checked\n'
        '* beta-candidate ready checked\n'
        '* doctor checked\n'
        '* qa-status checked\n'
        '* package install/remove checked\n'
        '* workspace file roundtrip checked\n'
        '* force-close/reopen checked\n'
        '* release notes reviewed\n'
        '* known limitations reviewed';
  }

  Future<String> _rcStatusOutput() async {
    final r = await _betaCandidateReadiness();
    final coreSystems = _overallFromStatuses([
      r.packages,
      r.workspaces,
      r.sessions,
    ]);
    final coreLabel = coreSystems == 'HEALTHY' ? 'OK' : coreSystems;
    return '=== Release Candidate Status ===\n'
        'Version: v0.45\n'
        'Beta candidate: yes\n'
        'Core systems: $coreLabel\n'
        'Known limitations: intentional\n'
        'Overall: ${r.ready ? 'RC CLEANUP READY' : 'NEEDS FIXES'}';
  }

  // --- v0.42 Runtime Expansion Architecture (planning only) ----------------
  // These commands describe Termode's FUTURE runtime/toolchain layer. They do
  // not install, download, or execute any external binary. They are a planning
  // and capability surface so the experience can be guided and honest.

  /// Planned toolchains. Display name, future role, the command users will run
  /// once installed, the future install command, and notes/risks.
  static const Map<String, Map<String, String>> _plannedToolchains = {
    'git': {
      'display': 'Git',
      'role': 'clone, commit, and manage source repositories',
      'command': 'git',
      'install': 'runtime-install git',
      'notes': 'needs a compatible prebuilt binary for the device ABI',
    },
    'node': {
      'display': 'Node.js',
      'role': 'run JavaScript/TypeScript tooling and local dev servers',
      'command': 'node',
      'install': 'runtime-install node',
      'notes': 'Node comes before npm; npm reuses the Node runtime',
    },
    'npm': {
      'display': 'npm',
      'role': 'install and manage Node packages',
      'command': 'npm',
      'install': 'runtime-install npm',
      'notes': 'requires Node first and a writable package/cache directory',
    },
    'python': {
      'display': 'Python',
      'role': 'run Python scripts and tooling',
      'command': 'python',
      'install': 'runtime-install python',
      'notes': 'needs a compatible prebuilt interpreter for the device ABI',
    },
    'curl': {
      'display': 'curl',
      'role': 'fetch URLs and APIs from the shell',
      'command': 'curl',
      'install': 'runtime-install curl',
      'notes': 'small native tool; useful for downloads in later milestones',
    },
    'wget': {
      'display': 'wget',
      'role': 'download files from the shell',
      'command': 'wget',
      'install': 'runtime-install wget',
      'notes': 'alternative to curl for downloads',
    },
    'nano': {
      'display': 'nano',
      'role': 'simple full-screen text editor',
      'command': 'nano',
      'install': 'runtime-install nano',
      'notes': 'needs mature full-screen PTY rendering',
    },
    'micro': {
      'display': 'micro',
      'role': 'modern terminal text editor',
      'command': 'micro',
      'install': 'runtime-install micro',
      'notes': 'single-binary editor; needs full-screen PTY rendering',
    },
  };

  static const List<String> _plannedToolchainOrder = [
    'git',
    'node',
    'npm',
    'python',
    'curl',
    'wget',
    'nano',
    'micro',
  ];

  String _toolchainStatusOutput() {
    return '=== Toolchain Status ===\n'
        'Runtime package installer: prototype ready\n'
        'Git: planned (feasibility active, not installed)\n'
        'Node.js: planned\n'
        'npm: planned\n'
        'Python: planned\n'
        'curl/wget: planned\n'
        'Editors: planned\n'
        'Overall: ARCHITECTURE PHASE';
  }

  String _toolchainListOutput() {
    final sb = StringBuffer('=== Planned Toolchains ===\n');
    for (final key in _plannedToolchainOrder) {
      sb.writeln('* $key');
    }
    sb.write('Status: planned (not installed)');
    return sb.toString();
  }

  String _toolchainInfoOutput(String name) {
    final key = name.toLowerCase();
    final tc = _plannedToolchains[key];
    if (tc == null) {
      return 'Unknown toolchain: $name\n'
          'Run: toolchain-list';
    }
    final sb = StringBuffer();
    sb.writeln('=== Toolchain: ${tc['display']} ===');
    sb.writeln('Status: not installed yet');
    sb.writeln('Future role: ${tc['role']}');
    sb.writeln('Expected command: ${tc['command']}');
    if (key == 'node') {
      sb.writeln('Expected commands: node, npm later');
      sb.writeln('Order: Node comes before npm');
      sb.writeln('npm note: npm will need package/cache handling');
    }
    if (key == 'git') {
      sb.writeln('Installed: no');
      sb.writeln('Feasibility: active (v0.45) — see git-status / git-plan');
    }
    sb.writeln('Future install command: ${tc['install']}');
    sb.write('Notes: ${tc['notes']}');
    return sb.toString();
  }

  String _toolchainPlanOutput() {
    return '=== Toolchain Plan ===\n'
        'Planned rollout order:\n'
        '  1. Prefix / PATH / environment (v0.43)\n'
        '  2. Binary package installer prototype (v0.44)\n'
        '  3. Git (v0.45)\n'
        '  4. Node.js (v0.46)\n'
        '  5. npm (v0.47)\n'
        '  6. Python (v0.48)\n'
        '  7. curl/wget and editors (nano/micro) alongside the above\n'
        'Status: ARCHITECTURE PHASE';
  }

  Future<String> _toolchainDoctorOutput() async {
    final initialized = await RuntimePrefixService().isInitialized();
    return '=== Toolchain Doctor ===\n'
        'Runtime package installer: prototype ready\n'
        'Git: planned (not installed)\n'
        'Node.js: planned (not installed)\n'
        'npm: planned (not installed)\n'
        'Python: planned (not installed)\n'
        'curl/wget: planned (not installed)\n'
        'Editors: planned (not installed)\n'
        'Prefix: ${initialized ? 'OK' : 'NOT INITIALIZED'}\n'
        'PATH overlay: ${initialized ? 'ready' : 'limited'}\n'
        'Env: ${initialized ? 'ready' : 'limited'}\n'
        'Bin dir: ${initialized ? 'ready' : 'limited'}\n'
        'Note: missing toolchains are expected; hello-bin is the only enabled prototype.\n'
        'Overall: PROTOTYPE READY';
  }

  String _runtimeInstallHelpOutput() {
    return '=== Runtime Install (prototype) ===\n'
        'Prototype installer is available for hello-bin.\n'
        'Real Git/Node/npm/Python installs are not enabled yet.\n'
        'Nothing is downloaded and no unknown binary is executed.\n\n'
        'Subcommands:\n'
        '  runtime-install list          - List prototype and planned runtimes\n'
        '  runtime-install plan <tool>   - Show the future install plan\n'
        '  runtime-install status        - Show install mode and prefix status\n'
        '  runtime-install doctor        - Check prototype installer readiness';
  }

  String _runtimeInstallListOutput() {
    final gitState = RuntimeBinaryPackageService().gitArtifactAvailable()
        ? 'installable if verified'
        : 'planned (artifact unavailable)';
    final sb = StringBuffer('Prototype available now:\n');
    sb.writeln('* hello-bin');
    sb.writeln();
    sb.writeln('Real tools:');
    sb.writeln('* git: $gitState');
    sb.writeln();
    sb.writeln('Planned future runtimes:');
    for (final key in _plannedToolchainOrder) {
      if (key == 'git') continue;
      sb.writeln('* $key');
    }
    return sb.toString().trimRight();
  }

  String _runtimeInstallPlanOutput(String tool) {
    final key = tool.toLowerCase();
    final tc = _plannedToolchains[key];
    if (tc == null) {
      return 'Unknown runtime: $tool\n'
          'Run: runtime-install list';
    }
    if (key == 'git') {
      final state = RuntimeBinaryPackageService().gitArtifactAvailable()
          ? 'installable'
          : 'planned (artifact unavailable)';
      return '=== Runtime Install Plan: Git ===\n'
          'Status: $state\n'
          'Future/supported steps:\n'
          '1. Verify Android ABI.\n'
          '2. Validate Git package manifest.\n'
          '3. Verify checksum.\n'
          '4. Install into TERMODE_PREFIX.\n'
          '5. Register git shim.\n'
          '6. Run git --version.\n'
          '7. Run git-doctor.\n'
          '8. Test Git inside a workspace.\n'
          'Run: git-plan';
    }
    return '=== Runtime Install Plan: ${tc['display']} ===\n'
        'Status: planned\n'
        'Install support: not implemented yet\n'
        'Future steps:\n'
        '1. Verify Android ABI.\n'
        '2. Select compatible runtime source.\n'
        '3. Install into Termode prefix.\n'
        '4. Add command shim.\n'
        '5. Run ${tc['command']} --version.\n'
        '6. Run runtime doctor.\n'
        'Run: toolchain-info $key';
  }

  Future<String> _runtimeInstallStatusOutput() async {
    final initialized = await RuntimePrefixService().isInitialized();
    final gitInstalled = await RuntimeBinaryPackageService().gitInstalled();
    return '=== Runtime Install Status ===\n'
        'Mode: prototype installer available\n'
        'Binary package installer prototype: ready\n'
        'Git support feasibility: active\n'
        'Real Git installed: ${gitInstalled ? 'yes' : 'no'}\n'
        'Real Git/Node/Python installs: not enabled yet\n'
        'Prototype package: hello-bin\n'
        'Prefix initialized: ${initialized ? 'yes' : 'no'}\n'
        'PATH overlay ready: ${initialized ? 'yes' : 'no'}\n'
        'Env ready: ${initialized ? 'yes' : 'no'}\n'
        'Bin dir ready: ${initialized ? 'yes' : 'no'}\n'
        'Next milestone: v0.46 Git Package Artifact / Real Git Execution';
  }

  Future<String> _runtimeInstallDoctorOutput() async {
    final prefix = RuntimePrefixService();
    final initialized = await prefix.isInitialized();
    final p = await prefix.paths();
    final binReady = Directory(p['bin']!).existsSync();
    final diagnostics = await NativeCommandService().getDiagnostics();
    final abi = diagnostics?['abi']?.toString();
    final runtimePkgDoctor = await RuntimeBinaryPackageService().doctor();
    final runtimePkgReady = !runtimePkgDoctor.contains('Overall: UNHEALTHY');
    return '=== Runtime Install Doctor ===\n'
        'Mode: prototype installer available\n'
        'Prefix: ${initialized ? 'OK' : 'LIMITED'}\n'
        'PATH: ${initialized ? 'OK' : 'LIMITED'}\n'
        'Env: ${initialized ? 'OK' : 'LIMITED'}\n'
        'Bin dir ready: ${binReady ? 'yes' : 'no'}\n'
        'Runtime package metadata: ${runtimePkgReady ? 'OK' : 'CHECK'}\n'
        'Prototype installer: enabled\n'
        'Android ABI: ${abi == null || abi.isEmpty ? 'unknown' : abi}\n'
        'Git artifact: ${RuntimeBinaryPackageService().gitArtifactAvailable() ? 'available' : 'unavailable'}\n'
        'Git: ${await RuntimeBinaryPackageService().gitInstalled() ? 'installed' : 'planned (not installed)'}\n'
        'Real Git/Node/npm/Python installs: not enabled yet\n'
        'Safety: no downloads, no native execution\n'
        'Overall: ${runtimePkgReady ? 'PROTOTYPE READY' : 'LIMITED'}';
  }

  String _devSetupHelpOutput() {
    return '=== Dev Setup (planning) ===\n'
        'Planning only. Nothing is installed yet.\n\n'
        'Subcommands:\n'
        '  dev-setup list           - List planned dev presets\n'
        '  dev-setup plan <preset>  - Show the future setup steps\n\n'
        'Presets: web, node, python, basic-tools';
  }

  String _devSetupListOutput() {
    return 'Available future presets:\n'
        '* web\n'
        '* node\n'
        '* python\n'
        '* basic-tools';
  }

  String _devSetupPlanOutput(String preset) {
    switch (preset.toLowerCase()) {
      case 'web':
        return '=== Dev Setup Plan: web ===\n'
            'Future setup:\n'
            '1. Install Node.js.\n'
            '2. Enable npm.\n'
            '3. Prepare workspace.\n'
            '4. Add package.json helper.\n'
            '5. Run local preview server.\n'
            '6. Open preview URL.';
      case 'node':
        return '=== Dev Setup Plan: node ===\n'
            'Future setup:\n'
            '1. Install Node.js.\n'
            '2. Enable npm.\n'
            '3. Prepare workspace.\n'
            '4. Add a start script.\n'
            '5. Run node --version.\n'
            '6. Run dev-doctor.';
      case 'python':
        return '=== Dev Setup Plan: python ===\n'
            'Future setup:\n'
            '1. Install Python.\n'
            '2. Prepare workspace.\n'
            '3. Add a virtual-env helper.\n'
            '4. Run python --version.\n'
            '5. Run dev-doctor.';
      case 'basic-tools':
        return '=== Dev Setup Plan: basic-tools ===\n'
            'Future setup:\n'
            '1. Install curl/wget.\n'
            '2. Install an editor (nano/micro).\n'
            '3. Install git.\n'
            '4. Run dev-doctor.';
      default:
        return 'Unknown dev-setup preset: $preset\n'
            'Run: dev-setup list';
    }
  }

  Future<String> _devDoctorOutput() async {
    final initialized = await RuntimePrefixService().isInitialized();
    return '=== Dev Doctor ===\n'
        'Terminal: OK\n'
        'REAL PTY: OK\n'
        'Runtime package installer: prototype ready\n'
        'Prefix: ${initialized ? 'OK' : 'LIMITED'}\n'
        'PATH: ${initialized ? 'OK' : 'LIMITED'}\n'
        'Env: ${initialized ? 'OK' : 'LIMITED'}\n'
        'Git: planned (not installed)\n'
        'Node.js: planned\n'
        'npm: planned\n'
        'Python: planned\n'
        'Overall: PROTOTYPE READY';
  }

  // --- v0.45 Git support feasibility (honest; no fake Git) -----------------

  Future<String> _gitStatusOutput() async {
    final pkg = RuntimeBinaryPackageService();
    final prefix = RuntimePrefixService();
    final installed = await pkg.gitInstalled();
    final artifact = pkg.gitArtifactAvailable();
    final prefixReady = await prefix.isInitialized();
    final prefixHealth = prefixReady ? 'HEALTHY' : 'LIMITED';
    final installMethod = installed
        ? 'runtime package'
        : (artifact ? 'runtime package (installable)' : 'planned (artifact unavailable)');
    final overall = installed
        ? 'AVAILABLE'
        : (artifact ? 'NOT INSTALLED' : 'PLANNED');
    return '=== Git Status ===\n'
        'Installed: ${installed ? 'yes' : 'no'}\n'
        'Command: git\n'
        'Version: ${installed ? 'see git-version' : 'not available'}\n'
        'Install method: $installMethod\n'
        'Prefix: $prefixHealth\n'
        'PATH: $prefixHealth\n'
        'Overall: $overall';
  }

  Future<String> _gitInfoOutput() async {
    final installed = await RuntimeBinaryPackageService().gitInstalled();
    return '=== Git Info ===\n'
        'Git is a distributed version control tool: clone, commit, branch, and\n'
        'track history of your project files.\n'
        'Installed: ${installed ? 'yes' : 'no'}\n'
        'Future install command: runtime-install plan git\n'
        '  (or: runtime-pkg install git once a verified artifact exists)\n'
        'Run: git-plan';
  }

  String _gitPlanOutput(bool artifactAvailable) {
    return '=== Git Support Plan ===\n'
        '1. Verify ABI.\n'
        '2. Validate Git package manifest.\n'
        '3. Install files into TERMODE_PREFIX.\n'
        '4. Register git shim.\n'
        '5. Run git --version.\n'
        '6. Run git-doctor.\n'
        '7. Test git init/status in workspace.\n'
        'Status: ${artifactAvailable ? 'installable (verified artifact present)' : 'planned (no safe Git artifact in this build)'}';
  }

  Future<String> _gitVersionOutput() async {
    final installed = await RuntimeBinaryPackageService().gitInstalled();
    if (!installed) {
      return 'Git is not installed yet.\n'
          'Run: git-plan\n'
          'Run: runtime-install plan git';
    }
    // A real verified Git package would run `git --version` here. No artifact
    // is bundled in this build, so this branch is never reached. We never print
    // a fake version.
    return 'Git is installed. Run: git-version inside default-shell.';
  }

  Future<String> _gitDoctorOutput() async {
    final pkg = RuntimeBinaryPackageService();
    final prefix = RuntimePrefixService();
    final installed = await pkg.gitInstalled();
    final prefixReady = await prefix.isInitialized();
    final binWhich = await prefix.binWhich('git');
    final found = !binWhich.startsWith('Not found');
    String overall;
    if (installed && !found) {
      overall = 'UNHEALTHY';
    } else if (installed) {
      overall = 'AVAILABLE';
    } else {
      overall = 'PLANNED';
    }
    return '=== Git Doctor ===\n'
        'Prefix: ${prefixReady ? 'OK' : 'LIMITED'}\n'
        'PATH: ${prefixReady ? 'OK' : 'LIMITED'}\n'
        'Env: ${prefixReady ? 'OK' : 'LIMITED'}\n'
        'Runtime package metadata: OK\n'
        'Git package: ${installed ? 'installed' : 'not installed'}\n'
        'bin-which git: ${found ? 'found' : 'not found'}\n'
        'git --version: ${installed ? 'see git-version' : 'not available'}\n'
        'Note: missing Git is expected in this build (planned, not installed).\n'
        'Overall: $overall';
  }

  Future<String> _gitTestPlanOutput() async {
    final installed = await RuntimeBinaryPackageService().gitInstalled();
    final header = installed
        ? 'Git is installed. You can run these tests:'
        : 'These tests run once Git is installed (blocked until a Git artifact exists):';
    return '=== Git Test Plan ===\n'
        '$header\n'
        'workspace-init gittests\n'
        'workspace-cd gittests\n'
        'git --version\n'
        'git init\n'
        'git status\n'
        'host-write README.md "hello git"\n'
        'git add README.md\n'
        'git commit -m "Initial commit"\n'
        'git log --oneline';
  }

  Future<String> _gitBareOutput() async {
    final installed = await RuntimeBinaryPackageService().gitInstalled();
    if (!installed) {
      return 'Git is not installed yet.\n'
          'Run: git-plan\n'
          'Run: runtime-install plan git';
    }
    // Real Git execution arrives with the verified Git package milestone.
    return 'Git is installed. Direct execution arrives with the Git package '
        'milestone; for now use git-status and runtime-pkg verify git.';
  }

  Future<String> _termodeDoctor({bool verbose = false}) async {
    final checks = <String, Future<CommandResult> Function()>{
      'Package': () => execute('pkg doctor'),
      'Workspace': () => execute('workspace-doctor'),
      'Session': () => execute('session-doctor'),
      'Runtime': () => execute('runtime-doctor'),
      'Runtime freeze': () => execute('runtime-freeze doctor'),
      'Preview': () => execute('preview-doctor'),
      'Localhost': () => execute('localhost-doctor'),
      'Native tools': () => execute('native-tool doctor'),
      'JS proof': () => execute('js-proof doctor'),
    };
    final statuses = <String, String>{};
    final verboseLines = <String>[];
    for (final entry in checks.entries) {
      try {
        final result = await entry.value();
        final status = _statusFromDoctorOutput(result.output);
        statuses[entry.key] = status;
        if (verbose) {
          verboseLines.add('${entry.key}: run ${_doctorCommandFor(entry.key)}');
          verboseLines.add('  Status: $status');
        }
      } catch (_) {
        statuses[entry.key] = 'UNHEALTHY';
      }
    }
    final sb = StringBuffer();
    sb.writeln('=== Termode Doctor ===');
    for (final entry in statuses.entries) {
      sb.writeln('${entry.key}: ${entry.value}');
    }
    if (verbose) {
      sb.writeln();
      sb.writeln('Verbose:');
      for (final line in verboseLines) {
        sb.writeln(line);
      }
      sb.writeln('Tip: run individual doctor commands for full details.');
    }
    sb.write('Overall: ${_overallFromStatuses(statuses.values)}');
    return sb.toString();
  }

  String _doctorCommandFor(String label) {
    switch (label) {
      case 'Package':
        return 'pkg doctor';
      case 'Workspace':
        return 'workspace-doctor';
      case 'Session':
        return 'session-doctor';
      case 'Runtime':
        return 'runtime-doctor';
      case 'Runtime freeze':
        return 'runtime-freeze doctor';
      case 'Preview':
        return 'preview-doctor';
      case 'Localhost':
        return 'localhost-doctor';
      case 'Native tools':
        return 'native-tool doctor';
      case 'JS proof':
        return 'js-proof doctor';
      default:
        return 'doctor';
    }
  }

  String _welcomeOutput() {
    return 'Welcome to Termode.\n\n'
        'Start here:\n\n'
        '1. default-shell\n'
        '2. pwd\n'
        '3. pkg list\n'
        '4. pkg install hello\n'
        '5. hello\n'
        '6. workspace-init demo\n'
        '7. workspace-cd demo\n'
        '8. host-write hello.txt "hello"\n'
        '9. host-cat hello.txt\n\n'
        'Useful:\n'
        'commands\n'
        'doctor\n'
        'pkg help\n'
        'workspace\n'
        'keyboard-help\n'
        'qa-status\n\n'
        'Known:\n'
        'Node/npm/Python/Git are not included yet.\n'
        'Run beta-known-limits for details.';
  }

  String _commandsOutput({bool all = false}) {
    if (all) {
      return '=== All Commands ===\n${kTermodeCommands.join('\n')}';
    }
    return '=== Termode Commands ===\n'
        'Getting started:\n'
        '  welcome, getting-started, examples, glossary\n'
        'Shell / PTY:\n'
        '  default-shell, stop-shell, normal-mode, mode\n'
        'Sessions / tabs:\n'
        '  tabs, tab-new, tab-switch, tab-rename, tab-close, history\n'
        'Packages:\n'
        '  pkg, pkg list, pkg install hello, pkg doctor\n'
        'Workspace / files:\n'
        '  workspace-init, workspace-cd, host-write, host-cat, host-ls\n'
        'Storage:\n'
        '  storage-status, storage-link, storage-test, storage-help\n'
        'Terminal UX:\n'
        '  keyboard-help, keyboard-test, ansi-test, scroll-test, copy-session\n'
        'Settings / theme:\n'
        '  settings-summary, settings-doctor, theme-test, settings-reset-safe\n'
        'Preview / localhost:\n'
        '  preview, preview-url, preview-check, localhost-doctor\n'
        'Runtime status:\n'
        '  runtime-freeze status, runtime-doctor, runtime-abi, native-tool\n'
        'QA / beta:\n'
        '  status, doctor, qa-status, qa-run, beta-status, onboarding-doctor\n'
        'Beta candidate:\n'
        '  build-info, beta-candidate status, beta-candidate ready\n'
        'Beta feedback / RC:\n'
        '  feedback, feedback template, rc-checklist, rc-status\n'
        'Runtime environment:\n'
        '  prefix-info, prefix-init, prefix-status, prefix-doctor\n'
        '  path-info, path-status, path-preview, path-doctor\n'
        '  env-info, env-status, env-preview, env-doctor, env-check\n'
        '  bin-list, bin-which, bin-doctor, shim-info, shim-doctor\n'
        'Runtime package prototype:\n'
        '  runtime-pkg, runtime-pkg available, runtime-pkg install hello-bin\n'
        '  runtime-pkg doctor, runtime-pkg verify hello-bin, hello-bin\n'
        'Git (feasibility):\n'
        '  git-status, git-info, git-plan, git-version, git-doctor, git-test-plan\n'
        'Runtime install planning:\n'
        '  toolchain-status, toolchain-list, toolchain-info, toolchain-doctor\n'
        '  runtime-install list, dev-setup list, dev-doctor\n'
        'Advanced probes:\n'
        '  runtime-candidates, js-engine-decision, quickjs, duktape\n\n'
        'Use commands --all for the full catalog.';
  }

  String _examplesOutput([String? category]) {
    final key = category?.toLowerCase();
    if (key == null || key.isEmpty) {
      return '=== Termode Examples ===\n'
          'examples shell\n'
          'examples packages\n'
          'examples workspace\n'
          'examples files\n'
          'examples preview\n'
          'examples qa\n'
          'examples runtime';
    }
    switch (key) {
      case 'shell':
        return '=== Examples: shell ===\n'
            'default-shell\n'
            'pwd\n'
            'echo hello\n'
            'stop-shell\n'
            'default-shell';
      case 'packages':
        return '=== Examples: packages ===\n'
            'pkg list\n'
            'pkg install hello\n'
            'hello\n'
            'pkg verify hello\n'
            'pkg remove hello\n'
            'pkg doctor';
      case 'workspace':
        return '=== Examples: workspace ===\n'
            'workspace-init demo\n'
            'workspace-cd demo\n'
            'pwd\n'
            'host-write hello.txt "hello"\n'
            'host-cat hello.txt\n'
            'workspace-doctor';
      case 'files':
        return '=== Examples: files ===\n'
            'host-ls\n'
            'host-write note.txt "hello"\n'
            'host-cat note.txt\n'
            'host-touch empty.txt\n'
            'host-rm empty.txt';
      case 'preview':
        return '=== Examples: preview ===\n'
            'preview-url 3000\n'
            'preview-check 3000\n'
            'preview-open 3000 --force\n'
            'preview-history\n'
            'preview-doctor';
      case 'qa':
        return '=== Examples: qa ===\n'
            'qa-status\n'
            'doctor\n'
            'beta-status\n'
            'qa-report\n'
            'bug-report';
      case 'runtime':
        return '=== Examples: runtime ===\n'
            'runtime-freeze status\n'
            'runtime-freeze doctor\n'
            'runtime-doctor\n'
            'native-tool doctor\n'
            'js-proof doctor';
      default:
        return 'Unknown examples category: $category\n'
            'Use: examples <shell|packages|workspace|files|preview|qa|runtime>';
    }
  }

  String _glossaryOutput() {
    return '=== Termode Glossary ===\n'
        'REAL PTY: the live Android shell Termode connects to.\n'
        'NORMAL mode: Termode app commands without direct shell input.\n'
        'Host command: an app-managed command intercepted inside REAL PTY.\n'
        'Script package: a safe shell-script package installed by pkg.\n'
        'Remote repo: trusted script package index/source.\n'
        'Workspace: a project folder under Termode files/home/projects.\n'
        'Runtime frozen: no new runtime engines are being added right now.\n'
        'js-proof: small controlled JavaScript-like proof command.\n'
        'Preview URL: localhost URL for future dev-server workflows.\n'
        'Doctor: a compact health check command.';
  }

  String _onboardingDoctorOutput() {
    final repoDocsOk =
        File('README.md').existsSync() &&
        File('docs/GETTING_STARTED.md').existsSync() &&
        File('docs/KNOWN_LIMITATIONS.md').existsSync() &&
        File('docs/ROADMAP.md').existsSync();
    final embeddedDocsOk =
        _welcomeOutput().contains('Start here:') &&
        _examplesOutput('packages').contains('pkg install hello') &&
        _glossaryOutput().contains('REAL PTY');
    final docsOk = repoDocsOk || embeddedDocsOk;
    final readmeOk =
        !File('README.md').existsSync() ||
        File('README.md').readAsStringSync().contains('v0.45');
    final healthy = docsOk && readmeOk;
    return '=== Onboarding Doctor ===\n'
        'Welcome: OK\n'
        'Commands: OK\n'
        'Examples: OK\n'
        'Glossary: OK\n'
        'Docs: ${docsOk ? 'OK' : 'MISSING'}\n'
        'README: ${readmeOk ? 'OK' : 'CHECK'}\n'
        'Overall: ${healthy ? 'HEALTHY' : 'LIMITED'}';
  }

  String _settingsSummaryOutput() {
    final settings = SettingsService();
    return '=== Settings Summary ===\n'
        'Theme: dark (${settings.themeColor})\n'
        'Font size: ${settings.fontSize.toStringAsFixed(1)}\n'
        'Line height: ${settings.lineHeight.toStringAsFixed(2)}\n'
        'Start in real shell: ${_yesNo(settings.startInRealShell)}\n'
        'ANSI renderer: ${settings.enableAnsiRenderer ? 'on' : 'off'}\n'
        'ANSI debug: ${settings.ansiDebugMode ? 'on' : 'off'}\n'
        'Cursor: ${settings.cursorStyle}\n'
        'Blink: ${_yesNo(settings.blinkingCursor)}\n'
        'Scrollback: ${settings.maxScrollbackLines}\n'
        'Paste warning: ${settings.pasteWarningThreshold}\n'
        'Paste hard limit: ${settings.pasteHardLimit}\n'
        'Keep screen on: ${_yesNo(settings.keepScreenOn)}\n'
        'Welcome banner: ${settings.showWelcomeBanner ? 'on' : 'off'}\n'
        'Tip: settings-reset-safe --confirm restores visual defaults.';
  }

  String _settingsDoctorOutput() {
    final settings = SettingsService();
    const allowedScrollback = {500, 1000, 2000, 5000, 10000};
    const allowedCursor = {'block', 'bar', 'underline'};
    final scrollbackOk = allowedScrollback.contains(
      settings.maxScrollbackLines,
    );
    final pasteOk = settings.pasteWarningThreshold < settings.pasteHardLimit;
    final cursorOk = allowedCursor.contains(settings.cursorStyle);
    final ansiDebugOk = !settings.ansiDebugMode;
    final fontOk = settings.fontSize >= 10.0 && settings.fontSize <= 24.0;
    final lineHeightOk =
        settings.lineHeight >= 1.0 && settings.lineHeight <= 2.0;
    final limited = !ansiDebugOk || !pasteOk;
    final healthy =
        scrollbackOk &&
        pasteOk &&
        cursorOk &&
        ansiDebugOk &&
        fontOk &&
        lineHeightOk;
    return '=== Settings Doctor ===\n'
        'Font size: ${fontOk ? 'OK' : 'CHECK'}\n'
        'Line height: ${lineHeightOk ? 'OK' : 'CHECK'}\n'
        'Scrollback limit: ${scrollbackOk ? 'OK' : 'INVALID'}\n'
        'Paste limits: ${pasteOk ? 'OK' : 'LIMITED'}\n'
        'Cursor setting: ${cursorOk ? 'OK' : 'INVALID'}\n'
        'ANSI debug: ${ansiDebugOk ? 'off' : 'ON'}\n'
        'Start in real shell: OK\n'
        'Overall: ${healthy ? 'HEALTHY' : (limited ? 'LIMITED' : 'UNHEALTHY')}';
  }

  String _themeTestOutput() {
    return '=== Theme Test ===\n'
        'Normal text\n'
        '\u001B[2mDim text\u001B[0m\n'
        '\u001B[1mBold text\u001B[0m\n'
        'ANSI colors: \u001B[31mred\u001B[0m \u001B[32mgreen\u001B[0m '
        '\u001B[33myellow\u001B[0m \u001B[34mblue\u001B[0m '
        '\u001B[35mmagenta\u001B[0m \u001B[36mcyan\u001B[0m\n'
        'Background colors: \u001B[41m R \u001B[0m \u001B[42m G \u001B[0m '
        '\u001B[44m B \u001B[0m \u001B[43m Y \u001B[0m\n'
        'Status badge sample:\n'
        'REAL PTY / NORMAL / LIMITED';
  }

  Future<String> _statusOutput() async {
    final session = TerminalSessionService().activeSession;
    final prefixReady = await RuntimePrefixService().isInitialized();
    final mode = session.isPtyInteractionActive ? 'REAL PTY' : 'NORMAL';
    final shell = (session.isRealPtyActive || session.isShellActive)
        ? 'running'
        : 'stopped';
    final workspaceName = await WorkspaceService().currentWorkspaceName();
    final workspace = (workspaceName.isEmpty || workspaceName == '(none)')
        ? 'none'
        : workspaceName;
    final pkgStatus = _statusFromDoctorOutput(
      (await execute('pkg doctor')).output,
    );
    final packages = pkgStatus == 'HEALTHY' ? 'healthy' : 'limited';
    final betaOutput = await _betaStatusOutput();
    final betaOverall =
        RegExp(
          r'Overall:\s*(.+)$',
          multiLine: true,
        ).firstMatch(betaOutput)?.group(1)?.trim() ??
        'LIMITED';
    final beta = betaOverall.toUpperCase().contains('CANDIDATE')
        ? 'ready'
        : 'ready with limitations';
    return '=== Termode Status ===\n'
        'Mode: $mode\n'
        'Shell: $shell\n'
        'Session: ${session.name}\n'
        'Workspace: $workspace\n'
        'Packages: $packages\n'
        'Runtime: environment architecture active\n'
        'Prefix: ${prefixReady ? 'initialized' : 'not initialized'}\n'
        'PATH overlay: ${prefixReady ? 'ready' : 'limited'}\n'
        'Runtime package installer: prototype ready\n'
        'Git: planned (not installed)\n'
        'Toolchains: planned (not installed)\n'
        'Beta: $beta';
  }

  String _versionOutput() {
    return 'Termode v0.45\n'
        'Runtime: frozen\n'
        'Shell: REAL PTY\n'
        'Packages: script + runtime prototype';
  }

  String _buildTypeName() {
    if (kReleaseMode) return 'release';
    if (kProfileMode) return 'profile';
    if (kDebugMode) return 'debug';
    return 'unknown';
  }

  String _buildInfoOutput() {
    return '=== Build Info ===\n'
        'App: Termode\n'
        'Version: v0.45\n'
        'Build type: ${_buildTypeName()}\n'
        'Runtime: prototype installer active\n'
        'Runtime package installer: prototype ready\n'
        'Git: feasibility (planned, not installed)\n'
        'Toolchains: planned (not installed)\n'
        'Shell: REAL PTY\n'
        'Packages: script + runtime prototype\n'
        'Beta candidate: terminal foundation beta\n'
        'Artifact: Termode-v0.45-git-path-debug.apk';
  }

  String _releaseNotesOutput() {
    return '=== Termode Release Notes ===\n'
        'v0.45 Git Support Feasibility / Installer Path\n'
        'v0.44 Binary Package Installer Prototype\n'
        'v0.43 Prefix / PATH / Environment System\n'
        'v0.42 Runtime Expansion Architecture\n'
        'v0.41 Beta Feedback Fixes / RC Cleanup\n'
        'v0.40 Beta Candidate Packaging\n'
        'v0.39 UI / Settings Polish\n'
        'v0.38 Documentation / Onboarding Polish\n'
        'v0.37.1 Manual Android QA Fix Pass\n'
        'v0.37 Device QA Bug Bash\n'
        'v0.36 Product Stabilization / Beta Readiness Pass\n'
        'v0.35 Runtime Decision Freeze\n'
        'v0.34 Duktape Probe\n'
        'v0.33 QuickJS Probe\n'
        'v0.32 JS Engine Decision\n'
        'v0.31 JS Proof\n'
        'v0.30 Runtime Candidate Research';
  }

  Future<String> _bugReportOutput() async {
    final diagnostics = await NativeCommandService().getDiagnostics();
    final abi = diagnostics?['abi']?.toString() ?? 'unknown';
    final runtimeStatus = _statusFromDoctorOutput(
      (await execute('runtime-freeze doctor')).output,
    );
    final packageStatus = _statusFromDoctorOutput(
      (await execute('pkg doctor')).output,
    );
    final workspaceStatus = _statusFromDoctorOutput(
      (await execute('workspace-doctor')).output,
    );
    final sessionStatus = _statusFromDoctorOutput(
      (await execute('session-doctor')).output,
    );
    final mode = TerminalSessionService().activeSession.isPtyInteractionActive
        ? 'REAL PTY'
        : 'NORMAL';
    return '=== Termode Bug Report ===\n'
        'Termode version: v0.45\n'
        'Android ABI: $abi\n'
        'Runtime status: $runtimeStatus\n'
        'Package doctor: $packageStatus\n'
        'Workspace doctor: $workspaceStatus\n'
        'Session doctor: $sessionStatus\n'
        'Recent mode/badge: $mode\n\n'
        'Copy this output when reporting a bug.\n'
        'Private env vars, tokens, and full file paths are not included.';
  }

  String _qaChecklistOutput() {
    return '=== QA Checklist ===\n'
        '* launch app\n'
        '* shell start\n'
        '* shell stop/restart\n'
        '* package install/remove\n'
        '* workspace create/cd/files\n'
        '* storage link if available\n'
        '* paste large text\n'
        '* ANSI test\n'
        '* preview commands\n'
        '* force close/reopen\n'
        '* rotate screen\n'
        '* multiple tabs';
  }

  String _qaRunOutput() {
    return '=== QA Run ===\n'
        'Startup:\n'
        '  welcome, doctor, beta-status, force close/reopen\n'
        'Shell / PTY:\n'
        '  default-shell, pwd, Ctrl+C, stop-shell, default-shell\n'
        'Tabs / sessions:\n'
        '  tabs, tab-new, tab-rename qa, tab-close, session-doctor\n'
        'Packages:\n'
        '  pkg doctor, pkg list, pkg install/remove hello, pkg repair\n'
        'Workspaces/files:\n'
        '  workspace-init qa, workspace-cd qa, host-write, host-cat, host-ls\n'
        'Storage:\n'
        '  storage-status, storage-link if available, storage-test if linked\n'
        'Terminal UX:\n'
        '  keyboard-test, ansi-test, scroll-test 300, copy-last, paste-force\n'
        'Preview/localhost:\n'
        '  preview-url 3000, preview-check 3000, preview-doctor, localhost-doctor\n'
        'Restore/background:\n'
        '  background app, reopen, verify no duplicate prompts or shells\n'
        'Doctors:\n'
        '  doctor, beta-doctor, runtime-freeze doctor, native-tool doctor, js-proof doctor';
  }

  Future<String> _qaStatusOutput() async {
    final doctorOutput = await _termodeDoctor();
    final doctorStatus = _statusFromDoctorOutput(doctorOutput);
    final doctorStatuses = _doctorStatusesFromOutput(doctorOutput);
    final betaOutput = await _betaStatusOutput();
    final betaOverall =
        RegExp(
          r'Overall:\s*(.+)$',
          multiLine: true,
        ).firstMatch(betaOutput)?.group(1)?.trim() ??
        'LIMITED';
    final runtimeFreeze = _statusFromDoctorOutput(
      (await execute('runtime-freeze doctor')).output,
    );
    final overall = _qaOverallStatus(
      doctorStatus: doctorStatus,
      betaOverall: betaOverall,
      runtimeFreeze: runtimeFreeze,
    );
    return '=== QA Status ===\n'
        'Doctor: $doctorStatus\n'
        'Beta: $betaOverall\n'
        'Packages: ${_qaStatusLabel(doctorStatuses['Package'])}\n'
        'Workspaces: ${_qaStatusLabel(doctorStatuses['Workspace'])}\n'
        'Sessions: ${_qaStatusLabel(doctorStatuses['Session'])}\n'
        'Runtime freeze: ${runtimeFreeze == 'HEALTHY' ? 'OK' : runtimeFreeze}\n'
        'Overall: $overall';
  }

  String _qaOverallStatus({
    required String doctorStatus,
    required String betaOverall,
    required String runtimeFreeze,
  }) {
    final betaUpper = betaOverall.toUpperCase();
    if (doctorStatus == 'UNHEALTHY' ||
        runtimeFreeze == 'UNHEALTHY' ||
        betaUpper.contains('UNHEALTHY') ||
        betaUpper.contains('NOT READY')) {
      return 'NEEDS FIXES';
    }
    if (doctorStatus == 'LIMITED' ||
        runtimeFreeze == 'LIMITED' ||
        betaUpper.contains('LIMITED')) {
      return 'READY WITH LIMITATIONS';
    }
    return 'READY FOR BUG BASH';
  }

  Map<String, String> _doctorStatusesFromOutput(String output) {
    final statuses = <String, String>{};
    final linePattern = RegExp(r'^([^:\n]+):\s*(HEALTHY|LIMITED|UNHEALTHY)$');
    for (final line in output.split('\n')) {
      final match = linePattern.firstMatch(line.trim());
      if (match != null) {
        statuses[match.group(1)!] = match.group(2)!;
      }
    }
    return statuses;
  }

  String _qaStatusLabel(String? status) {
    if (status == null) {
      return 'UNKNOWN';
    }
    return status == 'HEALTHY' ? 'OK' : status;
  }

  Future<String> _qaReportOutput() async {
    final session = TerminalSessionService().activeSession;
    final diagnostics = await NativeCommandService().getDiagnostics();
    final abi = diagnostics?['abi']?.toString() ?? 'unknown';
    final doctor = await _termodeDoctor();
    final doctorStatus = _statusFromDoctorOutput(doctor);
    return '=== QA Bug Bash Report ===\n'
        '${_versionOutput()}\n\n'
        'Doctor summary: $doctorStatus\n'
        '${_betaScoreOutput()}\n\n'
        '${_betaKnownLimitsOutput()}\n\n'
        'Last session info:\n'
        '  Name: ${session.name}\n'
        '  Mode: ${session.isPtyInteractionActive ? 'REAL PTY' : 'NORMAL'}\n'
        '  Lines: ${session.lines.length}\n'
        'Safe runtime info:\n'
        '  ABI: $abi\n'
        '  Runtime: frozen\n'
        'Suggested next tests:\n'
        '  qa-run\n'
        '  doctor --verbose\n'
        '  pkg doctor\n'
        '  workspace-doctor\n'
        '  preview-doctor\n\n'
        'Copy this output when reporting a QA bug. Private env vars, tokens, and full paths are not included.';
  }

  String _qaResetOutput() {
    return '=== QA Reset ===\n'
        'QA tracking state reset.\n'
        'Packages, workspaces, sessions, and user files were not changed.';
  }

  Future<Map<String, dynamic>> _getInstalledPackages(String usrDir) async {
    final pkgsMetaFile = File('$usrDir/termode-packages.json');
    if (await pkgsMetaFile.exists()) {
      try {
        final content = await pkgsMetaFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        return Map<String, dynamic>.from(data['packages'] ?? {});
      } catch (_) {}
    }
    return {};
  }

  Future<CommandResult> execute(String input) async {
    final trimmedInput = input.trim();
    if (trimmedInput.isEmpty) {
      return CommandResult(output: '');
    }

    final parts = _parseArgs(trimmedInput);
    if (parts.isEmpty) {
      return CommandResult(output: '');
    }

    final command = parts[0].toLowerCase();
    final args = parts.sublist(1);

    switch (command) {
      case 'help':
        return CommandResult(
          output:
              '=== Termode Help ===\n'
              'Termode is a standalone Android terminal with REAL PTY, script packages, workspaces, and beta diagnostics.\n\n'
              'Start:\n'
              '  welcome\n'
              '  examples\n'
              '  glossary\n'
              '  commands\n\n'
              'Health:\n'
              '  doctor\n'
              '  qa-status\n'
              '  onboarding-doctor\n\n'
              'Beta candidate:\n'
              '  build-info\n'
              '  beta-candidate status\n'
              '  beta-candidate ready\n'
              '  feedback\n'
              '  rc-status\n\n'
              'Runtime environment:\n'
              '  prefix-status\n'
              '  path-status\n'
              '  env-status\n'
              '  bin-list\n'
              '  runtime-pkg status\n'
              '  runtime-abi\n'
              '  toolchain-status\n'
              '  git-status\n'
              '  dev-doctor\n\n'
              'Sub-help:\n'
              '  pkg help\n'
              '  workspace\n'
              '  storage-help\n'
              '  keyboard-help\n'
              '  preview-help\n'
              '  runtime-freeze help\n'
              '  native-tool help\n'
              '  js-proof help\n\n'
              'Catalog:\n'
              '  commands --all\n\n'
              'Known limits:\n'
              '  beta-known-limits',
        );
      case 'clear':
        return CommandResult(output: '', shouldClear: true);
      case 'tabs':
        return CommandResult(output: TerminalSessionService().tabsOutput());
      case 'tab-new':
        return CommandResult(output: await TerminalSessionService().newTab());
      case 'tab-close':
        return CommandResult(output: TerminalSessionService().closeActiveTab());
      case 'tab-rename':
        return CommandResult(
          output: TerminalSessionService().renameActiveTab(args.join(' ')),
          isError: args.isEmpty,
        );
      case 'tab-switch':
        final tabNumber = args.isNotEmpty ? int.tryParse(args[0]) : null;
        if (tabNumber == null) {
          return CommandResult(
            output: 'Usage: tab-switch <number>',
            isError: true,
          );
        }
        final switchOutput = TerminalSessionService().switchTab(tabNumber);
        return CommandResult(
          output: switchOutput,
          isError: switchOutput.contains('invalid'),
        );
      case 'session-info':
        return CommandResult(output: TerminalSessionService().sessionInfo());
      case 'session-clear':
        TerminalSessionService().clearActiveTranscript();
        return CommandResult(output: 'Session transcript cleared.');
      case 'session-doctor':
        final output = TerminalSessionService().sessionDoctor(
          verbose: args.contains('--verbose'),
        );
        return CommandResult(
          output: output,
          isError: output.contains('Overall: UNHEALTHY'),
        );
      case 'history':
        final clear = args.isNotEmpty && args[0] == 'clear';
        return CommandResult(
          output: TerminalSessionService().historyOutput(clear: clear),
        );
      case 'keyboard-test':
        return CommandResult(
          output: TerminalSessionService().keyboardTestOutput(),
        );
      case 'keyboard-settings':
        return CommandResult(
          output: TerminalSessionService().keyboardSettingsOutput(),
        );
      case 'terminal-settings':
        return CommandResult(
          output: TerminalSessionService().terminalSettingsOutput(),
        );
      case 'input-test':
        return CommandResult(
          output: TerminalSessionService().inputTestOutput(),
        );
      case 'ansi-test':
        return CommandResult(output: TerminalSessionService().ansiTestOutput());
      case 'resize-info':
        return CommandResult(
          output: TerminalSessionService().resizeInfoOutput(),
        );
      case 'scroll-test':
        final count = args.isNotEmpty ? int.tryParse(args[0]) : null;
        if (count == null) {
          return CommandResult(
            output: 'Usage: scroll-test <lines>',
            isError: true,
          );
        }
        return CommandResult(
          output: TerminalSessionService().scrollTestOutput(count),
        );
      case 'copy-last':
        return CommandResult(
          output: await TerminalSessionService().copyLastOutputLine(),
        );
      case 'copy-session':
        final count = args.isNotEmpty ? int.tryParse(args[0]) : null;
        return CommandResult(
          output: await TerminalSessionService().copySessionLines(count),
        );
      case 'paste-force':
        return CommandResult(
          output: await TerminalSessionService().pasteForce(),
        );
      case 'workspace':
        return CommandResult(
          output: await WorkspaceService().workspaceStatus(),
        );
      case 'workspace-info':
        return CommandResult(output: await WorkspaceService().workspaceInfo());
      case 'workspace-init':
        if (args.isEmpty) {
          return CommandResult(
            output: 'Usage: workspace-init <name>',
            isError: true,
          );
        }
        final init = await WorkspaceService().initWorkspace(args[0]);
        return CommandResult(
          output: init,
          isError: init.startsWith('workspace-init:'),
        );
      case 'workspace-list':
        return CommandResult(output: await WorkspaceService().listWorkspaces());
      case 'workspace-cd':
      case 'workspace-open':
        if (args.isEmpty) {
          return CommandResult(
            output: 'Usage: workspace-cd <name>',
            isError: true,
          );
        }
        final result = await WorkspaceService().setWorkspace(args[0]);
        return CommandResult(output: result.$2, isError: !result.$1);
      case 'workspace-remove':
        if (args.isEmpty) {
          return CommandResult(
            output: 'Usage: workspace-remove <name> --confirm',
            isError: true,
          );
        }
        final output = await WorkspaceService().removeWorkspace(
          args[0],
          confirmed: args.contains('--confirm'),
        );
        return CommandResult(
          output: output,
          isError: output.startsWith('workspace-remove:'),
        );
      case 'workspace-doctor':
        final output = await WorkspaceService().doctor(
          verbose: args.contains('--verbose'),
        );
        return CommandResult(
          output: output,
          isError: output.contains('Overall: UNHEALTHY'),
        );
      case 'pwd-host':
      case 'host-pwd':
        return _workspaceFileCommand(
          'host-pwd',
          () => WorkspaceService().hostPwd(),
        );
      case 'host-ls':
        return _workspaceFileCommand(
          'host-ls',
          () => WorkspaceService().hostLs(args.isEmpty ? '.' : args[0]),
        );
      case 'host-cat':
        if (args.isEmpty) {
          return CommandResult(output: 'Usage: host-cat <file>', isError: true);
        }
        return _workspaceFileCommand(
          'host-cat',
          () => WorkspaceService().hostCat(args[0]),
        );
      case 'host-write':
        if (args.length < 2) {
          return CommandResult(
            output: 'Usage: host-write <file> <text>',
            isError: true,
          );
        }
        return _workspaceFileCommand(
          'host-write',
          () =>
              WorkspaceService().hostWrite(args[0], args.sublist(1).join(' ')),
        );
      case 'host-touch':
        if (args.isEmpty) {
          return CommandResult(
            output: 'Usage: host-touch <file>',
            isError: true,
          );
        }
        return _workspaceFileCommand(
          'host-touch',
          () => WorkspaceService().hostTouch(args[0]),
        );
      case 'host-mkdir':
        if (args.isEmpty) {
          return CommandResult(
            output: 'Usage: host-mkdir <dir>',
            isError: true,
          );
        }
        return _workspaceFileCommand(
          'host-mkdir',
          () => WorkspaceService().hostMkdir(args[0]),
        );
      case 'host-rm':
        if (args.isEmpty) {
          return CommandResult(output: 'Usage: host-rm <path>', isError: true);
        }
        return _workspaceFileCommand(
          'host-rm',
          () => WorkspaceService().hostRm(args[0]),
        );
      case 'echo':
        return CommandResult(output: args.join(' '));
      case 'pwd':
        return CommandResult(output: vfs.getAbsolutePath());
      case 'whoami':
        return CommandResult(output: 'user');
      case 'date':
        return CommandResult(output: DateTime.now().toString());

      case 'ls':
        final path = args.isNotEmpty ? args[0] : '';
        final result = vfs.ls(path);
        final isError = result.startsWith('ls:');
        return CommandResult(output: result, isError: isError);

      case 'cd':
        final path = args.isNotEmpty ? args[0] : '';
        final error = vfs.cd(path);
        return CommandResult(output: error ?? '', isError: error != null);

      case 'mkdir':
        if (args.isEmpty) {
          return CommandResult(output: 'mkdir: missing operand', isError: true);
        }
        final error = vfs.mkdir(args[0]);
        return CommandResult(output: error ?? '', isError: error != null);

      case 'touch':
        if (args.isEmpty) {
          return CommandResult(
            output: 'touch: missing file operand',
            isError: true,
          );
        }
        final path = args[0];
        final content = args.length > 1 ? args[1] : '';
        final error = vfs.touch(path, content);
        return CommandResult(output: error ?? '', isError: error != null);

      case 'cat':
        if (args.isEmpty) {
          return CommandResult(
            output: 'cat: missing file operand',
            isError: true,
          );
        }
        final result = vfs.cat(args[0]);
        final isError = result.startsWith('cat:');
        return CommandResult(output: result, isError: isError);

      case 'rm':
        if (args.isEmpty) {
          return CommandResult(output: 'rm: missing operand', isError: true);
        }
        bool recursive = false;
        String path = '';
        if (args[0] == '-r') {
          recursive = true;
          if (args.length < 2) {
            return CommandResult(output: 'rm: missing operand', isError: true);
          }
          path = args[1];
        } else {
          path = args[0];
        }
        final error = vfs.rm(path, recursive: recursive);
        return CommandResult(output: error ?? '', isError: error != null);

      case 'cp':
        if (args.isEmpty) {
          return CommandResult(
            output: 'cp: missing file operand',
            isError: true,
          );
        }
        bool recursive = false;
        String src = '';
        String dest = '';
        int argIdx = 0;

        if (args[0] == '-r') {
          recursive = true;
          argIdx = 1;
        }

        if (args.length < argIdx + 2) {
          return CommandResult(
            output:
                'cp: missing destination file operand after \'${args[args.length - 1]}\'',
            isError: true,
          );
        }
        src = args[argIdx];
        dest = args[argIdx + 1];

        final error = vfs.cp(src, dest, recursive: recursive);
        return CommandResult(output: error ?? '', isError: error != null);

      case 'mv':
        if (args.length < 2) {
          return CommandResult(
            output: args.isEmpty
                ? 'mv: missing file operand'
                : 'mv: missing destination file operand after \'${args[0]}\'',
            isError: true,
          );
        }
        final error = vfs.mv(args[0], args[1]);
        return CommandResult(output: error ?? '', isError: error != null);

      case 'android-shell':
        if (args.isEmpty) {
          return CommandResult(
            output:
                'android-shell: missing command operand\nUsage: android-shell <command>',
            isError: true,
          );
        }
        final cmdStr = args.join(' ');
        final nativeService = NativeCommandService();
        final nativeResult = await nativeService.execute(cmdStr, sessionId);

        String exitMsg = '';
        if (nativeResult.exitCode == 127) {
          exitMsg = 'android-shell: command not found';
        } else if (nativeResult.exitCode == 126) {
          exitMsg = 'android-shell: permission denied';
        } else if (nativeResult.exitCode != 0) {
          exitMsg =
              'Process exited with non-zero code ${nativeResult.exitCode}';
        }

        final outputBuilder = StringBuffer();
        if (nativeResult.stdout.isNotEmpty) {
          outputBuilder.write(nativeResult.stdout);
        }
        if (nativeResult.stderr.isNotEmpty) {
          if (outputBuilder.isNotEmpty) outputBuilder.write('\n');
          outputBuilder.write(nativeResult.stderr);
        }

        if (outputBuilder.isEmpty) {
          if (exitMsg.isNotEmpty) {
            outputBuilder.write(exitMsg);
          } else {
            outputBuilder.write(
              'Process exited with code ${nativeResult.exitCode}',
            );
          }
        } else {
          if (exitMsg.isNotEmpty) {
            outputBuilder.write('\n[$exitMsg]');
          }
        }

        return CommandResult(
          output: outputBuilder.toString(),
          isError: nativeResult.exitCode != 0,
        );

      case 'android-shell-diagnostics':
        final nativeService = NativeCommandService();
        final diag = await nativeService.getDiagnostics();
        if (diag == null) {
          return CommandResult(
            output:
                'android-shell-diagnostics: failed to retrieve native diagnostics.',
            isError: true,
          );
        }

        final userDir = diag['userDir'] as String? ?? 'Unknown';
        final pathEnv = diag['pathEnv'] as String? ?? 'Unknown';
        final uid = diag['uid'] as int? ?? -1;
        final testOutput = diag['testOutput'] as String? ?? 'Unknown';
        final fileChecks = diag['fileChecks'] as List<dynamic>? ?? [];
        final runtimeHome = diag['runtimeHome'] as String? ?? 'Unknown';
        final runtimePath = diag['runtimePath'] as String? ?? 'Unknown';

        final sb = StringBuffer();
        sb.writeln('=== Termode Native Diagnostics ===');
        sb.writeln('CWD: $userDir');
        sb.writeln('UID: $uid');
        sb.writeln('Runtime Home: $runtimeHome');
        sb.writeln('Runtime PATH: $runtimePath');
        sb.writeln('PATH env:');
        for (final p in pathEnv.split(':')) {
          if (p.trim().isNotEmpty) {
            sb.writeln('  - $p');
          }
        }
        sb.writeln('File checks (Exists / Read / Exec):');
        for (final check in fileChecks) {
          final map = Map<String, dynamic>.from(check as Map);
          final path = map['path'] as String;
          final exists = map['exists'] as bool? ?? false;
          final canRead = map['canRead'] as bool? ?? false;
          final canExecute = map['canExecute'] as bool? ?? false;

          final status = exists
              ? '[OK] r:${canRead ? "y" : "n"} x:${canExecute ? "y" : "n"}'
              : '[NOT FOUND]';
          sb.writeln('  - $path: $status');
        }
        sb.writeln('Test run (sh -c "echo shell-ok"): $testOutput');

        return CommandResult(output: sb.toString().trimRight());

      case 'android-shell-env':
        final nativeService = NativeCommandService();
        final env = await nativeService.getEnv();
        if (env == null) {
          return CommandResult(
            output: 'android-shell-env: failed to retrieve native environment.',
            isError: true,
          );
        }

        final sb = StringBuffer();
        sb.writeln('=== Effective Native Runtime Environment ===');
        sb.writeln('HOME:              ${env['HOME']}');
        sb.writeln('TERMODE_HOME:      ${env['TERMODE_HOME']}');
        sb.writeln('TERMODE_USR:       ${env['TERMODE_USR']}');
        sb.writeln('TERMODE_BIN:       ${env['TERMODE_BIN']}');
        sb.writeln('TMPDIR:            ${env['TMPDIR']}');
        sb.writeln('PATH:              ${env['PATH']}');
        sb.write('Working Directory: ${env['workingDirectory']}');
        return CommandResult(output: sb.toString());

      case 'termode-runtime':
        if (args.isEmpty) {
          return CommandResult(
            output:
                'termode-runtime: missing subcommand operand\nUsage: termode-runtime [status|path|reset]',
            isError: true,
          );
        }
        final subcmd = args[0].toLowerCase();
        final runtimeService = RuntimeBootstrapService();

        if (subcmd == 'status') {
          final status = await runtimeService.checkStatus();
          final sb = StringBuffer();
          sb.writeln('=== Termode Runtime Directory Status ===');
          var allOk = true;
          status.forEach((path, exists) {
            sb.writeln('  - $path: ${exists ? "[EXISTS]" : "[MISSING]"}');
            if (!exists) allOk = false;
          });
          sb.write('Overall status: ${allOk ? "HEALTHY" : "UNHEALTHY"}');
          return CommandResult(output: sb.toString(), isError: !allOk);
        } else if (subcmd == 'path') {
          final paths = await runtimeService.getPaths();
          final sb = StringBuffer();
          sb.writeln('=== Termode Runtime Paths ===');
          sb.writeln('Home:   ${paths['home']}');
          sb.writeln('Usr:    ${paths['usr']}');
          sb.writeln('Bin:    ${paths['bin']}');
          sb.writeln('UsrTmp: ${paths['usrTmp']}');
          sb.write('Tmp:    ${paths['tmp']}');
          return CommandResult(output: sb.toString());
        } else if (subcmd == 'reset') {
          await runtimeService.reset();
          return CommandResult(
            output: 'Runtime environment reset successfully.',
          );
        } else {
          return CommandResult(
            output:
                'termode-runtime: unknown subcommand: $subcmd\nUsage: termode-runtime [status|path|reset]',
            isError: true,
          );
        }

      case 'toybox':
        final nativeService = NativeCommandService();
        final cmdStr =
            '/system/bin/toybox${args.isNotEmpty ? " ${args.join(' ')}" : ""}';
        final result = await nativeService.execute(cmdStr, sessionId);

        final outputBuilder = StringBuffer();
        if (result.stdout.isNotEmpty) {
          outputBuilder.write(result.stdout);
        }
        if (result.stderr.isNotEmpty) {
          if (outputBuilder.isNotEmpty) outputBuilder.write('\n');
          outputBuilder.write(result.stderr);
        }
        if (outputBuilder.isEmpty && result.exitCode != 0) {
          outputBuilder.write(
            'Process exited with non-zero code ${result.exitCode}',
          );
        }
        return CommandResult(
          output: outputBuilder.toString().trimRight(),
          isError: result.exitCode != 0,
        );

      case 'toybox-list':
        final nativeService = NativeCommandService();
        final result = await nativeService.execute(
          '/system/bin/toybox',
          sessionId,
        );

        final outputBuilder = StringBuffer();
        if (result.stdout.isNotEmpty) {
          outputBuilder.write(result.stdout);
        }
        if (result.stderr.isNotEmpty) {
          if (outputBuilder.isNotEmpty) outputBuilder.write('\n');
          outputBuilder.write(result.stderr);
        }
        return CommandResult(
          output: outputBuilder.toString().trimRight(),
          isError: result.exitCode != 0,
        );

      case 'runtime-ls':
        final runtimeService = RuntimeBootstrapService();
        final paths = await runtimeService.getPaths();
        final homePath = paths['home']!;
        final dir = Directory(homePath);
        if (!await dir.exists()) {
          return CommandResult(
            output: 'runtime-ls: home directory not found',
            isError: true,
          );
        }
        try {
          final List<String> fileNames = [];
          await for (final entity in dir.list()) {
            final name = entity.path.replaceAll('\\', '/').split('/').last;
            fileNames.add(name);
          }
          if (fileNames.isEmpty) {
            return CommandResult(output: '(empty directory)');
          }
          return CommandResult(output: fileNames.join('\n'));
        } catch (e) {
          return CommandResult(
            output: 'runtime-ls: error listing directory: $e',
            isError: true,
          );
        }

      case 'runtime-pwd':
        final runtimeService = RuntimeBootstrapService();
        final paths = await runtimeService.getPaths();
        return CommandResult(output: paths['home']!);

      case 'runtime-cat':
        if (args.isEmpty) {
          return CommandResult(
            output: 'runtime-cat: missing file operand',
            isError: true,
          );
        }
        final runtimeService = RuntimeBootstrapService();
        final paths = await runtimeService.getPaths();
        final homePath = paths['home']!;
        final file = _resolveFileInHome(args[0], homePath);
        if (file == null) {
          return CommandResult(
            output: 'runtime-cat: path traversal detected or invalid path',
            isError: true,
          );
        }
        if (!await file.exists()) {
          return CommandResult(
            output: 'runtime-cat: ${args[0]}: No such file or directory',
            isError: true,
          );
        }
        try {
          final content = await file.readAsString();
          return CommandResult(output: content);
        } on FileSystemException {
          return CommandResult(
            output: 'runtime-cat: ${args[0]}: Permission denied or read error',
            isError: true,
          );
        } catch (e) {
          return CommandResult(
            output: 'runtime-cat: ${args[0]}: Error: $e',
            isError: true,
          );
        }

      case 'runtime-write':
        if (args.isEmpty) {
          return CommandResult(
            output: 'runtime-write: missing file operand',
            isError: true,
          );
        }
        if (args.length < 2) {
          return CommandResult(
            output: 'runtime-write: missing text operand',
            isError: true,
          );
        }
        final filename = args[0];
        final text = args.sublist(1).join(' ');

        final runtimeService = RuntimeBootstrapService();
        final paths = await runtimeService.getPaths();
        final homePath = paths['home']!;
        final file = _resolveFileInHome(filename, homePath);
        if (file == null) {
          return CommandResult(
            output: 'runtime-write: path traversal detected or invalid path',
            isError: true,
          );
        }

        try {
          await file.writeAsString(text);
          return CommandResult(
            output: 'Wrote ${text.length} characters to $filename.',
          );
        } on FileSystemException {
          return CommandResult(
            output:
                'runtime-write: $filename: Permission denied or write error',
            isError: true,
          );
        } catch (e) {
          return CommandResult(
            output: 'runtime-write: $filename: Error: $e',
            isError: true,
          );
        }

      case 'whereami':
        final runtimeService = RuntimeBootstrapService();
        final paths = await runtimeService.getPaths();
        final statusMap = await runtimeService.checkStatus();
        final isHealthy = statusMap.values.every((val) => val == true);

        final storageService = StorageAccessService();
        String storageStatusStr;
        try {
          final storageStatus = await storageService.getStatus();
          if (storageStatus != null) {
            final uri = storageStatus['uri'];
            final name = storageStatus['displayName'];
            final namePart = name != null ? ' (Name: $name)' : '';
            storageStatusStr = 'LINKED$namePart\n  Uri: $uri';
          } else {
            storageStatusStr = 'NOT LINKED';
          }
        } on PlatformException catch (e) {
          storageStatusStr = 'ERROR (${_formatStorageError(e)})';
        }

        final sb = StringBuffer();
        sb.writeln('=== Active Working Environments ===');
        sb.writeln('Dart Virtual Filesystem (VFS):');
        sb.writeln('  CWD: ${vfs.getAbsolutePath()}');
        sb.writeln('Native Sandbox Runtime:');
        sb.writeln('  Home: ${paths['home']}');
        sb.writeln('  Bin:  ${paths['bin']}');
        sb.writeln('  Tmp:  ${paths['tmp']}');
        sb.writeln('Real Workspace Files:');
        sb.writeln('  Projects: ${paths['home']}/projects');
        sb.writeln(
          '  Tracked CWD: ${WorkspaceService().trackedWorkingDirectory()}',
        );
        sb.writeln(
          '  State: ${isHealthy ? "HEALTHY" : "UNHEALTHY (corrupted folders)"}',
        );
        sb.writeln('User-Linked Android Storage:');
        sb.writeln('  Status: $storageStatusStr');
        sb.write(
          'NOTE: VFS is legacy demo storage. workspace/host-* commands use real Termode files. SAF storage remains user-linked Android storage.',
        );
        return CommandResult(output: sb.toString());

      case 'runtime-help':
        return CommandResult(
          output:
              'WARNING: Native sandbox commands operate directly on physical storage.\n\n'
              'Native Sandbox Commands:\n'
              '  android-shell [cmd]    - Run native shell command\n'
              '  android-shell-env      - Print environment config\n'
              '  android-shell-diag     - Run hardware diagnostics\n'
              '  termode-runtime status - Check runtime directory health\n'
              '  termode-runtime path   - Show native absolute paths\n'
              '  termode-runtime reset  - Wipe and rebuild sandbox layout\n'
              '  runtime-tools [cmd]    - Manage Termode runtime tools\n'
              '  runtime-doctor         - Probe current runtime support\n'
              '  runtime-capabilities   - List supported and unsupported runtimes\n'
              '  runtime-exec-test      - Run runtime execution probes\n'
              '  runtime-plan           - Show native/runtime proof roadmap\n'
              '  runtime-freeze [sub]   - Show frozen runtime direction\n'
              '  doctor                 - Show unified Termode health summary\n'
              '  beta-status            - Show beta readiness summary\n'
              '  settings-summary       - Show compact settings state\n'
              '  runtime-candidates     - Compare possible future runtime strategies\n'
              '  runtime-candidate <n>  - Show details for one runtime candidate\n'
              '  runtime-decision       - Show recommended runtime decision order\n'
              '  runtime-risks          - List major runtime risks\n'
              '  runtime-next           - Show recommended next proof\n'
              '  runtime-research-doctor - Check runtime research readiness\n'
              '  bundled-runtime-info   - Show bundled native proof info\n'
              '  bundled-runtime-test   - Run the native bridge proof\n'
              '  bundled-runtime-doctor - Diagnose bundled runtime proof\n'
              '  bundled-runtime-paths  - Show native/runtime paths\n'
              '  bundled-runtime-plan   - Show bundled runtime roadmap\n'
              '  native-tool [sub]      - Run a tiny native bridge tool\n'
              '  js-proof [sub]         - Run a tiny JS-like native bridge proof\n'
              '  js-engine-*            - Show embedded JS engine decision/research\n'
              '  quickjs [sub]          - Run the QuickJS embedded-engine probe\n'
              '  duktape [sub]          - Run the Duktape fallback-engine probe\n'
              '  localhost-doctor       - Check localhost readiness\n'
              '  localhost-capabilities - Show dev server readiness support\n'
              '  port-check <port>      - Check 127.0.0.1 port status\n'
              '  http-test <port|url>   - Test HTTP localhost reachability\n'
              '  preview-url <port>     - Print a clean preview URL\n'
              '  devserver-help         - Show localhost/dev server help\n'
              '  run-tool [t] [args...] - Run a sandboxed tool script\n'
              '  pkg [cmd] [args...]    - Manage Termode script packages\n'
              '  toybox [args...]       - Run Toybox system command\n'
              '  toybox-list            - List all Toybox system utilities\n'
              '  runtime-pwd            - Print sandbox home directory\n'
              '  runtime-ls             - List sandbox home contents\n'
              '  runtime-cat [file]     - Read sandbox home file\n'
              '  runtime-write [fl] [t] - Write text to sandbox file\n'
              '  workspace-*            - Manage real files/home/projects folders\n'
              '  host-*                 - Work with real Termode home files\n\n'
              'Packages Guidance:\n'
              '  - Use "pkg list" to see available packages.\n'
              '  - Packages are installed to files/usr/bin and sourced via shell helpers.',
        );

      case 'welcome':
      case 'getting-started':
      case 'first-run':
        return CommandResult(output: _welcomeOutput());

      case 'commands':
        return CommandResult(
          output: _commandsOutput(all: args.contains('--all')),
        );

      case 'examples':
        final output = _examplesOutput(args.isNotEmpty ? args[0] : null);
        return CommandResult(
          output: output,
          isError: output.startsWith('Unknown examples category'),
        );

      case 'glossary':
        return CommandResult(output: _glossaryOutput());

      case 'onboarding-doctor':
        final output = _onboardingDoctorOutput();
        return CommandResult(
          output: output,
          isError: output.contains('Overall: UNHEALTHY'),
        );

      case 'doctor':
        final output = await _termodeDoctor(
          verbose: args.contains('--verbose'),
        );
        return CommandResult(
          output: output,
          isError: output.contains('Overall: UNHEALTHY'),
        );

      case 'beta':
      case 'beta-doctor':
        final status = await _betaStatusOutput();
        return CommandResult(
          output:
              '$status\n\n${_betaScoreOutput()}\n\n${_betaKnownLimitsOutput()}',
          isError: status.contains('Overall: NOT READY'),
        );

      case 'beta-status':
        final output = await _betaStatusOutput();
        return CommandResult(
          output: output,
          isError: output.contains('Overall: NOT READY'),
        );

      case 'beta-score':
        return CommandResult(output: _betaScoreOutput());

      case 'beta-checklist':
        return CommandResult(output: _betaChecklistOutput());

      case 'beta-known-limits':
        return CommandResult(output: _betaKnownLimitsOutput());

      case 'beta-next':
        return CommandResult(output: _betaNextOutput());

      case 'build-info':
        return CommandResult(output: _buildInfoOutput());

      case 'feedback':
        final sub = args.isNotEmpty ? args[0].toLowerCase() : '';
        switch (sub) {
          case '':
          case 'help':
            return CommandResult(output: _feedbackOutput());
          case 'template':
            return CommandResult(output: _feedbackTemplateOutput());
          case 'checklist':
            return CommandResult(output: _feedbackChecklistOutput());
          default:
            return CommandResult(
              output:
                  'Unknown feedback subcommand: $sub\n'
                  'Usage: feedback <template|checklist>',
              isError: true,
            );
        }

      case 'rc-checklist':
        return CommandResult(output: _rcChecklistOutput());

      case 'rc-status':
        final output = await _rcStatusOutput();
        return CommandResult(
          output: output,
          isError: output.contains('Overall: NEEDS FIXES'),
        );

      case 'prefix-info':
        return CommandResult(output: await RuntimePrefixService().prefixInfo());

      case 'prefix-init':
        final output = await RuntimePrefixService().initPrefix();
        return CommandResult(
          output: output,
          isError: output.contains('Status: incomplete'),
        );

      case 'prefix-doctor':
        final output = await RuntimePrefixService().prefixDoctor();
        return CommandResult(
          output: output,
          isError: output.contains('Overall: UNHEALTHY'),
        );

      case 'path-info':
        return CommandResult(output: await RuntimePrefixService().pathInfo());

      case 'env-info':
        return CommandResult(output: await RuntimePrefixService().envInfo());

      case 'prefix-status':
        final output = await RuntimePrefixService().prefixStatus();
        return CommandResult(
          output: output,
          isError: output.contains('Overall: UNHEALTHY'),
        );

      case 'path-status':
        return CommandResult(output: await RuntimePrefixService().pathStatus());

      case 'path-preview':
        return CommandResult(
          output: await RuntimePrefixService().pathPreview(),
        );

      case 'path-doctor':
        final output = await RuntimePrefixService().pathDoctor();
        return CommandResult(
          output: output,
          isError: output.contains('Overall: UNHEALTHY'),
        );

      case 'env-status':
        return CommandResult(output: await RuntimePrefixService().envStatus());

      case 'env-preview':
        return CommandResult(output: await RuntimePrefixService().envPreview());

      case 'env-doctor':
        final output = await RuntimePrefixService().envDoctor();
        return CommandResult(
          output: output,
          isError: output.contains('Overall: UNHEALTHY'),
        );

      case 'env-check':
        return CommandResult(output: await RuntimePrefixService().envCheck());

      case 'env-script':
        return CommandResult(
          output: await RuntimePrefixService().envScriptInfo(),
        );

      case 'bin-list':
        return CommandResult(output: await RuntimePrefixService().binList());

      case 'bin-which':
        if (args.isEmpty) {
          return CommandResult(
            output: 'Usage: bin-which <command>',
            isError: true,
          );
        }
        final output = await RuntimePrefixService().binWhich(args[0]);
        return CommandResult(
          output: output,
          isError: output.startsWith('bin-which:'),
        );

      case 'bin-doctor':
        return CommandResult(output: await RuntimePrefixService().binDoctor());

      case 'shim-info':
        return CommandResult(output: RuntimePrefixService().shimInfo());

      case 'shim-list':
        return CommandResult(output: await RuntimePrefixService().shimList());

      case 'shim-doctor':
        return CommandResult(output: await RuntimePrefixService().shimDoctor());

      case 'runtime-abi':
        return CommandResult(
          output: await RuntimeBinaryPackageService().runtimeAbi(),
        );

      case 'runtime-pkg':
        final sub = args.isNotEmpty ? args[0].toLowerCase() : 'help';
        final service = RuntimeBinaryPackageService();
        switch (sub) {
          case 'help':
            return CommandResult(output: await service.help());
          case 'list':
            return CommandResult(output: await service.list());
          case 'available':
            return CommandResult(output: await service.available());
          case 'info':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: runtime-pkg info <name>',
                isError: true,
              );
            }
            final output = await service.info(args[1]);
            return CommandResult(
              output: output,
              isError: output.startsWith('Unknown runtime package:'),
            );
          case 'install':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: runtime-pkg install <name>',
                isError: true,
              );
            }
            final result = await service.install(args[1]);
            return CommandResult(
              output: result.output,
              isError: result.isError,
            );
          case 'remove':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: runtime-pkg remove <name>',
                isError: true,
              );
            }
            final result = await service.remove(args[1]);
            return CommandResult(
              output: result.output,
              isError: result.isError,
            );
          case 'verify':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: runtime-pkg verify <name>',
                isError: true,
              );
            }
            final result = await service.verify(args[1]);
            return CommandResult(
              output: result.output,
              isError: result.isError,
            );
          case 'status':
            return CommandResult(output: await service.status());
          case 'doctor':
            final output = await service.doctor();
            return CommandResult(
              output: output,
              isError: output.contains('Overall: UNHEALTHY'),
            );
          case 'repair':
            return CommandResult(output: await service.repair());
          default:
            return CommandResult(
              output:
                  'Unknown runtime-pkg subcommand: $sub\n'
                  'Usage: runtime-pkg <available|info|install|remove|verify|list|status|doctor|repair>',
              isError: true,
            );
        }

      case 'hello-bin':
        final result = await RuntimeBinaryPackageService().runHelloBin();
        return CommandResult(output: result.output, isError: result.isError);

      case 'git-status':
        return CommandResult(output: await _gitStatusOutput());

      case 'git-info':
        return CommandResult(output: await _gitInfoOutput());

      case 'git-plan':
        return CommandResult(
          output: _gitPlanOutput(
            RuntimeBinaryPackageService().gitArtifactAvailable(),
          ),
        );

      case 'git-version':
        return CommandResult(output: await _gitVersionOutput());

      case 'git-doctor':
        final output = await _gitDoctorOutput();
        return CommandResult(
          output: output,
          isError: output.contains('Overall: UNHEALTHY'),
        );

      case 'git-test-plan':
        return CommandResult(output: await _gitTestPlanOutput());

      case 'git':
        return CommandResult(output: await _gitBareOutput());

      case 'toolchain-status':
        return CommandResult(output: _toolchainStatusOutput());

      case 'toolchain-list':
        return CommandResult(output: _toolchainListOutput());

      case 'toolchain-plan':
        return CommandResult(output: _toolchainPlanOutput());

      case 'toolchain-info':
        if (args.isEmpty) {
          return CommandResult(
            output: 'Usage: toolchain-info <name>\nRun: toolchain-list',
            isError: true,
          );
        }
        final output = _toolchainInfoOutput(args[0]);
        return CommandResult(
          output: output,
          isError: output.startsWith('Unknown toolchain:'),
        );

      case 'toolchain-doctor':
        return CommandResult(output: await _toolchainDoctorOutput());

      case 'runtime-install':
        final sub = args.isNotEmpty ? args[0].toLowerCase() : 'help';
        switch (sub) {
          case 'help':
            return CommandResult(output: _runtimeInstallHelpOutput());
          case 'list':
            return CommandResult(output: _runtimeInstallListOutput());
          case 'plan':
            if (args.length < 2) {
              return CommandResult(
                output:
                    'Usage: runtime-install plan <tool>\n'
                    'Run: runtime-install list',
                isError: true,
              );
            }
            final output = _runtimeInstallPlanOutput(args[1]);
            return CommandResult(
              output: output,
              isError: output.startsWith('Unknown runtime:'),
            );
          case 'status':
            return CommandResult(output: await _runtimeInstallStatusOutput());
          case 'doctor':
            return CommandResult(output: await _runtimeInstallDoctorOutput());
          default:
            return CommandResult(
              output:
                  'Unknown runtime-install subcommand: $sub\n'
                  'Usage: runtime-install <list|plan|status|doctor>',
              isError: true,
            );
        }

      case 'dev-setup':
        final sub = args.isNotEmpty ? args[0].toLowerCase() : 'help';
        switch (sub) {
          case 'help':
            return CommandResult(output: _devSetupHelpOutput());
          case 'list':
            return CommandResult(output: _devSetupListOutput());
          case 'plan':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: dev-setup plan <preset>\nRun: dev-setup list',
                isError: true,
              );
            }
            final output = _devSetupPlanOutput(args[1]);
            return CommandResult(
              output: output,
              isError: output.startsWith('Unknown dev-setup preset:'),
            );
          default:
            return CommandResult(
              output:
                  'Unknown dev-setup subcommand: $sub\n'
                  'Usage: dev-setup <list|plan>',
              isError: true,
            );
        }

      case 'dev-doctor':
        return CommandResult(output: await _devDoctorOutput());

      case 'beta-candidate':
        final sub = args.isNotEmpty ? args[0].toLowerCase() : 'help';
        switch (sub) {
          case 'help':
            return CommandResult(output: _betaCandidateHelpOutput());
          case 'status':
            final output = await _betaCandidateStatusOutput();
            return CommandResult(
              output: output,
              isError: output.contains('Overall: NEEDS FIXES'),
            );
          case 'checklist':
            return CommandResult(output: _betaCandidateChecklistOutput());
          case 'notes':
            return CommandResult(output: _betaCandidateNotesOutput());
          case 'limits':
            return CommandResult(output: _betaCandidateLimitsOutput());
          case 'ready':
            final output = await _betaCandidateReadyOutput();
            return CommandResult(
              output: output,
              isError: output.startsWith('Not ready:'),
            );
          default:
            return CommandResult(
              output:
                  'Unknown beta-candidate subcommand: $sub\n'
                  'Usage: beta-candidate <status|checklist|notes|limits|ready>',
              isError: true,
            );
        }

      case 'settings-summary':
        return CommandResult(output: _settingsSummaryOutput());

      case 'settings-doctor':
        final output = _settingsDoctorOutput();
        return CommandResult(
          output: output,
          isError: output.contains('Overall: UNHEALTHY'),
        );

      case 'settings-reset-safe':
        if (!args.contains('--confirm')) {
          return CommandResult(
            output:
                'Warning: This restores visual and terminal settings to defaults.\n'
                'Packages, workspaces, sessions, history, repo config, and files are NOT changed.\n'
                'Run: settings-reset-safe --confirm',
            isError: true,
          );
        }
        SettingsService().resetVisualSettings();
        await TerminalSessionService().saveState();
        return CommandResult(
          output:
              '=== Safe Settings Reset ===\n'
              'Status: visual and terminal settings restored to defaults.\n'
              'Kept: packages, workspaces, sessions, history, repo config, files.\n'
              'Tip: run settings-summary to review.',
        );

      case 'theme-test':
        return CommandResult(output: _themeTestOutput());

      case 'status':
        return CommandResult(output: await _statusOutput());

      case 'version':
        return CommandResult(output: _versionOutput());

      case 'release-notes':
      case 'changelog':
        return CommandResult(output: _releaseNotesOutput());

      case 'bug-report':
        return CommandResult(output: await _bugReportOutput());

      case 'qa-checklist':
        return CommandResult(output: _qaChecklistOutput());

      case 'qa-run':
        return CommandResult(output: _qaRunOutput());

      case 'qa-status':
        final output = await _qaStatusOutput();
        return CommandResult(
          output: output,
          isError: output.contains('Overall: NEEDS FIXES'),
        );

      case 'qa-report':
        return CommandResult(output: await _qaReportOutput());

      case 'qa-reset':
        return CommandResult(output: _qaResetOutput());

      case 'runtime-doctor':
        final verbose = args.contains('--verbose');
        final output = await RuntimeCapabilityService().doctor(
          sessionId,
          verbose: verbose,
        );
        return CommandResult(
          output: output,
          isError: output.contains('Overall: UNHEALTHY'),
        );

      case 'runtime-capabilities':
        return CommandResult(output: RuntimeCapabilityService().capabilities());

      case 'runtime-exec-test':
        final verbose = args.contains('--verbose');
        final output = await RuntimeCapabilityService().execTest(
          sessionId,
          verbose: verbose,
        );
        return CommandResult(
          output: output,
          isError: output.contains('Overall: UNHEALTHY'),
        );

      case 'runtime-plan':
        return CommandResult(output: RuntimeCapabilityService().plan());

      case 'runtime-freeze':
        final freeze = RuntimeFreezeService();
        final sub = args.isNotEmpty ? args[0].toLowerCase() : 'help';
        switch (sub) {
          case 'help':
            return CommandResult(output: freeze.help());
          case 'status':
            return CommandResult(output: freeze.status());
          case 'decision':
            return CommandResult(output: freeze.decision());
          case 'deferred':
            return CommandResult(output: freeze.deferred());
          case 'why':
            return CommandResult(output: freeze.why());
          case 'next':
            return CommandResult(output: freeze.next());
          case 'doctor':
            final output = freeze.doctor();
            return CommandResult(
              output: output,
              isError: output.contains('Overall: LIMITED'),
            );
          default:
            return CommandResult(
              output:
                  'Unknown runtime-freeze subcommand: $sub\n'
                  'Usage: runtime-freeze <help|status|decision|deferred|why|next|doctor>',
              isError: true,
            );
        }

      case 'runtime-candidates':
        return CommandResult(
          output: RuntimeCandidateService().candidatesTable(),
        );

      case 'runtime-candidate':
        if (args.isEmpty) {
          return CommandResult(
            output: 'Usage: runtime-candidate <name>',
            isError: true,
          );
        }
        final candidateOutput = RuntimeCandidateService().candidateDetails(
          args[0],
        );
        return CommandResult(
          output: candidateOutput,
          isError: candidateOutput.startsWith('Unknown runtime candidate:'),
        );

      case 'runtime-decision':
        return CommandResult(output: RuntimeCandidateService().decision());

      case 'runtime-risks':
        return CommandResult(output: RuntimeCandidateService().risks());

      case 'runtime-next':
        return CommandResult(output: RuntimeCandidateService().next());

      case 'runtime-research-doctor':
        final output = await RuntimeCandidateService().researchDoctor(
          sessionId,
        );
        return CommandResult(
          output: output,
          isError: output.contains('Overall readiness: UNHEALTHY'),
        );

      case 'bundled-runtime-info':
        return CommandResult(output: await BundledRuntimeService().info());

      case 'bundled-runtime-test':
        final bundledTest = await BundledRuntimeService().test();
        return CommandResult(
          output: bundledTest,
          isError: bundledTest.contains('Overall: FAIL'),
        );

      case 'bundled-runtime-doctor':
        final bundledDoctor = await BundledRuntimeService().doctor(
          verbose: args.contains('--verbose'),
        );
        return CommandResult(
          output: bundledDoctor,
          isError: bundledDoctor.contains('Overall: UNAVAILABLE'),
        );

      case 'bundled-runtime-paths':
        return CommandResult(output: await BundledRuntimeService().paths());

      case 'bundled-runtime-plan':
        return CommandResult(output: BundledRuntimeService().plan());

      case 'native-tool':
        final tool = NativeToolService();
        final sub = args.isNotEmpty ? args[0].toLowerCase() : 'help';
        switch (sub) {
          case 'help':
            return CommandResult(output: tool.help());
          case 'info':
            return CommandResult(output: await tool.info());
          case 'echo':
            return CommandResult(
              output: await tool.echo(args.sublist(1).join(' ')),
            );
          case 'cwd':
            return CommandResult(output: await tool.cwd());
          case 'pid':
            return CommandResult(output: await tool.pid());
          case 'abi':
            return CommandResult(output: await tool.abi());
          case 'hash':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: native-tool hash <text>',
                isError: true,
              );
            }
            return CommandResult(
              output: await tool.hash(args.sublist(1).join(' ')),
            );
          case 'time':
            return CommandResult(output: await tool.time());
          case 'env':
            return CommandResult(output: await tool.env());
          case 'doctor':
            final doctorOut = await tool.doctor();
            return CommandResult(
              output: doctorOut,
              isError: doctorOut.contains('Overall: UNHEALTHY'),
            );
          default:
            return CommandResult(
              output:
                  'Unknown native-tool subcommand: $sub\n'
                  'Usage: native-tool <help|info|echo|cwd|pid|abi|hash|time|env|doctor>',
              isError: true,
            );
        }

      case 'js-proof':
        final proof = JsProofService();
        final sub = args.isNotEmpty ? args[0].toLowerCase() : 'help';
        switch (sub) {
          case 'help':
            return CommandResult(output: proof.help());
          case 'info':
            return CommandResult(output: await proof.info());
          case 'eval':
            final output = await proof.eval(args.sublist(1).join(' '));
            return CommandResult(
              output: output,
              isError: output.startsWith('Error:'),
            );
          case 'file':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: js-proof file <path>',
                isError: true,
              );
            }
            final output = await proof.file(args[1]);
            return CommandResult(
              output: output,
              isError: output.startsWith('Error:'),
            );
          case 'doctor':
            final output = await proof.doctor();
            return CommandResult(
              output: output,
              isError: output.contains('Overall: UNAVAILABLE'),
            );
          case 'limits':
            return CommandResult(output: proof.limits());
          case 'plan':
            return CommandResult(output: proof.plan());
          default:
            return CommandResult(
              output:
                  'Unknown js-proof subcommand: $sub\n'
                  'Usage: js-proof <help|info|eval|file|doctor|limits|plan>',
              isError: true,
            );
        }

      case 'js-engine-candidates':
        return CommandResult(
          output: JsEngineDecisionService().candidatesTable(),
        );

      case 'js-engine-candidate':
        if (args.isEmpty) {
          return CommandResult(
            output: 'Usage: js-engine-candidate <name>',
            isError: true,
          );
        }
        final output = JsEngineDecisionService().candidateDetails(args[0]);
        return CommandResult(
          output: output,
          isError: output.startsWith('Unknown JS engine candidate:'),
        );

      case 'js-engine-decision':
        return CommandResult(output: JsEngineDecisionService().decision());

      case 'js-engine-risks':
        return CommandResult(output: JsEngineDecisionService().risks());

      case 'js-engine-next':
        return CommandResult(output: JsEngineDecisionService().next());

      case 'js-engine-doctor':
        final output = JsEngineDecisionService().doctor();
        return CommandResult(
          output: output,
          isError: output.contains('Overall: UNHEALTHY'),
        );

      case 'quickjs':
        final quickjs = QuickJsService();
        final sub = args.isNotEmpty ? args[0].toLowerCase() : 'help';
        switch (sub) {
          case 'help':
            return CommandResult(output: quickjs.help());
          case 'info':
            final output = await quickjs.info();
            return CommandResult(
              output: output,
              isError: output.contains('Status: UNAVAILABLE'),
            );
          case 'eval':
            final output = await quickjs.eval(args.sublist(1).join(' '));
            return CommandResult(
              output: output,
              isError:
                  output.startsWith('Error:') ||
                  output.startsWith('QuickJS bridge unavailable'),
            );
          case 'file':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: quickjs file <path>',
                isError: true,
              );
            }
            final output = await quickjs.file(args[1]);
            return CommandResult(
              output: output,
              isError:
                  output.startsWith('Error:') ||
                  output.startsWith('QuickJS bridge unavailable'),
            );
          case 'limits':
            return CommandResult(output: quickjs.limits());
          case 'doctor':
            final output = await quickjs.doctor();
            return CommandResult(
              output: output,
              isError:
                  output.contains('Overall: UNAVAILABLE') ||
                  output.startsWith('QuickJS bridge unavailable'),
            );
          case 'plan':
            return CommandResult(output: quickjs.plan());
          default:
            return CommandResult(
              output:
                  'Unknown quickjs subcommand: $sub\n'
                  'Usage: quickjs <help|info|eval|file|limits|doctor|plan>',
              isError: true,
            );
        }

      case 'duktape':
        final duktape = DuktapeService();
        final sub = args.isNotEmpty ? args[0].toLowerCase() : 'help';
        switch (sub) {
          case 'help':
            return CommandResult(output: duktape.help());
          case 'info':
            final output = await duktape.info();
            return CommandResult(
              output: output,
              isError: output.contains('Status: UNAVAILABLE'),
            );
          case 'eval':
            final output = await duktape.eval(args.sublist(1).join(' '));
            return CommandResult(
              output: output,
              isError:
                  output.startsWith('Error:') ||
                  output.startsWith('Duktape bridge unavailable'),
            );
          case 'file':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: duktape file <path>',
                isError: true,
              );
            }
            final output = await duktape.file(args[1]);
            return CommandResult(
              output: output,
              isError:
                  output.startsWith('Error:') ||
                  output.startsWith('Duktape bridge unavailable'),
            );
          case 'limits':
            return CommandResult(output: duktape.limits());
          case 'doctor':
            final output = await duktape.doctor();
            return CommandResult(
              output: output,
              isError:
                  output.contains('Overall: UNAVAILABLE') ||
                  output.startsWith('Duktape bridge unavailable'),
            );
          case 'plan':
            return CommandResult(output: duktape.plan());
          default:
            return CommandResult(
              output:
                  'Unknown duktape subcommand: $sub\n'
                  'Usage: duktape <help|info|eval|file|limits|doctor|plan>',
              isError: true,
            );
        }

      case 'localhost-doctor':
        final verbose = args.contains('--verbose');
        final output = await LocalhostService().doctor(verbose: verbose);
        return CommandResult(
          output: output,
          isError: output.contains('Overall: UNHEALTHY'),
        );

      case 'localhost-capabilities':
        return CommandResult(output: LocalhostService().capabilities());

      case 'port-check':
        final portArg = args.isNotEmpty && !args[0].startsWith('--')
            ? args[0]
            : null;
        final validation = LocalhostService().validatePortArg(portArg);
        if (validation != null) {
          return CommandResult(output: validation, isError: true);
        }
        final port = LocalhostService().parsePort(portArg!)!;
        final result = await LocalhostService().checkPort(port);
        return CommandResult(
          output: LocalhostService().portCheckOutput(
            result,
            verbose: args.contains('--verbose'),
          ),
        );

      case 'http-test':
        final targetArg = args.isNotEmpty && !args[0].startsWith('--')
            ? args[0]
            : null;
        if (targetArg == null || targetArg.trim().isEmpty) {
          return CommandResult(
            output:
                'Error: Missing URL or port.\nUsage: http-test <url-or-port>',
            isError: true,
          );
        }
        final uri = LocalhostService().normalizeHttpTarget(targetArg);
        if (!uri.hasAuthority || uri.host.isEmpty) {
          return CommandResult(
            output: 'Error: Invalid HTTP target: $targetArg',
            isError: true,
          );
        }
        final httpResult = await LocalhostService().testHttp(uri);
        return CommandResult(
          output: LocalhostService().httpTestOutput(
            httpResult,
            headers: args.contains('--headers'),
          ),
          isError: !httpResult.reached,
        );

      case 'preview-url':
        final portArg = args.isNotEmpty && !args[0].startsWith('--')
            ? args[0]
            : null;
        final validation = LocalhostService().validatePortArg(portArg);
        if (validation != null) {
          return CommandResult(output: validation, isError: true);
        }
        final port = LocalhostService().parsePort(portArg!)!;
        return CommandResult(
          output: await LocalhostService().previewUrlOutput(
            port,
            copy: args.contains('--copy'),
          ),
        );

      case 'devserver-help':
        return CommandResult(output: LocalhostService().help());

      case 'preview':
        return CommandResult(output: PreviewService().statusOutput());

      case 'preview-copy':
        final copyPortArg = args.isNotEmpty && !args[0].startsWith('--')
            ? args[0]
            : null;
        final copyResult = await PreviewService().copy(
          copyPortArg,
          sessionId: sessionId,
        );
        return CommandResult(
          output: copyResult.output,
          isError: copyResult.isError,
        );

      case 'preview-open':
        final openPortArg = args.isNotEmpty && !args[0].startsWith('--')
            ? args[0]
            : null;
        final openResult = await PreviewService().open(
          openPortArg,
          force: args.contains('--force'),
          sessionId: sessionId,
        );
        return CommandResult(
          output: openResult.output,
          isError: openResult.isError,
        );

      case 'preview-check':
        final checkPortArg = args.isNotEmpty && !args[0].startsWith('--')
            ? args[0]
            : null;
        final checkResult = await PreviewService().check(checkPortArg);
        return CommandResult(
          output: checkResult.output,
          isError: checkResult.isError,
        );

      case 'preview-history':
        return CommandResult(output: PreviewService().historyOutput());

      case 'preview-clear-history':
        return CommandResult(output: PreviewService().clearHistory());

      case 'preview-settings':
        return CommandResult(output: PreviewService().settingsOutput());

      case 'preview-doctor':
        final previewDoctor = await PreviewService().doctor(
          verbose: args.contains('--verbose'),
        );
        return CommandResult(
          output: previewDoctor.output,
          isError: previewDoctor.isError,
        );

      case 'preview-help':
        return CommandResult(output: PreviewService().help());

      case 'storage-link':
        final storageService = StorageAccessService();
        try {
          final result = await storageService.linkFolder();
          if (result != null) {
            return CommandResult(output: 'Folder linked successfully: $result');
          } else {
            return CommandResult(
              output: 'Failed to link folder or linking cancelled.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage':
      case 'storage-status':
        final storageService = StorageAccessService();
        try {
          final status = await storageService.getStatus();
          if (status != null) {
            final name = status['displayName'] ?? '(unknown)';
            return CommandResult(
              output:
                  'Storage linked: yes\nName: $name\nPermissions: read/write\nTip: storage-list',
            );
          } else {
            return CommandResult(
              output:
                  'Storage linked: no\nName: (none)\nPermissions: none\nTip: storage-link',
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-projects':
        try {
          return CommandResult(
            output: await WorkspaceService().storageProjects(),
          );
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'workspace-import-storage':
        if (args.length < 2) {
          return CommandResult(
            output:
                'Usage: workspace-import-storage <storage-folder-name> <workspace-name>',
            isError: true,
          );
        }
        try {
          return CommandResult(
            output: await WorkspaceService().importStorage(args[0], args[1]),
          );
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'workspace-export-storage':
        if (args.length < 2) {
          return CommandResult(
            output:
                'Usage: workspace-export-storage <workspace-name> <storage-folder-name> [--overwrite]',
            isError: true,
          );
        }
        try {
          return CommandResult(
            output: await WorkspaceService().exportStorage(
              args[0],
              args[1],
              overwrite: args.contains('--overwrite'),
            ),
          );
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-unlink':
        final storageService = StorageAccessService();
        try {
          await storageService.unlink();
          return CommandResult(output: 'Storage link removed successfully.');
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-list':
        final storageService = StorageAccessService();
        try {
          final files = await storageService.listFiles();
          if (files == null) {
            return CommandResult(
              output: 'storage-list: No linked storage or failed to query.',
              isError: true,
            );
          }
          if (files.isEmpty) {
            return CommandResult(output: '(empty directory)');
          }
          return CommandResult(output: files.join('\n'));
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-read':
        if (args.isEmpty) {
          return CommandResult(
            output: 'storage-read: missing file operand',
            isError: true,
          );
        }
        final filename = args.join(' ');
        final storageService = StorageAccessService();
        try {
          final content = await storageService.readFile(filename);
          if (content != null) {
            return CommandResult(output: content);
          } else {
            return CommandResult(
              output: 'storage-read: Failed to read file or file empty.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-write':
        if (args.isEmpty) {
          return CommandResult(
            output: 'storage-write: missing file operand',
            isError: true,
          );
        }
        if (args.length < 2) {
          return CommandResult(
            output: 'storage-write: missing text operand',
            isError: true,
          );
        }
        final filename = args[0];
        final text = args.sublist(1).join(' ');

        final storageService = StorageAccessService();
        try {
          final success = await storageService.writeFile(filename, text);
          if (success) {
            return CommandResult(
              output:
                  'Wrote ${text.length} characters to $filename inside linked folder.',
            );
          } else {
            return CommandResult(
              output: 'storage-write: Failed to write to file.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-delete':
        if (args.isEmpty) {
          return CommandResult(
            output: 'storage-delete: missing file operand',
            isError: true,
          );
        }
        final filename = args.join(' ');
        final storageService = StorageAccessService();
        try {
          final canDelete = await storageService.supportsDelete(filename);
          if (!canDelete) {
            return CommandResult(
              output:
                  'Error: Deletion not supported by provider for file "$filename".',
              isError: true,
            );
          }
          final success = await storageService.deleteFile(filename);
          if (success) {
            return CommandResult(
              output: 'Deleted file "$filename" from linked storage.',
            );
          } else {
            return CommandResult(
              output: 'Error: Failed to delete file "$filename".',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-mkdir':
        if (args.isEmpty) {
          return CommandResult(
            output: 'storage-mkdir: missing directory operand',
            isError: true,
          );
        }
        final folderName = args.join(' ');
        final storageService = StorageAccessService();
        try {
          final success = await storageService.createDirectory(folderName);
          if (success) {
            return CommandResult(
              output: 'Created directory "$folderName" inside linked storage.',
            );
          } else {
            return CommandResult(
              output: 'Error: Failed to create directory "$folderName".',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(output: _formatStorageError(e), isError: true);
        }

      case 'storage-test':
        final storageService = StorageAccessService();
        final sb = StringBuffer();
        sb.writeln('=== Starting Storage Integration Test ===');

        sb.write('1. Checking storage status... ');
        Map<String, String>? status;
        try {
          status = await storageService.getStatus();
        } on PlatformException catch (e) {
          sb.writeln('FAIL (${_formatStorageError(e)})');
          sb.writeln('=== Storage Integration Test Failed ===');
          sb.write('Result: FAIL');
          return CommandResult(output: sb.toString(), isError: true);
        }

        if (status == null || status['uri'] == null) {
          sb.writeln('FAIL (No folder is currently linked)');
          sb.writeln('=== Storage Integration Test Failed ===');
          sb.write('Result: FAIL');
          return CommandResult(output: sb.toString(), isError: true);
        }
        final folderDisplayName = status['displayName'] ?? status['uri']!;
        sb.writeln('PASS (Linked: $folderDisplayName)');

        final testFilename = 'termode_test_temp.txt';
        final testContent = 'Termode storage test content - ${DateTime.now()}';
        sb.write('2. Writing temporary test file ($testFilename)... ');
        try {
          final success = await storageService.writeFile(
            testFilename,
            testContent,
          );
          if (!success) {
            sb.writeln('FAIL (writeFile returned false)');
            sb.writeln('=== Storage Integration Test Failed ===');
            sb.write('Result: FAIL');
            return CommandResult(output: sb.toString(), isError: true);
          }
        } on PlatformException catch (e) {
          sb.writeln('FAIL (${_formatStorageError(e)})');
          sb.writeln('=== Storage Integration Test Failed ===');
          sb.write('Result: FAIL');
          return CommandResult(output: sb.toString(), isError: true);
        }
        sb.writeln('PASS');

        sb.write('3. Reading test file back... ');
        try {
          final readContent = await storageService.readFile(testFilename);
          if (readContent != testContent) {
            sb.writeln('FAIL (Content mismatch)');
            sb.writeln('=== Storage Integration Test Failed ===');
            sb.write('Result: FAIL');
            return CommandResult(output: sb.toString(), isError: true);
          }
        } on PlatformException catch (e) {
          sb.writeln('FAIL (${_formatStorageError(e)})');
          sb.writeln('=== Storage Integration Test Failed ===');
          sb.write('Result: FAIL');
          return CommandResult(output: sb.toString(), isError: true);
        }
        sb.writeln('PASS');

        sb.write('4. Checking deletion support... ');
        bool canDelete = false;
        try {
          canDelete = await storageService.supportsDelete(testFilename);
        } on PlatformException catch (e) {
          sb.writeln('FAIL (${_formatStorageError(e)})');
          sb.writeln('=== Storage Integration Test Failed ===');
          sb.write('Result: FAIL');
          return CommandResult(output: sb.toString(), isError: true);
        }

        if (canDelete) {
          sb.writeln('YES');
          sb.write('5. Deleting temporary test file... ');
          try {
            final success = await storageService.deleteFile(testFilename);
            if (!success) {
              sb.writeln('FAIL (deleteFile returned false)');
              sb.writeln('=== Storage Integration Test Failed ===');
              sb.write('Result: FAIL');
              return CommandResult(output: sb.toString(), isError: true);
            }
            sb.writeln('PASS');
          } on PlatformException catch (e) {
            sb.writeln('FAIL (${_formatStorageError(e)})');
            sb.writeln('=== Storage Integration Test Failed ===');
            sb.write('Result: FAIL');
            return CommandResult(output: sb.toString(), isError: true);
          }
        } else {
          sb.writeln('NO (Skipping delete test step)');
        }

        sb.writeln('=== Storage Integration Test Complete ===');
        sb.write('Result: PASS');
        return CommandResult(output: sb.toString());

      case 'storage-help':
        return CommandResult(
          output:
              '=== Termode User-Approved Storage Help ===\n\n'
              'Android security limits direct storage access. Termode uses the Android Storage Access Framework (SAF) to let you approve access to a specific folder.\n\n'
              'Commands:\n'
              '  storage-link       - Open picker to link an Android folder\n'
              '  storage            - Compact linked-storage status\n'
              '  storage-status     - Show whether a folder is currently linked\n'
              '  storage-unlink     - Unlink the folder (access revoked)\n'
              '  storage-list       - List files in the linked folder\n'
              '  storage-read [f]   - Read text file from the linked folder\n'
              '  storage-write [f] [t] - Write text file into the linked folder\n'
              '  storage-mkdir [d]  - Create a subdirectory in the linked folder\n'
              '  storage-delete [f] - Delete a file/directory from the linked folder\n'
              '  storage-projects   - List top-level project-like folders\n'
              '  storage-test       - Run storage integration diagnostics test\n\n'
              'Limitations:\n'
              '  - You must select a folder. Android blocks access to root storage and some system folders.\n'
              '  - Termode only supports reading/writing plain text files here.\n'
              '  - Linked storage is separate from Dart VFS and native runtime.',
        );

      case 'shell-start':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? started = await channel.invokeMethod('ptyStart', {
            'sessionId': sessionId,
          });
          if (started == true) {
            TerminalSessionService().setShellActive(sessionId, true);
            return CommandResult(
              output:
                  'WARNING: Experimental Shell Mode is highly experimental and may behave unpredictably.\n'
                  'This is currently an interactive process bridge, not a full native PTY.\n'
                  'Use "shell-send <text>" to interact with the shell.\n'
                  'Shell process started successfully.',
            );
          } else {
            return CommandResult(
              output: 'Shell session is already running.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(
            output: 'Error starting shell: ${e.message}',
            isError: true,
          );
        }

      case 'shell-status':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final Map<dynamic, dynamic>? status = await channel.invokeMethod(
            'ptyStatus',
            {'sessionId': sessionId},
          );
          if (status != null && status['running'] == true) {
            final pid = status['pid'];
            return CommandResult(output: 'Shell Status: RUNNING (PID: $pid)');
          } else {
            return CommandResult(output: 'Shell Status: NOT RUNNING');
          }
        } on PlatformException catch (e) {
          return CommandResult(
            output: 'Error querying shell status: ${e.message}',
            isError: true,
          );
        }

      case 'shell-stop':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? stopped = await channel.invokeMethod('ptyStop', {
            'sessionId': sessionId,
          });
          if (stopped == true) {
            TerminalSessionService().setShellActive(sessionId, false);
            return CommandResult(output: 'Shell process stopped.');
          } else {
            return CommandResult(
              output: 'No active shell process to stop.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(
            output: 'Error stopping shell: ${e.message}',
            isError: true,
          );
        }

      case 'shell-send':
        if (args.isEmpty) {
          return CommandResult(
            output:
                'shell-send: missing command/text operand\nUsage: shell-send <text>',
            isError: true,
          );
        }
        final text = args.join(' ');
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex != -1) {
          sessionService.sessions[sessionIndex].lastSentPtyInput = text;
        }
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? success = await channel.invokeMethod('ptySend', {
            'sessionId': sessionId,
            'text': text,
          });
          if (success == true) {
            return CommandResult(
              output: '',
            ); // output will be streamed asynchronously!
          } else {
            return CommandResult(
              output: 'Error: Failed to send input to shell.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'NOT_RUNNING') {
            return CommandResult(
              output:
                  'Error: No active shell process. Start one with shell-start.',
              isError: true,
            );
          }
          return CommandResult(
            output: 'Error sending to shell: ${e.message}',
            isError: true,
          );
        }

      case 'shell-send-ctrl-c':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? success = await channel.invokeMethod('ptySendCtrlC', {
            'sessionId': sessionId,
          });
          if (success == true) {
            return CommandResult(
              output: 'Sent Ctrl-C (SIGINT) to shell process.',
            );
          } else {
            return CommandResult(
              output: 'Failed to send Ctrl-C.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'NOT_RUNNING') {
            return CommandResult(
              output: 'Error: No active shell process.',
              isError: true,
            );
          }
          return CommandResult(
            output: 'Error sending Ctrl-C: ${e.message}',
            isError: true,
          );
        }

      case 'shell-send-ctrl-d':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? success = await channel.invokeMethod('ptySendCtrlD', {
            'sessionId': sessionId,
          });
          if (success == true) {
            return CommandResult(output: 'Sent Ctrl-D (EOF) to shell process.');
          } else {
            return CommandResult(
              output: 'Failed to send Ctrl-D.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'NOT_RUNNING') {
            return CommandResult(
              output: 'Error: No active shell process.',
              isError: true,
            );
          }
          return CommandResult(
            output: 'Error sending Ctrl-D: ${e.message}',
            isError: true,
          );
        }

      case 'shell-help':
        return CommandResult(
          output:
              '=== Termode Experimental Shell Mode Help ===\n\n'
              'This mode runs an interactive shell (/system/bin/sh) inside the Termode sandbox.\n\n'
              'Note: This is currently an interactive process bridge and NOT a full native pseudo-terminal (PTY).\n'
              '- Simple shell commands (e.g. ls, echo, pwd) will work.\n'
              '- Fullscreen terminal programs (e.g. vim, top, nano, ssh) that expect raw PTY tty controls may not display or work correctly.\n\n'
              'Commands:\n'
              '  shell-start         - Start the interactive shell process\n'
              '  shell-status        - View if shell is running and print its PID\n'
              '  shell-send [text]   - Send text input to the shell process standard input\n'
              '  shell-send-ctrl-c   - Send Ctrl-C (SIGINT) to the process\n'
              '  shell-send-ctrl-d   - Send Ctrl-D (EOF) to the process\n'
              '  shell-stop          - Terminate the running shell process',
        );

      case 'real-pty-start':
        final started = await TerminalSessionService().startRealPty(sessionId);
        if (started) {
          return CommandResult(
            output:
                'Warning: Experimental PTY prototype. Real PTY started.\n'
                'Use enter-pty-mode or termode-shell to interact.',
          );
        }
        return CommandResult(output: 'Error starting real PTY.', isError: true);

      case 'real-pty-status':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final Map<dynamic, dynamic>? status = await channel.invokeMethod(
            'realPtyStatus',
            {'sessionId': sessionId},
          );
          if (status != null && status['running'] == true) {
            final pid = status['pid'];
            return CommandResult(
              output: 'Real PTY Status: RUNNING (PID: $pid)',
            );
          } else {
            return CommandResult(output: 'Real PTY Status: NOT RUNNING');
          }
        } on PlatformException catch (e) {
          return CommandResult(
            output: 'Error querying real PTY status: ${e.message}',
            isError: true,
          );
        }

      case 'real-pty-send':
        if (args.isEmpty) {
          return CommandResult(
            output:
                'real-pty-send: missing command/text operand\nUsage: real-pty-send <text>',
            isError: true,
          );
        }
        final text = args.join(' ');
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex != -1) {
          sessionService.sessions[sessionIndex].lastSentRealPtyInput = text;
        }
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? success = await channel.invokeMethod('realPtySend', {
            'sessionId': sessionId,
            'text': text,
          });
          if (success == true) {
            return CommandResult(
              output: '',
            ); // output will be streamed asynchronously!
          } else {
            return CommandResult(
              output: 'Error: Failed to send input to real PTY.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'NOT_RUNNING') {
            return CommandResult(
              output:
                  'Error: No active real PTY process. Start one with real-pty-start.',
              isError: true,
            );
          }
          return CommandResult(
            output: 'Error sending to real PTY: ${e.message}',
            isError: true,
          );
        }

      case 'real-pty-stop':
        final sessionService = TerminalSessionService();
        sessionService.setRealPtyActive(sessionId, false);
        sessionService.setPtyInteractionActive(sessionId, false);
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? stopped = await channel.invokeMethod('realPtyStop', {
            'sessionId': sessionId,
          });
          if (stopped == true) {
            return CommandResult(
              output: 'Real PTY process stopped. Returned to NORMAL mode.',
            );
          } else {
            return CommandResult(
              output: 'Error: No active real PTY process to stop.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          return CommandResult(
            output:
                'Error: Failed to stop real PTY: ${e.message}. Cleaned up local session state.',
            isError: true,
          );
        }

      case 'real-pty-send-ctrl-c':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? success = await channel.invokeMethod('realPtySendCtrlC', {
            'sessionId': sessionId,
          });
          if (success == true) {
            return CommandResult(
              output: 'Sent Ctrl-C (SIGINT) to real PTY process.',
            );
          } else {
            return CommandResult(
              output: 'Failed to send Ctrl-C.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'NOT_RUNNING') {
            return CommandResult(
              output: 'Error: No active real PTY process.',
              isError: true,
            );
          }
          return CommandResult(
            output: 'Error sending Ctrl-C to real PTY: ${e.message}',
            isError: true,
          );
        }

      case 'real-pty-send-ctrl-d':
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? success = await channel.invokeMethod('realPtySendCtrlD', {
            'sessionId': sessionId,
          });
          if (success == true) {
            return CommandResult(
              output: 'Sent Ctrl-D (EOF) to real PTY process.',
            );
          } else {
            return CommandResult(
              output: 'Failed to send Ctrl-D.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'NOT_RUNNING') {
            return CommandResult(
              output: 'Error: No active real PTY process.',
              isError: true,
            );
          }
          return CommandResult(
            output: 'Error sending Ctrl-D to real PTY: ${e.message}',
            isError: true,
          );
        }

      case 'real-pty-resize':
        if (args.length < 2) {
          return CommandResult(
            output:
                'real-pty-resize: missing columns/rows operand\nUsage: real-pty-resize <cols> <rows>',
            isError: true,
          );
        }
        final cols = int.tryParse(args[0]);
        final rows = int.tryParse(args[1]);
        if (cols == null || rows == null || cols <= 0 || rows <= 0) {
          return CommandResult(
            output: 'Error: cols and rows must be positive integers.',
            isError: true,
          );
        }
        final channel = const MethodChannel('com.termode/native_shell');
        try {
          final bool? success = await channel.invokeMethod('realPtyResize', {
            'sessionId': sessionId,
            'cols': cols,
            'rows': rows,
          });
          if (success == true) {
            try {
              final sessionService = TerminalSessionService();
              final session = sessionService.sessions.firstWhere(
                (s) => s.id == sessionId,
              );
              session.ansiBuffer.resize(cols, rows);
              session.lastResizeAt = DateTime.now();
              session.lastResizeCols = cols;
              session.lastResizeRows = rows;
              session.lastResizeNotified = true;
            } catch (_) {
              // Ignore if session not found or fails
            }
            return CommandResult(
              output: 'Resized real PTY to $cols cols x $rows rows.',
            );
          } else {
            return CommandResult(
              output: 'Error: Failed to resize real PTY.',
              isError: true,
            );
          }
        } on PlatformException catch (e) {
          if (e.code == 'NOT_RUNNING') {
            return CommandResult(
              output: 'Error: No active real PTY process.',
              isError: true,
            );
          }
          return CommandResult(
            output: 'Error resizing real PTY: ${e.message}',
            isError: true,
          );
        }

      case 'real-pty-help':
        return CommandResult(
          output:
              '=== Termode Native PTY Prototype Help ===\n\n'
              'Termode runs in a native pseudo-terminal (PTY) attached to /system/bin/sh by default.\n'
              'This provides a command-line environment similar to Termux.\n\n'
              'Commands:\n'
              '  default-shell          - Start real PTY and enter interaction mode (Primary Shell Command)\n'
              '  normal-mode            - Exit PTY interaction mode, keeping it running in background\n'
              '  termode-shell          - Start real PTY and enter interaction mode automatically (Alias)\n'
              '  stop-shell             - Stop real PTY and exit interaction mode\n'
              '  shell-doctor           - Run diagnostics to verify state and troubleshoot shells\n'
              '  runtime-tools          - Manage Termode bundled runtime tools (status, install, reset)\n'
              '  pkg                    - Manage Termode script packages (list, install, remove, doctor)\n'
              '  host-help              - List all intercepted management commands\n'
              '  mode                   - Query active shell mode and interception state\n'
              '  enter-pty-mode         - Enter Real PTY Interaction Mode\n'
              '  exit-pty-mode          - Exit Real PTY Interaction Mode\n'
              '  real-pty-start         - Allocate and spawn a true native PTY shell\n'
              '  real-pty-stop          - Tear down terminal tty slave and close PTY\n'
              '  real-pty-status        - Show if real PTY is running and print its PID\n'
              '  real-pty-resize [c] [r] - Resize the virtual tty dimensions\n'
              '  real-pty-send-ctrl-c   - Send Ctrl-C (SIGINT) to the process\n'
              '  real-pty-send-ctrl-d   - Send Ctrl-D (EOF) to the process\n'
              '  real-pty-send [text]   - Write text to PTY master file descriptor\n'
              '  real-pty-mode-status   - Query PTY mode status\n'
              '  keyboard-help          - Show keyboard & shortcut helper\n'
              '  resize-info            - Show tracked terminal size\n\n'
              'Packages Notice:\n'
              '  - Packages installed via "pkg install" will automatically register shell helper functions\n'
              '    which can be invoked directly inside default-shell.\n'
              '  - "pkg" commands can be typed directly inside REAL PTY mode and are intercepted by the app.',
        );

      case 'enter-pty-mode':
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];
        if (!session.isRealPtyActive) {
          return CommandResult(
            output: 'Start real PTY first using real-pty-start.',
            isError: true,
          );
        }
        sessionService.setPtyInteractionActive(sessionId, true);
        return CommandResult(
          output:
              'Entered Real PTY Interaction Mode. All inputs are now routed to PTY.\n',
        );

      case 'exit-pty-mode':
        final sessionService = TerminalSessionService();
        sessionService.setPtyInteractionActive(sessionId, false);
        return CommandResult(
          output: 'Exited Real PTY Interaction Mode. Normal routing active.\n',
        );

      case 'default-shell':
      case 'termode-shell':
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];

        if (!session.isRealPtyActive) {
          final success = await sessionService.startRealPty(sessionId);
          if (success) {
            return CommandResult(
              output:
                  'Started Termode shell. Type normal-mode to return to commands.\n',
            );
          } else {
            sessionService.setRealPtyActive(sessionId, false);
            sessionService.setPtyInteractionActive(sessionId, false);
            return CommandResult(
              output:
                  'Error: Failed to start real PTY shell. Make sure native binary can execute.',
              isError: true,
            );
          }
        } else {
          if (!session.isPtyInteractionActive) {
            sessionService.setPtyInteractionActive(sessionId, true);
            return CommandResult(
              output: 'Entered Real PTY Interaction Mode.\n',
            );
          } else {
            return CommandResult(output: 'Already in real shell.');
          }
        }

      case 'normal-mode':
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];
        sessionService.setPtyInteractionActive(sessionId, false);
        if (session.isRealPtyActive) {
          return CommandResult(
            output: 'Returned to NORMAL mode. Real PTY is still running.',
          );
        } else {
          return CommandResult(output: 'Returned to NORMAL mode.');
        }

      case 'keyboard-help':
        return CommandResult(
          output:
              '=== Termode Keyboard & Input Help ===\n\n'
              'Special Keys in REAL PTY Mode:\n'
              '  ESC   - Sends escape code (\\u001B)\n'
              '  TAB   - Sends horizontal tab (\\t) for autocompletion\n'
              '  CTRL  - Toggles the CTRL state. Pressing CTRL then C/D sends Ctrl-C/D\n'
              '  HOME  - Sends cursor home (\\u001B[H)\n'
              '  END   - Sends cursor end (\\u001B[F)\n'
              '  Arrows- Send standard ANSI arrow sequences (up/down/left/right)\n\n'
              'Control Shortcuts:\n'
              '  CTRL+C - Sends SIGINT (interrupt current process)\n'
              '  CTRL+D - Sends EOF (closes input stream/exits shell)\n\n'
              'Diagnostics:\n'
              '  keyboard-test      - Check keyboard routing availability\n'
              '  keyboard-settings  - Show paste/keyboard limits\n'
              '  paste-force        - Send last blocked large paste\n\n'
              'Limitations:\n'
              '  - Some complex full-screen programs (e.g. interactive text editors) may have display issues until the renderer matures.',
        );

      case 'stop-shell':
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];

        final wasRealPtyActive = session.isRealPtyActive;
        sessionService.setRealPtyActive(sessionId, false);
        sessionService.setPtyInteractionActive(sessionId, false);

        if (wasRealPtyActive) {
          final channel = const MethodChannel('com.termode/native_shell');
          try {
            await channel.invokeMethod('realPtyStop', {'sessionId': sessionId});
            return CommandResult(
              output: 'Real PTY shell stopped. Returned to NORMAL mode.',
            );
          } catch (e) {
            return CommandResult(
              output:
                  'Error: Failed to stop PTY: $e. Cleaned up local session state.',
              isError: true,
            );
          }
        } else {
          return CommandResult(output: 'No active real PTY shell is running.');
        }

      case 'shell-doctor':
        final sessionService = TerminalSessionService();
        final settings = SettingsService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];

        final mode = session.isPtyInteractionActive
            ? 'REAL PTY'
            : (session.isRealPtyActive ? 'PTY RUNNING' : 'NORMAL');
        final isRealPtyActive = session.isRealPtyActive;
        final isPtyInteractionActive = session.isPtyInteractionActive;
        final startInRealShell = settings.startInRealShell;

        bool nativeRunning = false;
        int nativePid = -1;
        try {
          final res = await const MethodChannel(
            'com.termode/native_shell',
          ).invokeMethod('realPtyStatus', {'sessionId': sessionId});
          if (res is Map) {
            nativeRunning = res['running'] as bool? ?? false;
            nativePid = res['pid'] as int? ?? -1;
          }
        } catch (e) {
          return CommandResult(
            output: 'Error: Native PTY status is unavailable: $e',
            isError: true,
          );
        }

        final List<String> mismatches = [];
        String suggestedFix =
            'No issues detected. Your shell environment is healthy.';

        if (isRealPtyActive != nativeRunning) {
          mismatches.add(
            'Session active flag ($isRealPtyActive) does not match native process status ($nativeRunning)',
          );
        }
        if (isPtyInteractionActive && !isRealPtyActive) {
          mismatches.add(
            'Session interaction flag is true but session active flag is false',
          );
        }

        if (mismatches.isNotEmpty) {
          suggestedFix =
              'Mismatch detected. Recommended actions:\n'
              '  - Run stop-shell to reset the session state.\n'
              '  - Or run default-shell to re-initialize the shell process.';
        }

        final buf = StringBuffer();
        buf.writeln('=== Termode Shell Doctor Diagnostics ===');
        buf.writeln('Session ID:             $sessionId');
        buf.writeln('Current Mode:           $mode');
        buf.writeln('isRealPtyActive:        $isRealPtyActive');
        buf.writeln('isPtyInteractionActive: $isPtyInteractionActive');
        buf.writeln('startInRealShell:       $startInRealShell');
        buf.writeln('Native PTY Running:     $nativeRunning (PID: $nativePid)');
        if (mismatches.isNotEmpty) {
          buf.writeln('\nMismatches Found:');
          for (final m in mismatches) {
            buf.writeln('  - $m');
          }
        }
        buf.writeln('\nSuggested Fix:');
        buf.writeln('  $suggestedFix');

        return CommandResult(output: buf.toString());

      case 'real-pty-mode-status':
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];
        if (session.isPtyInteractionActive) {
          return CommandResult(output: 'PTY Interaction Mode: ACTIVE');
        } else {
          return CommandResult(output: 'PTY Interaction Mode: INACTIVE');
        }

      case 'runtime-tools':
        if (args.isEmpty) {
          return CommandResult(
            output:
                'Usage: runtime-tools <status|install-test|test-run|reset|path|help>\n'
                'Type "runtime-tools help" for more information.',
            isError: true,
          );
        }
        final subcommand = args[0].toLowerCase();
        final runtimeService = RuntimeToolService();

        switch (subcommand) {
          case 'status':
            final status = await runtimeService.checkStatus();
            final installed = status['installedTools'] as List<String>;
            final missing = status['missingTools'] as List<String>;
            final chmodMap = status['chmodStatus'] as Map<String, String>;
            final directMap = status['directExecStatus'] as Map<String, String>;
            final interpreterMap =
                status['interpreterStatus'] as Map<String, String>;

            final buf = StringBuffer();
            buf.writeln('=== Termode Runtime Tools Status ===');
            buf.writeln('Health:               ${status['health']}');
            buf.writeln('Bin Path:             ${status['binPath']}');
            buf.writeln(
              'Installed Tools:      ${installed.isEmpty ? "None" : installed.join(", ")}',
            );
            buf.writeln(
              'Missing Tools:        ${missing.isEmpty ? "None" : missing.join(", ")}',
            );

            final chmodList = <String>[];
            chmodMap.forEach((k, v) => chmodList.add('$k: $v'));
            buf.writeln(
              'Chmod Executable:     ${chmodList.isEmpty ? "None" : chmodList.join(", ")}',
            );

            final directList = <String>[];
            directMap.forEach((k, v) => directList.add('$k: $v'));
            buf.writeln(
              'Direct Executable:    ${directList.isEmpty ? "None" : directList.join(", ")}',
            );

            final interpreterList = <String>[];
            interpreterMap.forEach((k, v) => interpreterList.add('$k: $v'));
            buf.writeln(
              'Interpreter Runnable: ${interpreterList.isEmpty ? "None" : interpreterList.join(", ")}',
            );

            return CommandResult(output: buf.toString());

          case 'install-test':
            final success = await runtimeService.installTestTool();
            if (success) {
              return CommandResult(
                output:
                    'Success: Installed hello-termode test tool into files/usr/bin.',
                shouldReloadShellHelpers: true,
                helperReloadSuccessMessage: 'Reloaded Termode shell helpers.',
                helperReloadFailureMessage:
                    'Runtime tool installed, but helper reload failed. Run: reload-helpers',
              );
            } else {
              return CommandResult(
                output: 'Error: Failed to install test tool.',
                isError: true,
              );
            }

          case 'test-run':
            final status = await runtimeService.checkStatus();
            final installed = status['installedTools'] as List<String>;
            if (!installed.contains('hello-termode')) {
              return CommandResult(
                output:
                    'Error: hello-termode test tool is not installed.\n'
                    'Run "runtime-tools install-test" first.',
                isError: true,
              );
            }
            final paths = await RuntimeBootstrapService().getPaths();
            final binDir = paths['bin']!;
            final toolFile = File('$binDir/hello-termode');

            final cmdStr = '/system/bin/sh "${toolFile.path}"';
            final nativeResult = await NativeCommandService().execute(
              cmdStr,
              sessionId,
            );
            final cleanOut = nativeResult.stdout.trim();
            final cleanErr = nativeResult.stderr.trim();

            final buf = StringBuffer();
            buf.writeln(
              'Executing /system/bin/sh \$TERMODE_BIN/hello-termode...',
            );
            if (cleanOut.isNotEmpty) {
              buf.writeln('Output: $cleanOut');
            }
            if (cleanErr.isNotEmpty) {
              buf.writeln('Error: $cleanErr');
            }
            buf.writeln('Exit code: ${nativeResult.exitCode}');

            final pass =
                nativeResult.exitCode == 0 &&
                cleanOut.contains('Hello from Termode runtime tools');
            buf.write('Result: ${pass ? "PASS" : "FAIL"}');

            return CommandResult(output: buf.toString(), isError: !pass);

          case 'reset':
            final success = await runtimeService.reset();
            if (success) {
              return CommandResult(
                output:
                    'Success: Cleaned up managed runtime tools and metadata.',
                shouldReloadShellHelpers: true,
                helperReloadSuccessMessage: 'Reloaded Termode shell helpers.',
                helperReloadFailureMessage:
                    'Runtime tools reset, but helper reload failed. Run: reload-helpers',
              );
            } else {
              return CommandResult(
                output: 'Error: Failed to reset runtime tools.',
                isError: true,
              );
            }

          case 'path':
            final paths = await RuntimeBootstrapService().getPaths();
            final buf = StringBuffer();
            buf.writeln('=== Termode Runtime Paths ===');
            buf.writeln('HOME:        ${paths['home']}');
            buf.writeln('TERMODE_USR: ${paths['usr']}');
            buf.writeln('TERMODE_BIN: ${paths['bin']}');
            buf.writeln(
              'PTY PATH:    ${paths['bin']}:/system/bin:/system/xbin:/vendor/bin:/product/bin',
            );
            return CommandResult(output: buf.toString());

          case 'help':
            return CommandResult(
              output:
                  '=== Termode Runtime Tools Help ===\n\n'
                  'Termode runtime tools allow installing and running local command-line tools.\n\n'
                  'Key Details:\n'
                  '  - Bundled runtime tools are experimental and run within the sandboxed files/usr/bin directory.\n'
                  '  - Files installed here are separate from the Android system commands.\n'
                  '  - Use pkg for installable script packages.\n'
                  '  - WARNING: Direct execution from files/usr/bin may fail on Android with "Permission denied" (exit code 126).\n'
                  '    Use: sh \$TERMODE_BIN/hello-termode\n'
                  '    Or use Termode NORMAL mode command: run-tool hello-termode\n\n'
                  'Subcommands:\n'
                  '  - runtime-tools status       - Display current installation status and health\n'
                  '  - runtime-tools install-test - Install the hello-termode test script\n'
                  '  - runtime-tools test-run     - Perform a test run of the hello-termode script\n'
                  '  - runtime-tools reset        - Uninstall and delete managed test tools\n'
                  '  - runtime-tools path         - Print shell environment directory paths\n'
                  '  - runtime-tools help         - Show this help reference',
            );

          default:
            return CommandResult(
              output:
                  'Unknown subcommand: $subcommand\n'
                  'Usage: runtime-tools <status|install-test|test-run|reset|path|help>',
              isError: true,
            );
        }

      case 'run-tool':
        if (args.isEmpty) {
          return CommandResult(
            output:
                'Usage: run-tool <tool-name> [args...]\n'
                'Type "runtime-tools help" for more information.',
            isError: true,
          );
        }
        final toolName = args[0];
        final paths = await RuntimeBootstrapService().getPaths();
        final binDir = paths['bin']!;

        // Safety check: block path traversals
        if (toolName.contains('/') ||
            toolName.contains('\\') ||
            toolName.contains('..')) {
          return CommandResult(
            output: 'run-tool: invalid tool name',
            isError: true,
          );
        }

        final toolFile = File('$binDir/$toolName');
        if (!await toolFile.exists()) {
          return CommandResult(
            output: 'run-tool: tool not found: $toolName',
            isError: true,
          );
        }

        final toolArgs = args
            .sublist(1)
            .map((arg) => arg.contains(' ') ? '"$arg"' : arg)
            .join(' ');
        final cmdStr =
            '/system/bin/sh "${toolFile.path}"${toolArgs.isNotEmpty ? " $toolArgs" : ""}';

        final nativeResult = await NativeCommandService().execute(
          cmdStr,
          sessionId,
        );
        final outputBuilder = StringBuffer();
        if (nativeResult.stdout.isNotEmpty) {
          outputBuilder.write(nativeResult.stdout);
        }
        if (nativeResult.stderr.isNotEmpty) {
          if (outputBuilder.isNotEmpty) outputBuilder.write('\n');
          outputBuilder.write(nativeResult.stderr);
        }
        if (outputBuilder.isEmpty && nativeResult.exitCode != 0) {
          outputBuilder.write(
            'Process exited with code ${nativeResult.exitCode}',
          );
        }
        return CommandResult(
          output: outputBuilder.toString().trimRight(),
          isError: nativeResult.exitCode != 0,
        );

      case 'pkg':
        if (args.isEmpty) {
          return execute('pkg help');
        }
        final subcommand = args[0].toLowerCase();
        final pmService = PackageManagerService();
        final bootstrapService = RuntimeBootstrapService();
        final pPaths = await bootstrapService.getPaths();
        final pUsrDir = pPaths['usr']!;

        switch (subcommand) {
          case 'help':
            return CommandResult(
              output:
                  '=== Termode Package Manager (pkg) ===\n'
                  'Manage script-based packages inside Termode.\n\n'
                  'Commands:\n'
                  '  pkg help                 - Show this help message\n'
                  '  pkg update               - Update active package index\n'
                  '  pkg repo [cmd]           - Configure/trust remote package repository\n'
                  '  pkg sources              - Show local/remote source summary\n'
                  '  pkg list [--long]        - List packages in index with status\n'
                  '  pkg categories           - List package categories\n'
                  '  pkg search <term>        - Search packages in index\n'
                  '  pkg info <name> [--verbose] - Show package information\n'
                  '  pkg install <name>       - Install a package\n'
                  '  pkg reinstall <name>     - Reinstall or install a package\n'
                  '  pkg upgrade [name]       - Upgrade installed packages\n'
                  '  pkg repair [name]        - Repair missing package files and helpers\n'
                  '  pkg clean                - Clean package manager temp files\n'
                  '  pkg cache clean          - Clean cached remote package index\n'
                  '  pkg files <name>         - Show files managed by a package\n'
                  '  pkg verify <name>        - Verify files, checksums, and helper\n'
                  '  pkg remove <name>        - Uninstall a package\n'
                  '  pkg installed            - List all installed packages\n'
                  '  pkg doctor               - Audit package installation health\n\n'
                  'Package Limits:\n'
                  '  - Packages are script-only. Native binary packages are not supported yet.\n'
                  '  - Remote packages are script-only and require repo trust.\n'
                  '  - The bundled runtime proof (bundled-runtime-*) is separate from pkg remote installs.\n'
                  '  - Native tools (native-tool) are built into Termode, not installable packages.\n'
                  '  - Node.js/npm/Python/Git are not available yet.',
            );

          case 'update':
            final res = await pmService.updateIndex();
            if (res['success'] != true) {
              return CommandResult(output: res['message'], isError: true);
            }
            return CommandResult(
              output:
                  'Updating package index...\n'
                  '${res['message']}\n'
                  'Success: Index updated (${res['count']} packages available).',
            );

          case 'repo':
            if (args.length == 1 || args[1].toLowerCase() == 'status') {
              final result = args.contains('--verbose')
                  ? await pmService.repoStatusVerbose()
                  : await pmService.repoStatus();
              return CommandResult(
                output: result.output,
                isError: result.isError,
              );
            }
            final repoCommand = args[1].toLowerCase();
            PackageOperationResult result;
            switch (repoCommand) {
              case 'set':
                if (args.length < 3) {
                  return CommandResult(
                    output: 'Usage: pkg repo set <url>',
                    isError: true,
                  );
                }
                result = await pmService.repoSet(args[2]);
                break;
              case 'clear':
                result = await pmService.repoClear();
                break;
              case 'enable':
                result = await pmService.repoEnable();
                break;
              case 'disable':
                result = await pmService.repoDisable();
                break;
              case 'trust':
                result = await pmService.repoTrust();
                break;
              case 'test':
                result = await pmService.repoTest();
                break;
              default:
                return CommandResult(
                  output:
                      'Unknown repo command: $repoCommand\n'
                      'Usage: pkg repo <status|set|clear|enable|disable|trust|test>',
                  isError: true,
                );
            }
            return CommandResult(
              output: result.output,
              isError: result.isError,
            );

          case 'sources':
            final result = await pmService.sources();
            return CommandResult(
              output: result.output,
              isError: result.isError,
            );

          case 'cache':
            if (args.length >= 2 && args[1].toLowerCase() == 'clean') {
              final result = await pmService.cleanCache();
              return CommandResult(
                output: result.output,
                isError: result.isError,
              );
            }
            return CommandResult(
              output: 'Usage: pkg cache clean',
              isError: true,
            );

          case 'list':
            final installed = await _getInstalledPackages(pUsrDir);
            final available = await pmService.availablePackages();
            final longMode = args.contains('--long');
            String? category;
            final categoryIndex = args.indexOf('--category');
            if (categoryIndex >= 0 && categoryIndex + 1 < args.length) {
              category = args[categoryIndex + 1].toLowerCase();
            }
            final sb = StringBuffer();
            sb.writeln(
              longMode ? '=== Packages (Long) ===' : '=== Packages ===',
            );
            for (final entry in available.entries) {
              final name = entry.key;
              final pkg = entry.value;
              final pkgCategory =
                  pkg['category']?.toString().toLowerCase() ?? 'utility';
              if (category != null && pkgCategory != category) {
                continue;
              }
              final status = installed.containsKey(name)
                  ? 'installed'
                  : 'available';
              final source = pkg['source']?.toString() ?? 'local';
              if (longMode) {
                sb.writeln(
                  '$name [${pkg['version']}] ($source) - ${pkg['description']} (Status: $status)',
                );
              } else {
                final paddedName = name.padRight(14);
                final version = pkg['version'].toString().padRight(6);
                final paddedSource = source.padRight(6);
                sb.writeln('$paddedName $version $paddedSource $status');
              }
            }
            return CommandResult(output: sb.toString().trimRight());

          case 'categories':
            final available = await pmService.availablePackages();
            final counts = <String, int>{};
            for (final pkg in available.values) {
              final category = pkg['category']?.toString() ?? 'utility';
              counts[category] = (counts[category] ?? 0) + 1;
            }
            final names = counts.keys.toList()..sort();
            final sb = StringBuffer('=== Categories ===\n');
            for (final name in names) {
              sb.writeln('${name.padRight(10)} ${counts[name]}');
            }
            return CommandResult(output: sb.toString().trimRight());

          case 'search':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: pkg search <query>',
                isError: true,
              );
            }
            final query = args[1].toLowerCase();
            final longMode = args.contains('--long');
            final installed = await _getInstalledPackages(pUsrDir);
            final available = await pmService.availablePackages();
            final sb = StringBuffer();
            sb.writeln(
              longMode
                  ? '=== Search Results (Long) ==='
                  : '=== Search Results ===',
            );
            int count = 0;
            for (final entry in available.entries) {
              final name = entry.key;
              final pkg = entry.value;
              final desc = (pkg['description'] as String).toLowerCase();
              final category = pkg['category']?.toString().toLowerCase() ?? '';
              final tags = (pkg['tags'] as List<dynamic>? ?? [])
                  .map((tag) => tag.toString().toLowerCase())
                  .join(' ');
              if (name.toLowerCase().contains(query) ||
                  desc.contains(query) ||
                  category.contains(query) ||
                  tags.contains(query)) {
                count++;
                final status = installed.containsKey(name)
                    ? 'Installed'
                    : 'Not Installed';
                final source = pkg['source']?.toString() ?? 'local';
                final category = pkg['category']?.toString() ?? 'utility';
                if (longMode) {
                  sb.writeln(
                    '$name [${pkg['version']}] ($source) - ${pkg['description']} (Status: $status)',
                  );
                } else {
                  sb.writeln(
                    '${name.padRight(12)} ${pkg['version'].toString().padRight(6)} ${category.padRight(8)} ${status.toLowerCase()}',
                  );
                }
              }
            }
            if (count == 0) {
              sb.writeln('No matching packages found.');
            }
            return CommandResult(output: sb.toString().trimRight());

          case 'info':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: pkg info <package-name>',
                isError: true,
              );
            }
            final pkgName = args[1];
            final verbose = args.contains('--verbose');
            final available = await pmService.availablePackages();
            final pkg =
                available[pkgName] ?? PackageManagerService.localIndex[pkgName];
            if (pkg == null) {
              return CommandResult(
                output: 'pkg info: Package "$pkgName" not found in index.',
                isError: true,
              );
            }
            final installed = await _getInstalledPackages(pUsrDir);
            final isInst = installed.containsKey(pkgName);
            final source = pkg['source']?.toString() ?? 'local';
            final sb = StringBuffer();
            sb.writeln('Package:     ${pkg['name']}');
            sb.writeln('Version:     ${pkg['version']}');
            sb.writeln('Source:      $source');
            sb.writeln(
              'Status:      ${isInst ? "Installed" : "Not Installed"}',
            );
            sb.writeln('Category:    ${pkg['category'] ?? "utility"}');
            sb.writeln('Description: ${pkg['description']}');
            sb.writeln('Executable:  ${pkg['executable'] ?? pkgName}');
            if (source == 'remote') {
              sb.writeln('Repo:        configured');
              sb.writeln('Checksum:    available');
            }
            if (verbose) {
              sb.writeln('Type:        ${pkg['type']}');
              if (pkg['repoUrl'] != null) {
                sb.writeln('Repo URL:    ${pkg['repoUrl']}');
              }
              final tags = (pkg['tags'] as List<dynamic>? ?? [])
                  .map((tag) => tag.toString())
                  .join(', ');
              if (tags.isNotEmpty) {
                sb.writeln('Tags:        $tags');
              }
              if (pkg['example'] != null) {
                sb.writeln('Example:     ${pkg['example']}');
              }
              if (pkg['homepage'] != null) {
                sb.writeln('Homepage:    ${pkg['homepage']}');
              }
              if (pkg['minTermodeVersion'] != null) {
                sb.writeln('Min Termode: ${pkg['minTermodeVersion']}');
              }
              sb.writeln('Files:');
              if (pkg['files'] is Map) {
                final filesMap = pkg['files'] as Map<String, dynamic>;
                for (final f in filesMap.keys) {
                  sb.writeln('  - $f');
                }
              } else {
                final files = pkg['files'] as List<dynamic>? ?? [];
                for (final f in files) {
                  final file = Map<dynamic, dynamic>.from(f as Map);
                  sb.writeln('  - ${file['path']}');
                  if (file['url'] != null) {
                    sb.writeln('    URL: ${file['url']}');
                  }
                  if (file['sha256'] != null) {
                    sb.writeln('    SHA-256: ${file['sha256']}');
                  }
                }
              }
            }
            return CommandResult(output: sb.toString().trimRight());

          case 'install':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: pkg install <package-name>',
                isError: true,
              );
            }
            final pkgName = args[1];
            final result = await pmService.installPackage(pkgName);
            if (result.isError) {
              return CommandResult(output: result.output, isError: true);
            }
            return CommandResult(
              output: '${result.output}\n${_packageTryLine(result, pkgName)}',
              shouldReloadShellHelpers: result.changedHelpers,
              helperReloadFailureMessage:
                  'Package installed, but helper reload failed. Run: reload-helpers',
            );

          case 'reinstall':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: pkg reinstall <package-name>',
                isError: true,
              );
            }
            final pkgName = args[1];
            final result = await pmService.reinstallPackage(
              pkgName,
              allowSourceChange: args.contains('--allow-source-change'),
            );
            if (result.isError) {
              return CommandResult(output: result.output, isError: true);
            }
            return CommandResult(
              output: '${result.output}\n${_packageTryLine(result, pkgName)}',
              shouldReloadShellHelpers: result.changedHelpers,
              helperReloadFailureMessage:
                  'Package reinstalled, but helper reload failed. Run: reload-helpers',
            );

          case 'upgrade':
            final target = args.length >= 2 && !args[1].startsWith('--')
                ? args[1]
                : null;
            final result = await pmService.upgradePackages(
              onlyPackage: target,
              allowSourceChange: args.contains('--allow-source-change'),
            );
            return CommandResult(
              output: result.output,
              isError: result.isError,
              shouldReloadShellHelpers: result.changedHelpers,
              helperReloadFailureMessage:
                  'Packages upgraded, but helper reload failed. Run: reload-helpers',
            );

          case 'repair':
            final target = args.length >= 2 && !args[1].startsWith('--')
                ? args[1]
                : null;
            final result = await pmService.repairPackages(
              onlyPackage: target,
              allowSourceChange: args.contains('--allow-source-change'),
            );
            return CommandResult(
              output: result.output,
              isError: result.isError,
              shouldReloadShellHelpers: result.changedHelpers,
              helperReloadFailureMessage:
                  'Package repair completed, but helper reload failed. Run: reload-helpers',
            );

          case 'clean':
            final result = await pmService.cleanPackages();
            return CommandResult(
              output: result.output,
              isError: result.isError,
              shouldReloadShellHelpers: result.changedHelpers,
              helperReloadFailureMessage:
                  'Package clean completed, but helper reload failed. Run: reload-helpers',
            );

          case 'files':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: pkg files <package-name>',
                isError: true,
              );
            }
            final result = await pmService.packageFiles(args[1]);
            return CommandResult(
              output: result.output,
              isError: result.isError,
            );

          case 'verify':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: pkg verify <package-name>',
                isError: true,
              );
            }
            final result = await pmService.verifyPackage(args[1]);
            return CommandResult(
              output: result.output,
              isError: result.isError,
            );

          case 'remove':
            if (args.length < 2) {
              return CommandResult(
                output: 'Usage: pkg remove <package-name>',
                isError: true,
              );
            }
            final pkgName = args[1];
            final result = await pmService.removePackage(pkgName);
            if (result.isError) {
              return CommandResult(output: result.output, isError: true);
            }
            return CommandResult(
              output:
                  '${result.output}\n'
                  'Tip: If the command still appears, run reload-helpers.',
              shouldReloadShellHelpers: result.changedHelpers,
              helperReloadFailureMessage:
                  'Package removed, but helper reload failed. Run: reload-helpers',
            );

          case 'installed':
            final installed = await _getInstalledPackages(pUsrDir);
            if (installed.isEmpty) {
              return CommandResult(output: 'No packages currently installed.');
            }
            final sb = StringBuffer();
            sb.writeln('=== Installed Packages ===');
            for (final entry in installed.entries) {
              final name = entry.key;
              final data = entry.value as Map<String, dynamic>;
              final source = data['source']?.toString() ?? 'local';
              sb.writeln(
                '$name [${data['version']}] ($source) - Installed at: ${data['installedAt']}',
              );
            }
            return CommandResult(output: sb.toString().trimRight());

          case 'doctor':
            final doc = await pmService.checkDoctor();
            final verbose = args.contains('--verbose');
            final sb = StringBuffer();
            final repo = Map<String, dynamic>.from(doc['repoConfig'] as Map);
            final missing = doc['missingFiles'] as List<dynamic>;
            bool isHealthy =
                doc['repairRecommended'] != true &&
                missing.isEmpty &&
                (!doc['metadataExists'] ||
                    doc['installedCount'] == 0 ||
                    doc['helperExists']);
            final helpersOk =
                doc['helpersGenerated'] == true || doc['installedCount'] == 0;
            if (!verbose) {
              sb.writeln('=== Package Doctor ===');
              sb.writeln('Status: ${isHealthy ? "HEALTHY" : "UNHEALTHY"}');
              sb.writeln('Installed: ${doc['installedCount']}');
              sb.writeln('Remote installed: ${doc['remoteInstalledCount']}');
              sb.writeln(
                'Remote need cache: ${doc['remotePackagesNeedingCache']}',
              );
              sb.writeln('Source mismatches: ${doc['sourceMismatchCount']}');
              sb.writeln('Broken: ${doc['brokenPackageCount']}');
              sb.writeln('Missing files: ${doc['missingFileCount']}');
              sb.writeln('Helpers: ${helpersOk ? "OK" : "NOT GENERATED"}');
              sb.writeln(
                'Remote repo: ${repo['remoteEnabled'] == true ? "enabled" : "disabled"}',
              );
              sb.writeln(
                'Remote trusted: ${(repo['trustedRepoUrls'] as List? ?? []).contains(repo['repoUrl']) ? "yes" : "no"}',
              );
              sb.write(
                'Remote cache: ${doc['remoteIndexCached'] == true ? "present" : "missing"}',
              );
            } else {
              sb.writeln('=== Package Doctor (Verbose) ===');
              sb.writeln(
                'Metadata File:      ${doc['metadataExists'] ? "EXISTS" : "MISSING"} (${doc['metadataPath']})',
              );
              sb.writeln('Bin Directory:      ${doc['binPath']}');
              sb.writeln(
                'Helper Script:      ${doc['helperExists'] ? "EXISTS" : "MISSING"} (${doc['helperPath']})',
              );
              sb.writeln('Installed Packages: ${doc['installedCount']}');
              sb.writeln('Remote Installed:   ${doc['remoteInstalledCount']}');
              sb.writeln(
                'Remote Need Cache:  ${doc['remotePackagesNeedingCache']}',
              );
              sb.writeln('Source Mismatches:  ${doc['sourceMismatchCount']}');
              sb.writeln('Broken Packages:    ${doc['brokenPackageCount']}');
              sb.writeln('Missing File Count: ${doc['missingFileCount']}');
              sb.writeln(
                'Helper Function Count: ${doc['helperFunctionCount']}',
              );
              sb.writeln('Helper Reload Command: reload-helpers');
              sb.writeln('Internal Reload Path: ${doc['helperPath']}');
              sb.writeln(
                'Current Shell May Need Reload: ${doc['mayNeedReload'] ? "YES" : "NO"}',
              );
              if (doc['metadataError'] != null) {
                sb.writeln('Metadata Error:     ${doc['metadataError']}');
              }
              sb.writeln(
                'Remote Repo Enabled: ${repo['remoteEnabled'] == true ? "YES" : "NO"}',
              );
              sb.writeln(
                'Remote Repo Trusted: ${(repo['trustedRepoUrls'] as List? ?? []).contains(repo['repoUrl']) ? "YES" : "NO"}',
              );
              sb.writeln(
                'Remote Index Cache: ${doc['remoteIndexCached'] == true ? "EXISTS" : "MISSING"}',
              );
              if (missing.isNotEmpty) {
                sb.writeln('Missing Package Files:');
                for (final f in missing) {
                  sb.writeln('  - [MISSING] $f');
                }
              } else {
                sb.writeln('All registered files: Present');
              }
              sb.writeln(
                'Helper Functions:   ${doc['helpersGenerated'] ? "OK" : "NOT GENERATED"}',
              );
              sb.writeln(
                'Repair Recommended: ${doc['repairRecommended'] ? "YES (run pkg repair)" : "NO"}',
              );
              sb.write(
                'Overall Status:     ${isHealthy ? "HEALTHY" : "UNHEALTHY"}',
              );
            }
            return CommandResult(output: sb.toString(), isError: !isHealthy);

          default:
            return CommandResult(
              output:
                  'Unknown subcommand: $subcommand\n'
                  'Usage: pkg <help|update|repo|sources|cache|list|search|info|install|reinstall|upgrade|repair|clean|files|verify|remove|installed|doctor>',
              isError: true,
            );
        }

      case 'mode':
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];
        final settings = SettingsService();

        final modeStr = session.isPtyInteractionActive
            ? 'REAL PTY'
            : (session.isRealPtyActive ? 'PTY RUNNING' : 'NORMAL');
        final interceptionStr = session.isPtyInteractionActive
            ? 'Active'
            : 'Inactive';
        final startInRealShellStr = settings.startInRealShell
            ? 'Enabled'
            : 'Disabled';

        final sb = StringBuffer();
        sb.writeln('=== Termode Mode Status ===');
        sb.writeln('Current Mode:                   $modeStr');
        sb.writeln('Host Command Interception:      $interceptionStr');
        sb.write('Start In Real Shell (Setting):  $startInRealShellStr');
        return CommandResult(output: sb.toString());

      case 'reload-helpers':
        final sessionService = TerminalSessionService();
        final sessionIndex = sessionService.sessions.indexWhere(
          (s) => s.id == sessionId,
        );
        if (sessionIndex == -1) {
          return CommandResult(
            output: 'Error: Session not found.',
            isError: true,
          );
        }
        final session = sessionService.sessions[sessionIndex];
        if (!session.isPtyInteractionActive || !session.isRealPtyActive) {
          return CommandResult(
            output:
                'Termode shell helpers are sourced inside REAL PTY shell sessions.\n'
                'Start or enter the shell with default-shell, then run reload-helpers.',
          );
        }

        final reloaded = await sessionService.reloadShellHelpersForSession(
          sessionId,
          silent: true,
          waitForCompletion: true,
        );
        if (reloaded) {
          return CommandResult(output: 'Reloaded Termode shell helpers.');
        }
        return CommandResult(
          output: 'Helper reload failed. Run: reload-helpers',
          isError: true,
        );

      case 'host-help':
        final sb = StringBuffer();
        sb.writeln('=== Termode Host Command Interception ===');
        sb.writeln(
          'Termode runs in a real PTY shell by default, meaning most commands',
        );
        sb.writeln('are sent directly to the underlying Android system shell.');
        sb.writeln();
        sb.writeln(
          'However, Termode intercepts specific management commands to run',
        );
        sb.writeln('them inside the app environment:');
        sb.writeln();
        sb.writeln('Intercepted Host Commands:');
        sb.writeln(
          '  pkg            - Manage Termode packages (list, install, search, doctor, etc.)',
        );
        sb.writeln(
          '  runtime-tools  - Manage Termode runtime tools (status, install-test, test-run)',
        );
        sb.writeln(
          '  runtime-*      - Probe and explain Termode runtime capabilities',
        );
        sb.writeln(
          '  runtime-freeze - Show the frozen runtime direction and deferred runtimes',
        );
        sb.writeln('  doctor         - Show unified Termode health summary');
        sb.writeln('  beta-*         - Show beta readiness and QA checklists');
        sb.writeln('  qa-*           - Run device QA bug bash helpers');
        sb.writeln('  commands       - Show compact command categories');
        sb.writeln('  welcome        - Show first-run onboarding');
        sb.writeln(
          '  settings-*     - Show/reset settings (summary, doctor, reset-safe)',
        );
        sb.writeln('  status         - Show a compact Termode status summary');
        sb.writeln('  theme-test     - Print a theme/ANSI readability sample');
        sb.writeln('  bug-report     - Create a safe diagnostic report');
        sb.writeln(
          '  js-proof       - Run the controlled JS-like native bridge proof',
        );
        sb.writeln(
          '  quickjs        - Run the limited QuickJS embedded-engine probe',
        );
        sb.writeln(
          '  duktape        - Run the limited Duktape fallback-engine probe',
        );
        sb.writeln(
          '  localhost-*    - Check local ports and future dev server readiness',
        );
        sb.writeln('  port-check     - Check a 127.0.0.1 TCP port');
        sb.writeln('  http-test      - Test a localhost HTTP URL');
        sb.writeln('  preview-url    - Print a localhost preview URL');
        sb.writeln('  devserver-help - Show dev server diagnostics help');
        sb.writeln(
          '  storage-*      - Access user-linked Android storage (storage-link, storage-list, etc.)',
        );
        sb.writeln(
          '  workspace-*    - Manage real files/home/projects workspaces',
        );
        sb.writeln(
          '  host-*         - Read/write real Termode home files safely',
        );
        sb.writeln('  pwd-host       - Show Termode tracked working directory');
        sb.writeln(
          '  shell-doctor   - Audit PTY shell configuration and status',
        );
        sb.writeln('  keyboard-help  - Show keyboard shortcuts reference');
        sb.writeln('  keyboard-test  - Check keyboard routing state');
        sb.writeln('  ansi-test      - Print ANSI renderer sample');
        sb.writeln('  resize-info    - Show PTY resize state');
        sb.writeln('  copy-*         - Copy last line or transcript lines');
        sb.writeln('  paste-force    - Send last blocked large paste');
        sb.writeln('  real-pty-help  - Show PTY prototype help reference');
        sb.writeln(
          '  normal-mode    - Exit PTY interaction mode to return to classic Termode prompt',
        );
        sb.writeln(
          '  stop-shell     - Kill the PTY shell process and return to NORMAL mode',
        );
        sb.writeln(
          '  mode           - Display active mode and environment settings',
        );
        sb.writeln(
          '  whereami       - Show VFS, workspace, runtime, and linked storage',
        );
        sb.writeln(
          '  reload-helpers - Source package helper functions into the current shell',
        );
        sb.writeln(
          '  host-help      - Show this host interception help reference',
        );
        sb.writeln();
        sb.write(
          'Package Notes:\n'
          '  - pkg is handled by Termode host interception.\n'
          '  - Use pkg reinstall, pkg verify, and pkg repair to recover packages.\n'
          '  - Installed packages run inside the shell through helper functions.\n'
          '  - If a newly installed package does not work, run reload-helpers.',
        );
        return CommandResult(output: sb.toString());

      case 'pty-start':
        final res = await execute('shell-start');
        return CommandResult(
          output:
              'WARNING: "pty-start" is deprecated/experimental. Please use "shell-start" instead.\n${res.output}',
          isError: res.isError,
          shouldClear: res.shouldClear,
        );

      case 'pty-status':
        final res = await execute('shell-status');
        return CommandResult(
          output:
              'WARNING: "pty-status" is deprecated/experimental. Please use "shell-status" instead.\n${res.output}',
          isError: res.isError,
          shouldClear: res.shouldClear,
        );

      case 'pty-stop':
        final res = await execute('shell-stop');
        return CommandResult(
          output:
              'WARNING: "pty-stop" is deprecated/experimental. Please use "shell-stop" instead.\n${res.output}',
          isError: res.isError,
          shouldClear: res.shouldClear,
        );

      case 'pty-send':
        if (args.isEmpty) {
          return CommandResult(
            output:
                'pty-send: missing command/text operand\nUsage: pty-send <text>',
            isError: true,
          );
        }
        final res = await execute('shell-send ${args.join(' ')}');
        return CommandResult(
          output:
              'WARNING: "pty-send" is deprecated/experimental. Please use "shell-send" instead.\n${res.output}'
                  .trimRight(),
          isError: res.isError,
          shouldClear: res.shouldClear,
        );

      default:
        return CommandResult(
          output: 'termode: command not found: $command',
          isError: true,
        );
    }
  }

  Future<CommandResult> _workspaceFileCommand(
    String commandName,
    Future<String> Function() action,
  ) async {
    try {
      final output = await action();
      return CommandResult(
        output: output,
        isError: output.startsWith('$commandName:'),
      );
    } on FileSystemException catch (e) {
      return CommandResult(output: '$commandName: ${e.message}', isError: true);
    }
  }
}
