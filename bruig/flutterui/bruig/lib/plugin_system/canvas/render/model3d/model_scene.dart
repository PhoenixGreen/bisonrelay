import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

// model_scene.dart is a 3D object drawn on Flutter GPU: its .glb read once
// into a scene of its own, posed by its animations at the times its clips
// say, and seen either framed whole in its box -- turned, tilted, brought
// closer -- or standing on a stage, through the stage's camera.
//
// As the characters are (see vrm_character.dart): a frame is drawn as the
// canvas asks for it, never ahead, so an export frame is the frame asked for.

/// ModelPlay is one of a model's animations playing: its name, how far in,
/// in seconds, and how much it counts.
typedef ModelPlay = (String name, double time, double weight);

/// ModelScene is one 3D object's model, read into a scene of its own.
class ModelScene extends ChangeNotifier {
  final Scene scene = Scene()..maxGpuFramesInFlight = 0;

  bool _disposed = false;

  /// dispose lets go of the scene's GPU memory; it draws nothing after.
  @override
  void dispose() {
    _disposed = true;
    scene.dispose();
    super.dispose();
  }

  Node? _node;
  final Map<String, AnimationClip> _clips = {};

  /// _centre and _size are the model's middle and how big it is, at rest:
  /// what it is framed by.
  vm.Vector3 _centre = vm.Vector3.zero();
  vm.Vector3 _size = vm.Vector3.all(1);

  /// error is why it could not be read, if it could not.
  String? error;

  bool get ready => _node != null;

  /// animations are the model's own, by name.
  Iterable<String> get animations => _clips.keys;

  /// load reads [bytes] -- a .glb -- into the scene.
  Future<void> load(Uint8List bytes) async {
    try {
      var node = await Node.fromGlbBytes(bytes, maxTextureSize: 2048);
      var bounds = node.combinedWorldBounds;
      if (bounds != null) {
        _centre = (bounds.min + bounds.max) * 0.5;
        _size = bounds.max - bounds.min;
      }
      for (var a in node.parsedAnimations) {
        _clips[a.name] = node.createAnimationClip(a)
          ..playing = false
          ..weight = 0;
      }
      scene.add(node);
      _node = node;
    } catch (e) {
      error = "This model could not be drawn: $e";
    }
    // Let go of while it loaded: nobody is listening.
    if (!_disposed) notifyListeners();
  }

  /// _pose sets each animation where [plays] has it, and the rest to
  /// nothing: as it is at that moment, however it got there.
  void _pose(List<ModelPlay> plays) {
    for (var c in _clips.values) {
      c.weight = 0;
    }
    for (var (name, time, weight) in plays) {
      var c = _clips[name];
      if (c == null) continue;
      c
        ..playbackTime = time
        ..weight = weight;
    }
    scene.update(0);
  }

  /// paint draws it framed whole in [box]: seen from [turn] degrees round
  /// and [tilt] above, [zoom] times closer.
  void paint(ui.Canvas canvas, ui.Rect box,
      {double turn = 0,
      double tilt = 0,
      double zoom = 1,
      List<ModelPlay> plays = const [],
      double pixelRatio = 1}) {
    // Let go of (see dispose), it draws nothing.
    if (_disposed) return;
    var node = _node;
    if (node == null || box.width < 1 || box.height < 1) return;
    node.localTransform = vm.Matrix4.identity();
    _pose(plays);
    const fov = 35 * math.pi / 180;
    var aspect = box.width / box.height;
    // Far enough back for its widest side to fit, either way.
    var radius = math.max(0.01, _size.length / 2);
    var fit = radius / math.sin(fov / 2) / math.min(1.0, aspect);
    var distance = fit / math.max(0.05, zoom);
    var a = turn * math.pi / 180, b = tilt * math.pi / 180;
    // A glTF model faces +z: seen from in front at turn nought.
    var eye = _centre +
        vm.Vector3(math.sin(a) * math.cos(b), math.sin(b),
                math.cos(a) * math.cos(b)) *
            distance;
    var camera = PerspectiveCamera(
        fovRadiansY: fov,
        position: eye,
        target: _centre.clone(),
        fovNear: math.max(0.001, distance / 1000),
        fovFar: distance * 10 + radius * 4);
    scene.render(camera, canvas, viewport: box, pixelRatio: pixelRatio);
  }

  /// paintOnStage draws it standing on a stage seen in [box], from [eye]
  /// looking at [target] (the stage's metres): at [x], [z], [lift] off the
  /// floor, turned to [facing] degrees, [height] metres tall.
  void paintOnStage(ui.Canvas canvas, ui.Rect box,
      {required (double, double, double) eye,
      required (double, double, double) target,
      required double fovY,
      double x = 0,
      double z = 0,
      double lift = 0,
      double facing = 0,
      double height = 1.6,
      List<ModelPlay> plays = const [],
      double pixelRatio = 1}) {
    // Let go of (see dispose), it draws nothing.
    if (_disposed) return;
    var node = _node;
    if (node == null || box.width < 1 || box.height < 1) return;
    // The stage's metres in the scene's: across mirrored, as for the stage
    // and the characters (see StageScene.paint).
    vm.Vector3 toScene((double, double, double) v) =>
        vm.Vector3(-v.$1, v.$2, v.$3);
    var scale = height / math.max(0.001, _size.y);
    var feet = vm.Vector3(_centre.x, _centre.y - _size.y / 2, _centre.z);
    // Facing nought, towards the camera, as a glTF model already does;
    // turned the other way round, for the mirror.
    node.localTransform = vm.Matrix4.translation(toScene((x, lift, z)))
      ..rotateY(-facing * math.pi / 180)
      ..scaleByDouble(scale, scale, scale, 1)
      ..translateByVector3(-feet);
    _pose(plays);
    var camera = PerspectiveCamera(
        fovRadiansY: fovY,
        position: toScene(eye),
        target: toScene(target),
        fovNear: 0.05,
        fovFar: 300);
    scene.render(camera, canvas, viewport: box, pixelRatio: pixelRatio);
  }
}
