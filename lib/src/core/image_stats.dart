import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';

/// A single-channel greyscale view of a camera frame.
class LumaImage {
  const LumaImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.rowStride,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int rowStride;

  int at(int x, int y) => bytes[y * rowStride + x];
}

/// Statistics computed over the face region of one frame.
class FaceRegionStats {
  const FaceRegionStats({
    required this.meanLuma,
    required this.stdDev,
    required this.laplacianVariance,
    required this.saturatedFraction,
    required this.entropy,
    required this.thumbnail,
  });

  final double meanLuma;
  final double stdDev;
  final double laplacianVariance;
  final double saturatedFraction;
  final double entropy;
  final List<int> thumbnail;

  static const int thumbSide = 12;
}

/// Pulls the luminance channel out of a [CameraImage].
///
/// Android delivers YUV_420_888 or NV21, where plane 0 is already luma.
/// iOS delivers BGRA8888, so we convert with the integer Rec.601 weights.
LumaImage extractLuma(CameraImage image) {
  final group = image.format.group;
  if (group == ImageFormatGroup.yuv420 || group == ImageFormatGroup.nv21) {
    final plane = image.planes.first;
    return LumaImage(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      rowStride: plane.bytesPerRow,
    );
  }

  final src = image.planes.first.bytes;
  final stride = image.planes.first.bytesPerRow;
  final out = Uint8List(image.width * image.height);
  for (var y = 0; y < image.height; y++) {
    var si = y * stride;
    final di = y * image.width;
    for (var x = 0; x < image.width; x++) {
      final b = src[si];
      final g = src[si + 1];
      final r = src[si + 2];
      out[di + x] = (r * 77 + g * 150 + b * 29) >> 8;
      si += 4;
    }
  }
  return LumaImage(
    bytes: out,
    width: image.width,
    height: image.height,
    rowStride: image.width,
  );
}

/// ML Kit reports face boxes in the *rotated* image space. The luma buffer is
/// still in sensor orientation, so map the rectangle back before sampling.
Rect mapRectToSensor(Rect r, int rotationDegrees, int sensorW, int sensorH) {
  switch (rotationDegrees % 360) {
    case 90:
      return Rect.fromLTRB(
          r.top, sensorH - r.right, r.bottom, sensorH - r.left);
    case 180:
      return Rect.fromLTRB(sensorW - r.right, sensorH - r.bottom,
          sensorW - r.left, sensorH - r.top);
    case 270:
      return Rect.fromLTRB(
          sensorW - r.bottom, r.left, sensorW - r.top, r.right);
    default:
      return r;
  }
}

/// Computes every per-frame statistic in a single pass over a subsampled grid,
/// so the cost stays roughly constant regardless of preview resolution.
FaceRegionStats computeFaceStats(LumaImage luma, Rect faceRect) {
  final left = faceRect.left.clamp(0.0, luma.width - 1.0).toInt();
  final top = faceRect.top.clamp(0.0, luma.height - 1.0).toInt();
  final right = faceRect.right.clamp(1.0, luma.width - 1.0).toInt();
  final bottom = faceRect.bottom.clamp(1.0, luma.height - 1.0).toInt();

  final w = math.max(right - left, 2);
  final h = math.max(bottom - top, 2);

  // Aim for ~60 samples per axis whatever the resolution.
  final stepX = math.max(1, w ~/ 60);
  final stepY = math.max(1, h ~/ 60);

  var count = 0;
  var sum = 0.0;
  var sumSq = 0.0;
  var saturated = 0;
  var lapSum = 0.0;
  var lapSumSq = 0.0;
  var lapCount = 0;
  final histogram = List<int>.filled(64, 0);

  for (var y = top + stepY; y < bottom - stepY; y += stepY) {
    for (var x = left + stepX; x < right - stepX; x += stepX) {
      final v = luma.at(x, y).toDouble();
      sum += v;
      sumSq += v * v;
      count++;
      if (v > 244) saturated++;
      histogram[(v ~/ 4).clamp(0, 63)]++;

      // 4-neighbour Laplacian on the subsampled grid.
      final lap = 4 * v -
          luma.at(x - stepX, y) -
          luma.at(x + stepX, y) -
          luma.at(x, y - stepY) -
          luma.at(x, y + stepY);
      lapSum += lap;
      lapSumSq += lap * lap;
      lapCount++;
    }
  }

  if (count == 0) {
    return FaceRegionStats(
      meanLuma: 0,
      stdDev: 0,
      laplacianVariance: 0,
      saturatedFraction: 0,
      entropy: 0,
      thumbnail: List<int>.filled(
          FaceRegionStats.thumbSide * FaceRegionStats.thumbSide, 0),
    );
  }

  final mean = sum / count;
  final variance = math.max(0.0, sumSq / count - mean * mean);
  final lapMean = lapSum / lapCount;
  final lapVar = math.max(0.0, lapSumSq / lapCount - lapMean * lapMean);

  var entropy = 0.0;
  for (final bin in histogram) {
    if (bin == 0) continue;
    final p = bin / count;
    entropy -= p * (math.log(p) / math.ln2);
  }

  // Downscale the face region to a fixed thumbnail for frame-to-frame diffs.
  const side = FaceRegionStats.thumbSide;
  final thumb = List<int>.filled(side * side, 0);
  for (var ty = 0; ty < side; ty++) {
    final sy =
        (top + (h * (ty + 0.5) / side)).toInt().clamp(0, luma.height - 1);
    for (var tx = 0; tx < side; tx++) {
      final sx =
          (left + (w * (tx + 0.5) / side)).toInt().clamp(0, luma.width - 1);
      thumb[ty * side + tx] = luma.at(sx, sy);
    }
  }

  return FaceRegionStats(
    meanLuma: mean / 255.0,
    stdDev: math.sqrt(variance) / 255.0,
    laplacianVariance: lapVar,
    saturatedFraction: saturated / count,
    entropy: entropy,
    thumbnail: thumb,
  );
}

/// Mean absolute difference between two thumbnails, in 0..255 units.
double thumbnailDelta(List<int> a, List<int> b) {
  if (a.length != b.length || a.isEmpty) return 0;
  var total = 0;
  for (var i = 0; i < a.length; i++) {
    total += (a[i] - b[i]).abs();
  }
  return total / a.length;
}
