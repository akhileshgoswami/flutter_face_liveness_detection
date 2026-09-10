import 'dart:ui';

/// The capture oval, in whatever coordinate space [size] is given in - the
/// screen for the UI overlay, the rotated camera frame for the controller's
/// alignment gate and still crop. Same proportions for both (driven by
/// [LivenessConfig.ovalWidthFraction]/[ovalHeightRatio]/[ovalCenterYFraction]),
/// so a face that looks centred in the oval on screen is also centred by
/// this math in the frame.
Rect ovalRectFor(
  Size size, {
  double widthFraction = 0.72,
  double heightRatio = 1.32,
  double centerYFraction = 0.4,
}) {
  final width = size.width * widthFraction;
  final height = width * heightRatio;
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height * centerYFraction),
    width: width,
    height: height,
  );
}

/// Whether [faceBox]'s center falls inside the capture oval for a frame of
/// [frameSize].
bool isFaceCenteredInOval(
  Rect faceBox,
  Size frameSize, {
  double widthFraction = 0.72,
  double heightRatio = 1.32,
  double centerYFraction = 0.4,
}) {
  final oval = ovalRectFor(
    frameSize,
    widthFraction: widthFraction,
    heightRatio: heightRatio,
    centerYFraction: centerYFraction,
  );
  final rx = oval.width / 2;
  final ry = oval.height / 2;
  if (rx <= 0 || ry <= 0) return false;

  final dx = faceBox.center.dx - oval.center.dx;
  final dy = faceBox.center.dy - oval.center.dy;
  return (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1.0;
}
