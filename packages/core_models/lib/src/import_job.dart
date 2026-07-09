import 'package:meta/meta.dart';

import 'json.dart';

/// Progress of a batched ML publications import (row of `import_jobs`, RF-36).
@immutable
class ImportJob {
  const ImportJob({
    required this.id,
    required this.mlAccountId,
    required this.status,
    this.total,
    this.processed = 0,
    this.failed = 0,
    this.errors = const [],
    this.startedAt,
    this.finishedAt,
  });

  final String id;
  final String mlAccountId;

  /// pending | processing | done | error (mirrors ml_event_status).
  final String status;

  /// Total listings reported by ML; null until the first page is read.
  final int? total;
  final int processed;
  final int failed;
  final List<String> errors;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  bool get isRunning => status == 'pending' || status == 'processing';
  bool get isDone => status == 'done';

  /// 0..1 progress, or null while the total is unknown.
  double? get progress {
    final t = total;
    if (t == null || t <= 0) return null;
    final done = (processed + failed).clamp(0, t);
    return done / t;
  }

  factory ImportJob.fromJson(Map<String, dynamic> json) => ImportJob(
        id: json['id'] as String,
        mlAccountId: json['ml_account_id'] as String,
        status: (json['status'] as String?) ?? 'pending',
        total: asIntOrNull(json['total']),
        processed: asInt(json['processed']),
        failed: asInt(json['failed']),
        errors: [
          for (final e in (json['errors'] as List?) ?? const []) e.toString(),
        ],
        startedAt: asDateTime(json['started_at']),
        finishedAt: asDateTime(json['finished_at']),
      );
}
