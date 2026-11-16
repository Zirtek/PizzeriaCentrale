import 'dart:js_interop';

@JS('PizzeriaAudio.triggerAlert')
external JSPromise<JSAny?> _jsTriggerAlert(bool playSound);

class ReadyOrderAlertPlatform {
  static Future<void> playChimeAndVibrate({required bool playSound}) async {
    try {
      await _jsTriggerAlert(playSound).toDart;
    } catch (_) {}
  }
}