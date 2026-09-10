# Changelog

## 0.2.3

- Add `requireFaceInOval` (default `false`): when on, a detected face outside
  the on-screen capture oval is treated like "no face" - challenges won't
  advance and the final still won't be captured - until it's recentred.
- Captured still now crops to the face by default (`cropToFace`, default
  `true`) instead of saving the full camera frame, using the last
  known-good face box from the session plus a configurable margin
  (`faceCropPadding`, default `0.4`). Set `cropToFace: false` for the old
  full-frame capture.
- Add `LivenessScreen.showCapturedImagePreview` (default `false`): shows a
  thumbnail of the captured still on the result card when the session
  passes.
- Add `ovalCrop` (default `true`): when `cropToFace` is on, the captured
  still is cropped to the on-screen oval's bounding box with everything
  outside the ellipse painted black, instead of a padded rectangle around
  the face box. Set `ovalCrop: false` for the old rectangular face crop.
- Oval size/position is now configurable: `ovalWidthFraction` (default
  `0.72`, fraction of screen/frame width), `ovalHeightRatio` (default
  `1.32`, oval height as a multiple of its width), and
  `ovalCenterYFraction` (default `0.4`, vertical center as a fraction of
  height from the top). Drives the on-screen oval, the `requireFaceInOval`
  gate, and the `ovalCrop` capture shape consistently.
- Add `captureCropScale` (default `1.0`): shrinks (or grows) just the
  `ovalCrop` capture area around the oval's center, independent of the
  on-screen guide oval - e.g. `0.8` crops the final still tighter on the
  face while the displayed oval stays the same size.

## 0.2.1

- Add `preCaptureDelay` (default 900ms): a "Hold still" pause between the
  last challenge passing and the final photo, so the still isn't snapped
  mid-turn right after a turn/nod challenge. Set to `Duration.zero` for the
  old instant-capture behaviour.

## 0.2.0

- Add mask detection: a worn mask flattens the nose/mouth region relative to
  the eyes/forehead, and the analyzer now watches for that texture drop every
  frame. A session that looks masked for too long, or too consistently, fails
  fast with `LivenessFailure.maskDetected` instead of completing challenges or
  capturing a photo. Tunable via `enableMaskDetection`, `maskDetectionFrames`,
  `maskTextureRatio`, `maskEntropyDrop`, `maskSessionFraction`.
- Face detector now defaults to ML Kit's `FaceDetectorMode.fast` for quicker
  per-frame detection on mid-range devices.

## 0.1.1

- Add screenshots to README.

## 0.1.0

- Initial release: on-device face liveness detection with randomized active
  challenges (blink, smile, turn left/right, nod down, hold still) and a
  multi-signal passive anti-spoof analyzer (brightness, sharpness, glare,
  texture, micro-motion, motion correlation, depth parallax).
- Optional pluggable `AntiSpoofModel` for a trained network signal.
