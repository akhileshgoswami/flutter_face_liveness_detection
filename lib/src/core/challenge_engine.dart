import 'dart:math';

import '../config/liveness_config.dart';
import '../models/frame_sample.dart';
import '../models/liveness_challenge.dart';

enum ChallengeOutcome { pending, passed, timedOut }

class ChallengeUpdate {
  const ChallengeUpdate({
    required this.outcome,
    required this.current,
    required this.completed,
    required this.total,
    required this.sequenceFinished,
  });

  final ChallengeOutcome outcome;
  final LivenessChallenge? current;
  final int completed;
  final int total;
  final bool sequenceFinished;

  double get progress => total == 0 ? 0 : completed / total;
}

/// Runs the challenge sequence as a small state machine.
///
/// Every challenge requires a neutral pose first, then the target pose. That
/// ordering stops one held expression from satisfying several challenges, and
/// it means a replayed video has to match the randomised order to pass.
class ChallengeEngine {
  ChallengeEngine(this.config, {Random? random})
      : _random = random ?? Random.secure();

  final LivenessConfig config;
  final Random _random;

  late List<LivenessChallenge> _sequence;
  int _index = 0;
  int _challengeStartedAtMs = 0;
  bool _neutralSeen = false;
  int _stillSinceMs = 0;

  List<LivenessChallenge> get sequence => List.unmodifiable(_sequence);
  List<LivenessChallenge> get completed =>
      List.unmodifiable(_sequence.take(_index));
  LivenessChallenge? get current =>
      _index < _sequence.length ? _sequence[_index] : null;
  bool get isFinished => _index >= _sequence.length;
  bool get includesBlink => _sequence.contains(LivenessChallenge.blink);

  void start(int nowMs) {
    _sequence = _buildSequence();
    _index = 0;
    _challengeStartedAtMs = nowMs;
    _neutralSeen = false;
    _stillSinceMs = 0;
  }

  List<LivenessChallenge> _buildSequence() {
    final pool = List<LivenessChallenge>.from(config.challengePool);
    if (pool.isEmpty) return [LivenessChallenge.blink];

    if (config.randomizeOrder) pool.shuffle(_random);

    final count = config.challengeCount.clamp(1, pool.length);
    final picked = pool.take(count).toList();

    if (config.alwaysIncludeYawSweep &&
        !picked.any((c) => c.producesYawSweep)) {
      final sweep = pool.firstWhere(
        (c) => c.producesYawSweep,
        orElse: () => LivenessChallenge.turnLeft,
      );
      picked[picked.length - 1] = sweep;
      if (config.randomizeOrder) picked.shuffle(_random);
    }
    return picked;
  }

  /// Feed one analysed frame. Returns the state after this frame.
  ChallengeUpdate update(FrameSample s) {
    final challenge = current;
    if (challenge == null) {
      return ChallengeUpdate(
        outcome: ChallengeOutcome.passed,
        current: null,
        completed: _index,
        total: _sequence.length,
        sequenceFinished: true,
      );
    }

    if (s.timestampMs - _challengeStartedAtMs >
        config.challengeTimeout.inMilliseconds) {
      return _update(ChallengeOutcome.timedOut);
    }

    if (!_neutralSeen) {
      if (_isNeutral(s, challenge)) _neutralSeen = true;
      return _update(ChallengeOutcome.pending);
    }

    if (_isSatisfied(s, challenge)) {
      _index++;
      _challengeStartedAtMs = s.timestampMs;
      _neutralSeen = false;
      _stillSinceMs = 0;
      return _update(ChallengeOutcome.passed);
    }

    return _update(ChallengeOutcome.pending);
  }

  ChallengeUpdate _update(ChallengeOutcome outcome) => ChallengeUpdate(
        outcome: outcome,
        current: current,
        completed: _index,
        total: _sequence.length,
        sequenceFinished: isFinished,
      );

  /// Yaw sign flips on a mirrored front-camera preview.
  double _userYaw(FrameSample s) => config.mirrorYaw ? s.yaw : -s.yaw;

  bool _isNeutral(FrameSample s, LivenessChallenge c) {
    switch (c) {
      case LivenessChallenge.blink:
        return (s.eyeOpenAverage ?? 1.0) > config.eyeOpenProbability;
      case LivenessChallenge.smile:
        return (s.smiling ?? 0.0) < 0.35;
      case LivenessChallenge.turnLeft:
      case LivenessChallenge.turnRight:
        return _userYaw(s).abs() < config.yawThresholdDeg * 0.4;
      case LivenessChallenge.nodDown:
        return s.pitch.abs() < config.pitchThresholdDeg * 0.5;
      case LivenessChallenge.holdStill:
        return true;
    }
  }

  bool _isSatisfied(FrameSample s, LivenessChallenge c) {
    switch (c) {
      case LivenessChallenge.blink:
        return (s.eyeOpenAverage ?? 1.0) < config.eyeClosedProbability;
      case LivenessChallenge.smile:
        return (s.smiling ?? 0.0) > config.smileProbability;
      case LivenessChallenge.turnLeft:
        return _userYaw(s) > config.yawThresholdDeg;
      case LivenessChallenge.turnRight:
        return _userYaw(s) < -config.yawThresholdDeg;
      case LivenessChallenge.nodDown:
        return s.pitch < -config.pitchThresholdDeg;
      case LivenessChallenge.holdStill:
        final steady = _userYaw(s).abs() < 12 &&
            s.pitch.abs() < 12 &&
            s.centreOffset < 0.10;
        if (!steady) {
          _stillSinceMs = 0;
          return false;
        }
        if (_stillSinceMs == 0) {
          _stillSinceMs = s.timestampMs;
          return false;
        }
        return s.timestampMs - _stillSinceMs > 1200;
    }
  }
}
