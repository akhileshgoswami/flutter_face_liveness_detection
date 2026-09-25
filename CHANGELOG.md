# Changelog

## 0.2.6

- Challenges are now optional: pass `challengeCount: 0` (or an empty
  `challengePool`) to skip active challenges entirely. The session collects
  face frames, then scores on the passive anti-spoof signals only
  (brightness, sharpness, glare, texture, micro-motion, mask check).
  Previously `challengeCount` was clamped to at least 1 and an empty pool
  fell back to a blink challenge.
- Add `LivenessConfig.passiveFrameCount` (default `12`): frames to collect
  before scoring when no challenges are requested. Capped at
  `analysisWindow`.
- Example app: challenge picker now allows deselecting every challenge.

## 0.2.5

- Add `LivenessConfig.messages` (`LivenessMessages`): every user-facing
  string the package shows - status copy ("Position your face in the
  oval", "Hold still", "Checking", ...), per-challenge instructions
  (including `holdStillInstruction`, default `'Hold still and look at the
  camera'`), result-card copy for each `LivenessFailure`, and the error
  panel/permission copy - is now overridable without forking the UI. Every
  field defaults to the current copy, so leaving `messages` unset changes
  nothing.
- `LivenessConfig.instructionBuilder` still takes priority over
  `messages`'s per-challenge fields when both are supplied.

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
