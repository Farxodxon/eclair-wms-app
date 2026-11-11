import 'dart:math';

class QueuedOp {
  QueuedOp({
    required this.id,
    required this.userId,
    required this.type,
    required this.path,
    required this.body,
    required this.label,
    required this.createdAt,
    required this.status,
    this.error,
    this.attempts = 0,
    this.inProgressSince,
  });

  /// Idempotency-Key.
  final String id;
  final int userId;
  final String type;
  final String path;
  final Map<String, dynamic> body;
  final String label;
  final String createdAt;
  final String status;
  final String? error;
  final int attempts;
  final String? inProgressSince;

  QueuedOp copyWith({
    String? status,
    String? error,
    int? attempts,
    String? inProgressSince,
  }) {
    return QueuedOp(
      id: id,
      userId: userId,
      type: type,
      path: path,
      body: body,
      label: label,
      createdAt: createdAt,
      status: status ?? this.status,
      error: error ?? this.error,
      attempts: attempts ?? this.attempts,
      inProgressSince: inProgressSince ?? this.inProgressSince,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'type': type,
        'path': path,
        'body': body,
        'label': label,
        'created_at': createdAt,
        'status': status,
        'error': error,
        'attempts': attempts,
        'in_progress_since': inProgressSince,
      };

  factory QueuedOp.fromJson(Map<String, dynamic> json) {
    return QueuedOp(
      id: json['id'] as String? ?? '',
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      type: json['type'] as String? ?? 'out',
      path: json['path'] as String? ?? '/inventory/out',
      body: Map<String, dynamic>.from((json['body'] as Map?) ?? const {}),
      label: json['label'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      error: json['error'] as String?,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      inProgressSince: json['in_progress_since'] as String?,
    );
  }
}

String newOpId() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 32; i++) {
    buffer.write(random.nextInt(16).toRadixString(16));
  }
  return buffer.toString();
}
