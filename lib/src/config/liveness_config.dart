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

/// Every user-facing string the package shows, so you can localise or
/// reword any of them without forking the UI. Each field defaults to the
/// package's current copy, so leaving [LivenessConfig.messages] unset keeps
/// today's behaviour exactly as-is.
class LivenessMessages {
  const LivenessMessages({
    this.requestingCameraAccess = 'Requesting camera access',
    this.startingCamera = 'Starting camera',
    this.ready = 'Ready',
    this.positionFaceInOval = 'Position your face in the oval',
    this.noFaceDetected = 'No face detected',
    this.moveCloser = 'Move closer',
    this.moveBack = 'Move back a little',
    this.almostDone = 'Almost done',
    this.checking = 'Checking',
    this.holdStill = 'Hold still',
    this.verified = 'Verified',
    this.verificationFailed = 'Verification failed',
    this.blinkInstruction = 'Blink slowly',
    this.smileInstruction = 'Smile',
    this.turnLeftInstruction = 'Turn your head left',
    this.turnRightInstruction = 'Turn your head right',
    this.nodDownInstruction = 'Look down',
    this.holdStillInstruction = 'Hold still and look at the camera',
    this.liveFaceConfirmed = 'Live face confirmed',
    this.spoofDetectedResult =
        'That did not look like a live face. Try again in better light, without a screen or printout.',
    this.challengeTimeoutResult =
        'The step timed out. Start again and follow the prompt.',
    this.sessionTimeoutResult = 'The session ran out of time. Start again.',
    this.noFaceResult = 'No face was found. Centre your face in the oval.',
    this.multipleFacesResult =
        'More than one face was in frame. Try again alone.',
    this.poorQualityResult = 'The camera image was too dark or blurry.',
    this.maskDetectedResult =
        'A mask was detected. Please remove it and try again.',
    this.cameraErrorResult = 'The camera could not start. Check permissions.',
    this.permissionDeniedResult =
        'Camera permission is required to verify your face.',
    this.cancelledResult = 'Verification cancelled.',
    this.genericFailureResult = 'Verification failed.',
    this.cameraAccessNeededTitle = 'Camera access needed',
    this.cameraStartFailedTitle = 'The camera could not start',
    this.cameraAccessNeededBody =
        'Face verification needs the camera to check you are a real, present person.',
    this.unknownError = 'Unknown error',
    this.openSettings = 'Open settings',
    this.tryAgain = 'Try again',
    this.stepOfBuilder,
  });

  // --- Session status copy --------------------------------------------------

  final String requestingCameraAccess;
  final String startingCamera;
  final String ready;
  final String positionFaceInOval;
  final String noFaceDetected;
  final String moveCloser;
  final String moveBack;
  final String almostDone;
  final String checking;

  /// Shown during [LivenessConfig.preCaptureDelay], right before the final
  /// still is taken.
  final String holdStill;
  final String verified;
  final String verificationFailed;

  // --- Per-challenge instruction copy ---------------------------------------

  final String blinkInstruction;
  final String smileInstruction;
  final String turnLeftInstruction;
  final String turnRightInstruction;
  final String nodDownInstruction;
  final String holdStillInstruction;

  // --- Result card copy ------------------------------------------------------

  final String liveFaceConfirmed;
  final String spoofDetectedResult;
  final String challengeTimeoutResult;
  final String sessionTimeoutResult;
  final String noFaceResult;
  final String multipleFacesResult;
  final String poorQualityResult;
  final String maskDetectedResult;
  final String cameraErrorResult;
  final String permissionDeniedResult;
  final String cancelledResult;
  final String genericFailureResult;

  // --- Error panel copy ------------------------------------------------------

  final String cameraAccessNeededTitle;
  final String cameraStartFailedTitle;
  final String cameraAccessNeededBody;
  final String unknownError;
  final String openSettings;
  final String tryAgain;

  /// Builds the "Step X of Y" caption under the instruction text. Defaults to
  /// `'Step $step of $total'`.
  final String Function(int step, int total)? stepOfBuilder;

  String stepOf(int step, int total) =>
      stepOfBuilder?.call(step, total) ?? 'Step $step of $total';

  /// The default copy for [challenge], before [LivenessConfig.instructionBuilder]
  /// (if supplied) gets a chance to override it.
  String instructionFor(LivenessChallenge challenge) {
    switch (challenge) {
      case LivenessChallenge.blink:
        return blinkInstruction;
      case LivenessChallenge.smile:
        return smileInstruction;
      case LivenessChallenge.turnLeft:
        return turnLeftInstruction;
      case LivenessChallenge.turnRight:
        return turnRightInstruction;
      case LivenessChallenge.nodDown:
        return nodDownInstruction;
      case LivenessChallenge.holdStill:
        return holdStillInstruction;
    }
  }
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
    this.passiveFrameCount = 12,
    this.randomizeOrder = true,
    this.alwaysIncludeYawSweep = true,
    this.challengeTimeout = const Duration(seconds: 10),
    this.sessionTimeout = const Duration(seconds: 60),
    this.cameraLens = CameraLensDirection.front,
    this.resolution = ResolutionPreset.medium,
    this.processEveryNthFrame = 1,
    this.captureFinalImage = true,
    this.requireFaceInOval = false,
    this.preCaptureDelay = const Duration(milliseconds: 900),
    this.cropToFace = true,
    this.faceCropPadding = 0.4,
    this.ovalCrop = true,
    this.ovalWidthFraction = 0.72,
    this.ovalHeightRatio = 1.32,
    this.ovalCenterYFraction = 0.4,
    this.captureCropScale = 1.0,
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
    this.messages = const LivenessMessages(),
    this.instructionBuilder,
  });

  // --- Session shape -------------------------------------------------------

  final List<LivenessChallenge> challengePool;

  /// How many challenges to draw from the pool. Pass 0 (or an empty
  /// [challengePool]) to skip challenges entirely and score on the passive
  /// signals only.
  final int challengeCount;

  /// Frames to collect before scoring when no challenges are requested, so
  /// the passive signals (sharpness, texture, micro-motion...) have data.
  final int passiveFrameCount;

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

  /// Gate the whole session on the face staying centred in the on-screen
  /// oval, not just inside the frame. When on, a face detected outside the
  /// oval is treated like "no face" - challenges won't advance and the final
  /// still won't be captured - until it's repositioned.
  final bool requireFaceInOval;

  /// Pause before the final still, after challenges finish and scoring
  /// passes, so the user can settle back to a straight, centred pose instead
  /// of getting captured mid-turn from the last challenge.
  final Duration preCaptureDelay;

  /// Crop the captured still down to the face region instead of keeping the
  /// full camera frame. Uses the last known-good face box from the session.
  final bool cropToFace;

  /// Margin added around the detected face box before cropping, as a
  /// fraction of the box's width/height on each side. Keep some slack so the
  /// crop doesn't clip the chin/forehead/ears. Ignored when [ovalCrop] is on.
  final double faceCropPadding;

  /// When [cropToFace] is on, shape the crop to the same oval shown on
  /// screen instead of a padded rectangle around the face box: the still is
  /// cropped to the oval's bounding box and everything outside the ellipse
  /// is painted black, so only what the user saw inside the oval survives.
  final bool ovalCrop;

  /// Oval width as a fraction of the screen/frame width. Larger = wider oval.
  final double ovalWidthFraction;

  /// Oval height as a multiple of its own width. Larger = taller oval.
  final double ovalHeightRatio;

  /// Vertical center of the oval as a fraction of screen/frame height, from
  /// the top. Smaller = oval sits higher.
  final double ovalCenterYFraction;

  /// Shrinks (or grows) just the [ovalCrop] capture area around the oval's
  /// center, independent of the on-screen guide oval - e.g. 0.8 crops the
  /// final still to 80% of the displayed oval's width/height, tighter on
  /// the face, while the guide the user sees stays the same size. 1.0 = same
  /// as the on-screen oval.
  final double captureCropScale;

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

  /// Every user-facing string in the package. Override any field to reword
  /// or localise it; unset fields keep the current default copy.
  final LivenessMessages messages;

  /// Supply your own copy for localisation. Takes priority over
  /// [messages]'s per-challenge instruction fields when set.
  final String Function(LivenessChallenge challenge)? instructionBuilder;

  String instructionFor(LivenessChallenge challenge) =>
      instructionBuilder?.call(challenge) ?? messages.instructionFor(challenge);

  LivenessConfig copyWith({
    int? challengeCount,
    double? livenessThreshold,
    Duration? challengeTimeout,
    bool? useGyroscope,
    bool? requireFaceInOval,
    LivenessMessages? messages,
  }) =>
      LivenessConfig(
        challengePool: challengePool,
        challengeCount: challengeCount ?? this.challengeCount,
        passiveFrameCount: passiveFrameCount,
        randomizeOrder: randomizeOrder,
        alwaysIncludeYawSweep: alwaysIncludeYawSweep,
        challengeTimeout: challengeTimeout ?? this.challengeTimeout,
        sessionTimeout: sessionTimeout,
        cameraLens: cameraLens,
        resolution: resolution,
        processEveryNthFrame: processEveryNthFrame,
        captureFinalImage: captureFinalImage,
        requireFaceInOval: requireFaceInOval ?? this.requireFaceInOval,
        preCaptureDelay: preCaptureDelay,
        cropToFace: cropToFace,
        faceCropPadding: faceCropPadding,
        ovalCrop: ovalCrop,
        ovalWidthFraction: ovalWidthFraction,
        ovalHeightRatio: ovalHeightRatio,
        ovalCenterYFraction: ovalCenterYFraction,
        captureCropScale: captureCropScale,
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
        messages: messages ?? this.messages,
        instructionBuilder: instructionBuilder,
      );
}
