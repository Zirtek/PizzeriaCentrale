import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class ReadyOrderAlertService {
  ReadyOrderAlertService._();
  static final ReadyOrderAlertService instance = ReadyOrderAlertService._();

  final AudioPlayer _player = AudioPlayer();
  static Uint8List? _cachedChimeWav;
  bool _muted = false;

  bool get isMuted => _muted;

  void setMuted(bool muted) {
    _muted = muted;
  }

  /// Emette tripla vibrazione + campanello acustico "DIN-DON"
  Future<void> triggerOrderReadyAlert() async {
    await _vibratePattern();

    if (_muted) return;

    try {
      final wavBytes = _cachedChimeWav ??= _buildDoubleChimeWav();
      await _player.stop();
      await _player.play(
        BytesSource(wavBytes, mimeType: 'audio/wav'),
        volume: 1.0,
      );
    } catch (_) {
      // Fallback al suono di sistema se la riproduzione audio è bloccata
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
  }

  Future<void> _vibratePattern() async {
    try {
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 220));
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 220));
      await HapticFeedback.vibrate();
    } catch (_) {}
  }

  /// Genera in memoria un file WAV PCM 16-bit con doppio rintocco (880 Hz -> 1175 Hz)
  static Uint8List _buildDoubleChimeWav() {
    const int sampleRate = 22050;
    const double durationSeconds = 0.85;
    final int numSamples = (sampleRate * durationSeconds).round();
    final int dataSize = numSamples * 2;

    final byteData = ByteData(44 + dataSize);

    void writeAscii(int offset, String text) {
      for (int i = 0; i < text.length; i++) {
        byteData.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    // Header RIFF / WAVE standard
    writeAscii(0, 'RIFF');
    byteData.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    byteData.setUint32(16, 16, Endian.little); // PCM chunk size
    byteData.setUint16(20, 1, Endian.little); // PCM format
    byteData.setUint16(22, 1, Endian.little); // Mono
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
    byteData.setUint16(32, 2, Endian.little); // Block align
    byteData.setUint16(34, 16, Endian.little); // Bits per sample
    writeAscii(36, 'data');
    byteData.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      double sample = 0.0;

      // Primo rintocco ("DIN" - 880 Hz)
      if (t < 0.42) {
        final double attack = math.min(1.0, t / 0.012);
        final double decay = math.exp(-t * 6.5);
        final double env = attack * decay;
        sample += env *
            (0.75 * math.sin(2 * math.pi * 880.0 * t) +
                0.25 * math.sin(2 * math.pi * 1760.0 * t));
      }

      // Secondo rintocco ("DON" - 1174.66 Hz)
      if (t >= 0.34) {
        final double t2 = t - 0.34;
        final double attack = math.min(1.0, t2 / 0.012);
        final double decay = math.exp(-t2 * 5.2);
        final double env = attack * decay;
        sample += env *
            (0.75 * math.sin(2 * math.pi * 1174.66 * t2) +
                0.25 * math.sin(2 * math.pi * 2349.32 * t2));
      }

      final int pcm = (sample * 31000).round().clamp(-32767, 32767);
      byteData.setInt16(44 + i * 2, pcm, Endian.little);
    }

    return byteData.buffer.asUint8List();
  }
}