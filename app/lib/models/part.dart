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
    Map<String, dynamic>? meta;
    if (type == 'file') {
      content = '';
      meta = {};
      if (json['url'] is String) meta['url'] = json['url'];
      if (json['mime'] is String) meta['mime'] = json['mime'];
      final extra = json['metadata'] as Map<String, dynamic>?;
      if (extra != null) meta.addAll(extra);
    } else if (type == 'text') {
      content = json['text'] as String? ?? json['content'] as String? ?? '';
      meta = json['metadata'] as Map<String, dynamic>?;
    } else {
      content = json['content'] as String? ?? json['text'] as String? ?? '';
      meta = json['metadata'] as Map<String, dynamic>?;
    }
    return Part(
      type: type,
      content: content,
      language: json['language'] as String?,
      metadata: meta,
    );
  }

  bool get isCode => type == 'code';
  bool get isText => type == 'text';
  bool get isReasoning => type == 'reasoning';
  bool get isToolCall => type == 'toolCall' || type == 'tool_use' || type == 'tool';
  bool get isToolResult => type == 'toolResult' || type == 'tool_result';
  bool get isImage => type == 'file' && (_mime ?? '').startsWith('image/');
  bool get isFile => type == 'file';

  String? get _mime => metadata?['mime'] as String?;
  String? get imageUrl => metadata?['url'] as String?;
}
