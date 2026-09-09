import 'package:camera/camera.dart';

import '../models/liveness_challenge.dart';

/// Relative importance of each anti-spoof signal in the final score.
/// Weights are renormalised over whichever signals actually ran.
class SignalWeights {
  const SignalWeights({
    this.brightness = 0.6,
    this.sharpness = 1.0,
    this.glare = 1.2,
    this.texture = 1.0,
    this.microMotion = 1.4,
    this.blink = 1.0,
    this.motionCorrelation = 1.6,
    this.depthParallax = 2.0,
    this.model = 3.0,
  });

  final double brightness;
  final double sharpness;
  final double glare;
  final double texture;
  final double microMotion;
  final double blink;
  final double motionCorrelation;
  final double depthParallax;

  /// Weight given to a plugged-in [AntiSpoofModel], when one is supplied.
  final double model;
}

class LivenessConfig {
  const LivenessConfig({
    this.challengePool = const [
      LivenessChallenge.blink,
      LivenessChallenge.smile,
      LivenessChallenge.turnLeft,
      LivenessChallenge.turnRight,
      LivenessChallenge.nodDown,
    ],
    this.challengeCount = 3,
    this.randomizeOrder = true,
    this.alwaysIncludeYawSweep = true,
    this.challengeTimeout = const Duration(seconds: 10),
    this.sessionTimeout = const Duration(seconds: 60),
    this.cameraLens = CameraLensDirection.front,
    this.resolution = ResolutionPreset.medium,
    this.processEveryNthFrame = 1,
    this.captureFinalImage = true,
    this.preCaptureDelay = const Duration(milliseconds: 900),
    this.livenessThreshold = 0.62,
    this.weights = const SignalWeights(),
    this.minFaceAreaRatio = 0.02,
    this.maxFaceAreaRatio = 0.60,
    this.minBrightness = 0.16,
    this.maxBrightness = 0.90,
    this.blurThreshold = 30.0,
    this.maxSaturatedFraction = 0.055,
    this.yawThresholdDeg = 24.0,
    this.pitchThresholdDeg = 16.0,
    this.eyeClosedProbability = 0.22,
    this.eyeOpenProbability = 0.70,
    this.smileProbability = 0.72,
    this.mirrorYaw = true,
    this.useGyroscope = true,
    this.analysisWindow = 48,
    this.enableMaskDetection = true,
    this.maskDetectionFrames = 5,
    this.maskTextureRatio = 0.85,
    this.maskEntropyDrop = 0.3,
    this.maskSessionFraction = 0.3,
    this.instructionBuilder,
  });

  // --- Session shape -------------------------------------------------------

  final List<LivenessChallenge> challengePool;

  /// How many challenges to draw from the pool.
  final int challengeCount;

  /// Shuffle order every session. Keep this on: a fixed order lets an attacker
  /// pre-record one video that passes every time.
  final bool randomizeOrder;

  /// Force at least one turnLeft/turnRight into the sequence so the
  /// depth-parallax signal has data to work with.
  final bool alwaysIncludeYawSweep;

  final Duration challengeTimeout;
  final Duration sessionTimeout;

  // --- Camera --------------------------------------------------------------

  final CameraLensDirection cameraLens;
  final ResolutionPreset resolution;

  /// Analyse 1 in N frames. 2 is a good balance on mid-range Android.
  final int processEveryNthFrame;
  final bool captureFinalImage;

  /// Pause before the final still, after challenges finish and scoring
  /// passes, so the user can settle back to a straight, centred pose instead
  /// of getting captured mid-turn from the last challenge.
  final Duration preCaptureDelay;

  // --- Scoring -------------------------------------------------------------

  /// Session fails with [LivenessFailure.spoofDetected] below this score.
  final double livenessThreshold;
  final SignalWeights weights;

  // --- Frame quality gates -------------------------------------------------

  final double minFaceAreaRatio;
  final double maxFaceAreaRatio;
  final double minBrightness;
  final double maxBrightness;

  /// Laplacian variance below this counts as blurry.
  final double blurThreshold;

  /// Fraction of near-white pixels in the face region above which we suspect
  /// screen glare.
  final double maxSaturatedFraction;

  // --- Challenge detection -------------------------------------------------

  final double yawThresholdDeg;
  final double pitchThresholdDeg;
  final double eyeClosedProbability;
  final double eyeOpenProbability;
  final double smileProbability;

  /// Front cameras show a mirrored preview, so "turn left" from the user's
  /// point of view is a positive yaw from ML Kit's. Set false for rear lens.
  final bool mirrorYaw;

  // --- Analyzer ------------------------------------------------------------

  /// Number of recent samples kept for the passive signals.
  final int analysisWindow;

  /// Cross-check head rotation against device rotation. Disable on devices
  /// without a gyroscope; the signal just reports unavailable either way.
  final bool useGyroscope;

  /// Block challenge progress and final capture while ML Kit can't find the
  /// nose/mouth landmarks even though the eyes are visible - the signature of
  /// a mask covering the lower face.
  final bool enableMaskDetection;

  /// Consecutive suspected-mask frames required before the gate kicks in,
  /// so one bad frame doesn't block a bare face.
  final int maskDetectionFrames;

  /// Lower-face texture (stdDev) must drop below this fraction of the
  /// upper-face texture to count as "flat like a mask". Lower = stricter.
  final double maskTextureRatio;

  /// Minimum entropy drop (upper minus lower face) required alongside
  /// [maskTextureRatio] before flagging a mask.
  final double maskEntropyDrop;

  /// Session-wide backstop: if at least this fraction of all evaluated
  /// frames looked masked, the session fails and nothing is captured even
  /// if the consecutive-frame streak never latched.
  final double maskSessionFraction;

  /// Supply your own copy for localisation.
  final String Function(LivenessChallenge challenge)? instructionBuilder;

  String instructionFor(LivenessChallenge challenge) =>
      instructionBuilder?.call(challenge) ?? challenge.defaultInstruction;

  LivenessConfig copyWith({
    int? challengeCount,
    double? livenessThreshold,
    Duration? challengeTimeout,
    bool? useGyroscope,
  }) =>
      LivenessConfig(
        challengePool: challengePool,
        challengeCount: challengeCount ?? this.challengeCount,
        randomizeOrder: randomizeOrder,
        alwaysIncludeYawSweep: alwaysIncludeYawSweep,
        challengeTimeout: challengeTimeout ?? this.challengeTimeout,
        sessionTimeout: sessionTimeout,
        cameraLens: cameraLens,
        resolution: resolution,
        processEveryNthFrame: processEveryNthFrame,
        captureFinalImage: captureFinalImage,
        preCaptureDelay: preCaptureDelay,
        livenessThreshold: livenessThreshold ?? this.livenessThreshold,
        weights: weights,
        minFaceAreaRatio: minFaceAreaRatio,
        maxFaceAreaRatio: maxFaceAreaRatio,
        minBrightness: minBrightness,
        maxBrightness: maxBrightness,
        blurThreshold: blurThreshold,
        maxSaturatedFraction: maxSaturatedFraction,
        yawThresholdDeg: yawThresholdDeg,
        pitchThresholdDeg: pitchThresholdDeg,
        eyeClosedProbability: eyeClosedProbability,
        eyeOpenProbability: eyeOpenProbability,
        smileProbability: smileProbability,
        mirrorYaw: mirrorYaw,
        useGyroscope: useGyroscope ?? this.useGyroscope,
        analysisWindow: analysisWindow,
        enableMaskDetection: enableMaskDetection,
        maskDetectionFrames: maskDetectionFrames,
        maskTextureRatio: maskTextureRatio,
        maskEntropyDrop: maskEntropyDrop,
        maskSessionFraction: maskSessionFraction,
        instructionBuilder: instructionBuilder,
      );
}
