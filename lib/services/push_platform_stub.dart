import 'dart:async';

typedef PushCredentials = Map<String, String>;

class PushPlatformBridge {
  static Future<void> initialize() async {}
  static bool isSupported() => false;
  static Future<bool> isGranted() async => false;
  static Future<PushCredentials?> requestAndGetCredentials(
      String vapidPublicKey) async {
    return null;
  }
}