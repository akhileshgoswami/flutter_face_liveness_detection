import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

class _GyroSample {
  const _GyroSample(this.timestampMs, this.magnitude, this.y);
  final int timestampMs;
  final double magnitude;
  final double y;
}

/// Keeps a short history of device rotation so the analyzer can tell a head
/// that turned from a phone that was swung around a stationary photo.
class MotionTracker {
  MotionTracker({this.windowMs = 6000});

  final int windowMs;
  final List<_GyroSample> _samples = [];
  StreamSubscription<GyroscopeEvent>? _sub;
  bool _sensorAvailable = false;

  bool get isAvailable => _sensorAvailable && _samples.length >= 5;

  void start() {
    _sub ??= gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 40),
    ).listen(
      (event) {
        _sensorAvailable = true;
        final now = DateTime.now().millisecondsSinceEpoch;
        _samples.add(_GyroSample(
          now,
          math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z),
          event.y,
        ));
        _prune(now);
      },
      onError: (_) => _sensorAvailable = false,
      cancelOnError: false,
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _samples.clear();
  }

  void _prune(int now) {
    _samples.removeWhere((s) => now - s.timestampMs > windowMs);
  }

  /// Peak rotation rate (rad/s) observed between two timestamps.
  double peakRotationBetween(int startMs, int endMs) {
    var peak = 0.0;
    for (final s in _samples) {
      if (s.timestampMs >= startMs && s.timestampMs <= endMs) {
        peak = math.max(peak, s.magnitude);
      }
    }
    return peak;
  }

  /// Integrated yaw rotation of the *device* (radians) over a window. Used to
  /// check whether apparent head movement was really the phone moving.
  double integratedDeviceYaw(int startMs, int endMs) {
    var total = 0.0;
    _GyroSample? prev;
    for (final s in _samples) {
      if (s.timestampMs < startMs || s.timestampMs > endMs) {
        prev = s;
        continue;
      }
      if (prev != null) {
        final dt = (s.timestampMs - prev.timestampMs) / 1000.0;
        if (dt > 0 && dt < 0.5) total += s.y * dt;
      }
      prev = s;
    }
    return total;
  }
}
