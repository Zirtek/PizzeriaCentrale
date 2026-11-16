import 'ready_order_alert_stub.dart'
if (dart.library.js_interop) 'ready_order_alert_web.dart';

class ReadyOrderAlertService {
  ReadyOrderAlertService._();
  static final ReadyOrderAlertService instance = ReadyOrderAlertService._();

  bool _muted = false;

  bool get isMuted => _muted;

  void setMuted(bool muted) {
    _muted = muted;
  }

  Future<void> triggerOrderReadyAlert() async {
    await ReadyOrderAlertPlatform.playChimeAndVibrate(
      playSound: !_muted,
    );
  }
}