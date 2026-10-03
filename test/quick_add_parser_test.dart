import 'package:flutter_test/flutter_test.dart';
import 'package:helloworld/services/quick_add_parser.dart';

/// A Thursday at 10:00, so "tomorrow" is Friday and weekday maths is readable.
final DateTime now = DateTime(2026, 10, 8, 10);

void main() {
  test('the documented example', () {
    final result = QuickAddParser.parse('Call mom tomorrow 6pm', now: now);

    expect(result.title, 'Call mom');
    expect(result.dueAt, DateTime(2026, 10, 9, 18));
    expect(result.matchedDate, isTrue);
    expect(result.matchedTime, isTrue);
  });

  group('times', () {
    test('12-hour with minutes', () {
      final result = QuickAddParser.parse('Dentist tomorrow 6:30pm', now: now);
      expect(result.dueAt, DateTime(2026, 10, 9, 18, 30));
      expect(result.title, 'Dentist');
    });

    test('24-hour', () {
      final result = QuickAddParser.parse('Standup tomorrow 09:15', now: now);
      expect(result.dueAt, DateTime(2026, 10, 9, 9, 15));
    });

    test('noon and midnight do not follow the +12 rule', () {
      expect(
        QuickAddParser.parse('Lunch today 12pm', now: now).dueAt,
        DateTime(2026, 10, 8, 12),
      );
      expect(
        QuickAddParser.parse('Sleep today 12am', now: now).dueAt,
        DateTime(2026, 10, 8, 0),
      );
    });

    test('a bare time already past today rolls to tomorrow', () {
      // 6am typed at 10am means tomorrow, not four hours ago.
      final result = QuickAddParser.parse('Gym 6am', now: now);
      expect(result.dueAt, DateTime(2026, 10, 9, 6));
      expect(result.title, 'Gym');
    });
  });

  group('dates', () {
    test('today keeps the date and defaults the hour', () {
      final result = QuickAddParser.parse('Pay rent today', now: now);
      expect(result.dueAt, DateTime(2026, 10, 8, QuickAddParser.defaultHour));
      expect(result.title, 'Pay rent');
    });

    test('tonight implies an evening hour', () {
      final result = QuickAddParser.parse('Bins out tonight', now: now);
      expect(result.dueAt, DateTime(2026, 10, 8, 20));
      expect(result.title, 'Bins out');
    });

    test('a weekday name means the next such day', () {
      // Thursday the 8th -> the coming Monday is the 12th.
      final result = QuickAddParser.parse('Report monday 9am', now: now);
      expect(result.dueAt, DateTime(2026, 10, 12, 9));
      expect(result.title, 'Report');
    });

    test('the same weekday as today means next week, not today', () {
      final result = QuickAddParser.parse('Review thursday', now: now);
      expect(result.dueAt.day, 15);
    });

    test('"on friday" strips the preposition too', () {
      final result = QuickAddParser.parse('Email Sam on friday', now: now);
      expect(result.title, 'Email Sam');
      expect(result.dueAt, DateTime(2026, 10, 9, QuickAddParser.defaultHour));
    });
  });

  group('relative offsets', () {
    test('in 20 minutes', () {
      final result = QuickAddParser.parse('Check oven in 20 minutes', now: now);
      expect(result.dueAt, DateTime(2026, 10, 8, 10, 20));
      expect(result.title, 'Check oven');
    });

    test('in 2 hours', () {
      expect(
        QuickAddParser.parse('Call back in 2 hours', now: now).dueAt,
        DateTime(2026, 10, 8, 12),
      );
    });

    test('in 3 days', () {
      expect(
        QuickAddParser.parse('Water plants in 3 days', now: now).dueAt,
        DateTime(2026, 10, 11, 10),
      );
    });
  });

  group('fallbacks', () {
    test('no date keeps the whole text and flags nothing matched', () {
      final result = QuickAddParser.parse('Buy milk', now: now);

      expect(result.title, 'Buy milk');
      expect(result.matchedAnything, isFalse);
      expect(result.dueAt, DateTime(2026, 10, 8, QuickAddParser.defaultHour));
    });

    test('a title made only of date words is not left empty', () {
      // Stripping would empty the title, so the original text is kept.
      final result = QuickAddParser.parse('tomorrow', now: now);
      expect(result.title, 'tomorrow');
      expect(result.matchedDate, isTrue);
    });
  });
}
