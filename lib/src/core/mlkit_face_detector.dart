import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/face_landmarks.dart';

const Map<FaceLandmarkKey, FaceLandmarkType> _kptTypes = {
  FaceLandmarkKey.leftEye: FaceLandmarkType.leftEye,
  FaceLandmarkKey.rightEye: FaceLandmarkType.rightEye,
  FaceLandmarkKey.nose: FaceLandmarkType.noseBase,
  FaceLandmarkKey.mouthLeft: FaceLandmarkType.leftMouth,
  FaceLandmarkKey.mouthRight: FaceLandmarkType.rightMouth,
};

/// Face detection backed by Google ML Kit instead of a bundled model file.
///
/// ML Kit's on-device classifier already reports eye-open / smiling
/// probabilities and head Euler angles, so [DetectedFace] can carry those
/// straight through - the rest of this package (challenge engine, anti-spoof
/// analyzer) is the "own model": a liveness pipeline built on top of a
/// generic face detector, not a trained anti-spoof network.
class MlKitFaceDetector {
  MlKitFaceDetector({
    FaceDetectorMode performanceMode = FaceDetectorMode.fast,
  }) : _performanceMode = performanceMode;

  final FaceDetectorMode _performanceMode;

  FaceDetector? _faceDetector;

  Future<void> load() async {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: true,
        enableTracking: true,
        performanceMode: _performanceMode,
      ),
    );
  }

  /// Runs detection on one camera frame. [rotationDegrees] is how much the
  /// raw buffer must be rotated to appear upright - ML Kit rotates
  /// internally and returns [Face.boundingBox] already in that upright
  /// space, so callers can treat it like a normal display-space rectangle.
  Future<DetectedFace?> detect(CameraImage image, int rotationDegrees) async {
    final detector = _faceDetector;
    if (detector == null) return null;

    final inputImage = _toInputImage(image, rotationDegrees);
    if (inputImage == null) return null;

    final faces = await detector.processImage(inputImage);
    if (faces.isEmpty) return null;

    faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
        .compareTo(a.boundingBox.width * a.boundingBox.height));
    final face = faces.first;

    return DetectedFace(
      box: face.boundingBox,
      trackingId: face.trackingId,
      landmarks: _extractLandmarks(face),
      leftEyeOpenProbability: face.leftEyeOpenProbability,
      rightEyeOpenProbability: face.rightEyeOpenProbability,
      smilingProbability: face.smilingProbability,
      headEulerAngleX: face.headEulerAngleX,
      headEulerAngleY: face.headEulerAngleY,
      headEulerAngleZ: face.headEulerAngleZ,
    );
  }

  Future<void> close() async {
    await _faceDetector?.close();
    _faceDetector = null;
  }

  // --- Helpers ---------------------------------------------------------

  Map<FaceLandmarkKey, Offset> _extractLandmarks(Face face) {
    final map = <FaceLandmarkKey, Offset>{};
    _kptTypes.forEach((key, type) {
      final landmark = face.landmarks[type];
      if (landmark != null) {
        map[key] = Offset(
          landmark.position.x.toDouble(),
          landmark.position.y.toDouble(),
        );
      }
    });
    return map;
  }

  InputImage? _toInputImage(CameraImage image, int rotationDegrees) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees) ??
        InputImageRotation.rotation0deg;
    final format =
        Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }
}
