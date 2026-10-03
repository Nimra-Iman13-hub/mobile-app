import 'package:flutter_test/flutter_test.dart';
import 'package:helloworld/models/priority.dart';
import 'package:helloworld/models/reminder.dart';
import 'package:helloworld/models/repeat_rule.dart';

Reminder build({
  required DateTime dueAt,
  String title = 'Test',
  RepeatRule repeat = RepeatRule.none,
  bool isCompleted = false,
}) =>
    Reminder(
      id: 'r1',
      title: title,
      dueAt: dueAt,
      notificationId: 7,
      repeat: repeat,
      isCompleted: isCompleted,
    );

void main() {
  group('storage round-trip', () {
    test('keeps every field', () {
      final reminder = Reminder(
        id: 'r1',
        title: 'Call mom',
        note: 'about the weekend',
        dueAt: DateTime(2026, 10, 1, 18, 30),
        notificationId: 42,
        priority: Priority.high,
        repeat: const RepeatRule(
          kind: RepeatKind.customDays,
          weekdays: <int>{DateTime.monday, DateTime.friday},
        ),
      );

      final decoded = Reminder.decodeList(Reminder.encodeList([reminder]));

      expect(decoded, hasLength(1));
      expect(decoded.single.title, 'Call mom');
      expect(decoded.single.priority, Priority.high);
      expect(decoded.single.repeat.kind, RepeatKind.customDays);
      expect(decoded.single.repeat.weekdays, <int>{1, 5});
      // Stored UTC, read back local: same instant.
      expect(decoded.single.dueAt, DateTime(2026, 10, 1, 18, 30));
    });

    test('degrades instead of throwing', () {
      expect(Reminder.decodeList(null), isEmpty);
      expect(Reminder.decodeList('not json'), isEmpty);
      expect(Reminder.decodeList('{"not":"a list"}'), isEmpty);
    });

    test('skips one bad entry but keeps the rest', () {
      final good = build(dueAt: DateTime(2026, 10, 1, 9));
      final one = Reminder.encodeList([good]).replaceAll(RegExp(r'^\[|\]$'), '');
      expect(Reminder.decodeList('[$one,{"title":"broken"},$one]'), hasLength(2));
    });
  });

  group('markDone', () {
    test('closes a one-off reminder', () {
      final done = build(dueAt: DateTime(2026, 10, 1, 9))
          .markDone(now: DateTime(2026, 10, 1, 9, 30));

      expect(done.isCompleted, isTrue);
      expect(done.completedAt, DateTime(2026, 10, 1, 9, 30));
    });

    test('rolls a daily reminder forward instead of closing it', () {
      final rolled = build(
        dueAt: DateTime(2026, 10, 1, 9),
        repeat: const RepeatRule(kind: RepeatKind.daily),
      ).markDone(now: DateTime(2026, 10, 1, 9, 30));

      expect(rolled.isCompleted, isFalse);
      expect(rolled.dueAt, DateTime(2026, 10, 2, 9));
    });

    test('a repeating reminder ignored for days lands in the future', () {
      final rolled = build(
        dueAt: DateTime(2026, 10, 1, 9),
        repeat: const RepeatRule(kind: RepeatKind.daily),
      ).markDone(now: DateTime(2026, 10, 20, 14));

      expect(rolled.dueAt, DateTime(2026, 10, 21, 9));
    });
  });

  group('snoozedBy', () {
    test('measures from now, not the original due time', () {
      // Due 09:00 but snoozed at 11:00: "10 minutes" must mean 11:10.
      final snoozed = build(dueAt: DateTime(2026, 10, 1, 9)).snoozedBy(
        const Duration(minutes: 10),
        now: DateTime(2026, 10, 1, 11),
      );

      expect(snoozed.dueAt, DateTime(2026, 10, 1, 11, 10));
      expect(snoozed.isCompleted, isFalse);
    });
  });

  group('repeat rules', () {
    test('weekly steps seven days', () {
      const rule = RepeatRule(kind: RepeatKind.weekly);
      final anchor = DateTime(2026, 10, 1, 9);
      expect(rule.nextAfter(anchor, anchor), DateTime(2026, 10, 8, 9));
    });

    test('monthly clamps into a short month', () {
      const rule = RepeatRule(kind: RepeatKind.monthly);
      final anchor = DateTime(2026, 1, 31, 9);
      expect(rule.nextAfter(anchor, anchor), DateTime(2026, 2, 28, 9));
    });

    test('monthly recovers the original day after a clamped month', () {
      // Guards the classic bug: stepping from the previous occurrence would
      // stick on the 28th forever.
      const rule = RepeatRule(kind: RepeatKind.monthly);
      final anchor = DateTime(2026, 1, 31, 9);
      final february = rule.nextAfter(anchor, anchor)!;
      expect(rule.nextAfter(anchor, february), DateTime(2026, 3, 31, 9));
    });

    test('custom days walk the selected weekdays in order', () {
      // 2026-10-05 is a Monday. Mon/Wed selected.
      const rule = RepeatRule(
        kind: RepeatKind.customDays,
        weekdays: <int>{DateTime.monday, DateTime.wednesday},
      );
      final anchor = DateTime(2026, 10, 5, 9);

      final wednesday = rule.nextAfter(anchor, anchor)!;
      expect(wednesday, DateTime(2026, 10, 7, 9));
      expect(rule.nextAfter(anchor, wednesday), DateTime(2026, 10, 12, 9));
    });

    test('a non-repeating rule yields nothing', () {
      final anchor = DateTime(2026, 10, 1, 9);
      expect(RepeatRule.none.nextAfter(anchor, anchor), isNull);
    });
  });

  group('isToday', () {
    test('is true only for the same calendar day', () {
      final reminder = build(dueAt: DateTime(2026, 10, 8, 23));
      expect(reminder.isToday(DateTime(2026, 10, 8, 1)), isTrue);
      expect(reminder.isToday(DateTime(2026, 10, 9, 1)), isFalse);
    });
  });
}
