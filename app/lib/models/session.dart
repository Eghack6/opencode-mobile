class Session {
  final String id;
  final String? title;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? parentId;

  Session({
    required this.id,
    this.title,
    required this.createdAt,
    this.updatedAt,
    this.parentId,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    final time = json['time'] as Map<String, dynamic>? ?? {};
    return Session(
      id: json['id'] as String,
      title: json['title'] as String?,
      createdAt: _parseTime(time['created']),
      updatedAt: time['updated'] != null ? _parseTime(time['updated']) : null,
      parentId: json['parentID'] as String?,
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'parentID': parentId,
        'time': {
          'created': createdAt.millisecondsSinceEpoch,
          if (updatedAt != null) 'updated': updatedAt!.millisecondsSinceEpoch,
        },
      };
}
