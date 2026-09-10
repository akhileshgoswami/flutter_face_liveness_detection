import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../config/liveness_config.dart';
import '../core/anti_spoof_analyzer.dart';
import '../core/liveness_controller.dart';
import '../core/oval_geometry.dart';
import '../models/face_landmarks.dart';
import '../models/liveness_result.dart';

const _kAccent = Color(0xFF4ADE80);
const _kDanger = Color(0xFFF87171);
const _kBackdropTop = Color(0xFF0B0F17);
const _kBackdropBottom = Color(0xFF151B27);

/// Drop-in verification screen. Pops with a [LivenessResult], and also calls
/// [onCompleted] if you would rather keep the route.
class LivenessScreen extends StatefulWidget {
  const LivenessScreen({
    super.key,
    this.config,
    this.model,
    this.onCompleted,
    this.autoPop = true,
    this.showCapturedImagePreview = false,
  });

  final LivenessConfig? config;
  final AntiSpoofModel? model;
  final ValueChanged<LivenessResult>? onCompleted;
  final bool autoPop;

  /// Show a thumbnail of the captured still on the result card.
  final bool showCapturedImagePreview;

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

enum _ScreenError { none, permission, permissionPermanent, camera }

class _LivenessScreenState extends State<LivenessScreen> {
  late final LivenessController _controller;
  bool _ready = false;
  _ScreenError _error = _ScreenError.none;
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    _controller =
        LivenessController(config: widget.config, model: widget.model);
    _run();
  }

  Future<void> _run() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      final result = await _controller.start();
      if (!mounted) return;
      widget.onCompleted?.call(result);
      if (widget.autoPop) Navigator.of(context).pop(result);
    } on CameraPermissionDeniedException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.permanentlyDenied
          ? _ScreenError.permissionPermanent
          : _ScreenError.permission);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _ScreenError.camera;
        _errorDetail = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_kBackdropTop, _kBackdropBottom],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_ready &&
                  _error == _ScreenError.none &&
                  _controller.cameraController != null)
                _CameraLayer(controller: _controller.cameraController!),
              if (_error == _ScreenError.none)
                _OvalScrim(config: _controller.config),
              if (_error != _ScreenError.none)
                _ErrorPanel(kind: _error, detail: _errorDetail, onRetry: _retry)
              else
                _Hud(
                  config: _controller.config,
                  showCapturedImagePreview: widget.showCapturedImagePreview,
                ),
              Positioned(
                top: 8,
                left: 4,
                child: SafeArea(
                  child: IconButton(
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () async {
                      await _controller.cancel();
                      if (!context.mounted || !widget.autoPop) return;
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _retry() {
    setState(() {
      _error = _ScreenError.none;
      _errorDetail = null;
      _ready = false;
    });
    _run();
  }
}

class _CameraLayer extends StatelessWidget {
  const _CameraLayer({required this.controller});
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (size == null) return const SizedBox.shrink();
    final displaySize = Size(size.height, size.width);
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: displaySize.width,
        height: displaySize.height,
        child: Stack(
          children: [
            CameraPreview(controller),
            Selector<LivenessController,
                ({Rect? box, Map<FaceLandmarkKey, Offset>? lm})>(
              selector: (_, c) =>
                  (box: c.value.faceBox, lm: c.value.faceLandmarks),
              builder: (context, data, _) => CustomPaint(
                size: displaySize,
                painter:
                    _FaceOverlayPainter(faceBox: data.box, landmarks: data.lm),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the detected face box plus the five ML Kit landmark points over the
/// preview, in the same (display-orientation) coordinate space ML Kit
/// reports them in.
class _FaceOverlayPainter extends CustomPainter {
  _FaceOverlayPainter({this.faceBox, this.landmarks});

  final Rect? faceBox;
  final Map<FaceLandmarkKey, Offset>? landmarks;

  static const _colors = {
    FaceLandmarkKey.leftEye: Color(0xFF4ADE80),
    FaceLandmarkKey.rightEye: Color(0xFF4ADE80),
    FaceLandmarkKey.nose: Color(0xFFFACC15),
    FaceLandmarkKey.mouthLeft: Color(0xFFF472B6),
    FaceLandmarkKey.mouthRight: Color(0xFFF472B6),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final box = faceBox;
    if (box != null) {
      final boxPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0x99FFFFFF);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(12)),
        boxPaint,
      );
    }

    landmarks?.forEach((key, point) {
      canvas.drawCircle(
          point, 3, Paint()..color = _colors[key] ?? Colors.white70);
    });
  }

  @override
  bool shouldRepaint(covariant _FaceOverlayPainter oldDelegate) =>
      oldDelegate.faceBox != faceBox || oldDelegate.landmarks != landmarks;
}

/// Dims everything outside the capture oval so the user knows where to sit.
class _OvalScrim extends StatelessWidget {
  const _OvalScrim({required this.config});
  final LivenessConfig config;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ScrimPainter(config), size: Size.infinite);
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter(this.config);
  final LivenessConfig config;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = ovalRectFor(
      size,
      widthFraction: config.ovalWidthFraction,
      heightRatio: config.ovalHeightRatio,
      centerYFraction: config.ovalCenterYFraction,
    );
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addOval(oval)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(scrim, Paint()..color = const Color(0xE60B0F17));
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white24,
    );
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter oldDelegate) =>
      oldDelegate.config != config;
}

/// Progress ring, step dots, instruction copy and the result card - the main
/// heads-up display drawn over the camera preview.
class _Hud extends StatelessWidget {
  const _Hud({required this.config, required this.showCapturedImagePreview});

  final LivenessConfig config;
  final bool showCapturedImagePreview;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LivenessController>().value;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final oval = ovalRectFor(
          size,
          widthFraction: config.ovalWidthFraction,
          heightRatio: config.ovalHeightRatio,
          centerYFraction: config.ovalCenterYFraction,
        );
        return Stack(
          children: [
            _AnimatedProgressRing(
              progress: state.progress,
              active: state.phase == LivenessPhase.challenging,
              oval: oval,
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 44,
              child: SafeArea(
                bottom: false,
                child: Center(child: _StepDots(state: state)),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              top: oval.bottom + 30,
              child: Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.15),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      state.message == 'No face detected' ? '' : state.message,
                      key: ValueKey(state.message),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (state.total > 0)
                    Text(
                      'Step ${math.min(state.completed + 1, state.total)} of ${state.total}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                ],
              ),
            ),
            if (state.phase == LivenessPhase.done && state.result != null)
              _ResultSheet(
                result: state.result!,
                showCapturedImagePreview: showCapturedImagePreview,
              ),
          ],
        );
      },
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.state});
  final LivenessState state;

  @override
  Widget build(BuildContext context) {
    if (state.total == 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(state.total, (i) {
        final done = i < state.completed;
        final isCurrent = i == state.completed;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isCurrent ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color:
                done ? _kAccent : (isCurrent ? Colors.white : Colors.white24),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _AnimatedProgressRing extends StatefulWidget {
  const _AnimatedProgressRing(
      {required this.progress, required this.active, required this.oval});
  final double progress;
  final bool active;
  final Rect oval;

  @override
  State<_AnimatedProgressRing> createState() => _AnimatedProgressRingState();
}

class _AnimatedProgressRingState extends State<_AnimatedProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: widget.progress),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        builder: (context, animatedProgress, __) => CustomPaint(
          size: Size.infinite,
          painter: _ProgressRingPainter(
            progress: animatedProgress,
            active: widget.active,
            pulse: _pulse.value,
            oval: widget.oval,
          ),
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.progress,
    required this.active,
    required this.pulse,
    required this.oval,
  });

  final double progress;
  final bool active;
  final double pulse;
  final Rect oval;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = oval.inflate(10 + (active ? pulse * 2 : 0));
    if (progress > 0) {
      canvas.drawArc(
        ring,
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4
          ..color = _kAccent,
      );
    }
    if (active) {
      canvas.drawOval(
        oval.inflate(3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = _kAccent.withValues(alpha: 0.25 + pulse * 0.2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter old) =>
      old.progress != progress || old.active != active || old.pulse != pulse;
}

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({
    required this.result,
    required this.showCapturedImagePreview,
  });
  final LivenessResult result;
  final bool showCapturedImagePreview;

  @override
  Widget build(BuildContext context) {
    final good = result.isLive;
    return Align(
      alignment: Alignment.bottomCenter,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Transform.translate(
          offset: Offset(0, (1 - t) * 60),
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        ),
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xE6111826),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (good ? _kAccent : _kDanger).withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: (good ? _kAccent : _kDanger).withValues(alpha: 0.15),
                  blurRadius: 28,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showCapturedImagePreview &&
                    result.capturedImagePath != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        File(result.capturedImagePath!),
                        height: 160,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (good ? _kAccent : _kDanger)
                            .withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        good ? Icons.verified_rounded : Icons.gpp_bad_rounded,
                        color: good ? _kAccent : _kDanger,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        good
                            ? 'Live face confirmed'
                            : _failureCopy(result.failure),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _ScoreBar(score: result.livenessScore, good: good),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _failureCopy(LivenessFailure f) {
    switch (f) {
      case LivenessFailure.spoofDetected:
        return 'That did not look like a live face. Try again in better light, without a screen or printout.';
      case LivenessFailure.challengeTimeout:
        return 'The step timed out. Start again and follow the prompt.';
      case LivenessFailure.sessionTimeout:
        return 'The session ran out of time. Start again.';
      case LivenessFailure.noFace:
        return 'No face was found. Centre your face in the oval.';
      case LivenessFailure.multipleFaces:
        return 'More than one face was in frame. Try again alone.';
      case LivenessFailure.poorQuality:
        return 'The camera image was too dark or blurry.';
      case LivenessFailure.maskDetected:
        return 'A mask was detected. Please remove it and try again.';
      case LivenessFailure.cameraError:
        return 'The camera could not start. Check permissions.';
      case LivenessFailure.permissionDenied:
        return 'Camera permission is required to verify your face.';
      case LivenessFailure.cancelled:
        return 'Verification cancelled.';
      case LivenessFailure.none:
        return 'Verification failed.';
    }
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.score, required this.good});
  final double score;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? _kAccent : _kDanger;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 6,
              color: Colors.white.withValues(alpha: 0.08),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: score.clamp(0.0, 1.0),
                child: Container(color: color),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          score.toStringAsFixed(2),
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel(
      {required this.kind, required this.detail, required this.onRetry});
  final _ScreenError kind;
  final String? detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isPermission = kind == _ScreenError.permission ||
        kind == _ScreenError.permissionPermanent;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kDanger.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPermission
                    ? Icons.no_photography_rounded
                    : Icons.videocam_off_rounded,
                color: _kDanger,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isPermission
                  ? 'Camera access needed'
                  : 'The camera could not start',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              isPermission
                  ? 'Face verification needs the camera to check you are a real, present person.'
                  : (detail ?? 'Unknown error'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: const Color(0xFF0B0F17),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: kind == _ScreenError.permissionPermanent
                  ? openAppSettings
                  : onRetry,
              child: Text(kind == _ScreenError.permissionPermanent
                  ? 'Open settings'
                  : 'Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
