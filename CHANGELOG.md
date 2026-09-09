# Changelog

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
