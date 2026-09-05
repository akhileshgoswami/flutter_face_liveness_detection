import 'dart:ui';

/// Landmark points read off Google ML Kit's `Face.landmarks`, keyed the same
/// way ML Kit's own `FaceLandmarkType` does for the five points the rest of
/// this package cares about.
enum FaceLandmarkKey { leftEye, rightEye, nose, mouthLeft, mouthRight }

/// One detected face for a single frame.
///
/// ML Kit's face-detection classifier reports [leftEyeOpenProbability],
/// [rightEyeOpenProbability] and [smilingProbability] directly, and its pose
/// estimator reports head rotation as Euler angles - there is no need to
/// approximate any of those from pixels the way a bare bounding-box detector
/// would require.
class DetectedFace {
  const DetectedFace({
    required this.box,
    required this.trackingId,
    required this.landmarks,
    required this.leftEyeOpenProbability,
    required this.rightEyeOpenProbability,
    required this.smilingProbability,
    required this.headEulerAngleX,
    required this.headEulerAngleY,
    required this.headEulerAngleZ,
  });

  final Rect box;
  final int? trackingId;
  final Map<FaceLandmarkKey, Offset> landmarks;

  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final double? smilingProbability;

  /// Pitch (up/down), in degrees.
  final double? headEulerAngleX;

  /// Yaw (left/right), in degrees.
  final double? headEulerAngleY;

  /// Roll (tilt), in degrees.
  final double? headEulerAngleZ;
}
