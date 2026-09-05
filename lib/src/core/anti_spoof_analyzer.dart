import 'dart:math' as math;

import '../config/liveness_config.dart';
import '../models/frame_sample.dart';
import '../models/liveness_result.dart';
import 'image_stats.dart';
import 'motion_tracker.dart';

/// Extension point for a trained anti-spoof network (TFLite, Core ML, ONNX).
///
/// Implement this and pass it to [AntiSpoofAnalyzer] to add a learned signal
/// on top of the heuristics. The heuristics stay active either way.
abstract class AntiSpoofModel {
  /// Returns 0.0 (spoof) to 1.0 (live) for one face crop.
  Future<double> scoreFrame(LumaImage luma, FrameSample sample);
}

/// Accumulates per-frame samples and turns them into a set of independent
/// liveness signals, then a single weighted score.
///
/// Each signal answers a different attack:
///   brightness / sharpness  - low-effort photo captures
///   glare                   - a face displayed on another screen
///   texture                 - flat print with reduced skin detail
///   microMotion             - a frozen frame injected by a virtual camera
///   blink                   - a still photo held up to the lens
///   motionCorrelation       - a photo panned in front of a moving phone
///   depthParallax           - anything flat, including a high-res tablet
class AntiSpoofAnalyzer {
  AntiSpoofAnalyzer({
    required this.config,
    MotionTracker? motionTracker,
    this.model,
  }) : _motion = motionTracker;

  final LivenessConfig config;
  final MotionTracker? _motion;
  final AntiSpoofModel? model;

  final List<FrameSample> _samples = [];
  final List<double> _modelScores = [];

  bool _blinkArmed = false;
  bool _blinkObserved = false;
  int? _blinkClosedAtMs;

  int get sampleCount => _samples.length;

  void reset() {
    _samples.clear();
    _modelScores.clear();
    _blinkArmed = false;
    _blinkObserved = false;
    _blinkClosedAtMs = null;
  }

  void addModelScore(double score) => _modelScores.add(score.clamp(0.0, 1.0));

  void add(FrameSample sample) {
    _samples.add(sample);
    if (_samples.length > config.analysisWindow) {
      _samples.removeAt(0);
    }
    _trackBlink(sample);
  }

  /// A real blink closes and reopens within roughly 80-500 ms. A photo never
  /// closes; a looped video often "blinks" at an implausible cadence.
  void _trackBlink(FrameSample s) {
    final open = s.eyeOpenAverage;
    if (open == null) return;

    if (!_blinkArmed && open > config.eyeOpenProbability) {
      _blinkArmed = true;
      return;
    }
    if (_blinkArmed &&
        _blinkClosedAtMs == null &&
        open < config.eyeClosedProbability) {
      _blinkClosedAtMs = s.timestampMs;
      return;
    }
    final closedAt = _blinkClosedAtMs;
    if (closedAt != null && open > config.eyeOpenProbability) {
      final durationMs = s.timestampMs - closedAt;
      if (durationMs >= 60 && durationMs <= 700) {
        _blinkObserved = true;
      }
      _blinkClosedAtMs = null;
    }
  }

  // --- Individual signals --------------------------------------------------

  SignalScore _brightness() {
    if (_samples.isEmpty) return const SignalScore.unavailable('brightness');
    final mean = _mean(_samples.map((s) => s.meanLuma));
    final lo = config.minBrightness;
    final hi = config.maxBrightness;
    late final double score;
    if (mean < lo) {
      score = (mean / lo).clamp(0.0, 1.0);
    } else if (mean > hi) {
      score = ((1 - mean) / (1 - hi)).clamp(0.0, 1.0);
    } else {
      score = 1.0;
    }
    return SignalScore(
      name: 'brightness',
      available: true,
      score: score,
      weight: config.weights.brightness,
      detail: 'mean ${mean.toStringAsFixed(2)}',
    );
  }

  SignalScore _sharpness() {
    if (_samples.length < 3) return const SignalScore.unavailable('sharpness');
    // Use the best frames: a few soft frames during motion are normal.
    final values = _samples.map((s) => s.laplacianVariance).toList()..sort();
    final upper = values.sublist(values.length ~/ 2);
    final v = _mean(upper);
    return SignalScore(
      name: 'sharpness',
      available: true,
      score: (v / config.blurThreshold).clamp(0.0, 1.0),
      weight: config.weights.sharpness,
      detail: 'lapVar ${v.toStringAsFixed(1)}',
    );
  }

  SignalScore _glare() {
    if (_samples.length < 3) return const SignalScore.unavailable('glare');
    final worst = _samples
        .map((s) => s.saturatedFraction)
        .reduce((a, b) => a > b ? a : b);
    return SignalScore(
      name: 'glare',
      available: true,
      score: (1 - worst / config.maxSaturatedFraction).clamp(0.0, 1.0),
      weight: config.weights.glare,
      detail: 'peak ${(worst * 100).toStringAsFixed(1)}%',
    );
  }

  SignalScore _texture() {
    if (_samples.length < 3) return const SignalScore.unavailable('texture');
    final e = _mean(_samples.map((s) => s.textureEntropy));
    // Live skin under normal light lands around 4.5-6.0 bits on 64 bins.
    return SignalScore(
      name: 'texture',
      available: true,
      score: ((e - 3.2) / 1.8).clamp(0.0, 1.0),
      weight: config.weights.texture,
      detail: '${e.toStringAsFixed(2)} bits',
    );
  }

  SignalScore _microMotion() {
    if (_samples.length < 8) {
      return const SignalScore.unavailable('microMotion',
          detail: 'needs 8 frames');
    }
    var total = 0.0;
    var pairs = 0;
    for (var i = 1; i < _samples.length; i++) {
      total += thumbnailDelta(_samples[i - 1].thumbnail, _samples[i].thumbnail);
      pairs++;
    }
    final avg = total / pairs;
    // Anything under ~0.4 grey levels of change per pixel is suspiciously
    // static; a handheld camera on a live face never sits that still.
    return SignalScore(
      name: 'microMotion',
      available: true,
      score: (avg / 0.9).clamp(0.0, 1.0),
      weight: config.weights.microMotion,
      detail: 'delta ${avg.toStringAsFixed(2)}',
    );
  }

  SignalScore _blink(bool blinkWasRequested) {
    if (!blinkWasRequested) {
      return const SignalScore.unavailable('blink', detail: 'not challenged');
    }
    return SignalScore(
      name: 'blink',
      available: true,
      score: _blinkObserved ? 1.0 : 0.0,
      weight: config.weights.blink,
      detail: _blinkObserved ? 'natural blink seen' : 'no blink',
    );
  }

  /// If the head yaw swings but the phone swung by the same amount at the same
  /// time, the "head" probably never moved - the camera did.
  SignalScore _motionCorrelation() {
    final motion = _motion;
    if (motion == null || !config.useGyroscope || !motion.isAvailable) {
      return const SignalScore.unavailable('motionCorrelation',
          detail: 'no gyroscope');
    }
    if (_samples.length < 6) {
      return const SignalScore.unavailable('motionCorrelation');
    }

    final yaws = _samples.map((s) => s.yaw).toList();
    final headSweepDeg = yaws.reduce(math.max) - yaws.reduce(math.min);
    if (headSweepDeg < 10) {
      return const SignalScore.unavailable('motionCorrelation',
          detail: 'head barely moved');
    }

    final startMs = _samples.first.timestampMs;
    final endMs = _samples.last.timestampMs;
    final deviceYawDeg =
        motion.integratedDeviceYaw(startMs, endMs).abs() * 180 / math.pi;

    // Ratio near 0 = head moved on its own (good). Near 1 = the device
    // accounted for the whole apparent rotation (bad).
    final ratio = (deviceYawDeg / headSweepDeg).clamp(0.0, 1.5);
    return SignalScore(
      name: 'motionCorrelation',
      available: true,
      score: (1 - ratio / 0.75).clamp(0.0, 1.0),
      weight: config.weights.motionCorrelation,
      detail: 'head ${headSweepDeg.toStringAsFixed(0)}deg / '
          'device ${deviceYawDeg.toStringAsFixed(0)}deg',
    );
  }

  /// A 3D face self-occludes as it turns: the near eye drifts away from the
  /// nose while the far eye crowds it, so the eye-nose distance ratio tracks
  /// yaw steeply. A flat photo tilted in front of the lens keeps that ratio
  /// almost fixed, because a plane has no parallax.
  SignalScore _depthParallax() {
    final usable = _samples
        .where((s) =>
            s.leftEye != null && s.rightEye != null && s.noseBase != null)
        .toList();
    if (usable.length < 6) {
      return const SignalScore.unavailable('depthParallax',
          detail: 'no landmarks');
    }

    final yaws = usable.map((s) => s.yaw).toList();
    final sweep = yaws.reduce(math.max) - yaws.reduce(math.min);
    if (sweep < 14) {
      return const SignalScore.unavailable('depthParallax',
          detail: 'yaw sweep too small');
    }

    final ratios = <double>[];
    for (final s in usable) {
      final le = s.leftEye!;
      final re = s.rightEye!;
      final nose = s.noseBase!;
      final leftSpan = (nose.dx - le.dx).abs();
      final rightSpan = (re.dx - nose.dx).abs();
      if (leftSpan < 1 || rightSpan < 1) continue;
      ratios.add(math.log(leftSpan / rightSpan));
    }
    if (ratios.length < 6) {
      return const SignalScore.unavailable('depthParallax');
    }

    // Slope of log(ratio) against yaw. Real faces sit well above 0.02/deg.
    final slope = _slope(yaws.sublist(0, ratios.length), ratios).abs();
    return SignalScore(
      name: 'depthParallax',
      available: true,
      score: (slope / 0.022).clamp(0.0, 1.0),
      weight: config.weights.depthParallax,
      detail: 'slope ${slope.toStringAsFixed(4)}/deg over '
          '${sweep.toStringAsFixed(0)}deg',
    );
  }

  SignalScore _modelSignal() {
    if (model == null || _modelScores.isEmpty) {
      return const SignalScore.unavailable('model', detail: 'not configured');
    }
    // Trust the pessimistic end: one confident spoof frame matters more than
    // a run of ambiguous ones.
    final sorted = List<double>.from(_modelScores)..sort();
    final idx = (sorted.length * 0.25).floor().clamp(0, sorted.length - 1);
    return SignalScore(
      name: 'model',
      available: true,
      score: sorted[idx],
      weight: config.weights.model,
      detail: 'p25 of ${sorted.length} frames',
    );
  }

  // --- Aggregation ---------------------------------------------------------

  List<SignalScore> evaluate({required bool blinkWasRequested}) => [
        _brightness(),
        _sharpness(),
        _glare(),
        _texture(),
        _microMotion(),
        _blink(blinkWasRequested),
        _motionCorrelation(),
        _depthParallax(),
        _modelSignal(),
      ];

  /// Weighted mean over the signals that actually ran.
  static double combine(List<SignalScore> signals) {
    var weighted = 0.0;
    var totalWeight = 0.0;
    for (final s in signals) {
      if (!s.available || s.weight <= 0) continue;
      weighted += s.score * s.weight;
      totalWeight += s.weight;
    }
    if (totalWeight == 0) return 0;
    return weighted / totalWeight;
  }

  // --- Helpers -------------------------------------------------------------

  static double _mean(Iterable<double> values) {
    var sum = 0.0;
    var n = 0;
    for (final v in values) {
      sum += v;
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  static double _slope(List<double> xs, List<double> ys) {
    final n = math.min(xs.length, ys.length);
    if (n < 2) return 0;
    final mx = _mean(xs.take(n));
    final my = _mean(ys.take(n));
    var num = 0.0;
    var den = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = xs[i] - mx;
      num += dx * (ys[i] - my);
      den += dx * dx;
    }
    return den == 0 ? 0 : num / den;
  }
}
