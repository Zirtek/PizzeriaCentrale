import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

typedef PushCredentials = Map<String, String>;

@JS('PizzeriaPush.isSupported')
external bool _jsIsSupported();

@JS('PizzeriaPush.getPermissionState')
external String _jsGetPermissionState();

@JS('PizzeriaPush.subscribe')
external JSPromise<JSString?> _jsSubscribe(String vapidPublicKey);

class PushPlatformBridge {
  static Future<void> initialize() async {}

  static bool isSupported() {
    try {
      return _jsIsSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isGranted() async {
    try {
      return _jsGetPermissionState() == 'granted';
    } catch (_) {
      return false;
    }
  }

  static Future<PushCredentials?> requestAndGetCredentials(
      String vapidPublicKey) async {
    try {
      final rawJson = await _jsSubscribe(vapidPublicKey).toDart;
      if (rawJson == null || rawJson.toDart.isEmpty) return null;

      final decoded = jsonDecode(rawJson.toDart);
      if (decoded is! Map) return null;

      final map = Map<String, dynamic>.from(decoded);
      final endpoint = map['endpoint'] as String? ?? '';
      final rawKeys = map['keys'];
      final keys = rawKeys is Map
          ? Map<String, dynamic>.from(rawKeys)
          : <String, dynamic>{};
      final p256dh = keys['p256dh'] as String? ?? '';
      final auth = keys['auth'] as String? ?? '';

      if (endpoint.isEmpty || p256dh.isEmpty || auth.isEmpty) return null;

      return <String, String>{
        'platform': 'web',
        'token_or_endpoint': endpoint,
        'p256dh': p256dh,
        'auth': auth,
      };
    } catch (_) {
      return null;
    }
  }
}