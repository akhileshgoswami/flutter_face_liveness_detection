import 'dart:ui';

/// Everything the analyzer needs from a single camera frame, already reduced
/// to numbers so no pixel buffers are retained.
class FrameSample {
  const FrameSample({
    required this.timestampMs,
    required this.faceBox,
    required this.imageSize,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.leftEyeOpen,
    required this.rightEyeOpen,
    required this.smiling,
    required this.meanLuma,
    required this.lumaStdDev,
    required this.laplacianVariance,
    required this.saturatedFraction,
    required this.textureEntropy,
    required this.thumbnail,
    this.leftEye,
    this.rightEye,
    this.noseBase,
    this.mouthLeft,
    this.mouthRight,
  });

  final int timestampMs;
  final Rect faceBox;
  final Size imageSize;

  /// Head pose in degrees. Yaw is left/right, pitch up/down, roll tilt.
  final double yaw;
  final double pitch;
  final double roll;

  /// Eye-open / smile scores, or null when unavailable.
  final double? leftEyeOpen;
  final double? rightEyeOpen;
  final double? smiling;

  /// Statistics computed over the face region only.
  final double meanLuma; // 0..1
  final double lumaStdDev; // 0..1
  final double laplacianVariance; // raw, higher = sharper
  final double saturatedFraction; // 0..1, pixels near pure white
  final double textureEntropy; // bits, 0..6 over a 64-bin histogram

  /// Tiny greyscale copy of the face region used for frame-to-frame diffing.
  final List<int> thumbnail;

  final Offset? leftEye;
  final Offset? rightEye;
  final Offset? noseBase;
  final Offset? mouthLeft;
  final Offset? mouthRight;

  double get faceAreaRatio =>
      (faceBox.width * faceBox.height) / (imageSize.width * imageSize.height);

  double? get eyeOpenAverage {
    final l = leftEyeOpen;
    final r = rightEyeOpen;
    if (l == null && r == null) return null;
    if (l == null) return r;
    if (r == null) return l;
    return (l + r) / 2;
  }

  /// How far the face centre sits from the frame centre, in half-widths.
  double get centreOffset {
    final dx =
        (faceBox.center.dx - imageSize.width / 2) / (imageSize.width / 2);
    final dy =
        (faceBox.center.dy - imageSize.height / 2) / (imageSize.height / 2);
    return (dx * dx + dy * dy);
  }
}
