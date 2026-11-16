import 'supabase_service.dart';
import 'push_platform_stub.dart'
if (dart.library.io) 'push_platform_mobile.dart'
if (dart.library.js_interop) 'push_platform_web.dart';

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  // <-- INCOLLA QUI LA TUA VAPID_PUBLIC_KEY GENERATA IN CHROME AL PUNTO 1.2
  static const String vapidPublicKey = 'BKaVeLt00HR59X_a16tc6Epj3f9swXUFVj9jAy8nytoOfFCbkclvOzTkR4PEtU3a-XYeu-N9CDMtI00m57lyarM';

  Future<void> initialize() async {
    await PushPlatformBridge.initialize();
  }

  bool get isSupported => PushPlatformBridge.isSupported();

  Future<bool> isGranted() => PushPlatformBridge.isGranted();

  /// Richiede i permessi al dispositivo (Android FCM o iPhone Web Push)
  /// e salva il token su Supabase
  Future<bool> enableAndSyncForRider(String riderRole) async {
    if (!isSupported) return false;

    final creds =
    await PushPlatformBridge.requestAndGetCredentials(vapidPublicKey);
    if (creds == null) return false;

    await SupabaseService.instance.upsertPushToken(
      riderRole: riderRole,
      platform: creds['platform'] ?? 'android',
      tokenOrEndpoint: creds['token_or_endpoint'] ?? '',
      p256dh: creds['p256dh'],
      auth: creds['auth'],
    );
    return true;
  }
}