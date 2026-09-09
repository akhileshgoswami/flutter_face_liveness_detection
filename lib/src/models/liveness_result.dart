import 'liveness_challenge.dart';

enum LivenessFailure {
  none,
  sessionTimeout,
  challengeTimeout,
  noFace,
  multipleFaces,
  poorQuality,
  maskDetected,
  spoofDetected,
  cameraError,
  permissionDenied,
  cancelled,
}

/// One anti-spoof signal's verdict.
///
/// [available] is false when the signal could not run (not enough frames, no
/// yaw sweep, sensor missing). Unavailable signals are dropped from the final
/// score instead of counting as a failure.
class SignalScore {
  const SignalScore({
    required this.name,
    required this.available,
    required this.score,
    required this.weight,
    this.detail = '',
  });

  const SignalScore.unavailable(this.name, {this.detail = ''})
      : available = false,
        score = 0,
        weight = 0;

  final String name;
  final bool available;

  /// 0.0 = looks like a spoof, 1.0 = looks like a live face.
  final double score;
  final double weight;
  final String detail;

  @override
  String toString() =>
      available ? '$name=${score.toStringAsFixed(2)}' : '$name=n/a';
}

class LivenessResult {
  const LivenessResult({
    required this.isLive,
    required this.livenessScore,
    required this.failure,
    required this.signals,
    required this.completedChallenges,
    this.capturedImagePath,
    this.elapsed = Duration.zero,
  });

  factory LivenessResult.failed(
    LivenessFailure failure, {
    double score = 0,
    List<SignalScore> signals = const [],
    List<LivenessChallenge> completed = const [],
    Duration elapsed = Duration.zero,
  }) =>
      LivenessResult(
        isLive: false,
        livenessScore: score,
        failure: failure,
        signals: signals,
        completedChallenges: completed,
        elapsed: elapsed,
      );

  final bool isLive;

  /// Weighted mean of the available signals. 1.0 = confidently live.
  final double livenessScore;
  final LivenessFailure failure;
  final List<SignalScore> signals;
  final List<LivenessChallenge> completedChallenges;

  /// Path to the final selfie, if [LivenessConfig.captureFinalImage] was on.
  final String? capturedImagePath;
  final Duration elapsed;

  Map<String, Object?> toMap() => {
        'isLive': isLive,
        'livenessScore': livenessScore,
        'failure': failure.name,
        'elapsedMs': elapsed.inMilliseconds,
        'completedChallenges': completedChallenges.map((c) => c.name).toList(),
        'capturedImagePath': capturedImagePath,
        'signals': {
          for (final s in signals) s.name: s.available ? s.score : null,
        },
      };

  @override
  String toString() =>
      'LivenessResult(isLive: $isLive, score: ${livenessScore.toStringAsFixed(3)}, '
      'failure: ${failure.name}, signals: $signals)';
}
