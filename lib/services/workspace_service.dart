import 'dart:io';

import 'package:flutter/services.dart';

import 'runtime_bootstrap_service.dart';
import 'storage_access_service.dart';
import 'terminal_session_service.dart';

class WorkspaceService {
  static final WorkspaceService _instance = WorkspaceService._internal();
  factory WorkspaceService() => _instance;
  WorkspaceService._internal();

  final RuntimeBootstrapService _runtime = RuntimeBootstrapService();

  Future<Map<String, String>> paths() async {
    final runtimePaths = await _runtime.getPaths();
    final home = Directory(runtimePaths['home']!);
    final projectsRoot = Directory('${home.path}/projects');
    if (!home.existsSync()) {
      home.createSync(recursive: true);
    }
    if (!projectsRoot.existsSync()) {
      projectsRoot.createSync(recursive: true);
    }
    return {
      'home': home.absolute.path,
      'projectsRoot': projectsRoot.absolute.path,
    };
  }

  Future<Directory> projectsRoot() async {
    final p = await paths();
    return Directory(p['projectsRoot']!);
  }

  String? validateWorkspaceName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'workspace name is required';
    if (trimmed.contains('/') || trimmed.contains(r'\')) {
      return 'workspace name cannot contain slashes';
    }
    if (trimmed == '.' || trimmed == '..' || trimmed.startsWith('.')) {
      return 'workspace name is not safe';
    }
    if (trimmed.contains('..')) return 'workspace name cannot contain ..';
    final allowed = RegExp(r'^[A-Za-z0-9._-]+$');
    if (!allowed.hasMatch(trimmed)) {
      return 'workspace name can use letters, numbers, dot, dash, underscore';
    }
    return null;
  }

  Future<Directory?> workspaceDirectory(String name) async {
    if (validateWorkspaceName(name) != null) return null;
    final root = await projectsRoot();
    final dir = Directory(
      _normalizePath(
        Directory(
          '${root.path}${Platform.pathSeparator}${name.trim()}',
        ).absolute.path,
      ),
    );
    if (!isInside(dir.path, root.path)) return null;
    return dir;
  }

  bool isInside(String candidate, String root) {
    final candidatePath = _normalizePath(Directory(candidate).absolute.path);
    final rootPath = _normalizePath(Directory(root).absolute.path);
    return candidatePath == rootPath ||
        candidatePath.startsWith('$rootPath${Platform.pathSeparator}');
  }

  String _normalizePath(String path) {
    final slashPath = path.replaceAll(r'\', '/');
    final isAbsolute = slashPath.startsWith('/');
    final parts = <String>[];
    for (final part in slashPath.split('/')) {
      if (part.isEmpty || part == '.') {
        continue;
      }
      if (part == '..') {
        if (parts.isNotEmpty && parts.last != '..') {
          parts.removeLast();
        } else if (!isAbsolute) {
          parts.add(part);
        }
        continue;
      }
      parts.add(part);
    }
    final joined = parts.join(Platform.pathSeparator);
    return isAbsolute ? '${Platform.pathSeparator}$joined' : joined;
  }

  bool _containsParentTraversal(String path) {
    return path.replaceAll(r'\', '/').split('/').contains('..');
  }

  Future<String> currentWorkspaceName() async {
    final session = TerminalSessionService().activeSession;
    final root = await projectsRoot();
    final preferred = session.preferredWorkingDirectory;
    if (preferred != null && isInside(preferred, root.path)) {
      final relative = preferred.substring(root.path.length).trimLeft();
      final clean = relative
          .replaceFirst(RegExp(r'^[\\/]+'), '')
          .split(RegExp(r'[\\/]'))
          .first;
      if (clean.isNotEmpty) return clean;
    }
    return '(none)';
  }

  Future<String> workspaceStatus() async {
    final root = await projectsRoot();
    final current = await currentWorkspaceName();
    final projectCount = await _projectNames(
      root,
    ).then((names) => names.length);
    return 'Workspace: $current\nProjects: $projectCount\nRoot: ${root.path}';
  }

  Future<String> workspaceInfo() async {
    final runtimePaths = await paths();
    final sessionService = TerminalSessionService();
    final session = sessionService.activeSession;
    final storageStatus = await _storageLinkedText();
    final projectCount = (await _projectNames(
      Directory(runtimePaths['projectsRoot']!),
    )).length;
    return [
      'Current workspace: ${await currentWorkspaceName()}',
      'Workspace root: ${runtimePaths['projectsRoot']}',
      'Current directory: ${trackedWorkingDirectory()}',
      'Storage linked: $storageStatus',
      'Project count: $projectCount',
      if (session.preferredWorkingDirectory != null)
        'Preferred directory: ${session.preferredWorkingDirectory}',
    ].join('\n');
  }

  String trackedWorkingDirectory() {
    final session = TerminalSessionService().activeSession;
    return session.lastKnownWorkingDirectory ??
        session.preferredWorkingDirectory ??
        '(home)';
  }

  Future<String> initWorkspace(String name) async {
    final err = validateWorkspaceName(name);
    if (err != null) return 'workspace-init: $err';
    final dir = await workspaceDirectory(name);
    if (dir == null) return 'workspace-init: unsafe workspace path';
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final meta = File('${dir.path}/.termode-project');
    if (!meta.existsSync()) {
      meta.writeAsStringSync(
        'name=${name.trim()}\ncreatedAt=${DateTime.now().toIso8601String()}\n',
      );
    }
    return 'Workspace ready: ${name.trim()}';
  }

  Future<String> listWorkspaces() async {
    final root = await projectsRoot();
    final names = await _projectNames(root);
    if (names.isEmpty) return 'No workspaces.';
    return names.join('\n');
  }

  Future<(bool, String, Directory?)> setWorkspace(String name) async {
    final err = validateWorkspaceName(name);
    if (err != null) return (false, 'workspace-cd: $err', null);
    final dir = await workspaceDirectory(name);
    if (dir == null || !dir.existsSync()) {
      return (false, 'workspace-cd: workspace not found: ${name.trim()}', null);
    }
    final sessionService = TerminalSessionService();
    sessionService.setPreferredWorkingDirectory(dir.path);
    if (sessionService.activeSession.isPtyInteractionActive) {
      await sessionService.sendCdToRealPty(dir.path);
      return (true, 'Workspace: ${name.trim()}', dir);
    }
    return (true, 'Workspace selected for next shell: ${name.trim()}', dir);
  }

  Future<String> removeWorkspace(String name, {required bool confirmed}) async {
    final err = validateWorkspaceName(name);
    if (err != null) return 'workspace-remove: $err';
    if (!confirmed) {
      return 'This will remove workspace "$name".\nRun: workspace-remove $name --confirm';
    }
    final root = await projectsRoot();
    final dir = await workspaceDirectory(name);
    if (dir == null || !isInside(dir.path, root.path)) {
      return 'workspace-remove: unsafe workspace path';
    }
    if (!dir.existsSync()) return 'workspace-remove: workspace not found';
    dir.deleteSync(recursive: true);
    return 'Removed workspace: ${name.trim()}';
  }

  Future<String> doctor({bool verbose = false}) async {
    final runtimePaths = await paths();
    final home = Directory(runtimePaths['home']!);
    final root = Directory(runtimePaths['projectsRoot']!);
    final current = await currentWorkspaceName();
    final currentDir =
        TerminalSessionService().activeSession.preferredWorkingDirectory;
    final pathsSafe =
        currentDir == null ||
        isInside(currentDir, home.path) ||
        isInside(currentDir, root.path);
    final metaOk =
        current == '(none)' ||
        File('${root.path}/$current/.termode-project').existsSync();
    final storage = await _storageLinkedText();
    final healthy =
        home.existsSync() && root.existsSync() && pathsSafe && metaOk;
    final sb = StringBuffer();
    sb.writeln('=== Workspace Doctor ===');
    sb.writeln('Home: ${home.existsSync() ? "OK" : "MISSING"}');
    sb.writeln('Projects root: ${root.existsSync() ? "OK" : "MISSING"}');
    sb.writeln('Current workspace: ${metaOk ? "OK" : "CHECK"}');
    sb.writeln('Storage: $storage');
    sb.writeln('Paths: ${pathsSafe ? "safe" : "unsafe"}');
    if (verbose) {
      sb.writeln('Home path: ${home.path}');
      sb.writeln('Projects path: ${root.path}');
      sb.writeln('Tracked cwd: ${trackedWorkingDirectory()}');
    }
    sb.write('Overall: ${healthy ? "HEALTHY" : "UNHEALTHY"}');
    return sb.toString();
  }

  Future<String> hostPwd() async {
    final dir = await resolveHostPath('.');
    return dir.path;
  }

  Future<Directory> resolveHostPath(String input) async {
    final runtimePaths = await paths();
    final home = Directory(runtimePaths['home']!);
    final session = TerminalSessionService().activeSession;
    final base =
        session.preferredWorkingDirectory != null &&
            isInside(session.preferredWorkingDirectory!, home.path)
        ? Directory(session.preferredWorkingDirectory!)
        : home;
    final raw = input.trim().isEmpty ? '.' : input.trim();
    if (_containsParentTraversal(raw)) {
      throw FileSystemException(
        'relative path traversal is not allowed',
        input,
      );
    }
    final candidate = Directory(raw).isAbsolute
        ? Directory(raw).absolute
        : Directory('${base.path}/$raw').absolute;
    if (!isInside(candidate.path, home.path)) {
      throw FileSystemException('path escapes Termode home', input);
    }
    return candidate;
  }

  Future<File> resolveHostFile(String input) async {
    final dir = await resolveHostPath('.');
    if (_containsParentTraversal(input)) {
      throw FileSystemException(
        'relative path traversal is not allowed',
        input,
      );
    }
    final candidate = File(input).isAbsolute
        ? File(input).absolute
        : File('${dir.path}/${input.trim()}').absolute;
    final runtimePaths = await paths();
    if (!isInside(candidate.path, runtimePaths['home']!)) {
      throw FileSystemException('path escapes Termode home', input);
    }
    return candidate;
  }

  Future<String> hostLs([String path = '.']) async {
    final dir = await resolveHostPath(path);
    if (!dir.existsSync()) return 'host-ls: not found';
    final names =
        dir
            .listSync()
            .map((entity) => entity.path.split(Platform.pathSeparator).last)
            .toList()
          ..sort();
    return names.isEmpty ? '(empty)' : names.join('\n');
  }

  Future<String> hostCat(String path) async {
    final file = await resolveHostFile(path);
    if (!file.existsSync()) return 'host-cat: not found';
    return file.readAsStringSync();
  }

  Future<String> hostWrite(String path, String text) async {
    final file = await resolveHostFile(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
    return 'Wrote ${text.length} characters to $path.';
  }

  Future<String> hostTouch(String path) async {
    final file = await resolveHostFile(path);
    file.parent.createSync(recursive: true);
    if (!file.existsSync()) file.writeAsStringSync('');
    file.setLastModifiedSync(DateTime.now());
    return 'Touched $path.';
  }

  Future<String> hostMkdir(String path) async {
    final dir = await resolveHostPath(path);
    dir.createSync(recursive: true);
    return 'Created directory $path.';
  }

  Future<String> hostRm(String path) async {
    final runtimePaths = await _runtime.getPaths();
    final workspacePaths = await paths();
    final currentDirectory =
        TerminalSessionService().activeSession.preferredWorkingDirectory;
    final protectedRoots = [
      workspacePaths['home']!,
      workspacePaths['projectsRoot']!,
      ?currentDirectory,
      runtimePaths['usr']!,
      runtimePaths['bin']!,
      '${runtimePaths['usr']}/termode-packages.json',
      '${runtimePaths['usr']}/termode-shell-helpers.sh',
      '${runtimePaths['usr']}/termode-repo.json',
    ];
    final raw = path.trim();
    final absoluteRaw = File(raw).isAbsolute ? File(raw).absolute.path : null;
    for (final protected in protectedRoots) {
      if (absoluteRaw == File(protected).absolute.path ||
          (absoluteRaw != null && isInside(absoluteRaw, protected))) {
        return 'host-rm: protected Termode file';
      }
    }

    final target = await resolveHostPath(path);
    final targetPath = _normalizePath(target.path);
    for (final protected in protectedRoots) {
      if (targetPath == _normalizePath(Directory(protected).absolute.path)) {
        return 'host-rm: protected Termode path';
      }
    }

    final file = File(targetPath);
    if (!file.existsSync()) {
      final dir = Directory(targetPath);
      if (!dir.existsSync()) return 'host-rm: not found';
      if (dir.listSync().isNotEmpty) {
        return 'host-rm: directory not empty';
      }
      dir.deleteSync();
      return 'Removed directory $path.';
    }
    file.deleteSync();
    return 'Removed $path.';
  }

  Future<String> storageProjects() async {
    final storage = StorageAccessService();
    final files = await storage.listFiles();
    if (files == null || files.isEmpty) return 'No storage projects.';
    final dirs =
        files
            .where((name) => !name.contains('.') && !name.contains('/'))
            .toList()
          ..sort();
    return dirs.isEmpty ? 'No storage projects.' : dirs.join('\n');
  }

  Future<String> importStorage(String source, String workspaceName) async {
    final init = await initWorkspace(workspaceName);
    if (init.startsWith('workspace-init:')) return init;
    final dir = await workspaceDirectory(workspaceName);
    if (dir == null) return 'workspace-import-storage: unsafe workspace path';
    final storage = StorageAccessService();
    final files = await storage.listFiles() ?? const [];
    var copied = 0;
    for (final name in files) {
      if (name.contains('/') || name.contains(r'\')) continue;
      if (name == source || name.startsWith('$source-')) {
        String? content;
        try {
          content = await storage.readFile(name);
        } on PlatformException {
          continue;
        }
        if (content == null) continue;
        File('${dir.path}/$name').writeAsStringSync(content);
        copied++;
      }
    }
    return 'Imported $copied file(s) into $workspaceName. Shallow import only.';
  }

  Future<String> exportStorage(
    String workspaceName,
    String storageFolder, {
    required bool overwrite,
  }) async {
    final dir = await workspaceDirectory(workspaceName);
    if (dir == null || !dir.existsSync()) {
      return 'workspace-export-storage: workspace not found';
    }
    final storage = StorageAccessService();
    final existing = await storage.listFiles() ?? const [];
    var copied = 0;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name == '.termode-project') continue;
      final target = '$storageFolder-$name';
      if (!overwrite && existing.contains(target)) continue;
      final ok = await storage.writeFile(target, entity.readAsStringSync());
      if (ok) copied++;
    }
    return 'Exported $copied file(s) to linked storage.';
  }

  Future<List<String>> _projectNames(Directory root) async {
    if (!root.existsSync()) return const [];
    final names =
        root
            .listSync()
            .whereType<Directory>()
            .map((dir) => dir.path.split(Platform.pathSeparator).last)
            .where((name) => validateWorkspaceName(name) == null)
            .toList()
          ..sort();
    return names;
  }

  Future<String> _storageLinkedText() async {
    try {
      final status = await StorageAccessService().getStatus();
      return status == null ? 'no' : 'yes';
    } on PlatformException {
      return 'error';
    }
  }
}
