import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helloworld/main.dart';
import 'package:helloworld/services/notification_service.dart';
import 'package:helloworld/services/reminder_store.dart';
import 'package:helloworld/services/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guards against the app failing to paint at all — the failure mode that
/// looks like a blank screen in the browser and cannot be diagnosed from a
/// 200 on the document.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('renders the list screen on a cold start', (tester) async {
    final store = ReminderStore(notifications: NotificationService());

    await tester.pumpWidget(
      ReminderApp(
        store: store,
        notifications: NotificationService(),
        settings: SettingsStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('No reminders yet'), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'New'), findsOneWidget);
  });

  testWidgets('shows a stored reminder after load', (tester) async {
    final store = ReminderStore(notifications: NotificationService());

    await tester.pumpWidget(
      ReminderApp(
        store: store,
        notifications: NotificationService(),
        settings: SettingsStore(),
      ),
    );
    await store.add(
      title: 'Call mom',
      note: '',
      dueAt: DateTime.now().add(const Duration(hours: 2)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Call mom'), findsOneWidget);
  });
}
