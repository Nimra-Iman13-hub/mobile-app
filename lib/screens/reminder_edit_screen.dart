import 'package:flutter/material.dart';

import '../models/priority.dart';
import '../models/reminder.dart';
import '../models/repeat_rule.dart';

/// What the edit form produces.
typedef ReminderDraft = ({
  String title,
  String note,
  DateTime dueAt,
  Priority priority,
  RepeatRule repeat,
});

/// Create or edit a reminder. Passing [reminder] switches to edit mode.
///
/// Owns no storage: it returns a draft and lets the caller decide whether that
/// is an insert or an update, keeping persistence in one place.
class ReminderEditScreen extends StatefulWidget {
  const ReminderEditScreen({this.reminder, this.initialTitle, super.key});

  /// Null when creating.
  final Reminder? reminder;

  /// Pre-filled title, used when quick-add parsed a line but the user chose to
  /// open the full form.
  final String? initialTitle;

  static Future<ReminderDraft?> show(
    BuildContext context, {
    Reminder? reminder,
    String? initialTitle,
  }) {
    return Navigator.of(context).push<ReminderDraft>(
      MaterialPageRoute<ReminderDraft>(
        builder: (_) => ReminderEditScreen(
          reminder: reminder,
          initialTitle: initialTitle,
        ),
      ),
    );
  }

  @override
  State<ReminderEditScreen> createState() => _ReminderEditScreenState();
}

class _ReminderEditScreenState extends State<ReminderEditScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late DateTime _dueAt;
  late Priority _priority;
  late RepeatRule _repeat;

  bool get _isEditing => widget.reminder != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.reminder;
    _titleController = TextEditingController(
      text: existing?.title ?? widget.initialTitle ?? '',
    );
    _noteController = TextEditingController(text: existing?.note ?? '');
    _dueAt = existing?.dueAt ?? _defaultDueAt();
    _priority = existing?.priority ?? Priority.medium;
    _repeat = existing?.repeat ?? RepeatRule.none;
  }

  /// Next whole hour — "now" would be due before the user finished typing.
  static DateTime _defaultDueAt() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt,
      // Past dates allowed: people log things already missed. Flagged, not
      // blocked.
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked == null) return;
    setState(() {
      _dueAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _dueAt.hour,
        _dueAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt),
    );
    if (picked == null) return;
    setState(() {
      _dueAt = DateTime(
        _dueAt.year,
        _dueAt.month,
        _dueAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _pickRepeat() async {
    final result = await showModalBottomSheet<RepeatRule>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _RepeatSheet(initial: _repeat, anchor: _dueAt),
    );
    if (result != null) setState(() => _repeat = result);
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop<ReminderDraft>((
      title: _titleController.text.trim(),
      note: _noteController.text.trim(),
      dueAt: _dueAt,
      priority: _priority,
      repeat: _repeat,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = MaterialLocalizations.of(context);
    final isPast = _dueAt.isBefore(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit reminder' : 'New reminder'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            TextFormField(
              controller: _titleController,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'What needs doing?',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Give the reminder a title'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _noteController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.event_rounded),
                    title: const Text('Date'),
                    subtitle: Text(l10n.formatFullDate(_dueAt)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pickDate,
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('Time'),
                    subtitle: Text(
                      l10n.formatTimeOfDay(TimeOfDay.fromDateTime(_dueAt)),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pickTime,
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.repeat_rounded),
                    title: const Text('Repeat'),
                    subtitle: Text(_repeat.label),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pickRepeat,
                  ),
                ],
              ),
            ),

            if (isPast) ...<Widget>[
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'That time has passed, so no notification will be '
                      'scheduled.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),
            Text('PRIORITY', style: theme.textTheme.labelSmall),
            const SizedBox(height: 8),
            SegmentedButton<Priority>(
              segments: <ButtonSegment<Priority>>[
                for (final priority in Priority.values)
                  ButtonSegment<Priority>(
                    value: priority,
                    label: Text(priority.label),
                    icon: Icon(
                      Icons.circle,
                      size: 12,
                      color: priority.color(theme.colorScheme),
                    ),
                  ),
              ],
              selected: <Priority>{_priority},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _save,
            child: Text(_isEditing ? 'Save changes' : 'Add reminder'),
          ),
        ),
      ),
    );
  }
}

/// Repeat picker. Custom days only appear once "Custom days" is chosen, so the
/// common cases stay one tap.
class _RepeatSheet extends StatefulWidget {
  const _RepeatSheet({required this.initial, required this.anchor});

  final RepeatRule initial;
  final DateTime anchor;

  @override
  State<_RepeatSheet> createState() => _RepeatSheetState();
}

class _RepeatSheetState extends State<_RepeatSheet> {
  late RepeatKind _kind;
  late Set<int> _weekdays;

  @override
  void initState() {
    super.initState();
    _kind = widget.initial.kind;
    _weekdays = widget.initial.weekdays.isEmpty
        ? <int>{widget.anchor.weekday}
        : Set<int>.of(widget.initial.weekdays);
  }

  /// A custom-days rule with nothing selected would never fire.
  bool get _canSave =>
      _kind != RepeatKind.customDays || _weekdays.isNotEmpty;

  static const Map<RepeatKind, String> _labels = <RepeatKind, String>{
    RepeatKind.none: 'Never',
    RepeatKind.daily: 'Daily',
    RepeatKind.weekly: 'Weekly',
    RepeatKind.monthly: 'Monthly',
    RepeatKind.customDays: 'Custom days',
  };

  static const List<String> _dayLabels = <String>[
    'M', 'T', 'W', 'T', 'F', 'S', 'S',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Repeat', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final entry in _labels.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _kind == entry.key,
                  onSelected: (_) => setState(() => _kind = entry.key),
                ),
            ],
          ),
          if (_kind == RepeatKind.customDays) ...<Widget>[
            const SizedBox(height: 20),
            Wrap(
              spacing: 6,
              children: <Widget>[
                for (var day = DateTime.monday; day <= DateTime.sunday; day++)
                  FilterChip(
                    label: Text(_dayLabels[day - 1]),
                    selected: _weekdays.contains(day),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _weekdays.add(day);
                      } else {
                        _weekdays.remove(day);
                      }
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _canSave
                      ? () => Navigator.of(context).pop(
                            RepeatRule(
                              kind: _kind,
                              weekdays: _kind == RepeatKind.customDays
                                  ? _weekdays
                                  : const <int>{},
                            ),
                          )
                      : null,
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
