import 'dart:io';

import 'models/terminal_session.dart';
import 'services/command_service.dart';
import 'services/dev_stack_service.dart';
import 'services/npm_package_service.dart';
import 'services/runtime_binary_package_service.dart';
import 'services/runtime_bootstrap_service.dart';
import 'services/settings_service.dart';
import 'services/terminal_session_service.dart';
import 'services/virtual_filesystem.dart';
import 'services/workspace_service.dart';

/// Public, headless integration bridge for Termode.
///
/// Allows external applications and IDEs (such as Calypso IDE) to directly
/// embed and interact with Termode's execution engine, terminal sessions,
/// npm package manager, and dev stack presets without IPC, intents, or external processes.
class TermodeEngine {
  static final TermodeEngine instance = TermodeEngine._internal();
  factory TermodeEngine() => instance;
  TermodeEngine._internal();

  bool _initialized = false;

  /// Whether the Termode runtime engine has completed bootstrap initialization.
  bool get isInitialized => _initialized;

  /// Direct access to workspace management.
  WorkspaceService get workspaces => WorkspaceService();

  /// Direct access to npm package management and `package.json` manipulation.
  NpmPackageService get npm => NpmPackageService();

  /// Direct access to developer stack presets and scaffolding.
  DevStackService get stacks => DevStackService();

  /// Direct access to runtime package queries (Git, Node, npm).
  RuntimeBinaryPackageService get packages => RuntimeBinaryPackageService();

  /// Direct access to the terminal session manager.
  TerminalSessionService get sessions => TerminalSessionService();

  /// Active terminal session.
  TerminalSession get activeSession => TerminalSessionService().activeSession;

  /// Initializes the Termode runtime environment, settings, and prefix paths.
  Future<void> initialize({Directory? baseDir}) async {
    final runtime = RuntimeBootstrapService();
    if (baseDir != null) {
      runtime.overrideBaseDir = baseDir;
    }
    await runtime.init();
    SettingsService().loadFromJson(null);
    _initialized = true;
  }

  /// Programmatically executes a command in the Termode engine.
  ///
  /// If [workingDirectory] is provided, sets the session working directory
  /// before executing the command.
  Future<CommandResult> execute(
    String command, {
    String? workingDirectory,
    String? sessionId,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    final targetSessionId = sessionId ?? activeSession.id;
    if (workingDirectory != null) {
      final session = TerminalSessionService().getSession(targetSessionId);
      if (session != null) {
        session.preferredWorkingDirectory = workingDirectory;
      }
    }

    final vfs = VirtualFileSystem();
    final commandService = CommandService(vfs, targetSessionId);
    return commandService.execute(command);
  }

  /// Programmatically creates a new terminal session.
  TerminalSession createSession({
    String? name,
    String? workingDirectory,
  }) {
    final session = TerminalSessionService().createSession(name: name);
    if (workingDirectory != null) {
      session.preferredWorkingDirectory = workingDirectory;
    }
    return session;
  }

  /// Aggregates environment diagnostics across all subsystems.
  Future<Map<String, dynamic>> diagnostics({String? workingDirectory}) async {
    final cwd = workingDirectory ?? activeSession.preferredWorkingDirectory ?? 'app-home';
    final nodeInstalled = await packages.nodeInstalled();
    final npmInstalled = await packages.npmInstalled();
    final gitInstalled = await packages.gitInstalled();
    final stackDoc = await stacks.doctor(workingDirectory: cwd);
    final npmDoc = await npm.doctor(workingDirectory: cwd);

    return {
      'milestone': 'v0.68',
      'engine': 'Termode In-Process Native Engine',
      'initialized': _initialized,
      'activeWorkingDirectory': cwd,
      'runtimes': {
        'git': gitInstalled ? 'INSTALLED' : 'AVAILABLE (not installed)',
        'node': nodeInstalled ? 'INSTALLED' : 'PROTOTYPE (v0.66)',
        'npm': npmInstalled ? 'INSTALLED' : 'PROTOTYPE (v0.67)',
      },
      'stack': {
        'detected': stackDoc.detectedStackName ?? 'none',
        'hasPackageJson': stackDoc.hasPackageJson,
        'hasEntrypoint': stackDoc.hasEntrypoint,
        'scripts': stackDoc.availableScripts,
      },
      'npm': {
        'scriptsCount': npmDoc.scriptCount,
        'dependenciesCount': npmDoc.dependencyCount,
      },
    };
  }
}
