# flutter_face_liveness_detection

On-device face liveness detection for Flutter. Randomised active challenges
plus a multi-signal passive anti-spoof analyzer. No network calls, no SDK keys,
no per-verification pricing.

Written from scratch on top of Google ML Kit face detection. You own this code.

## What it checks

Active challenges (order shuffled every session, so a pre-recorded video can't
be replayed):

- blink, smile, turn left, turn right, look down, hold still

Passive signals, scored in parallel while the challenges run:

| Signal | Attack it targets |
| --- | --- |
| `brightness` | frames too dark or blown out to judge |
| `sharpness` | photo-of-a-photo, out-of-focus print |
| `glare` | face shown on another phone or monitor |
| `texture` | flat print with reduced skin detail |
| `microMotion` | a frozen frame injected by a virtual camera |
| `blink` | still photo held up to the lens |
| `motionCorrelation` | photo panned in front of a moving phone (gyro cross-check) |
| `depthParallax` | anything flat, including a high-res tablet |
| `model` | your own TFLite/Core ML network, if you plug one in |

Each signal returns 0 (spoof) to 1 (live) plus an `available` flag. Signals
that couldn't run are dropped and the remaining weights renormalise, so a
device without a gyroscope still gets a fair score.

## Install

```yaml
dependencies:
  flutter_face_liveness_detection: ^0.1.0
```

Android — `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

`minSdkVersion 21` and ML Kit needs `android/app/build.gradle` to keep
`multiDexEnabled true` if you're near the method limit.

iOS — `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Used to verify that a real person is present.</string>
```

## Use

```dart
final result = await Navigator.of(context).push<LivenessResult>(
  MaterialPageRoute(
    builder: (_) => LivenessScreen(
      config: LivenessConfig(
        challengeCount: 3,
        livenessThreshold: 0.62,
      ),
    ),
  ),
);

if (result != null && result.isLive) {
  print(result.livenessScore);
  print(result.capturedImagePath);
}
```

Headless, if you want your own UI:

```dart
final controller = LivenessController(config: const LivenessConfig());
await controller.initialize();
controller.addListener(() => print(controller.value.message));
final result = await controller.start();
await controller.dispose();
```

## Tuning

`livenessThreshold` is the one knob that matters. Start at 0.62, then run your
own bench: 50 real faces and 50 spoof attempts (print, phone screen, laptop
screen), log `result.toMap()` for each, and move the threshold to where your
false-reject and false-accept rates balance for your risk appetite.

`SignalWeights` lets you re-rank the signals. If your users are often in poor
light, drop `brightness` and `sharpness` weight and lean on `depthParallax`
and `motionCorrelation`, which are the two hardest to fake.

## Adding a trained model

The heuristics catch casual attacks. For a stronger passive check, implement
`AntiSpoofModel` with a silent-face network and pass it in — it becomes one
more weighted signal, it doesn't replace the rest.

```dart
class TflAntiSpoof implements AntiSpoofModel {
  @override
  Future<double> scoreFrame(LumaImage luma, FrameSample sample) async {
    // crop luma to sample.faceBox, resize to your model input, run, return 0..1
  }
}

LivenessScreen(model: TflAntiSpoof());
```

## Limits worth knowing

This runs entirely on the client, so it protects against someone holding up a
photo — not against someone who has rooted the device and patched the app, or
piped a virtual camera into it. For KYC, banking, or anything where money moves
on the result, treat this as a filter, not the decision: send the captured
frames to your server and re-verify there.

The `depthParallax` and `motionCorrelation` signals need the head to actually
sweep, which is why `alwaysIncludeYawSweep` defaults to true. Turn it off and
those two signals will usually report unavailable.

## Renaming

Everything keys off the package name in `pubspec.yaml`. To rename:

1. change `name:` in `pubspec.yaml`
2. rename `lib/flutter_face_liveness_detection.dart` to match
3. find-and-replace `flutter_face_liveness_detection` across the repo

No native code or platform channels to touch.
