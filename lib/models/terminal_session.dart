import 'terminal_line.dart';
import 'terminal_emulator_buffer.dart';
import '../services/ansi_parser.dart';
import '../services/virtual_filesystem.dart';

class TerminalSession {
  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<TerminalLine> lines;
  final List<String> commandHistory;
  int historyIndex;
  final VirtualFileSystem vfs;
  String currentInputDraft;
  String? lastExitMessage;
  String? preferredWorkingDirectory;
  String? lastKnownWorkingDirectory;

  // Transient execution state (not serialized to JSON)
  bool isExecutingNativeCommand = false;
  bool isShellActive = false;
  bool isRealPtyActive = false;
  bool isPtyInteractionActive = false;
  bool isLastLinePty = false;
  bool isPtyInitializing = false;
  bool hasAttemptedAutoStart = false;
  String? lastSentPtyInput;
  String? lastSentRealPtyInput;
  final TerminalEmulatorBuffer ansiBuffer = TerminalEmulatorBuffer();

  TerminalSession({
    required this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
    required this.lines,
    required this.commandHistory,
    required this.historyIndex,
    required this.vfs,
    this.currentInputDraft = '',
    this.lastExitMessage,
    this.preferredWorkingDirectory,
    this.lastKnownWorkingDirectory,
    this.isShellActive = false,
    this.isRealPtyActive = false,
    this.isPtyInteractionActive = false,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now() {
    final parser = AnsiParser(ansiBuffer);
    for (final line in lines) {
      parser.write('${line.text}\n');
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lines': lines.map((line) => line.toJson()).toList(),
      'commandHistory': commandHistory,
      'historyIndex': historyIndex,
      'cwd': vfs.getAbsolutePath(),
      'vfs': vfs.toJson(),
      'currentInputDraft': currentInputDraft,
      'lastExitMessage': lastExitMessage,
      'preferredWorkingDirectory': preferredWorkingDirectory,
      'lastKnownWorkingDirectory': lastKnownWorkingDirectory,
      'wasShellActive': isShellActive,
      'wasRealPtyActive': isRealPtyActive,
      'wasPtyInteractionActive': isPtyInteractionActive,
    };
  }

  factory TerminalSession.fromJson(Map<String, dynamic> json) {
    final sessionVfs = VirtualFileSystem.fromJson(
      json['vfs'] as Map<String, dynamic>,
    );
    final cwd = json['cwd'] as String? ?? '/home';
    sessionVfs.cd(cwd);
    final restoredLines = (json['lines'] as List<dynamic>? ?? [])
        .map((line) => TerminalLine.fromJson(line as Map<String, dynamic>))
        .toList();
    final hadLivePty =
        json['wasShellActive'] == true ||
        json['wasRealPtyActive'] == true ||
        json['wasPtyInteractionActive'] == true;
    if (hadLivePty &&
        (restoredLines.isEmpty ||
            restoredLines.last.text != '[previous shell session ended]')) {
      restoredLines.add(
        TerminalLine(
          text: '[previous shell session ended]',
          type: LineType.output,
        ),
      );
    }

    return TerminalSession(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      lines: restoredLines,
      commandHistory: List<String>.from(
        json['commandHistory'] as List<dynamic>? ?? const [],
      ),
      historyIndex: json['historyIndex'] as int? ?? -1,
      vfs: sessionVfs,
      currentInputDraft: json['currentInputDraft']?.toString() ?? '',
      lastExitMessage: json['lastExitMessage']?.toString(),
      preferredWorkingDirectory: json['preferredWorkingDirectory']?.toString(),
      lastKnownWorkingDirectory: json['lastKnownWorkingDirectory']?.toString(),
    );
  }
}
