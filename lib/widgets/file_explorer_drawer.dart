import 'dart:io';
import 'package:flutter/material.dart';
import '../services/file_explorer_service.dart';
import '../screens/quick_editor_screen.dart';

class FileExplorerDrawer extends StatefulWidget {
  final void Function(File file)? onOpenFile;
  final void Function(Directory dir)? onDirectoryChanged;
  final void Function(Directory dir)? onOpenTerminalHere;
  final void Function(String command, String workingDirectory)? onRunInTerminal;

  const FileExplorerDrawer({
    super.key,
    this.onOpenFile,
    this.onDirectoryChanged,
    this.onOpenTerminalHere,
    this.onRunInTerminal,
  });

  @override
  State<FileExplorerDrawer> createState() => _FileExplorerDrawerState();
}

class _FileExplorerDrawerState extends State<FileExplorerDrawer> {
  final FileExplorerService _service = FileExplorerService();
  Directory? _currentDir;
  List<FileEntryItem> _items = [];
  List<BreadcrumbItem> _breadcrumbs = [];
  bool _isLoading = true;
  bool _showHidden = false;
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  Future<void> _loadDirectory([Directory? dir]) async {
    setState(() => _isLoading = true);
    final target = dir ?? await _service.getCurrentDirectory();
    _currentDir = target;
    _service.setCurrentDirectory(target);

    final items = await _service.listDirectory(
      directory: target,
      showHidden: _showHidden,
    );
    final crumbs = await _service.getBreadcrumbs(target);

    if (mounted) {
      setState(() {
        _items = items;
        _breadcrumbs = crumbs;
        _isLoading = false;
      });
      if (widget.onDirectoryChanged != null && _currentDir != null) {
        widget.onDirectoryChanged!(_currentDir!);
      }
    }
  }

  void _navigateToDir(Directory dir) {
    _loadDirectory(dir);
  }

  void _navigateUp() {
    if (_currentDir != null && _currentDir!.parent.existsSync()) {
      _loadDirectory(_currentDir!.parent);
    }
  }

  void _openFile(File file) {
    Navigator.of(context).pop(); // close drawer
    if (widget.onOpenFile != null) {
      widget.onOpenFile!(file);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => QuickEditorScreen(
            file: file,
            onRunInTerminal: widget.onRunInTerminal,
          ),
        ),
      );
    }
  }

  Future<void> _showNewFileDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final createdName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text(
          'New File',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: const InputDecoration(
              hintText: 'e.g. script.py, app.js',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2D2D2D)),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF5AF78E)),
              ),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'File name required';
              if (val.contains('/') || val.contains(r'\')) {
                return 'No slashes allowed';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5AF78E),
              foregroundColor: Colors.black,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (createdName != null && _currentDir != null) {
      try {
        final newFile = await _service.createFile(_currentDir!, createdName);
        await _loadDirectory(_currentDir);
        if (mounted) {
          _openFile(newFile);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating file: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _showNewFolderDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final createdName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text(
          'New Folder',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: const InputDecoration(
              hintText: 'e.g. src, tests, scripts',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2D2D2D)),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF5AF78E)),
              ),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Folder name required';
              }
              if (val.contains('/') || val.contains(r'\')) {
                return 'No slashes allowed';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5AF78E),
              foregroundColor: Colors.black,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (createdName != null && _currentDir != null) {
      try {
        await _service.createDirectory(_currentDir!, createdName);
        await _loadDirectory(_currentDir);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating folder: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _showRenameDialog(FileEntryItem item) async {
    final controller = TextEditingController(text: item.name);
    final formKey = GlobalKey<FormState>();

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          item.isDirectory ? 'Rename Folder' : 'Rename File',
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: const InputDecoration(
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2D2D2D)),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF5AF78E)),
              ),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Name required';
              if (val.contains('/') || val.contains(r'\')) {
                return 'No slashes allowed';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5AF78E),
              foregroundColor: Colors.black,
            ),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName != null && newName != item.name) {
      try {
        final entity = item.isDirectory ? Directory(item.path) : File(item.path);
        await _service.renameEntity(entity, newName);
        await _loadDirectory(_currentDir);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error renaming: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _showDeleteConfirmDialog(FileEntryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          'Delete ${item.name}?',
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          item.isDirectory
              ? 'This folder and all its contents will be permanently deleted.'
              : 'This file will be permanently deleted.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final entity = item.isDirectory ? Directory(item.path) : File(item.path);
        await _service.deleteEntity(entity, recursive: true);
        await _loadDirectory(_currentDir);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Widget _buildItemIcon(FileEntryItem item) {
    if (item.isDirectory) {
      final name = item.name.toLowerCase();
      if (name == 'projects') {
        return const Icon(Icons.folder_special, color: Color(0xFF5AF78E), size: 20);
      }
      if (name.startsWith('.')) {
        return const Icon(Icons.folder_outlined, color: Colors.white38, size: 20);
      }
      return const Icon(Icons.folder, color: Color(0xFFE5C07B), size: 20);
    }

    switch (item.category) {
      case FileCategory.python:
        return const Icon(Icons.code, color: Color(0xFF61AFEF), size: 18);
      case FileCategory.javascript:
        return const Icon(Icons.javascript, color: Color(0xFFE5C07B), size: 20);
      case FileCategory.shell:
        return const Icon(Icons.terminal, color: Color(0xFF5AF78E), size: 18);
      case FileCategory.json:
        return const Icon(Icons.data_object, color: Color(0xFF98C379), size: 18);
      case FileCategory.markdown:
        return const Icon(Icons.menu_book, color: Color(0xFFC678DD), size: 18);
      case FileCategory.c:
        return const Icon(Icons.memory, color: Color(0xFFE06C75), size: 18);
      case FileCategory.image:
        return const Icon(Icons.image, color: Colors.tealAccent, size: 18);
      case FileCategory.text:
        return const Icon(Icons.description, color: Colors.white70, size: 18);
      case FileCategory.binary:
      default:
        return const Icon(Icons.insert_drive_file, color: Colors.white38, size: 18);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filterQuery.isEmpty
        ? _items
        : _items.where((it) => it.name.toLowerCase().contains(_filterQuery.toLowerCase())).toList();

    return Drawer(
      backgroundColor: const Color(0xFF18181B),
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            _buildHeader(),
            // Breadcrumbs Row
            _buildBreadcrumbs(),
            const Divider(height: 1, color: Color(0xFF2D2D2D)),
            // Filter Bar (if many items or searching)
            _buildFilterBar(),
            // File List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF5AF78E)),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            _filterQuery.isEmpty ? '(empty directory)' : 'No matching files',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, color: Color(0xFF242427)),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final runCmd = item.isDirectory
                                ? null
                                : _service.resolveRunCommand(File(item.path));

                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: _buildItemIcon(item),
                              title: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: item.isDirectory
                                      ? Colors.white
                                      : const Color(0xFFE0E0E0),
                                  fontFamily: 'monospace',
                                  fontWeight: item.isDirectory
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(
                                item.isDirectory
                                    ? item.formattedDate
                                    : '${item.formattedSize}  ${item.formattedDate}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                ),
                              ),
                              onTap: () {
                                if (item.isDirectory) {
                                  _navigateToDir(Directory(item.path));
                                } else if (item.isEditableText) {
                                  _openFile(File(item.path));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Cannot edit binary file: ${item.name}',
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                        ),
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              trailing: PopupMenuButton<String>(
                                icon: const Icon(
                                  Icons.more_vert,
                                  color: Colors.white38,
                                  size: 16,
                                ),
                                color: const Color(0xFF242427),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  side: const BorderSide(color: Color(0xFF2D2D2D)),
                                ),
                                onSelected: (val) {
                                  if (val == 'cd') {
                                    if (widget.onOpenTerminalHere != null && _currentDir != null) {
                                      final target = item.isDirectory
                                          ? Directory(item.path)
                                          : _currentDir!;
                                      widget.onOpenTerminalHere!(target);
                                    }
                                  } else if (val == 'run') {
                                    if (runCmd != null && widget.onRunInTerminal != null) {
                                      Navigator.of(context).pop();
                                      widget.onRunInTerminal!(
                                        runCmd,
                                        Directory(item.path).parent.path,
                                      );
                                    }
                                  } else if (val == 'edit') {
                                    _openFile(File(item.path));
                                  } else if (val == 'rename') {
                                    _showRenameDialog(item);
                                  } else if (val == 'delete') {
                                    _showDeleteConfirmDialog(item);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  if (item.isDirectory)
                                    const PopupMenuItem(
                                      value: 'cd',
                                      child: Row(
                                        children: [
                                          Icon(Icons.terminal, color: Color(0xFF5AF78E), size: 16),
                                          SizedBox(width: 8),
                                          Text(
                                            'CD Terminal Here',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontFamily: 'monospace',
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (!item.isDirectory && item.isEditableText)
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_outlined, color: Colors.white70, size: 16),
                                          SizedBox(width: 8),
                                          Text(
                                            'Edit File',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontFamily: 'monospace',
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (runCmd != null)
                                    const PopupMenuItem(
                                      value: 'run',
                                      child: Row(
                                        children: [
                                          Icon(Icons.play_arrow, color: Color(0xFF5AF78E), size: 16),
                                          SizedBox(width: 8),
                                          Text(
                                            'Run in Terminal',
                                            style: TextStyle(
                                              color: Color(0xFF5AF78E),
                                              fontFamily: 'monospace',
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const PopupMenuItem(
                                    value: 'rename',
                                    child: Row(
                                      children: [
                                        Icon(Icons.drive_file_rename_outline, color: Colors.white70, size: 16),
                                        SizedBox(width: 8),
                                        Text(
                                          'Rename',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline, color: Colors.redAccent, size: 16),
                                        SizedBox(width: 8),
                                        Text(
                                          'Delete',
                                          style: TextStyle(
                                            color: Colors.redAccent,
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: const Color(0xFF18181B),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, color: Color(0xFF5AF78E), size: 18),
          const SizedBox(width: 8),
          const Text(
            'FILES',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 1.1,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => _loadDirectory(_currentDir),
          ),
          IconButton(
            icon: const Icon(Icons.note_add_outlined, color: Colors.white70, size: 18),
            tooltip: 'New File',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _showNewFileDialog,
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, color: Colors.white70, size: 18),
            tooltip: 'New Folder',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _showNewFolderDialog,
          ),
          if (_currentDir != null && widget.onOpenTerminalHere != null)
            IconButton(
              icon: const Icon(Icons.terminal, color: Color(0xFF5AF78E), size: 18),
              tooltip: 'CD Terminal Here',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () {
                widget.onOpenTerminalHere!(_currentDir!);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    return Container(
      height: 36,
      color: const Color(0xFF1F1F23),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, color: Colors.white54, size: 16),
            tooltip: 'Up one directory',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _navigateUp,
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: _breadcrumbs.length,
              separatorBuilder: (_, _) => const Center(
                child: Text(
                  ' / ',
                  style: TextStyle(color: Colors.white30, fontSize: 11),
                ),
              ),
              itemBuilder: (context, index) {
                final crumb = _breadcrumbs[index];
                final isLast = index == _breadcrumbs.length - 1;

                return Center(
                  child: InkWell(
                    onTap: () {
                      if (!isLast) {
                        _navigateToDir(Directory(crumb.path));
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        crumb.label,
                        style: TextStyle(
                          color: isLast ? const Color(0xFF5AF78E) : Colors.white70,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: Icon(
              _showHidden ? Icons.visibility : Icons.visibility_off,
              color: _showHidden ? const Color(0xFF5AF78E) : Colors.white30,
              size: 16,
            ),
            tooltip: _showHidden ? 'Hide hidden files' : 'Show hidden files',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              setState(() => _showHidden = !_showHidden);
              _loadDirectory(_currentDir);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF18181B),
      child: TextField(
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          fontSize: 11,
        ),
        decoration: InputDecoration(
          hintText: 'Filter files...',
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
          prefixIcon: const Icon(Icons.search, color: Colors.white24, size: 14),
          prefixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          suffixIcon: _filterQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white38, size: 12),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  onPressed: () => setState(() => _filterQuery = ''),
                )
              : null,
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onChanged: (val) => setState(() => _filterQuery = val),
      ),
    );
  }
}
