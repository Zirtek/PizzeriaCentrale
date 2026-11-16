import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class ReadyOrderAlertPlatform {
  static final AudioPlayer _player = AudioPlayer();
  static Uint8List? _cachedChimeWav;
  static bool _audioConfigured = false;

  static Future<void> _ensureAndroidAudioContext() async {
    if (_audioConfigured) return;
    _audioConfigured = true;
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );
    } catch (_) {}
  }

  static Future<void> playChimeAndVibrate({required bool playSound}) async {
    // Avvia la vibrazione ripetuta in parallelo al suono
    _vibratePattern();

    if (!playSound) return;

    try {
      await _ensureAndroidAudioContext();
      final wavBytes = _cachedChimeWav ??= _buildDoubleChimeWav();
      await _player.stop();
      await _player.play(
        BytesSource(wavBytes, mimeType: 'audio/wav'),
        volume: 1.0,
      );
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
  }

  static Future<void> _vibratePattern() async {
    for (int i = 0; i < 5; i++) {
      try {
        await HapticFeedback.vibrate();
        await HapticFeedback.heavyImpact();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 240));
    }
  }

  /// Genera in memoria un file WAV PCM 16-bit con doppio rintocco "DIN-DON" ripetuto
  static Uint8List _buildDoubleChimeWav() {
    const int sampleRate = 22050;
    const double durationSeconds = 1.65;
    final int numSamples = (sampleRate * durationSeconds).round();
    final int dataSize = numSamples * 2;

    final byteData = ByteData(44 + dataSize);

    void writeAscii(int offset, String text) {
      for (int i = 0; i < text.length; i++) {
        byteData.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    byteData.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, 1, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    byteData.setUint32(40, dataSize, Endian.little);

    double chimeStrike(double localT, double freq, double decayRate) {
      if (localT < 0 || localT > 0.65) return 0.0;
      final double attack = math.min(1.0, localT / 0.01);
      final double decay = math.exp(-localT * decayRate);
      final double env = attack * decay;
      return env *
          (0.75 * math.sin(2 * math.pi * freq * localT) +
              0.25 * math.sin(2 * math.pi * (freq * 2) * localT));
    }

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      double sample = 0.0;

      // Primo DIN-DON
      sample += chimeStrike(t, 987.77, 6.0);
      sample += chimeStrike(t - 0.28, 783.99, 5.0);

      // Secondo DIN-DON
      sample += chimeStrike(t - 0.82, 987.77, 6.0);
      sample += chimeStrike(t - 1.10, 783.99, 4.8);

      final int pcm = (sample * 31500).round().clamp(-32767, 32767);
      byteData.setInt16(44 + i * 2, pcm, Endian.little);
    }

    return byteData.buffer.asUint8List();
  }
}