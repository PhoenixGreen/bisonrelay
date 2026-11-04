import 'package:flutter_scene/scene.dart';

// vrm_gpu.dart says whether this app can draw characters in 3D: Flutter GPU
// switched on (FLTEnableFlutterGPU in macOS's Info.plist) and Impeller
// drawing. Where it cannot (tests, and for now Windows and Linux) the Studio
// says so rather than showing an empty stage.

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
