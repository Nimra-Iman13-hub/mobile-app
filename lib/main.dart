import 'package:flutter/material.dart';

import 'screens/reminder_list_screen.dart';
import 'services/notification_service.dart';
import 'services/reminder_store.dart';
import 'services/settings_store.dart';

/// Startup.
///
/// The notification plugin and the theme preference are resolved before
/// `runApp`: the plugin because a notification that launched the app can only
/// be read once, the theme so the first frame is not the wrong colour.
/// Reminders load after the first frame, so a cold start paints immediately.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notifications = NotificationService();
  await notifications.init();

  final settings = SettingsStore();
  await settings.load();

  final store = ReminderStore(notifications: notifications);

  runApp(
    ReminderApp(
      store: store,
      notifications: notifications,
      settings: settings,
    ),
  );

  // Also re-lays every notification, which is what restores alarms after an
  // Android reboot or an app update.
  await store.load();
}

class ReminderApp extends StatelessWidget {
  const ReminderApp({
    required this.store,
    required this.notifications,
    required this.settings,
    super.key,
  });

  final ReminderStore store;
  final NotificationService notifications;
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'Reminders',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
        ),
        themeMode: settings.themeMode,
        home: ReminderListScreen(
          store: store,
          notifications: notifications,
          settings: settings,
        ),
      ),
    );
  }
}
