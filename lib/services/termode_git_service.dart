import 'dart:async';
import 'dart:io';

import 'package:termode/services/git_remote_transport_service.dart';
import 'package:termode/services/native_command_service.dart';
import 'package:termode/services/runtime_binary_package_service.dart';
import 'package:termode/services/terminal_session_service.dart';

enum TermodeGitFileKind {
  staged,
  modified,
  untracked,
  deleted,
  renamed,
  conflicted,
  copied,
  unknown,
}

class TermodeGitFileEntry {
  final String relativePath;
  final String absolutePath;
  final TermodeGitFileKind kind;
  final bool hasStagedChanges;
  final bool hasUnstagedChanges;
  final String indexStatus;
  final String workTreeStatus;

  const TermodeGitFileEntry({
    required this.relativePath,
    required this.absolutePath,
    required this.kind,
    required this.hasStagedChanges,
    required this.hasUnstagedChanges,
    required this.indexStatus,
    required this.workTreeStatus,
  });

  bool get canStage => hasUnstagedChanges && kind != TermodeGitFileKind.conflicted;
  bool get canUnstage => hasStagedChanges && kind != TermodeGitFileKind.conflicted;
}

class TermodeGitBranch {
  final String name;
  final bool isCurrent;

  const TermodeGitBranch({
    required this.name,
    this.isCurrent = false,
  });
}

class TermodeGitStatusSnapshot {
  final bool isRepo;
  final String repoPath;
  final String workTreePath;
  final String? branchName;
  final List<TermodeGitBranch> branches;
  final List<TermodeGitFileEntry> files;
  final Map<String, String> remotes;
  final String? upstream;
  final int ahead;
  final int behind;
  final bool isClean;

  const TermodeGitStatusSnapshot({
    required this.isRepo,
    this.repoPath = '',
    this.workTreePath = '',
    this.branchName,
    this.branches = const [],
    this.files = const [],
    this.remotes = const {},
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.isClean = true,
  });

  static const notRepo = TermodeGitStatusSnapshot(isRepo: false);
}

class TermodeGitDiffResult {
  final bool isSupported;
  final bool isBinary;
  final String relativePath;
  final String patch;
  final String? oldText;
  final String? newText;
  final String? message;

  const TermodeGitDiffResult({
    required this.isSupported,
    required this.isBinary,
    required this.relativePath,
    required this.patch,
    this.oldText,
    this.newText,
    this.message,
  });

  bool get hasTextPair => oldText != null || newText != null;
}

/// Service exposing structured, programmatic Git operations for Termode and embedding IDEs (Calypso IDE).
class TermodeGitService {
  static final TermodeGitService _instance = TermodeGitService._internal();
  factory TermodeGitService() => _instance;
  TermodeGitService._internal();

  final RuntimeBinaryPackageService _pkg = RuntimeBinaryPackageService();
  final GitRemoteTransportService _remote = GitRemoteTransportService();

  Future<NativeCommandResult> _run(List<String> args, {String? workingDirectory}) async {
    return _pkg.runGit(args, workingDirectory: workingDirectory);
  }

  /// Resolves the effective working directory.
  String _resolveCwd(String? dir) {
    if (dir != null && dir.isNotEmpty) return dir;
    final session = TerminalSessionService().activeSession;
    return session.preferredWorkingDirectory ?? Directory.current.path;
  }

  /// Checks if the target directory is inside an active Git work tree.
  Future<bool> isInsideWorkTree({String? workingDirectory}) async {
    final cwd = _resolveCwd(workingDirectory);
    final res = await _run(['rev-parse', '--is-inside-work-tree'], workingDirectory: cwd);
    return res.exitCode == 0 && res.stdout.trim() == 'true';
  }

  /// Gets the top-level root directory of the Git repository.
  Future<String?> getRepoRoot({String? workingDirectory}) async {
    final cwd = _resolveCwd(workingDirectory);
    final res = await _run(['rev-parse', '--show-toplevel'], workingDirectory: cwd);
    return res.exitCode == 0 ? res.stdout.trim() : null;
  }

  /// Returns full structured status snapshot for the repository.
  Future<TermodeGitStatusSnapshot> getStatus({String? workingDirectory}) async {
    final cwd = _resolveCwd(workingDirectory);
    final inside = await isInsideWorkTree(workingDirectory: cwd);
    if (!inside) {
      return TermodeGitStatusSnapshot.notRepo;
    }

    final toplevel = (await getRepoRoot(workingDirectory: cwd)) ?? cwd;
    final gitDirRes = await _run(['rev-parse', '--git-dir'], workingDirectory: toplevel);
    final gitDir = gitDirRes.exitCode == 0 ? gitDirRes.stdout.trim() : '$toplevel/.git';

    // Query status in machine-readable porcelain format with branch details
    final statusRes = await _run(['status', '--porcelain=v1', '-b', '-u'], workingDirectory: toplevel);
    final lines = statusRes.stdout.split('\n');

    String? branchName;
    String? upstream;
    int ahead = 0;
    int behind = 0;
    final files = <TermodeGitFileEntry>[];

    for (final rawLine in lines) {
      if (rawLine.trim().isEmpty) continue;

      if (rawLine.startsWith('## ')) {
        final bLine = rawLine.substring(3).trim();
        if (bLine.startsWith('Initial commit on ') || bLine.startsWith('No commits yet on ')) {
          branchName = bLine.split(' ').last;
        } else {
          final branchPart = bLine.split(' ')[0];
          if (branchPart.contains('...')) {
            final parts = branchPart.split('...');
            branchName = parts[0];
            upstream = parts.length > 1 ? parts[1] : null;
          } else {
            branchName = branchPart;
          }

          final aheadMatch = RegExp(r'ahead (\d+)').firstMatch(bLine);
          if (aheadMatch != null) ahead = int.tryParse(aheadMatch.group(1) ?? '0') ?? 0;

          final behindMatch = RegExp(r'behind (\d+)').firstMatch(bLine);
          if (behindMatch != null) behind = int.tryParse(behindMatch.group(1) ?? '0') ?? 0;
        }
        continue;
      }

      if (rawLine.length < 3) continue;
      final x = rawLine[0];
      final y = rawLine[1];
      var relPath = rawLine.substring(3).trim();
      if (relPath.contains(' -> ')) {
        relPath = relPath.split(' -> ').last.trim();
      }
      if (relPath.startsWith('"') && relPath.endsWith('"')) {
        relPath = relPath.substring(1, relPath.length - 1);
      }

      final absPath = '$toplevel/$relPath';
      final hasStaged = x != ' ' && x != '?';
      final hasUnstaged = y != ' ' && y != '?';

      TermodeGitFileKind kind;
      if (x == '?' && y == '?') {
        kind = TermodeGitFileKind.untracked;
      } else if (x == 'U' || y == 'U' || (x == 'A' && y == 'A') || (x == 'D' && y == 'D')) {
        kind = TermodeGitFileKind.conflicted;
      } else if (x == 'D' || y == 'D') {
        kind = TermodeGitFileKind.deleted;
      } else if (x == 'R' || y == 'R') {
        kind = TermodeGitFileKind.renamed;
      } else if (x == 'C' || y == 'C') {
        kind = TermodeGitFileKind.copied;
      } else if (x == 'M' || y == 'M') {
        kind = TermodeGitFileKind.modified;
      } else if (x == 'A') {
        kind = TermodeGitFileKind.staged;
      } else {
        kind = TermodeGitFileKind.unknown;
      }

      files.add(
        TermodeGitFileEntry(
          relativePath: relPath,
          absolutePath: absPath,
          kind: kind,
          hasStagedChanges: hasStaged,
          hasUnstagedChanges: hasUnstaged || kind == TermodeGitFileKind.untracked,
          indexStatus: x,
          workTreeStatus: y,
        ),
      );
    }

    final branches = await getBranches(workingDirectory: toplevel);
    final remotes = await _remote.listRemotes(workingDirectory: toplevel);

    return TermodeGitStatusSnapshot(
      isRepo: true,
      repoPath: gitDir,
      workTreePath: toplevel,
      branchName: branchName ?? (branches.where((b) => b.isCurrent).firstOrNull?.name ?? 'main'),
      branches: branches,
      files: files,
      remotes: remotes,
      upstream: upstream,
      ahead: ahead,
      behind: behind,
      isClean: files.isEmpty,
    );
  }

  /// Lists all local branches.
  Future<List<TermodeGitBranch>> getBranches({String? workingDirectory}) async {
    final cwd = _resolveCwd(workingDirectory);
    final res = await _run(['branch', '--list', '--no-color'], workingDirectory: cwd);
    if (res.exitCode != 0) return [];

    final list = <TermodeGitBranch>[];
    for (final line in res.stdout.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final isCurrent = line.startsWith('* ');
      final name = isCurrent ? line.substring(2).trim() : trimmed;
      list.add(TermodeGitBranch(name: name, isCurrent: isCurrent));
    }
    return list;
  }

  /// Retrieves the current branch name.
  Future<String?> getCurrentBranch({String? workingDirectory}) async {
    final cwd = _resolveCwd(workingDirectory);
    final res = await _run(['rev-parse', '--abbrev-ref', 'HEAD'], workingDirectory: cwd);
    return res.exitCode == 0 && res.stdout.trim().isNotEmpty ? res.stdout.trim() : null;
  }

  /// Fetches diff for a file (or entire repo) comparing working tree to HEAD, or staged changes.
  Future<TermodeGitDiffResult> getDiff({
    required String relativePath,
    String? workingDirectory,
    String? commitSha,
    bool staged = false,
  }) async {
    final cwd = _resolveCwd(workingDirectory);
    final toplevel = (await getRepoRoot(workingDirectory: cwd)) ?? cwd;
    final file = File('$toplevel/$relativePath');

    // Get old/base content
    String? oldText;
    final showArgs = <String>['show'];
    if (commitSha != null && commitSha.isNotEmpty) {
      showArgs.add('$commitSha:$relativePath');
    } else if (staged) {
      showArgs.add('HEAD:$relativePath');
    } else {
      showArgs.add(':$relativePath');
    }

    final oldRes = await _run(showArgs, workingDirectory: toplevel);
    if (oldRes.exitCode == 0) {
      oldText = oldRes.stdout;
    }

    // Get new content
    String? newText;
    if (staged) {
      final stagedRes = await _run(['show', ':$relativePath'], workingDirectory: toplevel);
      if (stagedRes.exitCode == 0) newText = stagedRes.stdout;
    } else if (await file.exists()) {
      try {
        newText = await file.readAsString();
      } catch (_) {
        return TermodeGitDiffResult(
          isSupported: true,
          isBinary: true,
          relativePath: relativePath,
          patch: '',
          message: 'Binary file differences cannot be displayed as text.',
        );
      }
    }

    // Generate patch
    final diffArgs = <String>['diff'];
    if (staged) {
      diffArgs.add('--staged');
    }
    if (commitSha != null && commitSha.isNotEmpty) {
      diffArgs.add('$commitSha^..$commitSha');
    }
    diffArgs.addAll(['--', relativePath]);

    final diffRes = await _run(diffArgs, workingDirectory: toplevel);
    final patch = diffRes.stdout;

    return TermodeGitDiffResult(
      isSupported: true,
      isBinary: false,
      relativePath: relativePath,
      patch: patch,
      oldText: oldText,
      newText: newText,
    );
  }

  /// Stages specific files or all files.
  Future<NativeCommandResult> stage(List<String> paths, {String? workingDirectory}) async {
    final cwd = _resolveCwd(workingDirectory);
    if (paths.isEmpty || (paths.length == 1 && (paths.first == '.' || paths.first == '-A'))) {
      return _run(['add', '-A'], workingDirectory: cwd);
    }
    return _run(['add', '-A', '--', ...paths], workingDirectory: cwd);
  }

  /// Unstages specific files or all files.
  Future<NativeCommandResult> unstage(List<String> paths, {String? workingDirectory}) async {
    final cwd = _resolveCwd(workingDirectory);
    if (paths.isEmpty || (paths.length == 1 && paths.first == '.')) {
      return _run(['restore', '--staged', '.'], workingDirectory: cwd);
    }
    return _run(['restore', '--staged', '--', ...paths], workingDirectory: cwd);
  }

  /// Commits staged changes with a commit message.
  Future<NativeCommandResult> commit(
    String message, {
    String? workingDirectory,
    String? author,
  }) async {
    final cwd = _resolveCwd(workingDirectory);
    final args = <String>['commit', '-m', message];
    if (author != null && author.isNotEmpty) {
      args.addAll(['--author', author]);
    }
    return _run(args, workingDirectory: cwd);
  }

  /// Checks out an existing branch or creates a new one.
  Future<NativeCommandResult> checkout(
    String branch, {
    bool create = false,
    String? workingDirectory,
  }) async {
    final cwd = _resolveCwd(workingDirectory);
    final args = create ? ['checkout', '-b', branch] : ['checkout', branch];
    return _run(args, workingDirectory: cwd);
  }

  /// Pushes local commits to remote repository via Smart-HTTP.
  Future<GitRemoteResult> push({
    String remote = 'origin',
    String? branch,
    bool force = false,
    String? workingDirectory,
    void Function(String message)? onProgress,
  }) async {
    final cwd = _resolveCwd(workingDirectory);
    return _remote.push(
      remote,
      branch: branch,
      force: force,
      workingDirectory: cwd,
      onProgress: onProgress,
    );
  }

  /// Pulls remote commits and fast-forwards/updates working tree.
  Future<GitRemoteResult> pull({
    String remote = 'origin',
    String? branch,
    String? workingDirectory,
    void Function(String message)? onProgress,
  }) async {
    final cwd = _resolveCwd(workingDirectory);
    return _remote.pull(
      remote,
      branch: branch,
      workingDirectory: cwd,
      onProgress: onProgress,
    );
  }

  /// Fetches remote commits without updating working tree.
  Future<GitRemoteResult> fetch({
    String remote = 'origin',
    String? branch,
    String? workingDirectory,
    void Function(String message)? onProgress,
  }) async {
    final cwd = _resolveCwd(workingDirectory);
    return _remote.fetch(
      remote,
      branch: branch,
      workingDirectory: cwd,
      onProgress: onProgress,
    );
  }
}
