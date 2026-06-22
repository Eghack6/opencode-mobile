import 'part.dart';

class Message {
  final String id;
  final String sessionId;
  final String role;
  final List<Part> parts;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.parts,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final time = json['time'] as Map<String, dynamic>? ?? {};
    return Message(
      id: json['id'] as String,
      sessionId: (json['sessionID'] as String?) ?? '',
      role: json['role'] as String? ?? 'user',
      parts: (json['parts'] as List<dynamic>?)
              ?.map((p) => Part.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: _parseTime(time['created']),
    );
  }

  static DateTime _parseTime(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      return DateTime.parse(value);
    }
    return DateTime.now();
  }

  String get textContent {
    return parts
        .where((p) => p.type == 'text')
        .map((p) => p.content)
        .join('\n');
  }

  String get fullContent {
    return parts.map((p) => p.content).join('\n');
  }

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
}
