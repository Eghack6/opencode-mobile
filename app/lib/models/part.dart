class Part {
  final String type;
  final String content;
  final String? language;
  final Map<String, dynamic>? metadata;

  Part({
    required this.type,
    required this.content,
    this.language,
    this.metadata,
  });

  factory Part.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'text';
    String content;
    if (type == 'text') {
      content = json['text'] as String? ?? json['content'] as String? ?? '';
    } else {
      content = json['content'] as String? ?? json['text'] as String? ?? '';
    }
    return Part(
      type: type,
      content: content,
      language: json['language'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  bool get isCode => type == 'code';
  bool get isText => type == 'text';
  bool get isReasoning => type == 'reasoning';
  bool get isToolCall => type == 'toolCall' || type == 'tool_use' || type == 'tool';
  bool get isToolResult => type == 'toolResult' || type == 'tool_result';
}
