import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/liveness_config.dart';
import '../models/face_landmarks.dart';
import '../models/frame_sample.dart';
import '../models/liveness_challenge.dart';
import '../models/liveness_result.dart';
import 'anti_spoof_analyzer.dart';
import 'challenge_engine.dart';
import 'image_stats.dart';
import 'mlkit_face_detector.dart';
import 'motion_tracker.dart';

/// Thrown by [LivenessController.initialize] when camera permission was
/// refused. Carry it to the UI to offer "open settings" when
/// [permanentlyDenied] is true.
class CameraPermissionDeniedException implements Exception {
  const CameraPermissionDeniedException({required this.permanentlyDenied});
  final bool permanentlyDenied;

  @override
  String toString() => 'Camera permission denied';
}

enum LivenessPhase {
  idle,
  preparing,
  searchingFace,
  challenging,
  scoring,
  done
}

/// Everything the UI needs to render a frame of the session.
class LivenessState {
  const LivenessState({
    this.phase = LivenessPhase.idle,
    this.message = '',
    this.currentChallenge,
    this.completed = 0,
    this.total = 0,
    this.faceBox,
    this.faceLandmarks,
    this.previewSize,
    this.result,
  });

  final LivenessPhase phase;
  final String message;
  final LivenessChallenge? currentChallenge;
  final int completed;
  final int total;
  final Rect? faceBox;
  final Map<FaceLandmarkKey, Offset>? faceLandmarks;
  final Size? previewSize;
  final LivenessResult? result;

  double get progress => total == 0 ? 0 : completed / total;

  LivenessState copyWith({
    LivenessPhase? phase,
    String? message,
    LivenessChallenge? currentChallenge,
    bool clearChallenge = false,
    int? completed,
    int? total,
    Rect? faceBox,
    Map<FaceLandmarkKey, Offset>? faceLandmarks,
    bool clearFaceBox = false,
    Size? previewSize,
    LivenessResult? result,
  }) =>
      LivenessState(
        phase: phase ?? this.phase,
        message: message ?? this.message,
        currentChallenge:
            clearChallenge ? null : (currentChallenge ?? this.currentChallenge),
        completed: completed ?? this.completed,
        total: total ?? this.total,
        faceBox: clearFaceBox ? null : (faceBox ?? this.faceBox),
        faceLandmarks:
            clearFaceBox ? null : (faceLandmarks ?? this.faceLandmarks),
        previewSize: previewSize ?? this.previewSize,
        result: result ?? this.result,
      );
}

/// Owns the camera, the ML Kit detector, the challenge engine and the
/// analyzer.
///
/// Drive it from a widget: `await controller.initialize()`, then
/// `controller.start()`, and listen to [state] / await [result].
class LivenessController extends ValueNotifier<LivenessState> {
  LivenessController({LivenessConfig? config, AntiSpoofModel? model})
      : config = config ?? const LivenessConfig(),
        _model = model,
        super(const LivenessState());

  final LivenessConfig config;
  final AntiSpoofModel? _model;

  CameraController? _camera;
  MlKitFaceDetector? _detector;
  late ChallengeEngine _engine;
  late AntiSpoofAnalyzer _analyzer;
  MotionTracker? _motion;

  Completer<LivenessResult>? _completer;
  int _frameCounter = 0;
  bool _busy = false;
  int _sessionStartMs = 0;
  int _sensorOrientation = 0;
  bool _disposed = false;

  CameraController? get cameraController => _camera;
  ValueListenable<LivenessState> get state => this;

  Future<void> initialize() async {
    value = value.copyWith(
        phase: LivenessPhase.preparing, message: 'Requesting camera access');

    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!status.isGranted) {
      throw CameraPermissionDeniedException(
          permanentlyDenied: status.isPermanentlyDenied);
    }

    value = value.copyWith(message: 'Starting camera');

    final cameras = await availableCameras();
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == config.cameraLens,
      orElse: () => cameras.first,
    );
    _sensorOrientation = camera.sensorOrientation;

    final controller = CameraController(
      camera,
      config.resolution,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    _camera = controller;

    _detector = MlKitFaceDetector();
    await _detector!.load();

    if (config.useGyroscope) {
      _motion = MotionTracker()..start();
    }

    _analyzer = AntiSpoofAnalyzer(
      config: config,
      motionTracker: _motion,
      model: _model,
    );
    _engine = ChallengeEngine(config);

    value = value.copyWith(
      previewSize: controller.value.previewSize,
      message: 'Ready',
    );
  }

  /// Runs one session and completes with the verdict.
  Future<LivenessResult> start() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return LivenessResult.failed(LivenessFailure.cameraError);
    }
    if (_completer != null && !_completer!.isCompleted) {
      return _completer!.future;
    }

    _completer = Completer<LivenessResult>();
    _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
    _frameCounter = 0;
    _analyzer.reset();
    _engine.start(_sessionStartMs);

    value = value.copyWith(
      phase: LivenessPhase.searchingFace,
      message: 'Position your face in the oval',
      total: _engine.sequence.length,
      completed: 0,
    );

    await camera.startImageStream(_onFrame);
    return _completer!.future;
  }

  Future<void> cancel() => _finish(LivenessResult.failed(
        LivenessFailure.cancelled,
        completed: _completer == null ? const [] : _engine.completed,
      ));

  // --- Frame pipeline ------------------------------------------------------

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _disposed) return;
    if (_frameCounter++ % config.processEveryNthFrame != 0) return;
    _busy = true;
    try {
      await _processFrame(image);
    } catch (e, st) {
      debugPrint('flutter_face_liveness_detection: frame error $e\n$st');
    } finally {
      _busy = false;
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _sessionStartMs > config.sessionTimeout.inMilliseconds) {
      await _finish(LivenessResult.failed(
        LivenessFailure.sessionTimeout,
        completed: _engine.completed,
        elapsed: Duration(milliseconds: now - _sessionStartMs),
      ));
      return;
    }

    final rotationDegrees = _resolveRotationDegrees();
    final face = await _detector!.detect(image, rotationDegrees);

    if (face == null) {
      value = value.copyWith(
        phase: LivenessPhase.searchingFace,
        message: 'No face detected',
        clearFaceBox: true,
      );
      return;
    }

    final rotatedSize = _rotatedSize(image, rotationDegrees);

    // Quality gate before anything else - garbage frames poison the signals.
    final areaRatio = (face.box.width * face.box.height) /
        (rotatedSize.width * rotatedSize.height);
    if (areaRatio < config.minFaceAreaRatio) {
      value = value.copyWith(
          message: 'Move closer',
          faceBox: face.box,
          faceLandmarks: face.landmarks);
      return;
    }
    if (areaRatio > config.maxFaceAreaRatio) {
      value = value.copyWith(
          message: 'Move back a little',
          faceBox: face.box,
          faceLandmarks: face.landmarks);
      return;
    }

    final luma = extractLuma(image);
    final sensorRect =
        mapRectToSensor(face.box, rotationDegrees, luma.width, luma.height);
    final stats = computeFaceStats(luma, sensorRect);

    final sample = FrameSample(
      timestampMs: now,
      faceBox: face.box,
      imageSize: rotatedSize,
      yaw: face.headEulerAngleY ?? 0,
      pitch: face.headEulerAngleX ?? 0,
      roll: face.headEulerAngleZ ?? 0,
      leftEyeOpen: face.leftEyeOpenProbability,
      rightEyeOpen: face.rightEyeOpenProbability,
      smiling: face.smilingProbability,
      meanLuma: stats.meanLuma,
      lumaStdDev: stats.stdDev,
      laplacianVariance: stats.laplacianVariance,
      saturatedFraction: stats.saturatedFraction,
      textureEntropy: stats.entropy,
      thumbnail: stats.thumbnail,
      leftEye: face.landmarks[FaceLandmarkKey.leftEye],
      rightEye: face.landmarks[FaceLandmarkKey.rightEye],
      noseBase: face.landmarks[FaceLandmarkKey.nose],
      mouthLeft: face.landmarks[FaceLandmarkKey.mouthLeft],
      mouthRight: face.landmarks[FaceLandmarkKey.mouthRight],
    );

    _analyzer.add(sample);
    if (_model != null) {
      _analyzer.addModelScore(await _model.scoreFrame(luma, sample));
    }

    final update = _engine.update(sample);

    if (update.outcome == ChallengeOutcome.timedOut) {
      await _finish(LivenessResult.failed(
        LivenessFailure.challengeTimeout,
        completed: _engine.completed,
        elapsed: Duration(milliseconds: now - _sessionStartMs),
      ));
      return;
    }

    if (update.outcome == ChallengeOutcome.passed) {
      HapticFeedback.lightImpact();
    }

    value = value.copyWith(
      phase: LivenessPhase.challenging,
      message: update.current == null
          ? 'Almost done'
          : config.instructionFor(update.current!),
      currentChallenge: update.current,
      clearChallenge: update.current == null,
      completed: update.completed,
      total: update.total,
      faceBox: face.box,
      faceLandmarks: face.landmarks,
    );

    if (update.sequenceFinished) {
      await _score(now);
    }
  }

  Future<void> _score(int now) async {
    value = value.copyWith(
        phase: LivenessPhase.scoring,
        message: 'Checking',
        clearChallenge: true);

    final signals =
        _analyzer.evaluate(blinkWasRequested: _engine.includesBlink);
    final score = AntiSpoofAnalyzer.combine(signals);
    final passed = score >= config.livenessThreshold;

    String? imagePath;
    if (passed && config.captureFinalImage) {
      imagePath = await _captureStill();
    }

    final result = LivenessResult(
      isLive: passed,
      livenessScore: score,
      failure: passed ? LivenessFailure.none : LivenessFailure.spoofDetected,
      signals: signals,
      completedChallenges: _engine.completed,
      capturedImagePath: imagePath,
      elapsed: Duration(milliseconds: now - _sessionStartMs),
    );

    await _finish(result);
  }

  /// Captures a still, downsizes it, and persists it under the app's
  /// documents directory so it survives past the ephemeral camera temp file.
  Future<String?> _captureStill() async {
    final camera = _camera;
    if (camera == null) return null;
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
      final shot = await camera.takePicture();

      var decoded = img.decodeImage(await File(shot.path).readAsBytes());
      if (decoded == null) return shot.path;

      // Some platform camera stacks write the still upright but leave a
      // stale EXIF orientation tag (or vice versa); bake it in explicitly
      // so the persisted copy is correct regardless of what the viewer does
      // with EXIF. Front camera stills come out of the sensor un-mirrored,
      // but users expect a selfie to look like the mirrored preview they
      // just saw, so flip horizontally for that lens only.
      decoded = img.bakeOrientation(decoded);
      if (config.cameraLens == CameraLensDirection.front) {
        decoded = img.flipHorizontal(decoded);
      }

      final resized =
          decoded.width > 640 ? img.copyResize(decoded, width: 640) : decoded;
      final jpg = img.encodeJpg(resized, quality: 85);

      final dir = Directory(
          '${(await getApplicationDocumentsDirectory()).path}/flutter_face_liveness_detection');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final savedPath =
          '${dir.path}/liveness_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(savedPath).writeAsBytes(jpg);

      try {
        await File(shot.path).delete();
      } catch (_) {}

      return savedPath;
    } catch (e) {
      debugPrint('flutter_face_liveness_detection: capture failed $e');
      return null;
    }
  }

  Future<void> _finish(LivenessResult result) async {
    final camera = _camera;
    if (camera != null && camera.value.isStreamingImages) {
      try {
        await camera.stopImageStream();
      } catch (_) {}
    }
    value = value.copyWith(
      phase: LivenessPhase.done,
      message: result.isLive ? 'Verified' : 'Verification failed',
      result: result,
      clearChallenge: true,
    );
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(result);
    }
  }

  // --- Conversion helpers --------------------------------------------------

  Size _rotatedSize(CameraImage image, int rotationDegrees) {
    final swapped = rotationDegrees % 180 == 90;
    return swapped
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());
  }

  /// Degrees to rotate the sensor buffer by so it is upright - what ML Kit's
  /// `InputImageMetadata.rotation` expects.
  int _resolveRotationDegrees() {
    final camera = _camera;
    if (camera == null) return 0;

    if (Platform.isIOS) {
      return ((_sensorOrientation ~/ 90) * 90) % 360;
    }

    const orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final deviceRotation = orientations[camera.value.deviceOrientation] ?? 0;

    return config.cameraLens == CameraLensDirection.front
        ? (360 - (_sensorOrientation + deviceRotation) % 360) % 360
        : (_sensorOrientation - deviceRotation + 360) % 360;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final camera = _camera;
    if (camera != null) {
      if (camera.value.isStreamingImages) {
        try {
          await camera.stopImageStream();
        } catch (_) {}
      }
      await camera.dispose();
    }
    await _detector?.close();
    await _motion?.dispose();
    super.dispose();
  }
}
