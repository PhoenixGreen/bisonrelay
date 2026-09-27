import 'dart:async';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

// video_key.dart takes the green out of a video frame, on the GPU.
//
// The shader is chroma_key.frag. It is run into an image of the frame's own
// size, and that keyed image is what the picture painter draws -- so the
// crop, the framing, the filter and the overlay all apply to the keyed
// picture exactly as they would to a photograph with its background removed.
//
// Keyed images are kept for a few calls, since the painter asks again on
// every repaint and a paused video, or a poster, is the same frame each time.

class VideoKey {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  /// ready says the shader is loaded. Until it is, frames are drawn unkeyed.
  static final ValueNotifier<bool> ready = ValueNotifier(false);

  /// load reads the shader, once. Safe to call as often as liked; the stage
  /// calls it when it opens and repaints when it has landed.
  static Future<void> load() => _loading ??= () async {
        try {
          _program =
              await ui.FragmentProgram.fromAsset("shaders/chroma_key.frag");
          ready.value = true;
        } catch (exception) {
          debugPrint("The green screen shader did not load: $exception");
        }
      }();

  static final List<(ui.Image, int, ui.Image)> _cache = [];
  static const _keep = 8;

  /// keyed is [frame] with [key]'s colour taken out, or [frame] itself when
  /// the shader is not there yet.
  static ui.Image keyed(ui.Image frame, ChromaKey key) {
    var program = _program;
    if (program == null || !key.on) return frame;
    var signature =
        Object.hash(key.color, key.tolerance, key.softness, key.spill);
    for (var (src, sig, out) in _cache) {
      if (identical(src, frame) && sig == signature) {
        return out;
      }
    }

    var w = frame.width.toDouble(), h = frame.height.toDouble();
    var shader = program.fragmentShader()
      ..setFloat(0, w)
      ..setFloat(1, h)
      ..setFloat(2, key.color.r)
      ..setFloat(3, key.color.g)
      ..setFloat(4, key.color.b)
      ..setFloat(5, key.tolerance)
      ..setFloat(6, key.softness)
      ..setFloat(7, key.spill)
      ..setImageSampler(0, frame);
    var recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
        .drawRect(Offset.zero & Size(w, h), Paint()..shader = shader);
    var picture = recorder.endRecording();
    var out = picture.toImageSync(frame.width, frame.height);
    picture.dispose();
    shader.dispose();

    _cache.add((frame, signature, out));
    while (_cache.length > _keep) {
      _cache.removeAt(0).$3.dispose();
    }
    return out;
  }

  /// forgetForTest empties the cache between tests.
  @visibleForTesting
  static void forgetForTest() {
    for (var entry in _cache) {
      entry.$3.dispose();
    }
    _cache.clear();
  }
}
