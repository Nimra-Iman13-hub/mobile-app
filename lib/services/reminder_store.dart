import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/priority.dart';
import '../models/reminder.dart';
import '../models/repeat_rule.dart';
import 'notification_service.dart';

/// Which group of reminders the list is showing.
enum ReminderFilter {
  all('All'),
  today('Today'),
  upcoming('Upcoming'),
  completed('Completed');

  const ReminderFilter(this.label);

  final String label;
}

/// How the open list is ordered.
enum ReminderSort {
  byDate('Date'),
  byPriority('Priority');

  const ReminderSort(this.label);

  final String label;
}

/// Holds the reminders and keeps storage and notifications in step.
///
/// A plain [ChangeNotifier]: one list, a handful of operations, so a
/// state-management package would be cost without benefit.
///
/// Invariant: every write persists and then re-syncs that reminder's
/// notification, in that order — a crash between the two loses an alarm
/// rather than the reminder.
class ReminderStore extends ChangeNotifier {
  ReminderStore({required NotificationService notifications})
      : _notifications = notifications;

  final NotificationService _notifications;

  static const String _storageKey = 'reminders';

  List<Reminder> _reminders = <Reminder>[];

  String _query = '';
  ReminderFilter _filter = ReminderFilter.all;
  ReminderSort _sort = ReminderSort.byDate;
  Set<Priority> _priorityFilter = <Priority>{};

  String get query => _query;
  ReminderFilter get filter => _filter;
  ReminderSort get sort => _sort;
  Set<Priority> get priorityFilter => Set<Priority>.unmodifiable(_priorityFilter);

  /// Everything stored, soonest first.
  List<Reminder> get all => List<Reminder>.unmodifiable(_reminders);

  bool get hasAny => _reminders.isNotEmpty;

  /// Open reminders matching the current search, filter and sort.
  List<Reminder> get visibleOpen {
    final items = _reminders
        .where((r) => !r.isCompleted)
        .where(_matchesQuery)
        .where(_matchesPriority)
        .where(_matchesFilter)
        .toList();

    items.sort(
      _sort == ReminderSort.byPriority
          // Priority first, then soonest within a priority — otherwise two
          // "high" items would sit in arbitrary order.
          ? (a, b) {
              final byRank = a.priority.rank.compareTo(b.priority.rank);
              return byRank != 0 ? byRank : a.dueAt.compareTo(b.dueAt);
            }
          : (a, b) => a.dueAt.compareTo(b.dueAt),
    );
    return List<Reminder>.unmodifiable(items);
  }

  /// Completed reminders matching the search, most recently finished first.
  List<Reminder> get visibleCompleted {
    if (_filter == ReminderFilter.today || _filter == ReminderFilter.upcoming) {
      return const <Reminder>[];
    }

    final items = _reminders
        .where((r) => r.isCompleted)
        .where(_matchesQuery)
        .where(_matchesPriority)
        .toList()
      ..sort((a, b) {
        final aAt = a.completedAt ?? a.dueAt;
        final bAt = b.completedAt ?? b.dueAt;
        return bAt.compareTo(aAt);
      });
    return List<Reminder>.unmodifiable(items);
  }

  bool _matchesQuery(Reminder r) {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return r.title.toLowerCase().contains(needle);
  }

  bool _matchesPriority(Reminder r) =>
      _priorityFilter.isEmpty || _priorityFilter.contains(r.priority);

  bool _matchesFilter(Reminder r) => switch (_filter) {
        ReminderFilter.all => true,
        ReminderFilter.today => r.isToday(),
        // Upcoming means strictly after today, so it does not duplicate Today.
        ReminderFilter.upcoming => !r.isToday() && !r.isPast(),
        ReminderFilter.completed => false,
      };

  // --- Search and filter ---------------------------------------------------

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void setFilter(ReminderFilter value) {
    _filter = value;
    notifyListeners();
  }

  void setSort(ReminderSort value) {
    _sort = value;
    notifyListeners();
  }

  void togglePriorityFilter(Priority priority) {
    _priorityFilter = <Priority>{..._priorityFilter};
    if (!_priorityFilter.remove(priority)) _priorityFilter.add(priority);
    notifyListeners();
  }

  void clearFilters() {
    _query = '';
    _filter = ReminderFilter.all;
    _priorityFilter = <Priority>{};
    notifyListeners();
  }

  // --- Writes --------------------------------------------------------------

  /// Loads from storage and re-lays every notification.
  ///
  /// The reschedule matters on Android, which drops pending alarms on reboot
  /// and on app update; doing it every launch survives both with no
  /// bookkeeping of our own.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _reminders = Reminder.decodeList(prefs.getString(_storageKey));
    _sortStored();
    notifyListeners();
    await _rescheduleAll();
  }

  Future<Reminder> add({
    required String title,
    required String note,
    required DateTime dueAt,
    Priority priority = Priority.medium,
    RepeatRule repeat = RepeatRule.none,
  }) async {
    final reminder = Reminder(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.trim(),
      note: note.trim(),
      dueAt: dueAt,
      priority: priority,
      repeat: repeat,
      notificationId: _nextNotificationId(),
    );

    _reminders = <Reminder>[..._reminders, reminder];
    await _commit();
    await _syncNotification(reminder);
    return reminder;
  }

  Future<void> update(Reminder updated) async {
    final index = _reminders.indexWhere((r) => r.id == updated.id);
    if (index == -1) return;

    _reminders = <Reminder>[..._reminders]..[index] = updated;
    await _commit();
    await _syncNotification(updated);
  }

  /// Marks done (or rolls a repeating reminder forward). Returns the previous
  /// version so the caller can offer an undo.
  Future<Reminder?> markDone(String id) async {
    final before = _byId(id);
    if (before == null) return null;
    await update(before.markDone());
    return before;
  }

  Future<void> markNotDone(String id) async {
    final reminder = _byId(id);
    if (reminder == null) return;
    await update(reminder.markNotDone());
  }

  /// Restores a reminder to exactly how it was — used by undo.
  Future<void> restoreVersion(Reminder previous) => update(previous);

  Future<void> snooze(String id, Duration duration) async {
    final reminder = _byId(id);
    if (reminder == null) return;
    await update(reminder.snoozedBy(duration));
  }

  /// Removes a reminder and cancels its alarm. Returns it for undo.
  Future<Reminder?> remove(String id) async {
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index == -1) return null;

    final removed = _reminders[index];
    _reminders = <Reminder>[..._reminders]..removeAt(index);
    await _commit();
    await _notifications.cancel(removed.notificationId);
    return removed;
  }

  /// Puts a removed reminder back with its original ids, so the alarm returns
  /// exactly as it was.
  Future<void> restore(Reminder reminder) async {
    if (_reminders.any((r) => r.id == reminder.id)) return;
    _reminders = <Reminder>[..._reminders, reminder];
    await _commit();
    await _syncNotification(reminder);
  }

  Reminder? _byId(String id) {
    for (final reminder in _reminders) {
      if (reminder.id == id) return reminder;
    }
    return null;
  }

  Future<void> _commit() async {
    _sortStored();
    await _persist();
    notifyListeners();
  }

  Future<void> _syncNotification(Reminder reminder) async {
    if (reminder.isCompleted) {
      await _notifications.cancel(reminder.notificationId);
      return;
    }
    await _notifications.schedule(
      id: reminder.notificationId,
      reminderId: reminder.id,
      title: reminder.title,
      body: reminder.note.isNotEmpty ? reminder.note : 'Reminder due now',
      when: reminder.dueAt,
    );
  }

  Future<void> _rescheduleAll() async {
    for (final reminder in _reminders) {
      await _syncNotification(reminder);
    }
  }

  /// A notification id not already taken, inside the 32-bit range the platform
  /// allows.
  int _nextNotificationId() {
    final used = _reminders.map((r) => r.notificationId).toSet();
    var candidate = DateTime.now().millisecondsSinceEpoch % 0x7FFFFF;
    while (used.contains(candidate)) {
      candidate = (candidate + 1) % 0x7FFFFF;
    }
    return candidate;
  }

  void _sortStored() {
    _reminders = <Reminder>[..._reminders]
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, Reminder.encodeList(_reminders));
  }
}
