import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_decal.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_face.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_look.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_move.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_performance.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_sculpt.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/plugin_system/canvas/model/lip_sync.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_look.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_mesh.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_pose.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_scene.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_shape.dart';
import 'package:bruig/plugin_system/canvas/storage/vroid_assets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:vector_math/vector_math.dart' as vm;

// vrm_character.dart is one 3D character in a scene of its own, as the
// Character Studio and the canvas both draw it: the shaped VRoid body, hair
// worn from other characters, clothes, decals, colours and look. Change what
// is drawn with [CharacterScene.show]; [tick] moves each frame on, and a
// SceneView or the canvas's painter draws it.

/// visemesOf is the face's mouth shapes for drawn mouth [m]: the nine an
/// animator draws (lip_sync.dart) made of the VRoid face's five. Shut and at
/// rest, none.
Map<String, double> visemesOf(MouthShape m) => switch (m) {
      MouthShape.rest || MouthShape.closed => const {},
      MouthShape.teeth => const {"MTH_I": 0.55, "MTH_E": 0.2},
      MouthShape.open => const {"MTH_E": 0.8},
      MouthShape.wide => const {"MTH_A": 0.9},
      MouthShape.round => const {"MTH_O": 0.8},
      MouthShape.pucker => const {"MTH_U": 0.9},
      MouthShape.lip => const {"MTH_I": 0.3, "MTH_U": 0.25},
      MouthShape.tongue => const {"MTH_A": 0.45, "MTH_E": 0.3},
    };

/// DecalLoader reads a decal's picture: RGBA, its width and height.
typedef DecalLoader = Future<(Uint8List, int, int)?> Function(String source);

/// bodyOverdrawTop and bodyOverdrawSide are how far past its box a
/// character framed whole is drawn, above and to each side, as shares of
/// the box's height: room for a hand raised, a leap, a kick.
const double bodyOverdrawTop = 0.35, bodyOverdrawSide = 0.42;

class CharacterScene extends ChangeNotifier {
  final Scene scene = Scene();

  /// paper is whether the look's paper is drawn behind: Studio, not canvas.
  final bool paper;
  final DecalLoader loadDecal;

  CharacterScene({required this.loadDecal, this.paper = true}) {
    // Every frame drawn, not the last held while the GPU catches up: an
    // export draws each once and must have it.
    if (!paper) scene.maxGpuFramesInFlight = 0;
    scene.directionalLight = DirectionalLight(direction: lightDirection(_look));
    StudioFinishPass.load().then((shader) {
      if (_disposed) return;
      _finishTried = true;
      if (shader != null) {
        _finish = StudioFinishPass(shader, _look, paper: paper);
        scene.addRenderPass(_finish!);
      }
      _restyle();
    });
  }

  bool _disposed = false;

  String? _body;
  CharacterShape _shape = const CharacterShape();
  CharacterOutfit _outfit = CharacterOutfit.asDesigned;
  CharacterLook _look = const CharacterLook();
  List<CharacterDecal> _decals = const [];
  List<SculptStroke> _sculpt = const [];
  List<PaintStroke> _paint = const [];

  ShapedAvatar? _avatar;
  String? _loading;

  ShapedAvatar? get avatar => _avatar;

  /// error is why it could not be drawn, if so.
  String? error;

  /// fetching names hair being first fetched, and how far, 0 to 1.
  String? fetching;
  double? fetched;

  /// own are the clothes the body comes with, once loaded.
  Set<WearSlot> get own => {
        for (final s in WearSlot.values)
          if (_avatar?.wardrobe?.hasOwn(s) ?? false) s,
      };

  void showDesign(CharacterDesign d) => show(
      body: d.body,
      shape: d.shape,
      outfit: d.outfit,
      look: d.look,
      decals: d.decals,
      sculpt: d.sculpt,
      paint: d.paint,
      face: d.face,
      move: d.move);

  /// show changes what is given and leaves the rest as it is.
  void show({
    required String body,
    required CharacterShape shape,
    required CharacterOutfit outfit,
    required CharacterLook look,
    required List<CharacterDecal> decals,
    List<SculptStroke> sculpt = const [],
    List<PaintStroke> paint = const [],
    CharacterFace face = const CharacterFace(),
    CharacterMove move = const CharacterMove(),
  }) {
    final hairChanged =
        _body == null || shape.hair(body) != _shape.hair(_body!);
    final bodyChanged = body != _body,
        outfitChanged = outfit != _outfit,
        lookChanged = look != _look,
        decalsChanged = !listEquals(decals, _decals),
        paintChanged = !listEquals(paint, _paint);
    _body = body;
    _shape = shape;
    _outfit = outfit;
    _look = look;
    _decals = decals;
    _sculpt = sculpt;
    _paint = paint;
    _face = face;
    _move = move;
    if (bodyChanged) {
      _load(body);
      return;
    }
    if (outfitChanged) _dress();
    if (lookChanged) _restyle();
    if (decalsChanged) _avatar?.decorate(decals, loadDecal);
    if (paintChanged) _repaint();
    if (hairChanged) _hair();
  }

  StudioFinishPass? _finish;
  bool _finishTried = false;

  void _restyle() {
    if (!_finishTried) return;
    _finish?.look = _look;
    scene.directionalLight = DirectionalLight(direction: lightDirection(_look));
    for (final a in [_avatar, ..._donors.values]) {
      a?.applyLook(_look, finished: _finish != null);
    }
  }

  // Hair taken from other characters: each kept whole here, all but its
  // hair hidden, and worn on the body's head.
  final Map<String, ShapedAvatar> _donors = {};
  final Set<String> _donorsLoading = {};

  /// _owner is whose hair [r] is to be: null for none.
  String? _owner(HairRole r) {
    final h = _shape.hair(_body!);
    return switch (r) {
      HairRole.front => h.fringe,
      HairRole.back => h.back,
      HairRole.tails => h.tails,
    };
  }

  /// _hair shows each piece of hair, loading its source character if needed.
  void _hair() {
    final a = _avatar, body = _body;
    if (a == null || body == null) return;
    a.showHair((r) => _owner(r) == body);
    final h = _shape.hair(body);
    final want = {h.back, h.fringe, if (h.tails case final t?) t}..remove(body);
    for (final id in _donors.keys.toList()) {
      if (!want.contains(id)) scene.remove(_donors.remove(id)!.holder);
    }
    for (final id in want) {
      final d = _donors[id];
      if (d == null) {
        _loadDonor(id);
      } else {
        d.showHair((r) => _owner(r) == id, donor: true);
      }
    }
  }

  Future<void> _loadDonor(String id) async {
    if (!_donorsLoading.add(id)) return;
    try {
      final model =
          [...vroidBodies, ...vroidHairSources].firstWhere((m) => m.id == id);
      if (!await VroidAssets.installed(id)) {
        // Fetched only for someone who chose to download the characters:
        // opening a received canvas is not that choice.
        if ((await VroidAssets.missing(vroidBodies)).isNotEmpty) {
          error = "This hair comes from a character not downloaded yet. "
              "Download the characters in Character Studio first.";
          return;
        }
        // Nor unless fetching is switched on: a received canvas must not
        // make a request the reader has forbidden.
        if (!await CanvasPreferences.fetchingAllowed()) {
          error = "This hair needs a download, and fetching is switched "
              "off: turn it on in Settings > Plugins > Canvas.";
          return;
        }
        fetching =
            hairSources.where((h) => h.$1 == id).firstOrNull?.$2 ?? "the hair";
        fetched = 0;
        _changed();
        await VroidAssets.install([model], progress: (p) {
          fetched = p;
          _changed();
        });
      }
      final bytes = await File(await VroidAssets.modelPath(id)).readAsBytes();
      final d = await ShapedAvatar.load(bytes);
      if (_disposed) return;
      _donors[id] = d;
      scene.add(d.holder);
      _restyle();
      _hair();
    } catch (e) {
      error = "This hair could not be fetched: $e";
    } finally {
      _donorsLoading.remove(id);
      fetching = null;
      fetched = null;
      _changed();
    }
  }

  Future<void> _load(String id) async {
    _loading = id;
    error = null;
    _changed();
    try {
      final bytes = await File(await VroidAssets.modelPath(id)).readAsBytes();
      final next = await ShapedAvatar.load(bytes);
      if (_disposed || _loading != id) return;
      next
        ..sculpt(_sculpt)
        ..apply(_shape);
      final old = _avatar;
      if (old != null) scene.remove(old.holder);
      scene.add(next.holder);
      next.update(0);
      _avatar = next;
      _restyle();
      _hair();
      unawaited(next.decorate(_decals, loadDecal));
      _blushed = -1;
      _repaint();
      _changed();
      await _dress();
    } catch (e) {
      error = "This character could not be drawn: $e";
      _changed();
    } finally {
      if (_loading == id) _loading = null;
    }
  }

  /// _dress puts the outfit on, reporting if it could not.
  Future<void> _dress() async {
    final a = _avatar;
    if (a == null) return;
    await a.dress(_outfit);
    if (a.dressError != null) {
      error = "The clothes could not be made: ${a.dressError}";
      _changed();
    }
  }

  /// ready completes when the body, its clothes, decals and borrowed hair are
  /// all here: for drawing it once, as an export does.
  Future<void> ready({Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final a = _avatar;
      final h = _body == null ? null : _shape.hair(_body!);
      final want = h == null
          ? const <String>{}
          : ({h.back, h.fringe, if (h.tails case final t?) t}..remove(_body));
      if (error != null) return;
      if (a != null &&
          _loading == null &&
          _finishTried &&
          !a.busy &&
          want.every(_donors.containsKey) &&
          _donorsLoading.isEmpty) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  /// tick moves it on by [dt] seconds, seen by [camera], eyes on [lookAt].
  void tick(double dt, Camera camera,
      {vm.Vector3? lookAt, double pixelRatio = 1}) {
    _finish?.pixelRatio = pixelRatio;
    final a = _avatar, body = _body;
    if (a == null || body == null) return;
    a
      ..sculpt(_sculpt)
      ..apply(_shape);
    final v = a.avatar;
    v.mtoonLighting.fromScene(scene);
    _clock += dt;
    _moveFace(dt);
    if (lookAt != null) {
      var at = lookAt;
      if (camera is PerspectiveCamera) {
        final f = camera.target - camera.position;
        final far = f.length;
        f.normalize();
        // forward × up is the screen's left in flutter_scene's view.
        final left = f.cross(vm.Vector3(0, 1, 0)).normalized();
        final up = left.cross(f).normalized();
        at = lookAt + (left * -_gazeX + up * _gazeY) * far * 0.6;
      }
      v.lookAt.target = at;
    }
    v.autoBlink.enabled = _face.blinks && (performance?.blink ?? true);
    if (!v.autoBlink.enabled) v.expressions.setValue('blink', 0);
    // Stood as its Move settings say, not in the T it was made in; the
    // face's head tilt over the stance's.
    if (!identical(_poser?.avatar, a)) _poser = VrmPoser(a);
    final (move, mt, strength, weight, mirror) = _moveNow(dt);
    _poser!.pose(move, dt,
        t: mt, strength: strength, weight: weight, mirror: mirror);
    final physics = (
      hair: _move.physicsOf("hair"),
      clothes: _move.physicsOf("clothes"),
      weight: _move.physicsOf("gravity"),
      wind: _move.physicsOf("wind"),
    );
    for (final x in [a, ..._donors.values]) {
      x.physics(
          hair: physics.hair,
          clothes: physics.clothes,
          weight: physics.weight,
          wind: physics.wind);
    }
    final head = v.humanoid.normalizedRotation(VrmHumanBone.head) ??
        vm.Quaternion.identity();
    v.humanoid.setNormalizedRotation(VrmHumanBone.head,
        head * vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), _tiltNow * 0.45));
    a.update(dt, camera: camera);
    a.wear(_unitsNow);
    if ((_mixNow.blush - _blushed).abs() > 0.02 ||
        ShapedAvatar.creaseKey(_shape) != _creased) {
      _blushed = _mixNow.blush;
      _repaint();
    }
    // The colours picked, and the years' grey; borrowed hair takes the
    // colour of the hair it mixes with unless one is picked.
    final colours = <VrmPart, int>{
      for (final (part, key) in const [
        (VrmPart.hair, "colour.hair"),
        (VrmPart.skin, "colour.skin"),
        (VrmPart.eyes, "colour.eyes"),
        (VrmPart.brows, "colour.brows"),
      ])
        if (_shape.colour(key) case final c?) part: c,
    };
    final grey = ageGrey(_shape.age);
    final back = _shape.hair(body).back;
    final main = back == body ? a : _donors[back];
    a.colour(colours, grey: grey);
    for (final MapEntry(key: id, value: d) in _donors.entries) {
      d.colour(colours,
          hairAs: id == back ? null : main?.hairAverage, grey: grey);
    }
    // Borrowed hair, scaled to this head.
    for (final d in _donors.values) {
      final mine = a.rig.face?.es, theirs = d.rig.face?.es;
      final grow = mine != null && theirs != null && theirs > 0
          ? (mine / theirs).clamp(0.8, 1.25).toDouble()
          : 1.0;
      d.apply(_shape, bones: false);
      d.wearOn(a, grow);
      d.avatar.mtoonLighting.fromScene(scene);
      d.update(dt, camera: camera);
    }
  }

  // On the canvas.

  /// _canvasCamera sees the character as the canvas draws it; _frame is the
  /// canvas frame it was last moved on to.
  final PerspectiveCamera _canvasCamera = PerspectiveCamera(
      fovRadiansY: 30 * vm.degrees2Radians, fovNear: 0.05, fovFar: 100);
  int? _frame;

  /// aim points [camera] at the character, showing what [framing] says in a
  /// picture [aspect] times as wide as high: from [turn] half turns round,
  /// [tilt] quarter turns up, [zoom] times closer.
  void aim(PerspectiveCamera camera,
      {Character3dFraming framing = Character3dFraming.body,
      double turn = 0,
      double tilt = 0,
      double zoom = 1,
      double aspect = 0.5,
      double reach = 0}) {
    final h = _avatar?.avatar.humanoid;
    vm.Vector3? at(VrmHumanBone b) => restAt(b) ?? h?.worldPosition(b);
    final head = at(VrmHumanBone.head) ?? vm.Vector3(0, 1.4, 0);
    // The hair's top, about three neck lengths over the head bone, or as
    // high as the hands go if higher.
    final top = math.max(reach,
        head.y + (head.y - (at(VrmHumanBone.neck)?.y ?? head.y * 0.94)) * 3);
    final (vm.Vector3 focus, double high, double wide) = switch (framing) {
      // Feet on the frame's bottom, where a game puts the ground, with a
      // little room over the hair.
      Character3dFraming.body => (
          vm.Vector3(head.x, top * 1.06 / 2, head.z),
          top * 1.06,
          top * 0.42
        ),
      Character3dFraming.waist => () {
          final hips = at(VrmHumanBone.hips)?.y ?? top * 0.53;
          return (
            vm.Vector3(head.x, (hips + top) / 2, head.z),
            (top - hips) * 1.12,
            top * 0.42
          );
        }(),
      // By the head where it is: a design posed with hips moved aside or
      // head turned is framed by its face, not where its head would be
      // standing straight.
      Character3dFraming.head => () {
          final posed = h?.worldPosition(VrmHumanBone.head) ?? head;
          final lift = posed.y - head.y;
          final neck = (at(VrmHumanBone.neck)?.y ?? head.y - 0.08) + lift;
          final crown = top + lift;
          final span = (crown - neck) * 1.75;
          return (
            vm.Vector3(posed.x, (neck + crown) / 2, posed.z),
            span,
            span * 0.9
          );
        }(),
    };
    final fit = math.max(high, wide / math.max(aspect, 0.05));
    final distance =
        fit / 2 / math.tan(camera.fovRadiansY / 2) / zoom.clamp(0.5, 3.0);
    final yaw = turn * math.pi, pitch = tilt * math.pi / 2 * 0.95;
    camera
      ..position = focus +
          vm.Vector3(math.sin(yaw) * math.cos(pitch), math.sin(pitch),
                  -math.cos(yaw) * math.cos(pitch)) *
              distance
      ..target = focus;
  }

  /// paint draws the character into [box] at [frame] of a canvas playing
  /// [frameRate] frames a second, seen as [aim] says, at [pixelRatio] pixels
  /// per canvas point. Moved on once per frame however often it is drawn,
  /// since the stage and an export both draw a frame more than once.
  void paint(ui.Canvas canvas, ui.Rect box,
      {required int frame,
      int frameRate = 12,
      Character3dFraming framing = Character3dFraming.body,
      double turn = 0,
      double tilt = 0,
      double zoom = 1,
      double pixelRatio = 1}) {
    // Disposed: draws nothing.
    if (_disposed) return;
    if (box.width < 1 || box.height < 1) return;
    final camera = _canvasCamera;
    aim(camera,
        framing: framing,
        turn: turn,
        tilt: tilt,
        zoom: zoom,
        aspect: box.width / box.height,
        reach: framing == Character3dFraming.body ? 0 : _reach());
    final dt = _advance(frame, frameRate);
    final t = _sceneTime!;
    // Carried across by its walks, turned the way it goes: the camera moves
    // and turns the other way so the framing stays put.
    final p = performance;
    if (p != null && (p.startsAt != 0 || p.clips.any((c) => c.dir != 0))) {
      final go = p.travelAt(t, _paceOf);
      aim(camera,
          framing: framing,
          turn: turn - go.turn * 0.5,
          tilt: tilt,
          zoom: zoom,
          aspect: box.width / box.height,
          reach: framing == Character3dFraming.body ? 0 : _reach());
      final f = camera.target - camera.position;
      // Only to the box's edge: a character is drawn only in its own box.
      final edge =
          f.length * math.tan(camera.fovRadiansY / 2) * box.width / box.height -
              _height * 0.3;
      // From the edge its walks start at, if they start at one.
      final x = (p.startsAt * math.max(0.0, edge) + go.x)
          .clamp(-math.max(0.0, edge), math.max(0.0, edge))
          .toDouble();
      f.normalize();
      final right = vm.Vector3(0, 1, 0).cross(f).normalized()..scale(x);
      camera
        ..position = camera.position - right
        ..target = camera.target - right;
    }
    // Seen whole past its box's top and sides (a raised arm, a kick, a
    // leap) rather than cut off or the body shrunk to make room. The box is
    // the body, standing on its bottom edge.
    var view = box;
    if (framing == Character3dFraming.body) {
      view = ui.Rect.fromLTRB(
          box.left - box.height * bodyOverdrawSide,
          box.top - box.height * bodyOverdrawTop,
          box.right + box.height * bodyOverdrawSide,
          box.bottom);
      _widen(camera, box, view);
    }
    tick(dt, camera, lookAt: camera.position, pixelRatio: pixelRatio);
    scene.update(dt);
    _shadow(canvas, view, camera, p?.shadow ?? "Soft");
    scene.render(camera, canvas, viewport: view, pixelRatio: pixelRatio);
  }

  /// _widen moves [camera] back so it sees the larger [view], [box] unmoved.
  void _widen(PerspectiveCamera camera, ui.Rect box, ui.Rect view) {
    final f = camera.target - camera.position;
    final d = f.length;
    f.normalize();
    final left = f.cross(vm.Vector3(0, 1, 0)).normalized();
    final up = left.cross(f).normalized();
    final perPoint = 2 * d * math.tan(camera.fovRadiansY / 2) / box.height;
    final shift = view.center - box.center;
    final target = camera.target -
        left * (shift.dx * perPoint) -
        up * (shift.dy * perPoint);
    camera
      ..target = target
      ..position = target - f * (d * view.height / box.height);
  }

  /// _reach is how high its hands go in what it does (cheering, jumping,
  /// waving), 0 where they stay below its head. Taken from what it is set to
  /// do, not where its hands are now, so the camera stays put as they rise.
  double _reach() {
    final p = performance;
    final stances = {
      _move.stance,
      if (p?.stance case final s?) s,
      for (final k in p?.keys ?? const <PoseKey>[]) k.stance,
    };
    final motions = {
      _move.motion,
      for (final c in p?.clips ?? const <MotionClip3d>[]) c.kind,
    };
    final up = stances.contains("Cheer") || motions.contains("Jump");
    final wave = stances.contains("Wave") || motions.contains("Wave");
    if (!up && !wave) return 0;
    // At rest, or as made if not yet stood: the arm is as long either way.
    final h = _avatar?.avatar.humanoid;
    vm.Vector3? at(VrmHumanBone b) => restAt(b) ?? h?.worldPosition(b);
    final shoulder = at(VrmHumanBone.rightUpperArm),
        elbow = at(VrmHumanBone.rightLowerArm),
        hand = at(VrmHumanBone.rightHand);
    if (shoulder == null || elbow == null || hand == null) return 0;
    // The arm straight up, and the hand past the wrist, with a little room.
    final arm = shoulder.distanceTo(elbow) + elbow.distanceTo(hand);
    var top = shoulder.y + (up ? arm : arm * 0.85) + _height * 0.13;
    if (motions.contains("Jump")) top += _height * 0.18;
    return top;
  }

  /// _advance moves it on to [frame] of a canvas at [frameRate], returning
  /// the seconds that took: 0 for the frame it is at.
  double _advance(int frame, int frameRate) {
    final last = _frame;
    final dt = last == null || frame <= last
        ? 0.0
        : ((frame - last) / math.max(1, frameRate)).clamp(0.0, 0.25);
    _frame = frame;
    // The motion where the frame has it, so an export plays it the same way.
    final t = frame / math.max(1, frameRate);
    _sceneTime = t;
    _motionTime = t * _move.speed;
    return dt;
  }

  final PerspectiveCamera _stageCamera =
      PerspectiveCamera(fovNear: 0.05, fovFar: 300);

  /// paintOnStage draws the character on a 3D stage in [box], at [frame] of
  /// a canvas at [frameRate]: on spot [x], [z] of the floor and [lift] off
  /// it, turned [facing] degrees, seen from [eye] looking at [target] with
  /// [fovY] radians vertical, all in stage metres (stage/stage_camera.dart).
  /// Its walks carry it across. [shadows] is whether the light casts any.
  void paintOnStage(ui.Canvas canvas, ui.Rect box,
      {required (double, double, double) eye,
      required (double, double, double) target,
      required double fovY,
      double x = 0,
      double z = 0,
      double lift = 0,
      double facing = 0,
      bool shadows = true,
      required int frame,
      int frameRate = 12,
      double pixelRatio = 1}) {
    // Disposed: draws nothing.
    if (_disposed) return;
    if (box.width < 1 || box.height < 1) return;
    final dt = _advance(frame, frameRate);
    final p = performance;
    final go = p != null && p.clips.any((c) => c.dir != 0)
        ? p.travelAt(_sceneTime!, _paceOf)
        : (x: 0.0, turn: 0.0);
    // Stage metres to scene, mirrored across: the scene's left is its right.
    vm.Vector3 toScene((double, double, double) v) =>
        vm.Vector3(-v.$1, v.$2, v.$3);
    // The camera is moved into the character's frame rather than the
    // character in front of the camera: the same picture, and the body's own
    // placing left alone.
    final at = toScene((x + go.x, lift, z));
    final turn = (facing + go.turn * 90) * math.pi / 180;
    final into = vm.Matrix4.rotationY(turn - math.pi);
    vm.Vector3 mine(vm.Vector3 w) => into.transformed3(w - at);
    final camera = _stageCamera
      ..fovRadiansY = fovY
      ..position = mine(toScene(eye))
      ..target = mine(toScene(target));
    tick(dt, camera, lookAt: camera.position, pixelRatio: pixelRatio);
    scene.update(dt);
    _shadow(canvas, box, camera, shadows ? (p?.shadow ?? "Soft") : "None");
    scene.render(camera, canvas, viewport: box, pixelRatio: pixelRatio);
  }

  /// performance is what it does in the canvas's scene, played at the frame
  /// [paint] draws. Null for as designed, as in the Studio.
  CharacterPerformance? performance;
  double? _sceneTime;

  /// sceneTime is how far [performance] has played, in seconds.
  set sceneTime(double? t) => _sceneTime = t;

  /// travel is how far its walks carry it, in metres, and how far it turns
  /// to face that way, in quarter turns, for a view that moves the other way
  /// as [paint] does. Nought with no performance.
  ({double x, double turn}) get travel {
    final p = performance, t = _sceneTime;
    if (p == null || t == null) return (x: 0.0, turn: 0.0);
    return p.travelAt(t, _paceOf);
  }

  /// _height is roughly how tall it is: what its walks are paced by.
  double get _height {
    final head = restAt(VrmHumanBone.head) ??
        _avatar?.avatar.humanoid.worldPosition(VrmHumanBone.head);
    return head == null ? 1.6 : head.y * 1.08;
  }

  /// _paceOf is how many metres a second walk or run [c] carries it.
  double _paceOf(MotionClip3d c) =>
      _height *
      (c.kind == "Run" ? 1.9 : 0.8) *
      (0.7 + 0.6 * _move.walkOf("pace")) *
      c.speed;

  /// _moveNow is the motion, its time, strength, share and mirroring now.
  (CharacterMove, double, double, double, bool) _moveNow(double dt) {
    final p = performance, t = _sceneTime;
    if (p == null || t == null) {
      // On the canvas, the frame's time; in the Studio, as it plays.
      final mt = _motionTime ?? (_moveClock += playing ? dt * _move.speed : 0);
      // Stopped: it stands in its stance.
      return (
        playing ? _move : _move.copyWith(motion: "Still"),
        mt,
        1,
        1,
        false
      );
    }
    var m = _move;
    final key = p.keyAt(t);
    final stance = key?.stance ?? p.stance;
    if (stance != null && stance != m.stance && moveStances.contains(stance)) {
      // A scene's stance places the hands and feet.
      m = m.copyWith(stance: stance, offsets: const {});
    }
    final lean = key?.lean ?? p.lean, tilt = key?.tilt ?? p.tilt;
    if (lean != 0) {
      m = m.withBody("lean", (m.bodyOf("lean") + lean).clamp(-1.0, 1.0));
    }
    if (tilt != 0) {
      m = m.withBody(
          "headTilt", (m.bodyOf("headTilt") + tilt).clamp(-1.0, 1.0));
    }
    if (p.clipAt(t) case (final c, final w)) {
      return (
        m.copyWith(motion: c.kind),
        (t - c.start) * c.speed,
        c.strength,
        w,
        c.mirror
      );
    }
    if (!p.breathe && m.motion == "Idle") m = m.copyWith(motion: "Still");
    return (m, t * m.speed, 1, 1, false);
  }

  /// shadowOn draws its ground shadow for a view that draws the scene itself
  /// (the Studio's), before the scene.
  void shadowOn(ui.Canvas canvas, ui.Rect box, PerspectiveCamera camera,
          {String kind = "Soft"}) =>
      _shadow(canvas, box, camera, kind);

  /// _shadow draws its ground shadow as [camera] sees it in [box], smaller as
  /// it leaves the ground.
  void _shadow(
      ui.Canvas canvas, ui.Rect box, PerspectiveCamera camera, String kind) {
    if (kind == "None") return;
    final hips = _avatar?.avatar.humanoid.worldPosition(VrmHumanBone.hips);
    if (hips == null) return;
    final rest = restAt(VrmHumanBone.hips)?.y ?? hips.y;
    final r = _height *
        0.16 /
        (1 + math.max(0.0, hips.y - rest) / math.max(0.1, _height) * 4);
    final f = (camera.target - camera.position)..normalize();
    final left = f.cross(vm.Vector3(0, 1, 0)).normalized();
    final up = left.cross(f).normalized();
    final k = 1 / math.tan(camera.fovRadiansY / 2),
        aspect = box.width / box.height;
    ui.Offset? seen(vm.Vector3 w) {
      final d = w - camera.position, z = d.dot(f);
      if (z < camera.fovNear) return null;
      return ui.Offset(
          box.center.dx - d.dot(left) / z * k / aspect * box.width / 2,
          box.center.dy - d.dot(up) / z * k * box.height / 2);
    }

    final at = [
      for (final (x, z) in const [
        (1.0, 0.0),
        (-1.0, 0.0),
        (0.0, 1.0),
        (0.0, -1.0)
      ])
        seen(vm.Vector3(hips.x + x * r, 0, hips.z + z * r * 0.8))
    ];
    if (at.any((o) => o == null)) return;
    final pts = at.cast<ui.Offset>();
    final oval = ui.Rect.fromLTRB(
        pts.map((o) => o.dx).reduce(math.min),
        pts.map((o) => o.dy).reduce(math.min),
        pts.map((o) => o.dx).reduce(math.max),
        pts.map((o) => o.dy).reduce(math.max));
    if (oval.width < 1) return;
    final soft = kind == "Soft";
    canvas
      ..save()
      ..clipRect(box)
      ..drawOval(
          soft ? oval.inflate(oval.width * 0.08) : oval,
          ui.Paint()
            ..color = ui.Color.fromARGB(soft ? 70 : 95, 0, 0, 0)
            ..maskFilter = soft
                ? ui.MaskFilter.blur(ui.BlurStyle.normal, oval.width * 0.09)
                : null)
      ..restore();
  }

  /// picture is a [width] by [height] PNG of it standing, for the library.
  Future<Uint8List?> picture(int width, int height) async {
    if (_avatar == null || _disposed) return null;
    final camera = PerspectiveCamera(
        fovRadiansY: 30 * vm.degrees2Radians, fovNear: 0.05, fovFar: 100);
    aim(camera, turn: 0.12, aspect: width / height);
    final rec = ui.PictureRecorder();
    final was = scene.maxGpuFramesInFlight;
    scene.maxGpuFramesInFlight = 0;
    try {
      scene.render(camera, ui.Canvas(rec),
          viewport: ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          pixelRatio: 1);
    } finally {
      scene.maxGpuFramesInFlight = was;
    }
    final image = await rec.endRecording().toImage(width, height);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png == null ? null : Uint8List.sublistView(png);
    } finally {
      image.dispose();
    }
  }

  /// settle lets hair and clothes fall still, for an export's first frame,
  /// which otherwise catches them swinging from how they were made.
  void settle() {
    aim(_canvasCamera);
    for (var i = 0; i < 45; i++) {
      tick(1 / 30, _canvasCamera, lookAt: _canvasCamera.position);
    }
  }

  // The face (character_face.dart).

  CharacterFace _face = const CharacterFace();
  String? _expression;

  // How it stands (character_move.dart), posed by vrm_pose.dart.
  CharacterMove _move = const CharacterMove();
  VrmPoser? _poser;

  /// playing is whether its motion plays (the Studio's Play and Stop); always
  /// on the canvas.
  bool playing = true;
  double _moveClock = 0;
  double? _motionTime;

  /// expression is a scene's chosen expression by name, worn in place of the
  /// face's own; null for its own.
  set expression(String? name) => _expression = name;

  SpokenLine? _line;
  double _lineAt = 0, _clock = 0;

  /// say has the mouth say [text], over the expression it wears.
  void say(String text) {
    _line = text.trim().isEmpty ? null : SpokenLine.of(text);
    _lineAt = _clock;
  }

  bool get saying => _line != null;

  FaceMix get _mixNow {
    final p = performance, t = _sceneTime;
    if (p == null || t == null) return _face.wearing(_expression);
    // A scene's feeling, part of the way to another.
    final feeling = p.keyAt(t)?.feeling ?? p.feeling;
    return FaceMix.lerp(
        _face.wearing(feeling), _face.wearing(p.mixTo), p.mixAmount);
  }

  SpokenLine? _spoken;
  String _spokenText = "";

  /// _mouthNow is the mouth's shapes as a line or scene has them; null for
  /// the face's own.
  Map<String, double>? _mouthNow() {
    final p = performance, t = _sceneTime;
    if (p == null || t == null) {
      final line = _line;
      if (line == null) return null;
      final mouth = line.mouthAt(_clock - _lineAt);
      if (mouth == null) {
        _line = null;
        _changed();
      }
      return mouth;
    }
    if (p.line.trim().isNotEmpty) {
      if (_spokenText != p.line) {
        _spokenText = p.line;
        _spoken = SpokenLine.of(p.line);
      }
      if (_spoken!.mouthAt(t - p.lineAt) case final m?) return m;
    }
    // Its lip sync, from a voice-over or a narrator's channel.
    if (p.mouthAt(t) case final m?) return visemesOf(m);
    return p.mouth == "rest" ? null : {"MTH_${p.mouth}": 0.85};
  }

  // The face now, eased toward what it is set to.
  Map<String, double> _unitsNow = const {};
  double _gazeX = 0, _gazeY = 0, _tiltNow = 0;
  bool _faceSettled = false;
  double _glanceX = 0, _glanceY = 0, _glanceNext = 0;
  final math.Random _random = math.Random(7);

  void _moveFace(double dt) {
    final mix = _mixNow;
    final want = Map<String, double>.of(mix.w);
    final line = _mouthNow();
    if (line != null) {
      // The line's shapes over the mouth's, the rest eased well off: only
      // halved, an open-mouthed face never shuts between words.
      for (final k in want.keys.toList()) {
        if (k.startsWith('MTH_')) want[k] = want[k]! * 0.15;
      }
      for (final e in line.entries) {
        want[e.key] = math.max(want[e.key] ?? 0, e.value);
      }
    }
    final glances = _face.glances && (performance?.glance ?? true);
    if (glances && _clock >= _glanceNext) {
      _glanceX = (_random.nextDouble() - 0.5) * 0.9;
      _glanceY = (_random.nextDouble() - 0.5) * 0.5;
      _glanceNext = _clock + 1.5 + _random.nextDouble() * 2.5;
    }
    if (!glances) _glanceX = _glanceY = 0;
    final k = !_faceSettled
        ? 1.0
        : line != null
            ? (1 - math.exp(-dt * 30))
            : (1 - math.exp(-dt * 10));
    _faceSettled = true;
    final next = <String, double>{};
    for (final key in {...want.keys, ..._unitsNow.keys}) {
      final v = (_unitsNow[key] ?? 0) +
          ((want[key] ?? 0) - (_unitsNow[key] ?? 0)) * k;
      if (v > 0.002) next[key] = v;
    }
    _unitsNow = next;
    _gazeX += (mix.gazeX + _glanceX - _gazeX) * k;
    _gazeY += (mix.gazeY + _glanceY - _gazeY) * k;
    _tiltNow += (mix.tilt - _tiltNow) * k;
  }

  double _blushed = 0;

  /// _creased is what the creases were last drawn from (ShapedAvatar.creases).
  String? _creased;

  /// _repaint paints what is painted on the character, and the blush.
  void _repaint() {
    final a = _avatar;
    if (a == null) return;
    final b = _mixNow.blush;
    _blushed = b;
    _creased = ShapedAvatar.creaseKey(_shape);
    a.paint([
      // The years' and the muscles' lines under whatever is painted.
      ...a.creases(_shape),
      ..._paint,
      if (b > 0.01)
        for (final (at, n, r) in a.blushAt)
          PaintStroke(
              on: "skin",
              colour: 0xf06a7a,
              radius: r,
              opacity: (b * 0.8).clamp(0.0, 1.0),
              softness: 1,
              points: [SculptPoint(at.x, at.y, at.z, n.x, n.y, n.z)]),
    ]);
  }

  /// dotsAt are the Move step's dots in the scene: hands, feet, hips, and
  /// over the head.
  Map<String, vm.Vector3> dotsAt() {
    final h = _avatar?.avatar.humanoid;
    if (h == null) return const {};
    vm.Vector3? at(VrmHumanBone b) => h.worldPosition(b);
    final head = at(VrmHumanBone.head), foot = at(VrmHumanBone.leftFoot);
    return {
      if (at(VrmHumanBone.leftHand) case final p?) "handL": p,
      if (at(VrmHumanBone.rightHand) case final p?) "handR": p,
      if (foot != null) "footL": foot,
      if (at(VrmHumanBone.rightFoot) case final p?) "footR": p,
      if (at(VrmHumanBone.hips) case final p?) "hips": p,
      if (head != null)
        "head": head +
            vm.Vector3(0, foot == null ? 0.3 : (head.y - foot.y) * 0.24, 0),
    };
  }

  /// toBody is scene point [world] in the body's own space, where a dragged
  /// dot's offset is kept.
  vm.Vector3? toBody(vm.Vector3 world) {
    final root = _avatar?.avatar.modelRoot;
    if (root == null) return null;
    return vm.Matrix4.inverted(root.globalTransform).transformed3(world);
  }

  /// restAt is where bone [b] is at rest, in the scene: what it is framed
  /// by, so the camera stays put as it jumps or crouches.
  vm.Vector3? restAt(VrmHumanBone b) =>
      identical(_poser?.avatar, _avatar) ? _poser?.restWorld(b) : null;

  /// pick is where a ray from [from] along [dir] first meets it.
  CharacterHit? pick(vm.Vector3 from, vm.Vector3 dir) =>
      _avatar?.pick(from, dir);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // Render targets, shadows and history are GPU memory the garbage
    // collector cannot see.
    scene.dispose();
    super.dispose();
  }
}
