/// What [QuickAddParser] pulled out of a line of text.
class QuickAddResult {
  const QuickAddResult({
    required this.title,
    required this.dueAt,
    required this.matchedDate,
    required this.matchedTime,
  });

  /// The input with any date/time words stripped out.
  final String title;

  final DateTime dueAt;

  /// Whether a date word was actually recognised, as opposed to defaulted.
  final bool matchedDate;

  /// Whether a time was actually recognised.
  final bool matchedTime;

  bool get matchedAnything => matchedDate || matchedTime;
}

/// Turns "Call mom tomorrow 6pm" into a title plus a due date.
///
/// Deliberately hand-rolled and small rather than a date-parsing library: it
/// covers the handful of phrasings people actually type into a quick-add box,
/// and anything it does not recognise falls back to a sensible default with
/// the full text kept as the title. Nothing is ever silently dropped.
abstract final class QuickAddParser {
  /// Default time for a date given without one ("tomorrow" -> 9am).
  static const int defaultHour = 9;

  static final Map<String, int> _weekdays = <String, int>{
    'monday': DateTime.monday,
    'mon': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'tue': DateTime.tuesday,
    'tues': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'wed': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'thu': DateTime.thursday,
    'thurs': DateTime.thursday,
    'friday': DateTime.friday,
    'fri': DateTime.friday,
    'saturday': DateTime.saturday,
    'sat': DateTime.saturday,
    'sunday': DateTime.sunday,
    'sun': DateTime.sunday,
  };

  /// "6pm", "6:30pm", "18:00", "6 pm".
  static final RegExp _timePattern = RegExp(
    r'\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b|\b(?:at\s+)?(\d{1,2}):(\d{2})\b',
    caseSensitive: false,
  );

  static final RegExp _tomorrow = RegExp(r'\btomorrow\b', caseSensitive: false);
  static final RegExp _today = RegExp(r'\btoday\b', caseSensitive: false);
  static final RegExp _tonight = RegExp(r'\btonight\b', caseSensitive: false);

  /// "next monday" / "monday" / "on friday".
  static final RegExp _weekdayPattern = RegExp(
    r'\b(?:on\s+|next\s+)?(monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thu|friday|fri|saturday|sat|sunday|sun)\b',
    caseSensitive: false,
  );

  /// "in 20 minutes", "in 2 hours", "in 3 days".
  static final RegExp _relativePattern = RegExp(
    r'\bin\s+(\d{1,3})\s*(minute|minutes|min|mins|hour|hours|hr|hrs|day|days)\b',
    caseSensitive: false,
  );

  static QuickAddResult parse(String input, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    var remaining = input;

    // Relative offsets are handled first and on their own: "in 2 hours"
    // fully determines the moment, so no date or clock time is also needed.
    final relative = _relativePattern.firstMatch(remaining);
    if (relative != null) {
      final amount = int.parse(relative.group(1)!);
      final unit = relative.group(2)!.toLowerCase();
      final duration = unit.startsWith('min')
          ? Duration(minutes: amount)
          : unit.startsWith('h')
              ? Duration(hours: amount)
              : Duration(days: amount);

      remaining = remaining.replaceRange(relative.start, relative.end, ' ');
      return QuickAddResult(
        title: _tidy(remaining, input),
        dueAt: reference.add(duration),
        matchedDate: true,
        matchedTime: true,
      );
    }

    var matchedDate = false;
    var matchedTime = false;
    var date = DateTime(reference.year, reference.month, reference.day);
    var hour = defaultHour;
    var minute = 0;

    // --- Time of day ---
    final timeMatch = _timePattern.firstMatch(remaining);
    if (timeMatch != null) {
      final meridiem = timeMatch.group(3)?.toLowerCase();
      if (meridiem != null) {
        final raw = int.parse(timeMatch.group(1)!);
        minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
        // 12am is midnight, 12pm is noon; neither follows the +12 rule.
        hour = switch (meridiem) {
          'pm' => raw == 12 ? 12 : raw + 12,
          _ => raw == 12 ? 0 : raw,
        };
      } else {
        hour = int.parse(timeMatch.group(4)!);
        minute = int.parse(timeMatch.group(5)!);
      }

      if (hour <= 23 && minute <= 59) {
        matchedTime = true;
        remaining = remaining.replaceRange(timeMatch.start, timeMatch.end, ' ');
      }
    }

    // --- Date ---
    if (_tomorrow.hasMatch(remaining)) {
      date = date.add(const Duration(days: 1));
      matchedDate = true;
      remaining = remaining.replaceAll(_tomorrow, ' ');
    } else if (_tonight.hasMatch(remaining)) {
      matchedDate = true;
      // "tonight" implies an evening hour unless a time was given explicitly.
      if (!matchedTime) {
        hour = 20;
        matchedTime = true;
      }
      remaining = remaining.replaceAll(_tonight, ' ');
    } else if (_today.hasMatch(remaining)) {
      matchedDate = true;
      remaining = remaining.replaceAll(_today, ' ');
    } else {
      final weekdayMatch = _weekdayPattern.firstMatch(remaining);
      if (weekdayMatch != null) {
        final target = _weekdays[weekdayMatch.group(1)!.toLowerCase()]!;
        // Always the next such weekday: "monday" on a Monday means next week,
        // which is what people mean when scheduling something.
        var delta = (target - date.weekday) % 7;
        if (delta == 0) delta = 7;
        date = date.add(Duration(days: delta));
        matchedDate = true;
        remaining =
            remaining.replaceRange(weekdayMatch.start, weekdayMatch.end, ' ');
      }
    }

    var dueAt = DateTime(date.year, date.month, date.day, hour, minute);

    // A bare time already gone today means tomorrow — "6pm" typed at 9pm is
    // not a request to schedule three hours ago.
    if (matchedTime && !matchedDate && dueAt.isBefore(reference)) {
      dueAt = dueAt.add(const Duration(days: 1));
    }

    return QuickAddResult(
      title: _tidy(remaining, input),
      dueAt: dueAt,
      matchedDate: matchedDate,
      matchedTime: matchedTime,
    );
  }

  /// Collapses whitespace and trims filler left behind by the removals.
  /// Falls back to the original text if stripping emptied the title.
  static String _tidy(String stripped, String original) {
    var result = stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
    result = result.replaceFirst(RegExp(r'\s+(at|on|in)$', caseSensitive: false), '');
    result = result.trim();
    return result.isEmpty ? original.trim() : result;
  }
}
