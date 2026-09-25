import 'dart:io';
import 'package:flutter/foundation.dart';
import 'runtime_bootstrap_service.dart';

enum FileCategory {
  directory,
  python,
  javascript,
  shell,
  json,
  markdown,
  c,
  text,
  image,
  binary,
}

class FileEntryItem {
  final String path;
  final String name;
  final String extension;
  final bool isDirectory;
  final int sizeInBytes;
  final DateTime lastModified;
  final FileCategory category;

  const FileEntryItem({
    required this.path,
    required this.name,
    required this.extension,
    required this.isDirectory,
    required this.sizeInBytes,
    required this.lastModified,
    required this.category,
  });

  String get formattedSize {
    if (isDirectory) return '';
    if (sizeInBytes < 1024) return '$sizeInBytes B';
    if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedDate {
    final y = lastModified.year.toString().padLeft(4, '0');
    final m = lastModified.month.toString().padLeft(2, '0');
    final d = lastModified.day.toString().padLeft(2, '0');
    final h = lastModified.hour.toString().padLeft(2, '0');
    final min = lastModified.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  bool get isEditableText {
    if (isDirectory) return false;
    return category == FileCategory.python ||
        category == FileCategory.javascript ||
        category == FileCategory.shell ||
        category == FileCategory.json ||
        category == FileCategory.markdown ||
        category == FileCategory.c ||
        category == FileCategory.text;
  }

  bool get canRunInTerminal {
    if (isDirectory) return false;
    return category == FileCategory.python ||
        category == FileCategory.javascript ||
        category == FileCategory.shell;
  }
}

class BreadcrumbItem {
  final String label;
  final String path;

  const BreadcrumbItem({required this.label, required this.path});
}

class FileExplorerService extends ChangeNotifier {
  static final FileExplorerService _instance = FileExplorerService._internal();
  factory FileExplorerService() => _instance;
  FileExplorerService._internal();

  Directory? _overrideHomeDir;
  Directory? _currentDirectory;

  @visibleForTesting
  set overrideHomeDir(Directory? dir) {
    _overrideHomeDir = dir;
    _currentDirectory = dir;
    notifyListeners();
  }

  Future<Directory> getHomeDirectory() async {
    if (_overrideHomeDir != null) {
      return _overrideHomeDir!;
    }
    try {
      final paths = await RuntimeBootstrapService().getPaths();
      final home = Directory(paths['home']!);
      if (!home.existsSync()) {
        home.createSync(recursive: true);
      }
      return home;
    } catch (_) {
      return Directory.current;
    }
  }

  Future<Directory> getCurrentDirectory() async {
    if (_currentDirectory != null && _currentDirectory!.existsSync()) {
      return _currentDirectory!;
    }
    final home = await getHomeDirectory();
    _currentDirectory = home;
    return home;
  }

  void setCurrentDirectory(Directory dir) {
    _currentDirectory = dir;
    notifyListeners();
  }

  FileCategory detectCategory(String filename, bool isDir) {
    if (isDir) return FileCategory.directory;
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == 0) {
      // Check common dotfiles / extensionless scripts
      final lower = filename.toLowerCase();
      if (lower == 'makefile' || lower == 'dockerfile' || lower == '.env') {
        return FileCategory.text;
      }
      return FileCategory.binary;
    }

    final ext = filename.substring(dotIndex + 1).toLowerCase();
    switch (ext) {
      case 'py':
      case 'pyw':
        return FileCategory.python;
      case 'js':
      case 'mjs':
      case 'cjs':
      case 'ts':
        return FileCategory.javascript;
      case 'sh':
      case 'bash':
      case 'zsh':
        return FileCategory.shell;
      case 'json':
        return FileCategory.json;
      case 'md':
      case 'markdown':
        return FileCategory.markdown;
      case 'c':
      case 'h':
      case 'cpp':
      case 'hpp':
      case 'cc':
        return FileCategory.c;
      case 'txt':
      case 'log':
      case 'yaml':
      case 'yml':
      case 'toml':
      case 'ini':
      case 'conf':
      case 'cfg':
      case 'env':
      case 'dart':
      case 'html':
      case 'css':
      case 'xml':
      case 'sql':
        return FileCategory.text;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
      case 'svg':
        return FileCategory.image;
      default:
        return FileCategory.binary;
    }
  }

  Future<List<FileEntryItem>> listDirectory({
    Directory? directory,
    bool showHidden = false,
  }) async {
    final targetDir = directory ?? await getCurrentDirectory();
    if (!targetDir.existsSync()) {
      return [];
    }

    try {
      final entities = targetDir.listSync(followLinks: false);
      final List<FileEntryItem> dirs = [];
      final List<FileEntryItem> files = [];

      for (final entity in entities) {
        final name = entity.path.split(RegExp(r'[\\/]')).last;
        if (!showHidden && name.startsWith('.')) {
          continue;
        }

        final isDir = entity is Directory;
        int size = 0;
        DateTime modified = DateTime.now();

        try {
          final stat = entity.statSync();
          size = stat.size;
          modified = stat.modified;
        } catch (_) {}

        final ext = isDir || !name.contains('.') ? '' : name.split('.').last;
        final item = FileEntryItem(
          path: entity.path,
          name: name,
          extension: ext,
          isDirectory: isDir,
          sizeInBytes: size,
          lastModified: modified,
          category: detectCategory(name, isDir),
        );

        if (isDir) {
          dirs.add(item);
        } else {
          files.add(item);
        }
      }

      dirs.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      files.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      return [...dirs, ...files];
    } catch (e) {
      debugPrint('FileExplorerService listDirectory error: $e');
      return [];
    }
  }

  Future<List<BreadcrumbItem>> getBreadcrumbs([Directory? directory]) async {
    final home = await getHomeDirectory();
    final current = directory ?? await getCurrentDirectory();

    final homePath = home.absolute.path.replaceAll(r'\', '/');
    final currentPath = current.absolute.path.replaceAll(r'\', '/');

    final breadcrumbs = <BreadcrumbItem>[];

    if (currentPath == homePath) {
      breadcrumbs.add(BreadcrumbItem(label: '~', path: home.path));
      return breadcrumbs;
    }

    if (currentPath.startsWith('$homePath/')) {
      breadcrumbs.add(BreadcrumbItem(label: '~', path: home.path));
      final relative = currentPath.substring(homePath.length + 1);
      final segments = relative.split('/');

      var accumulated = homePath;
      for (final seg in segments) {
        accumulated += '/$seg';
        breadcrumbs.add(
          BreadcrumbItem(
            label: seg,
            path: Directory(accumulated).path,
          ),
        );
      }
      return breadcrumbs;
    }

    // Outside home (e.g. root or custom path)
    final segments = currentPath.split('/').where((s) => s.isNotEmpty).toList();
    var acc = '';
    for (final seg in segments) {
      acc += '/$seg';
      breadcrumbs.add(
        BreadcrumbItem(
          label: seg,
          path: Directory(acc).path,
        ),
      );
    }
    return breadcrumbs;
  }

  Future<File> createFile(
    Directory parent,
    String name, [
    String initialContent = '',
  ]) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const FormatException('File name cannot be empty');
    }
    if (cleanName.contains('/') || cleanName.contains(r'\')) {
      throw const FormatException('File name cannot contain path separators');
    }

    final file = File('${parent.path}${Platform.pathSeparator}$cleanName');
    if (file.existsSync()) {
      throw FileSystemException('File already exists', file.path);
    }

    file.writeAsStringSync(initialContent);
    notifyListeners();
    return file;
  }

  Future<Directory> createDirectory(Directory parent, String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const FormatException('Directory name cannot be empty');
    }
    if (cleanName.contains('/') || cleanName.contains(r'\')) {
      throw const FormatException(
        'Directory name cannot contain path separators',
      );
    }

    final dir = Directory('${parent.path}${Platform.pathSeparator}$cleanName');
    if (dir.existsSync()) {
      throw FileSystemException('Directory already exists', dir.path);
    }

    dir.createSync(recursive: true);
    notifyListeners();
    return dir;
  }

  Future<FileSystemEntity> renameEntity(
    FileSystemEntity entity,
    String newName,
  ) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) {
      throw const FormatException('New name cannot be empty');
    }
    if (cleanName.contains('/') || cleanName.contains(r'\')) {
      throw const FormatException('Name cannot contain path separators');
    }

    final newPath =
        '${entity.parent.path}${Platform.pathSeparator}$cleanName';

    FileSystemEntity renamed;
    if (entity is Directory) {
      renamed = entity.renameSync(newPath);
    } else if (entity is File) {
      renamed = entity.renameSync(newPath);
    } else {
      throw UnsupportedError('Unsupported entity type');
    }

    notifyListeners();
    return renamed;
  }

  Future<void> deleteEntity(
    FileSystemEntity entity, {
    bool recursive = false,
  }) async {
    if (entity is Directory) {
      entity.deleteSync(recursive: recursive);
    } else if (entity is File) {
      entity.deleteSync();
    }
    notifyListeners();
  }

  String? resolveRunCommand(File file) {
    final name = file.path.split(RegExp(r'[\\/]')).last;
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1) return null;

    final ext = name.substring(dotIndex + 1).toLowerCase();
    switch (ext) {
      case 'py':
      case 'pyw':
        return 'python3 "$name"';
      case 'js':
      case 'mjs':
      case 'cjs':
        return 'node "$name"';
      case 'sh':
      case 'bash':
        return 'sh "$name"';
      default:
        return null;
    }
  }
}
