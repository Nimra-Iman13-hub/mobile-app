import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Where notification permission stands.
enum NotificationPermission { notRequested, granted, denied, unsupported }

/// What the user tapped on a notification.
enum NotificationAction {
  open('open'),
  markDone('done'),
  snooze5('snooze_5'),
  snooze10('snooze_10'),
  snooze30('snooze_30');

  const NotificationAction(this.id);

  final String id;

  String get label => switch (this) {
        NotificationAction.open => 'Open',
        NotificationAction.markDone => 'Done',
        NotificationAction.snooze5 => '5 min',
        NotificationAction.snooze10 => '10 min',
        NotificationAction.snooze30 => '30 min',
      };

  Duration? get snooze => switch (this) {
        NotificationAction.snooze5 => const Duration(minutes: 5),
        NotificationAction.snooze10 => const Duration(minutes: 10),
        NotificationAction.snooze30 => const Duration(minutes: 30),
        _ => null,
      };

  /// Buttons shown on the notification. Android collapses past three.
  static const List<NotificationAction> buttons = <NotificationAction>[
    NotificationAction.markDone,
    NotificationAction.snooze10,
    NotificationAction.snooze30,
  ];

  /// Snooze options offered inside the app, where there is room for all three.
  static const List<NotificationAction> snoozeOptions = <NotificationAction>[
    NotificationAction.snooze5,
    NotificationAction.snooze10,
    NotificationAction.snooze30,
  ];

  static NotificationAction fromId(String? id) {
    if (id == null || id.isEmpty) return NotificationAction.open;
    return NotificationAction.values.firstWhere(
      (a) => a.id == id,
      orElse: () => NotificationAction.open,
    );
  }
}

/// A notification response, paired with the reminder it refers to.
class NotificationEvent {
  const NotificationEvent({required this.reminderId, required this.action});

  final String reminderId;
  final NotificationAction action;
}

/// Schedules and cancels local notifications.
///
/// One code path for every platform: `flutter_local_notifications` 22
/// dispatches on `kIsWeb` internally.
///
/// Every call into the plugin is wrapped by [_guard]. That is not defensive
/// padding — when the plugin has not registered a platform implementation,
/// `resolvePlatformSpecificImplementation` throws `LateInitializationError`,
/// which is an `Error` and so is missed by any `on Exception` catch. Letting
/// that escape takes the whole app down with a blank screen on a platform that
/// simply has no notification support. Notifications are a feature; failing to
/// have them must never stop the app from running.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Web-only fallback timers, keyed by notification id.
  final Map<int, Timer> _webTimers = <int, Timer>{};

  final StreamController<NotificationEvent> _events =
      StreamController<NotificationEvent>.broadcast();

  /// Notification taps received while the app is running.
  Stream<NotificationEvent> get events => _events.stream;

  bool _available = false;

  static const String _channelId = 'reminders';
  static const String _channelName = 'Reminders';
  static const String _channelDescription = 'Alerts for reminders when due';
  static const String _darwinCategoryId = 'reminder_actions';

  /// False on web, where a scheduled reminder dies with the tab. The UI reads
  /// this so it can say so rather than promise something undeliverable.
  bool get schedulingSurvivesAppClose => !kIsWeb;

  /// Runs [body], swallowing anything the plugin throws (including `Error`s).
  Future<T?> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Object catch (error) {
      debugPrint('NotificationService: $error');
      return null;
    }
  }

  Future<void> init() async {
    await _configureTimeZone();

    final darwin = DarwinInitializationSettings(
      // Asked for later from a button, not over a blank first frame.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          _darwinCategoryId,
          actions: <DarwinNotificationAction>[
            for (final action in NotificationAction.buttons)
              DarwinNotificationAction.plain(action.id, action.label),
          ],
        ),
      ],
    );

    final settings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: darwin,
      macOS: darwin,
      web: const WebInitializationSettings(),
    );

    final result = await _guard(
      () => _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _onResponse,
      ),
    );

    // A null result means _guard caught something; treat the service as
    // unavailable so later calls short-circuit instead of throwing again.
    _available = result != null;
    if (_available) await _guard(_createAndroidChannel);
  }

  Future<void> _configureTimeZone() async {
    if (kIsWeb) return;

    await _guard(() async {
      tz_data.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    });
  }

  Future<void> _createAndroidChannel() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
      ),
    );
  }

  void _onResponse(NotificationResponse response) {
    final id = _decodePayload(response.payload);
    if (id == null) return;
    _events.add(
      NotificationEvent(
        reminderId: id,
        action: NotificationAction.fromId(response.actionId),
      ),
    );
  }

  // --- Permission ----------------------------------------------------------

  Future<NotificationPermission> permission() async {
    if (!_available) return NotificationPermission.unsupported;

    final result = await _guard<NotificationPermission>(() async {
      if (kIsWeb) {
        final web = _plugin.resolvePlatformSpecificImplementation<
            WebFlutterLocalNotificationsPlugin>();
        if (web == null) return NotificationPermission.unsupported;
        return switch (web.permissionStatus) {
          WebNotificationPermission.granted => NotificationPermission.granted,
          WebNotificationPermission.denied => NotificationPermission.denied,
          WebNotificationPermission.defaultPermissions =>
            NotificationPermission.notRequested,
        };
      }

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final enabled = await android.areNotificationsEnabled() ?? false;
        return enabled
            ? NotificationPermission.granted
            : NotificationPermission.notRequested;
      }
      return NotificationPermission.notRequested;
    });

    return result ?? NotificationPermission.unsupported;
  }

  /// Prompts for permission. Must come from a user gesture — browsers reject a
  /// request that did not follow a click.
  Future<NotificationPermission> requestPermission() async {
    if (!_available) return NotificationPermission.unsupported;

    final result = await _guard<NotificationPermission>(() async {
      if (kIsWeb) {
        final web = _plugin.resolvePlatformSpecificImplementation<
            WebFlutterLocalNotificationsPlugin>();
        if (web == null) return NotificationPermission.unsupported;
        final granted = await web.requestNotificationsPermission() ?? false;
        return granted
            ? NotificationPermission.granted
            : NotificationPermission.denied;
      }

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final granted = await android.requestNotificationsPermission() ?? false;
        // Android 12+ gates exact alarms separately; a refusal is survivable,
        // see the inexact fallback in _scheduleNative.
        await android.requestExactAlarmsPermission();
        return granted
            ? NotificationPermission.granted
            : NotificationPermission.denied;
      }

      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final granted = await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
        return granted
            ? NotificationPermission.granted
            : NotificationPermission.denied;
      }
      return NotificationPermission.unsupported;
    });

    return result ?? NotificationPermission.unsupported;
  }

  // --- Scheduling ----------------------------------------------------------

  /// Schedules a notification for [when], replacing any with the same [id].
  ///
  /// Returns false when nothing was scheduled: a past due time, or no support.
  /// Saving the reminder is the caller's business either way.
  Future<bool> schedule({
    required int id,
    required String reminderId,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    await cancel(id);
    if (!_available) return false;

    // A past due time has already been missed; firing it now would just be
    // noise on every launch.
    if (!when.isAfter(DateTime.now())) return false;

    if (kIsWeb) {
      return _scheduleWeb(
        id: id,
        reminderId: reminderId,
        title: title,
        body: body,
        when: when,
      );
    }
    final ok = await _guard(
      () => _scheduleNative(
        id: id,
        reminderId: reminderId,
        title: title,
        body: body,
        when: when,
      ),
    );
    return ok ?? false;
  }

  Future<bool> _scheduleNative({
    required int id,
    required String reminderId,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    final scheduledAt = tz.TZDateTime.from(when, tz.local);
    final payload = _encodePayload(reminderId);

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledAt,
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
      return true;
    } on PlatformException catch (error) {
      if (error.code != 'exact_alarms_not_permitted') rethrow;
      // Android 14 refuses exact alarms without the extra permission. A few
      // minutes late beats never arriving.
      debugPrint('NotificationService: exact alarms denied, using inexact');
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledAt,
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
      return true;
    }
  }

  /// Web stand-in: an in-page timer. `zonedSchedule` throws
  /// `UnsupportedError` on web because browsers cannot wake a closed page, so
  /// this fires only while the tab is open.
  bool _scheduleWeb({
    required int id,
    required String reminderId,
    required String title,
    required String body,
    required DateTime when,
  }) {
    final delay = when.difference(DateTime.now());
    if (delay.isNegative) return false;

    _webTimers[id] = Timer(delay, () {
      _webTimers.remove(id);
      unawaited(
        _guard(
          () => _plugin.show(
            id: id,
            title: title,
            body: body,
            payload: _encodePayload(reminderId),
          ),
        ),
      );
    });
    return true;
  }

  Future<void> cancel(int id) async {
    _webTimers.remove(id)?.cancel();
    if (!_available) return;
    await _guard(() => _plugin.cancel(id: id));
  }

  NotificationDetails _details() => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          actions: <AndroidNotificationAction>[
            for (final action in NotificationAction.buttons)
              AndroidNotificationAction(
                action.id,
                action.label,
                showsUserInterface: false,
                cancelNotification: true,
              ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: _darwinCategoryId,
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

  static String _encodePayload(String reminderId) =>
      jsonEncode(<String, Object?>{'reminderId': reminderId});

  static String? _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final id = decoded['reminderId'];
      return id is String && id.isNotEmpty ? id : null;
    } on FormatException {
      return null;
    }
  }

  void dispose() {
    for (final timer in _webTimers.values) {
      timer.cancel();
    }
    _webTimers.clear();
    unawaited(_events.close());
  }
}
