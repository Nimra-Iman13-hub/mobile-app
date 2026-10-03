import 'dart:convert';

import 'priority.dart';
import 'repeat_rule.dart';

/// A single reminder. Immutable; edits go through [copyWith].
class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.dueAt,
    required this.notificationId,
    this.note = '',
    this.priority = Priority.medium,
    this.repeat = RepeatRule.none,
    this.isCompleted = false,
    this.completedAt,
  });

  final String id;
  final String title;

  /// Optional; empty means no note.
  final String note;

  /// Due date and time, in local time.
  final DateTime dueAt;

  final Priority priority;
  final RepeatRule repeat;
  final bool isCompleted;
  final DateTime? completedAt;

  /// Key for the scheduled OS notification. Stored rather than derived from
  /// [id], because hashing a string to a 32-bit int risks two reminders
  /// cancelling each other's alarms.
  final int notificationId;

  bool isPast([DateTime? now]) => dueAt.isBefore(now ?? DateTime.now());

  /// Due within today (local), regardless of whether it has passed.
  bool isToday([DateTime? now]) {
    final today = now ?? DateTime.now();
    return dueAt.year == today.year &&
        dueAt.month == today.month &&
        dueAt.day == today.day;
  }

  Reminder copyWith({
    String? title,
    String? note,
    DateTime? dueAt,
    Priority? priority,
    RepeatRule? repeat,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return Reminder(
      id: id,
      title: title ?? this.title,
      note: note ?? this.note,
      dueAt: dueAt ?? this.dueAt,
      priority: priority ?? this.priority,
      repeat: repeat ?? this.repeat,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      notificationId: notificationId,
    );
  }

  /// Marks done.
  ///
  /// A repeating reminder is never finished: it rolls forward to its next
  /// occurrence and stays open, so one series stays one row instead of filling
  /// the Completed list with copies. When the rule yields nothing more, it
  /// closes normally.
  Reminder markDone({DateTime? now}) {
    final moment = now ?? DateTime.now();

    if (repeat.repeats) {
      final next = repeat.nextAfter(dueAt, moment);
      if (next != null) {
        return copyWith(
          dueAt: next,
          isCompleted: false,
          clearCompletedAt: true,
        );
      }
    }
    return copyWith(isCompleted: true, completedAt: moment);
  }

  Reminder markNotDone() =>
      copyWith(isCompleted: false, clearCompletedAt: true);

  /// Pushes the due time out from [now], not from the original due time — a
  /// "10 minutes" tapped an hour late must mean ten minutes from the tap.
  Reminder snoozedBy(Duration duration, {DateTime? now}) => copyWith(
        dueAt: (now ?? DateTime.now()).add(duration),
        isCompleted: false,
        clearCompletedAt: true,
      );

  /// Times are stored as UTC epoch milliseconds so a stored reminder keeps
  /// pointing at the same instant across a time-zone change, and converted
  /// back to local on read.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'note': note,
        'dueAtUtcMillis': dueAt.toUtc().millisecondsSinceEpoch,
        'notificationId': notificationId,
        'priority': priority.name,
        'repeat': repeat.toJson(),
        'isCompleted': isCompleted,
        'completedAtUtcMillis': completedAt?.toUtc().millisecondsSinceEpoch,
      };

  static Reminder fromJson(Map<String, Object?> json) {
    final due = json['dueAtUtcMillis'];
    final done = json['completedAtUtcMillis'];
    final repeatJson = json['repeat'];

    return Reminder(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      note: (json['note'] as String?) ?? '',
      dueAt: due is int ? _local(due) : DateTime.now(),
      notificationId: (json['notificationId'] as int?) ?? 0,
      priority: Priority.fromName(json['priority'] as String?),
      repeat: repeatJson is Map
          ? RepeatRule.fromJson(Map<String, Object?>.from(repeatJson))
          : RepeatRule.none,
      isCompleted: (json['isCompleted'] as bool?) ?? false,
      completedAt: done is int ? _local(done) : null,
    );
  }

  static DateTime _local(int millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();

  static String encodeList(List<Reminder> reminders) =>
      jsonEncode(reminders.map((r) => r.toJson()).toList());

  /// Skips any entry that cannot be read, rather than discarding the whole
  /// store over one bad row.
  static List<Reminder> decodeList(String? source) {
    if (source == null || source.isEmpty) return <Reminder>[];
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return <Reminder>[];

      final result = <Reminder>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        try {
          result.add(fromJson(Map<String, Object?>.from(entry)));
        } on Object {
          continue;
        }
      }
      return result;
    } on FormatException {
      return <Reminder>[];
    }
  }

  @override
  String toString() => 'Reminder($id, "$title", due $dueAt)';
}
