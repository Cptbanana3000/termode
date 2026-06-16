import 'terminal_line.dart';
import 'terminal_emulator_buffer.dart';
import '../services/ansi_parser.dart';
import '../services/virtual_filesystem.dart';

class TerminalSession {
  final String id;
  final String name;
  final List<TerminalLine> lines;
  final List<String> commandHistory;
  int historyIndex;
  final VirtualFileSystem vfs;
  
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
    required this.lines,
    required this.commandHistory,
    required this.historyIndex,
    required this.vfs,
    this.isShellActive = false,
    this.isRealPtyActive = false,
    this.isPtyInteractionActive = false,
  }) {
    final parser = AnsiParser(ansiBuffer);
    for (final line in lines) {
      parser.write('${line.text}\n');
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'lines': lines.map((line) => line.toJson()).toList(),
      'commandHistory': commandHistory,
      'historyIndex': historyIndex,
      'cwd': vfs.getAbsolutePath(),
      'vfs': vfs.toJson(),
    };
  }

  factory TerminalSession.fromJson(Map<String, dynamic> json) {
    final sessionVfs = VirtualFileSystem.fromJson(json['vfs'] as Map<String, dynamic>);
    final cwd = json['cwd'] as String? ?? '/home';
    sessionVfs.cd(cwd);

    return TerminalSession(
      id: json['id'] as String,
      name: json['name'] as String,
      lines: (json['lines'] as List<dynamic>)
          .map((line) => TerminalLine.fromJson(line as Map<String, dynamic>))
          .toList(),
      commandHistory: List<String>.from(json['commandHistory'] as List<dynamic>),
      historyIndex: json['historyIndex'] as int? ?? -1,
      vfs: sessionVfs,
    );
  }
}
