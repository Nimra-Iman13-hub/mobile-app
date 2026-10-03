/// How a reminder repeats.
enum RepeatKind {
  none,
  daily,
  weekly,
  monthly,

  /// Specific weekdays, e.g. Mon/Wed/Fri.
  customDays;

  static RepeatKind fromName(String? value) => RepeatKind.values.firstWhere(
        (k) => k.name == value,
        orElse: () => RepeatKind.none,
      );
}

/// A repeat rule plus the logic for finding the next occurrence.
class RepeatRule {
  const RepeatRule({this.kind = RepeatKind.none, this.weekdays = const <int>{}});

  static const RepeatRule none = RepeatRule();

  final RepeatKind kind;

  /// [DateTime.monday]..[DateTime.sunday]. Only used by [RepeatKind.customDays].
  final Set<int> weekdays;

  bool get repeats => kind != RepeatKind.none;

  String get label => switch (kind) {
        RepeatKind.none => 'Does not repeat',
        RepeatKind.daily => 'Daily',
        RepeatKind.weekly => 'Weekly',
        RepeatKind.monthly => 'Monthly',
        RepeatKind.customDays => weekdays.isEmpty
            ? 'Custom days'
            : (weekdays.toList()..sort()).map(_shortDay).join(', '),
      };

  static String _shortDay(int weekday) => switch (weekday) {
        DateTime.monday => 'Mon',
        DateTime.tuesday => 'Tue',
        DateTime.wednesday => 'Wed',
        DateTime.thursday => 'Thu',
        DateTime.friday => 'Fri',
        DateTime.saturday => 'Sat',
        _ => 'Sun',
      };

  /// The first occurrence strictly after [after], for a series anchored at
  /// [from] (which supplies the time of day and, for monthly, the day of
  /// month). Returns null when the rule does not repeat.
  ///
  /// Occurrences are computed from the anchor by index rather than by stepping
  /// off the previous result: "the 31st, monthly" clamps to 28 February, and
  /// stepping would then stay on the 28th forever instead of returning to the
  /// 31st in March.
  DateTime? nextAfter(DateTime from, DateTime after) {
    if (!repeats) return null;

    for (var i = 1; i <= 800; i++) {
      final candidate = _occurrence(from, i);
      if (candidate != null && candidate.isAfter(after)) return candidate;
    }
    return null;
  }

  DateTime? _occurrence(DateTime anchor, int index) {
    switch (kind) {
      case RepeatKind.none:
        return null;
      case RepeatKind.daily:
        return _addDays(anchor, index);
      case RepeatKind.weekly:
        return _addDays(anchor, index * 7);
      case RepeatKind.monthly:
        return _addMonths(anchor, index);
      case RepeatKind.customDays:
        final days = weekdays.isEmpty ? <int>{anchor.weekday} : weekdays;
        // Walk forward a day at a time and keep only the selected weekdays.
        // Bounded by the loop in nextAfter, and cheap for any real interval.
        var seen = 0;
        for (var offset = 1; offset <= 400; offset++) {
          final candidate = _addDays(anchor, offset);
          if (days.contains(candidate.weekday)) {
            seen++;
            if (seen == index) return candidate;
          }
        }
        return null;
    }
  }

  /// Uses the DateTime constructor rather than Duration so a daylight-saving
  /// shift keeps the wall-clock time: 09:00 stays 09:00.
  static DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days, d.hour, d.minute);

  /// Clamps the day so "the 31st" lands on the last day of a shorter month.
  static DateTime _addMonths(DateTime d, int months) {
    final target = DateTime(d.year, d.month + months);
    final daysInTarget = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(
      target.year,
      target.month,
      d.day <= daysInTarget ? d.day : daysInTarget,
      d.hour,
      d.minute,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'weekdays': weekdays.toList()..sort(),
      };

  static RepeatRule fromJson(Map<String, Object?>? json) {
    if (json == null) return none;
    return RepeatRule(
      kind: RepeatKind.fromName(json['kind'] as String?),
      weekdays: ((json['weekdays'] as List?) ?? const <dynamic>[])
          .whereType<int>()
          .where((d) => d >= DateTime.monday && d <= DateTime.sunday)
          .toSet(),
    );
  }

  RepeatRule copyWith({RepeatKind? kind, Set<int>? weekdays}) => RepeatRule(
        kind: kind ?? this.kind,
        weekdays: weekdays ?? this.weekdays,
      );

  @override
  bool operator ==(Object other) =>
      other is RepeatRule &&
      other.kind == kind &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays);

  @override
  int get hashCode => Object.hash(kind, Object.hashAllUnordered(weekdays));
}
