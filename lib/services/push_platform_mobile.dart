import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef PushCredentials = Map<String, String>;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushPlatformBridge {
  static bool _initialized = false;
  static final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'order_ready_channel',
    'Ordini Pronti Consegna',
    description: 'Notifiche urgenti quando un ordine è pronto per il rider',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      const androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
      await _localNotifications.initialize(
        settings: const InitializationSettings(android: androidInit),
      );

      final androidPlugin =
      _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_channel);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notif = message.notification;
        if (notif != null) {
          _localNotifications.show(
            id: notif.hashCode,
            title: notif.title,
            body: notif.body,
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                _channel.id,
                _channel.name,
                channelDescription: _channel.description,
                importance: Importance.max,
                priority: Priority.max,
                vibrationPattern:
                Int64List.fromList([0, 350, 150, 350, 150, 500]),
              ),
            ),
          );
        }
      });
    } catch (_) {}
  }

  static bool isSupported() => true;

  static Future<bool> isGranted() async {
    try {
      await initialize();
      final settings =
      await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  static Future<PushCredentials?> requestAndGetCredentials(
      String vapidPublicKey) async {
    try {
      await initialize();
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final allowed =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!allowed) return null;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return null;

      return {
        'platform': 'android',
        'token_or_endpoint': token,
      };
    } catch (_) {
      return null;
    }
  }
}