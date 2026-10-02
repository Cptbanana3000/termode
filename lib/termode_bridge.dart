import 'dart:async';
import 'dart:io';

import 'models/terminal_session.dart';
import 'services/command_service.dart';
import 'services/dev_server_service.dart';
import 'services/dev_stack_service.dart';
import 'services/localhost_service.dart';
import 'services/native_command_service.dart';
import 'services/npm_package_service.dart';
import 'services/osint_service.dart';
import 'services/pip_package_service.dart';
import 'services/python_environment_service.dart';
import 'services/runtime_binary_package_service.dart';
import 'services/runtime_bootstrap_service.dart';
import 'services/settings_service.dart';
import 'services/terminal_session_service.dart';
import 'services/virtual_filesystem.dart';
import 'services/workspace_service.dart';
import 'services/file_explorer_service.dart';
import 'services/port_monitor_service.dart';
import 'services/git_remote_transport_service.dart';
import 'services/git_credential_service.dart';
import 'services/git_ssh_service.dart';
import 'services/termode_git_service.dart';

export 'services/termode_git_service.dart';
export 'services/git_remote_transport_service.dart' show GitRemoteResult, GitRemoteRefAdvertisement;
export 'services/git_credential_service.dart' show GitCredential;
export 'services/git_ssh_service.dart' show SshKeyPair;

/// Public, headless integration bridge for Termode.
///
/// Allows external applications and IDEs (such as Calypso IDE) to directly
/// embed and interact with Termode's execution engine, terminal sessions,
/// npm package manager, Python 3.14 environment, dev servers, and dev stack presets
/// without IPC, intents, or external processes.
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

  /// Direct access to Python runtime environment and script execution.
  PythonEnvironmentService get python => PythonEnvironmentService();

  /// Direct access to pip package management and wheel operations.
  PipPackageService get pip => PipPackageService();

  /// Direct access to OSINT tools (Sherlock / Maigret).
  OsintService get osint => OsintService();

  /// Direct access to background dev servers supervision.
  DevServerService get devServers => DevServerService();

  /// Direct access to localhost and port inspection.
  LocalhostService get localhost => LocalhostService();

  /// Direct access to developer stack presets and scaffolding.
  DevStackService get stacks => DevStackService();

  /// Direct access to runtime package queries (Git, Node, npm).
  RuntimeBinaryPackageService get packages => RuntimeBinaryPackageService();

  /// Direct access to structured Git service (status, diff, staging, commits, branches).
  TermodeGitService get git => TermodeGitService();

  /// Direct access to authentic Git remote operations and transports.
  GitRemoteTransportService get gitRemote => GitRemoteTransportService();

  /// Direct access to Git credential storage (~/.git-credentials).
  GitCredentialService get gitCredentials => GitCredentialService();

  /// Direct access to Ed25519 SSH keypair generation and management.
  GitSshService get ssh => GitSshService();

  /// Direct access to the visual file explorer and workspace file system.
  FileExplorerService get files => FileExplorerService();

  /// Direct access to the active port and dev server monitor.
  PortMonitorService get portMonitor => PortMonitorService();

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

  /// Executes a command and streams output as text chunks.
  Stream<String> executeStream(
    String command, {
    String? workingDirectory,
    String? sessionId,
  }) async* {
    final result = await execute(
      command,
      workingDirectory: workingDirectory,
      sessionId: sessionId,
    );
    yield result.output;
  }

  /// Direct headless execution of Python scripts or modules.
  Future<NativeCommandResult> runPython(
    List<String> args, {
    String? workingDirectory,
    int timeoutMs = 60000,
  }) {
    return python.executePython(
      args,
      workingDirectory: workingDirectory,
      timeoutMs: timeoutMs,
    );
  }

  /// Direct headless execution of pip package manager commands.
  Future<NativeCommandResult> runPip(
    List<String> args, {
    String? workingDirectory,
    int timeoutMs = 120000,
  }) {
    return packages.runPip(
      args,
      workingDirectory: workingDirectory,
      timeoutMs: timeoutMs,
    );
  }

  /// Direct headless execution of Node.js scripts or modules.
  Future<NativeCommandResult> runNode(
    List<String> args, {
    String? workingDirectory,
    int timeoutMs = 60000,
  }) {
    return packages.runNode(
      args,
      workingDirectory: workingDirectory,
      timeoutMs: timeoutMs,
    );
  }

  /// Direct headless execution of local Git commands.
  Future<NativeCommandResult> runGit(
    List<String> args, {
    String? workingDirectory,
  }) {
    return packages.runGit(
      args,
      workingDirectory: workingDirectory,
    );
  }

  /// Programmatically queries structured Git status for a repository.
  Future<TermodeGitStatusSnapshot> getGitStatus({String? workingDirectory}) =>
      git.getStatus(workingDirectory: workingDirectory);

  /// Programmatically queries file diff (working tree vs HEAD or staged).
  Future<TermodeGitDiffResult> getGitDiff({
    required String relativePath,
    String? workingDirectory,
    String? commitSha,
    bool staged = false,
  }) => git.getDiff(
        relativePath: relativePath,
        workingDirectory: workingDirectory,
        commitSha: commitSha,
        staged: staged,
      );

  /// Programmatically stages files (`git add`).
  Future<NativeCommandResult> gitStage(List<String> paths, {String? workingDirectory}) =>
      git.stage(paths, workingDirectory: workingDirectory);

  /// Programmatically unstages files (`git restore --staged`).
  Future<NativeCommandResult> gitUnstage(List<String> paths, {String? workingDirectory}) =>
      git.unstage(paths, workingDirectory: workingDirectory);

  /// Programmatically commits staged changes.
  Future<NativeCommandResult> gitCommit(
    String message, {
    String? workingDirectory,
    String? author,
  }) => git.commit(message, workingDirectory: workingDirectory, author: author);

  /// Programmatically pushes local commits via Smart-HTTP.
  Future<GitRemoteResult> gitPush({
    String remote = 'origin',
    String? branch,
    bool force = false,
    String? workingDirectory,
    void Function(String message)? onProgress,
  }) => git.push(
        remote: remote,
        branch: branch,
        force: force,
        workingDirectory: workingDirectory,
        onProgress: onProgress,
      );

  /// Programmatically pulls remote commits.
  Future<GitRemoteResult> gitPull({
    String remote = 'origin',
    String? branch,
    String? workingDirectory,
    void Function(String message)? onProgress,
  }) => git.pull(
        remote: remote,
        branch: branch,
        workingDirectory: workingDirectory,
        onProgress: onProgress,
      );

  /// Programmatically fetches remote commits.
  Future<GitRemoteResult> gitFetch({
    String remote = 'origin',
    String? branch,
    String? workingDirectory,
    void Function(String message)? onProgress,
  }) => git.fetch(
        remote: remote,
        branch: branch,
        workingDirectory: workingDirectory,
        onProgress: onProgress,
      );

  /// Programmatically lists local branches.
  Future<List<TermodeGitBranch>> getGitBranches({String? workingDirectory}) =>
      git.getBranches(workingDirectory: workingDirectory);

  /// Programmatically checks out a branch.
  Future<NativeCommandResult> gitCheckout(
    String branch, {
    bool create = false,
    String? workingDirectory,
  }) => git.checkout(branch, create: create, workingDirectory: workingDirectory);

  /// Direct headless execution of npm commands.
  Future<NativeCommandResult> runNpm(
    List<String> args, {
    String? workingDirectory,
    int timeoutMs = 120000,
  }) {
    return packages.runNpm(
      args,
      workingDirectory: workingDirectory,
      timeoutMs: timeoutMs,
    );
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
    final pythonInstalled = await python.isPythonAvailable();
    final pipInstalled = await pip.isPipAvailable();
    final osintDoc = await osint.doctor();
    final stackDoc = await stacks.doctor(workingDirectory: cwd);
    final npmDoc = await npm.doctor(workingDirectory: cwd);
    final activeServers = await devServers.listServers();

    return {
      'milestone': 'v0.68',
      'engineMilestone': 'v0.83',
      'engine': 'Termode In-Process Native Engine',
      'initialized': _initialized,
      'activeWorkingDirectory': cwd,
      'runtimes': {
        'git': gitInstalled ? 'INSTALLED (arm64-v8a + Smart-HTTP)' : 'AVAILABLE (not installed)',
        'node': nodeInstalled ? 'INSTALLED' : 'PROTOTYPE (v0.66)',
        'npm': npmInstalled ? 'INSTALLED' : 'PROTOTYPE (v0.67)',
        'python': pythonInstalled ? 'INSTALLED (3.14)' : 'NOT_INSTALLED',
        'pip': pipInstalled ? 'INSTALLED (26.2)' : 'NOT_INSTALLED',
        'osint': osintDoc.sherlockReady ? 'READY' : 'NEEDS_SETUP',
      },
      'git': {
        'installed': gitInstalled,
        'remoteTransport': 'Smart-HTTP side-band-64k',
        'hasSshKey': await ssh.hasKeyPair(),
      },
      'servers': {
        'activeDevServers': activeServers.length,
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
