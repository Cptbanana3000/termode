import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/file_explorer_service.dart';
import '../widgets/syntax_highlighting_controller.dart';

class QuickEditorScreen extends StatefulWidget {
  final File file;
  final void Function(String command, String workingDirectory)? onRunInTerminal;

  const QuickEditorScreen({
    super.key,
    required this.file,
    this.onRunInTerminal,
  });

  @override
  State<QuickEditorScreen> createState() => _QuickEditorScreenState();
}

class _QuickEditorScreenState extends State<QuickEditorScreen> {
  final FileExplorerService _fileService = FileExplorerService();
  late final SyntaxHighlightingEditingController _controller;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = true;
  String? _loadError;
  bool _isDirty = false;
  double _fontSize = 13.0;
  int _currentLine = 1;
  int _currentCol = 1;
  int _totalLines = 1;
  String _savedContent = '';

  @override
  void initState() {
    super.initState();
    final cat = _fileService.detectCategory(widget.file.path, false);
    _controller = SyntaxHighlightingEditingController(category: cat);
    _controller.addListener(_onTextChanged);
    _loadFile();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _loadFile() {
    try {
      if (!widget.file.existsSync()) {
        _isLoading = false;
        _loadError = 'File does not exist: ${widget.file.path}';
        return;
      }

      final stat = widget.file.statSync();
      if (stat.size > 5 * 1024 * 1024) {
        _isLoading = false;
        _loadError = 'File is too large to open in quick editor (> 5 MB).';
        return;
      }

      final text = widget.file.readAsStringSync();
      _savedContent = text;
      _controller.text = text;
      _updateCursorPosition();

      _isLoading = false;
      _isDirty = false;
    } catch (e) {
      _isLoading = false;
      _loadError = 'Failed to load file: $e';
    }
  }

  void _onTextChanged() {
    final isDirtyNow = _controller.text != _savedContent;
    if (isDirtyNow != _isDirty) {
      if (mounted) {
        setState(() {
          _isDirty = isDirtyNow;
        });
      } else {
        _isDirty = isDirtyNow;
      }
    }
    _updateCursorPosition();
  }

  void _updateCursorPosition() {
    final text = _controller.text;
    final selection = _controller.selection;

    final lines = text.split('\n');
    _totalLines = lines.isEmpty ? 1 : lines.length;

    if (!selection.isValid || selection.baseOffset < 0) {
      _currentLine = 1;
      _currentCol = 1;
      return;
    }

    final offset = selection.baseOffset.clamp(0, text.length);
    final prefix = text.substring(0, offset);
    final prefixLines = prefix.split('\n');

    _currentLine = prefixLines.length;
    _currentCol = prefixLines.last.length + 1;
  }

  bool _saveFile() {
    try {
      widget.file.writeAsStringSync(_controller.text);
      _savedContent = _controller.text;
      setState(() {
        _isDirty = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${widget.file.path.split(RegExp(r'[\\/]')).last}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            backgroundColor: const Color(0xFF2D2D2D),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Save failed: $e',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  void _handleRunInTerminal() {
    final runCmd = _fileService.resolveRunCommand(widget.file);
    if (runCmd == null) return;

    if (_isDirty) {
      final saved = _saveFile();
      if (!saved) return;
    }

    final workDir = widget.file.parent.path;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    if (widget.onRunInTerminal != null) {
      widget.onRunInTerminal!(runCmd, workDir);
    }
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_isDirty) return true;

    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text(
          'Discard changes?',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'You have unsaved edits in this file. Discard them and leave?',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 13,
          ),
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
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    return shouldDiscard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.file.path.split(RegExp(r'[\\/]')).last;
    final runCmd = _fileService.resolveRunCommand(widget.file);

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await _confirmDiscardIfNeeded();
        if (shouldLeave && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            _saveFile();
          },
          const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
            if (runCmd != null) {
              _handleRunInTerminal();
            }
          },
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF1E1E1E),
          appBar: AppBar(
            backgroundColor: const Color(0xFF18181B),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              onPressed: () async {
                final canLeave = await _confirmDiscardIfNeeded();
                if (canLeave && context.mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (_isDirty) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF5AF78E),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.text_decrease, color: Colors.white70, size: 18),
                tooltip: 'Decrease font size',
                onPressed: () {
                  if (_fontSize > 9) {
                    setState(() => _fontSize -= 1.0);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.text_increase, color: Colors.white70, size: 18),
                tooltip: 'Increase font size',
                onPressed: () {
                  if (_fontSize < 28) {
                    setState(() => _fontSize += 1.0);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.save_outlined, color: Colors.white),
                tooltip: 'Save (Ctrl+S)',
                onPressed: _saveFile,
              ),
              if (runCmd != null) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ElevatedButton.icon(
                    onPressed: _handleRunInTerminal,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Run'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5AF78E),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      textStyle: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF5AF78E)),
                )
              : _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.redAccent,
                              size: 40,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _loadError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: Container(
                            color: const Color(0xFF1E1E1E),
                            child: SingleChildScrollView(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Line numbers gutter
                                  _buildLineNumbersGutter(),
                                  const SizedBox(width: 8),
                                  // Editor text field
                                  Expanded(
                                    child: TextField(
                                      controller: _controller,
                                      focusNode: _focusNode,
                                      maxLines: null,
                                      keyboardType: TextInputType.multiline,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: _fontSize,
                                        height: 1.5,
                                        color: const Color(0xFFD4D4D4),
                                      ),
                                      cursorColor: const Color(0xFF5AF78E),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Status Bar
                        _buildStatusBar(),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildLineNumbersGutter() {
    final count = _totalLines;
    final sb = StringBuffer();
    for (var i = 1; i <= count; i++) {
      sb.writeln(i);
    }

    return Container(
      width: 44,
      padding: const EdgeInsets.only(left: 8, right: 6),
      alignment: Alignment.topRight,
      child: Text(
        sb.toString(),
        textAlign: TextAlign.right,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: _fontSize,
          height: 1.5,
          color: Colors.white30,
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final catName = _controller.category.name.toUpperCase();

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF18181B),
        border: Border(
          top: BorderSide(color: Color(0xFF2D2D2D)),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Ln $_currentLine, Col $_currentCol',
            style: const TextStyle(
              color: Colors.white54,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '$_totalLines lines',
            style: const TextStyle(
              color: Colors.white38,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
          const Spacer(),
          if (_isDirty) ...[
            const Text(
              '• edited',
              style: TextStyle(
                color: Color(0xFF5AF78E),
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              catName,
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'UTF-8',
            style: TextStyle(
              color: Colors.white38,
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
