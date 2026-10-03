import 'dart:async';

import 'package:flutter/material.dart';

import '../models/priority.dart';
import '../models/reminder.dart';
import '../services/notification_service.dart';
import '../services/quick_add_parser.dart';
import '../services/reminder_store.dart';
import '../services/settings_store.dart';
import 'reminder_edit_screen.dart';
import 'settings_screen.dart';

/// The main list: quick add, search, filters, open and completed sections.
class ReminderListScreen extends StatefulWidget {
  const ReminderListScreen({
    required this.store,
    required this.notifications,
    required this.settings,
    super.key,
  });

  final ReminderStore store;
  final NotificationService notifications;
  final SettingsStore settings;

  @override
  State<ReminderListScreen> createState() => _ReminderListScreenState();
}

class _ReminderListScreenState extends State<ReminderListScreen> {
  final TextEditingController _quickAddController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  NotificationPermission _permission = NotificationPermission.notRequested;
  StreamSubscription<NotificationEvent>? _notificationSub;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChanged);

    // Notification buttons (Done / 10 min / 30 min) arrive here.
    _notificationSub =
        widget.notifications.events.listen(_handleNotificationEvent);

    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPermission());
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    unawaited(_notificationSub?.cancel());
    _quickAddController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handleNotificationEvent(NotificationEvent event) async {
    final snooze = event.action.snooze;
    if (snooze != null) {
      await widget.store.snooze(event.reminderId, snooze);
      if (mounted) _snack('Snoozed ${event.action.label}');
    } else if (event.action == NotificationAction.markDone) {
      await widget.store.markDone(event.reminderId);
      if (mounted) _snack('Marked done');
    }
  }

  Future<void> _refreshPermission() async {
    final permission = await widget.notifications.permission();
    if (mounted) setState(() => _permission = permission);
  }

  Future<void> _requestPermission() async {
    final result = await widget.notifications.requestPermission();
    if (!mounted) return;
    setState(() => _permission = result);
    _snack(switch (result) {
      NotificationPermission.granted => 'Notifications enabled',
      NotificationPermission.denied =>
        'Blocked. Reminders are still saved, but will not alert.',
      NotificationPermission.unsupported =>
        'This platform cannot show notifications.',
      NotificationPermission.notRequested => 'Permission not granted.',
    });
  }

  void _snack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  // --- Actions -------------------------------------------------------------

  /// Quick add: parses "Call mom tomorrow 6pm" into a title plus due date.
  Future<void> _quickAdd() async {
    final text = _quickAddController.text.trim();
    if (text.isEmpty) return;

    final parsed = QuickAddParser.parse(text);
    _quickAddController.clear();

    await widget.store.add(
      title: parsed.title,
      note: '',
      dueAt: parsed.dueAt,
    );
    if (!mounted) return;

    final when = MaterialLocalizations.of(context);
    _snack(
      parsed.matchedAnything
          // Say what was understood: a silent guess about the date is the one
          // thing that makes quick add untrustworthy.
          ? 'Added for ${when.formatMediumDate(parsed.dueAt)}, '
              '${when.formatTimeOfDay(TimeOfDay.fromDateTime(parsed.dueAt))}'
          : 'Added with a default time — no date found in that text',
    );
  }

  Future<void> _create() async {
    final draft = await ReminderEditScreen.show(context);
    if (draft == null) return;
    await widget.store.add(
      title: draft.title,
      note: draft.note,
      dueAt: draft.dueAt,
      priority: draft.priority,
      repeat: draft.repeat,
    );
    if (mounted) _snack('Reminder added');
  }

  Future<void> _edit(Reminder reminder) async {
    final draft = await ReminderEditScreen.show(context, reminder: reminder);
    if (draft == null) return;
    await widget.store.update(
      reminder.copyWith(
        title: draft.title,
        note: draft.note,
        dueAt: draft.dueAt,
        priority: draft.priority,
        repeat: draft.repeat,
      ),
    );
    if (mounted) _snack('Reminder updated');
  }

  Future<void> _toggleDone(Reminder reminder) async {
    if (reminder.isCompleted) {
      await widget.store.markNotDone(reminder.id);
      return;
    }

    final before = await widget.store.markDone(reminder.id);
    if (before == null || !mounted) return;

    _snack(
      before.repeat.repeats ? 'Moved to the next occurrence' : 'Marked done',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => widget.store.restoreVersion(before),
      ),
    );
  }

  Future<void> _snooze(Reminder reminder) async {
    final action = await showModalBottomSheet<NotificationAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final option in NotificationAction.snoozeOptions)
              ListTile(
                leading: const Icon(Icons.snooze_rounded),
                title: Text('Snooze ${option.label}'),
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
          ],
        ),
      ),
    );
    if (action?.snooze == null) return;

    await widget.store.snooze(reminder.id, action!.snooze!);
    if (mounted) _snack('Snoozed ${action.label}');
  }

  Future<bool> _confirmDelete(Reminder reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: Text('"${reminder.title}" will be removed.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    final removed = await widget.store.remove(reminder.id);
    if (removed == null || !mounted) return true;

    _snack(
      'Reminder deleted',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => widget.store.restore(removed),
      ),
    );
    return true;
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final open = store.visibleOpen;
    final completed = store.visibleCompleted;
    final nothingToShow = open.isEmpty && completed.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search titles',
                  border: InputBorder.none,
                ),
                onChanged: store.setQuery,
              )
            : const Text('Reminders'),
        actions: <Widget>[
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _searching ? 'Close search' : 'Search',
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _searchController.clear();
                store.setQuery('');
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort by ${store.sort == ReminderSort.byDate ? 'priority' : 'date'}',
            onPressed: () => store.setSort(
              store.sort == ReminderSort.byDate
                  ? ReminderSort.byPriority
                  : ReminderSort.byDate,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(settings: widget.settings),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
      ),
      body: Column(
        children: <Widget>[
          _NotificationBanner(
            permission: _permission,
            survivesAppClose: widget.notifications.schedulingSurvivesAppClose,
            onRequest: _requestPermission,
          ),
          _QuickAddBar(
            controller: _quickAddController,
            onSubmit: _quickAdd,
          ),
          _FilterBar(store: store),
          Expanded(
            child: nothingToShow
                ? _EmptyState(
                    hasAny: store.hasAny,
                    onClear: store.clearFilters,
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: <Widget>[
                      for (final reminder in open)
                        _ReminderTile(
                          reminder: reminder,
                          onTap: () => _edit(reminder),
                          onToggleDone: () => _toggleDone(reminder),
                          onSnooze: () => _snooze(reminder),
                          onConfirmDelete: () => _confirmDelete(reminder),
                        ),
                      if (completed.isNotEmpty) ...<Widget>[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                          child: Text(
                            'COMPLETED',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        for (final reminder in completed)
                          _ReminderTile(
                            reminder: reminder,
                            onTap: () => _edit(reminder),
                            onToggleDone: () => _toggleDone(reminder),
                            onSnooze: () => _snooze(reminder),
                            onConfirmDelete: () => _confirmDelete(reminder),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuickAddBar extends StatelessWidget {
  const _QuickAddBar({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => onSubmit(),
        decoration: InputDecoration(
          hintText: 'Call mom tomorrow 6pm',
          prefixIcon: const Icon(Icons.bolt_rounded),
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'Quick add',
            onPressed: onSubmit,
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.store});

  final ReminderStore store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          for (final filter in ReminderFilter.values) ...<Widget>[
            ChoiceChip(
              label: Text(filter.label),
              selected: store.filter == filter,
              onSelected: (_) => store.setFilter(filter),
            ),
            const SizedBox(width: 6),
          ],
          const SizedBox(width: 6),
          for (final priority in Priority.values) ...<Widget>[
            FilterChip(
              label: Text(priority.label),
              avatar: Icon(
                Icons.circle,
                size: 12,
                color: priority.color(scheme),
              ),
              selected: store.priorityFilter.contains(priority),
              onSelected: (_) => store.togglePriorityFilter(priority),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// A row. Swipe right to toggle done, left to delete.
class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.reminder,
    required this.onTap,
    required this.onToggleDone,
    required this.onSnooze,
    required this.onConfirmDelete,
  });

  final Reminder reminder;
  final VoidCallback onTap;
  final VoidCallback onToggleDone;
  final VoidCallback onSnooze;
  final Future<bool> Function() onConfirmDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = MaterialLocalizations.of(context);
    final overdue = !reminder.isCompleted && reminder.isPast();

    return Dismissible(
      key: ValueKey<String>(reminder.id),
      background: ColoredBox(
        color: scheme.primaryContainer,
        child: const Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Icon(Icons.check_rounded),
          ),
        ),
      ),
      secondaryBackground: ColoredBox(
        color: scheme.errorContainer,
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Icon(Icons.delete_outline_rounded),
          ),
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onToggleDone();
          // Refuse the dismissal: the reminder still exists, it just moves to
          // another section, and animating it out would briefly show it gone.
          return false;
        }
        return onConfirmDelete();
      },
      child: ListTile(
        onTap: onTap,
        onLongPress: reminder.isCompleted ? null : onSnooze,
        leading: IconButton(
          tooltip: reminder.isCompleted ? 'Mark not done' : 'Mark done',
          icon: Icon(
            reminder.isCompleted
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: reminder.isCompleted
                ? scheme.primary
                : reminder.priority.color(scheme),
          ),
          onPressed: onToggleDone,
        ),
        title: Text(
          reminder.title,
          style: reminder.isCompleted
              ? theme.textTheme.bodyLarge?.copyWith(
                  decoration: TextDecoration.lineThrough,
                  color: scheme.onSurfaceVariant,
                )
              : theme.textTheme.bodyLarge,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  '${l10n.formatMediumDate(reminder.dueAt)} · '
                  '${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(reminder.dueAt))}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: overdue ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
                if (reminder.repeat.repeats) ...<Widget>[
                  const SizedBox(width: 8),
                  Icon(Icons.repeat_rounded, size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 2),
                  Text(
                    reminder.repeat.label,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            if (reminder.note.isNotEmpty)
              Text(
                reminder.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        trailing: Icon(
          Icons.circle,
          size: 10,
          color: reminder.priority.color(scheme),
        ),
      ),
    );
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({
    required this.permission,
    required this.survivesAppClose,
    required this.onRequest,
  });

  final NotificationPermission permission;
  final bool survivesAppClose;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (String message, bool showButton) = switch (permission) {
      NotificationPermission.granted when survivesAppClose => ('', false),
      NotificationPermission.granted => (
          'Notifications only fire while this tab is open — browsers cannot '
              'wake a closed page.',
          false,
        ),
      NotificationPermission.notRequested => (
          'Turn on notifications to be alerted when a reminder is due.',
          true,
        ),
      NotificationPermission.denied => (
          'Notifications are blocked. Reminders still save, but will not '
              'alert.',
          false,
        ),
      NotificationPermission.unsupported => (
          'This platform cannot show notifications.',
          false,
        ),
    };

    if (message.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          if (showButton)
            TextButton(onPressed: onRequest, child: const Text('Enable')),
        ],
      ),
    );
  }
}

/// Distinguishes "nothing yet" from "filters hide everything" — showing the
/// first to someone with a stray filter is how a filter looks like data loss.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAny, required this.onClear});

  final bool hasAny;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              hasAny ? Icons.search_off_rounded : Icons.notifications_none_rounded,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              hasAny ? 'No matches' : 'No reminders yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              hasAny
                  ? 'No reminders match the current search and filters.'
                  : 'Use quick add above, or tap New.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (hasAny) ...<Widget>[
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: onClear,
                child: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
