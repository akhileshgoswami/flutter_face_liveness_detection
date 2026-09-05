/// flutter_face_liveness_detection
///
/// On-device face liveness detection built on Google ML Kit face detection:
/// randomized active challenges plus a multi-signal passive anti-spoof
/// analyzer. No network calls, no SDK keys.
library flutter_face_liveness_detection;

export 'src/config/liveness_config.dart';
export 'src/models/face_landmarks.dart';
export 'src/models/liveness_challenge.dart';
export 'src/models/liveness_result.dart';
export 'src/models/frame_sample.dart';
export 'src/core/anti_spoof_analyzer.dart'
    show AntiSpoofAnalyzer, AntiSpoofModel;
export 'src/core/liveness_controller.dart';
export 'src/ui/liveness_screen.dart';
