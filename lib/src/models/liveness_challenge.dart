/// The actions a user can be asked to perform during a session.
enum LivenessChallenge {
  blink,
  smile,
  turnLeft,
  turnRight,
  nodDown,
  holdStill,
}

extension LivenessChallengeInfo on LivenessChallenge {
  /// Short instruction shown on screen. Override via
  /// [LivenessConfig.instructionBuilder] to localise.
  String get defaultInstruction {
    switch (this) {
      case LivenessChallenge.blink:
        return 'Blink slowly';
      case LivenessChallenge.smile:
        return 'Smile';
      case LivenessChallenge.turnLeft:
        return 'Turn your head left';
      case LivenessChallenge.turnRight:
        return 'Turn your head right';
      case LivenessChallenge.nodDown:
        return 'Look down';
      case LivenessChallenge.holdStill:
        return 'Hold still and look at the camera';
    }
  }

  /// Challenges that produce a wide yaw sweep, which the depth-parallax
  /// signal needs in order to run.
  bool get producesYawSweep =>
      this == LivenessChallenge.turnLeft || this == LivenessChallenge.turnRight;
}
