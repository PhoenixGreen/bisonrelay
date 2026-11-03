import 'package:flutter_scene/scene.dart';

// vrm_gpu.dart says whether this app can draw characters in 3D: Flutter GPU
// is switched on (FLTEnableFlutterGPU in macOS's Info.plist) and Impeller is
// drawing. Where it cannot -- tests, which run without Flutter GPU, and for
// now Windows and Linux, where it is not switched on -- the Studio says so
// rather than showing an empty stage.

Future<bool>? _ready;

/// flutterGpuReady is whether 3D characters can be drawn, found once.
Future<bool> flutterGpuReady() => _ready ??= () async {
      try {
        await Scene.initializeStaticResources();
        return true;
      } catch (_) {
        return false;
      }
    }();
