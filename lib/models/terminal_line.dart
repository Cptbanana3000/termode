enum LineType {
  input,
  output,
  error,
}

class TerminalLine {
  final String text;
  final LineType type;

  TerminalLine({
    required this.text,
    required this.type,
  });

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'type': type.name,
    };
  }

  factory TerminalLine.fromJson(Map<String, dynamic> json) {
    return TerminalLine(
      text: json['text'] as String,
      type: LineType.values.byName(json['type'] as String),
    );
  }
}
