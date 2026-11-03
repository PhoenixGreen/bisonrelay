import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_decal.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_face.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_look.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_move.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_sculpt.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
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

// vrm_character.dart is one new 3D character in a scene of its own, as the
// Character Studio and the canvas both draw it: the VRoid body shaped, the
// hair worn from other characters on its head, its clothes and decals, its
// colours, and its look with the finish over it. What is drawn is changed
// with [CharacterScene.show]; each frame is moved on with [tick] and drawn
// by whoever holds the scene -- a SceneView, or the canvas's painter.

/// DecalLoader reads a decal's picture: RGBA, its width and height.
typedef DecalLoader = Future<(Uint8List, int, int)?> Function(String source);

/// CharacterScene is one character, drawn in its own scene.
class CharacterScene extends ChangeNotifier {
  final Scene scene = Scene();

  /// paper is whether the look's paper is drawn behind the character: in
  /// the Studio, not on a canvas.
  final bool paper;
  final DecalLoader loadDecal;

  CharacterScene({required this.loadDecal, this.paper = true}) {
    // Every frame drawn, rather than the last held while the GPU catches
    // up: an export draws each once, and must have it.
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

  /// avatar is the body drawn, once loaded.
  ShapedAvatar? get avatar => _avatar;

  /// error is why it could not be drawn, if it could not.
  String? error;

  /// fetching names hair being fetched for the first time, and fetched how
  /// far, from nought to one.
  String? fetching;
  double? fetched;

  /// own are the clothes the body comes with, once it is here.
  Set<WearSlot> get own => {
        for (final s in WearSlot.values)
          if (_avatar?.wardrobe?.hasOwn(s) ?? false) s,
      };

  /// showDesign draws [d].
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

  /// show draws this: what changed is changed, the rest left as it is.
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

  /// _restyle draws everything in the look.
  void _restyle() {
    if (!_finishTried) return;
    _finish?.look = _look;
    scene.directionalLight = DirectionalLight(direction: lightDirection(_look));
    for (final a in [_avatar, ..._donors.values]) {
      a?.applyLook(_look, finished: _finish != null);
    }
  }

  // The hair: the body's own, or pieces of other characters' -- each kept
  // here whole, all but its hair hidden, and worn on the body's head.
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

  /// _hair shows each piece of hair from where it is to come, fetching and
  /// loading the characters it comes from that are not here yet.
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
      next.decorate(_decals, loadDecal);
      _blushed = -1;
      _repaint();
      _changed();
      await _dress();
    } catch (e) {
      error = "This character could not be drawn: $e";
      _changed();
    }
  }

  /// _dress puts the outfit on, and says so if it could not be.
  Future<void> _dress() async {
    final a = _avatar;
    if (a == null) return;
    await a.dress(_outfit);
    if (a.dressError != null) {
      error = "The clothes could not be made: ${a.dressError}";
      _changed();
    }
  }

  /// ready is when everything asked for is here: the body, its clothes
  /// and decals, and the hair from others. For drawing it once, as an
  /// export does, rather than as it arrives.
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
          _finishTried &&
          !a.busy &&
          want.every(_donors.containsKey) &&
          _donorsLoading.isEmpty) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  /// tick moves the character on by [dt] seconds, seen by [camera], with
  /// its eyes on [lookAt].
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
      // Where the face's eyes are set to look, as the viewer sees it.
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
    v.autoBlink.enabled = _face.blinks && !_noBlink;
    if (!v.autoBlink.enabled) v.expressions.setValue('blink', 0);
    // Stood as its Move settings say, rather than in the T it was made in;
    // the face's tilt of the head over the stance's.
    if (!identical(_poser?.avatar, a)) _poser = VrmPoser(a);
    // The motion's time: on the canvas, the frame's; in the Studio, as it
    // plays.
    final mt =
        _motionTime ?? (_moveClock += _move.playing ? dt * _move.speed : 0);
    _poser!.pose(_move, dt, t: mt);
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
    if ((_mixNow.blush - _blushed).abs() > 0.02) {
      _blushed = _mixNow.blush;
      _repaint();
    }
    // The colours picked, and the years' grey; hair from others takes the
    // colour of the hair it is mixed with, unless one is picked.
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
    // Hair from others, on this head, grown or shrunk to its size.
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

  // ---------------------------------------------------------------------
  // On the canvas.

  /// _canvasCamera sees the character as the canvas draws it; _frame is the
  /// canvas's frame it was last moved on to.
  final PerspectiveCamera _canvasCamera = PerspectiveCamera(
      fovRadiansY: 30 * vm.degrees2Radians, fovNear: 0.05, fovFar: 100);
  int? _frame;

  /// aim points [camera] at the character, showing as much of it as
  /// [framing] says in a picture [aspect] times as wide as it is high: from
  /// [turn] half turns round, [tilt] quarter turns up, [zoom] times closer.
  void aim(PerspectiveCamera camera,
      {Character3dFraming framing = Character3dFraming.body,
      double turn = 0,
      double tilt = 0,
      double zoom = 1,
      double aspect = 0.5}) {
    final h = _avatar?.avatar.humanoid;
    vm.Vector3? at(VrmHumanBone b) => restAt(b) ?? h?.worldPosition(b);
    final head = at(VrmHumanBone.head) ?? vm.Vector3(0, 1.4, 0);
    // The top of the hair, over the head bone by about three times the
    // neck's length.
    final top =
        head.y + (head.y - (at(VrmHumanBone.neck)?.y ?? head.y * 0.94)) * 3;
    final (vm.Vector3 focus, double high, double wide) = switch (framing) {
      Character3dFraming.body => (
          vm.Vector3(head.x, top / 2, head.z),
          top * 1.1,
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
      Character3dFraming.head => () {
          final neck = at(VrmHumanBone.neck)?.y ?? head.y - 0.08;
          final span = (top - neck) * 1.75;
          return (
            vm.Vector3(head.x, (neck + top) / 2, head.z),
            span,
            span * 0.9
          );
        }(),
    };
    // Far enough off for the taller of the two to fit.
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

  /// paint draws the character into [box] on [canvas] at [frame] of a
  /// canvas playing [frameRate] frames a second, seen as [aim] says, with
  /// [pixelRatio] pixels to each of the canvas's points. It is moved on
  /// once a frame, however often the frame is drawn: the stage and an
  /// export both draw one more than once.
  void paint(ui.Canvas canvas, ui.Rect box,
      {required int frame,
      int frameRate = 12,
      Character3dFraming framing = Character3dFraming.body,
      double turn = 0,
      double tilt = 0,
      double zoom = 1,
      double pixelRatio = 1}) {
    if (box.width < 1 || box.height < 1) return;
    final camera = _canvasCamera;
    aim(camera,
        framing: framing,
        turn: turn,
        tilt: tilt,
        zoom: zoom,
        aspect: box.width / box.height);
    final last = _frame;
    final dt = last == null || frame <= last
        ? 0.0
        : ((frame - last) / math.max(1, frameRate)).clamp(0.0, 0.25);
    _frame = frame;
    // The motion where the frame has it, so an export plays it the same
    // every time.
    _motionTime = frame / math.max(1, frameRate) * _move.speed;
    tick(dt, camera, lookAt: camera.position, pixelRatio: pixelRatio);
    scene.update(dt);
    scene.render(camera, canvas, viewport: box, pixelRatio: pixelRatio);
  }

  /// picture is the character standing, [width] by [height] pixels, as a
  /// PNG: for the library's list of characters. Null before it is drawn.
  Future<Uint8List?> picture(int width, int height) async {
    if (_avatar == null) return null;
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

  /// settle lets the hair and clothes fall still, as they would by the time
  /// anybody looks: for the first frame of an export, which otherwise
  /// catches them swinging from how they were made.
  void settle() {
    aim(_canvasCamera);
    for (var i = 0; i < 45; i++) {
      tick(1 / 30, _canvasCamera, lookAt: _canvasCamera.position);
    }
  }

  // ---------------------------------------------------------------------
  // The face (character_face.dart).

  CharacterFace _face = const CharacterFace();
  String? _expression;

  // How it stands (character_move.dart), posed by vrm_pose.dart.
  CharacterMove _move = const CharacterMove();
  VrmPoser? _poser;
  double _moveClock = 0;
  double? _motionTime;

  /// expression is the expression worn, by name, in place of the face's
  /// own: a scene's choice for a character on the canvas. Null for its own.
  set expression(String? name) => _expression = name;

  /// noBlink stops the face blinking by itself, whatever it is set to: for
  /// a picture of it.
  set noBlink(bool v) => _noBlink = v;
  bool _noBlink = false;

  SpokenLine? _line;
  double _lineAt = 0, _clock = 0;

  /// say has the mouth say [text], over the expression it wears.
  void say(String text) {
    _line = text.trim().isEmpty ? null : SpokenLine.of(text);
    _lineAt = _clock;
  }

  /// saying is whether a line is being said.
  bool get saying => _line != null;

  FaceMix get _mixNow => _face.wearing(_expression);

  // The face as it is now, eased toward what it is set to.
  Map<String, double> _unitsNow = const {};
  double _gazeX = 0, _gazeY = 0, _tiltNow = 0;
  bool _faceSettled = false;
  double _glanceX = 0, _glanceY = 0, _glanceNext = 0;
  final math.Random _random = math.Random(7);

  void _moveFace(double dt) {
    final mix = _mixNow;
    final want = Map<String, double>.of(mix.w);
    final line = _line;
    if (line != null) {
      final mouth = line.mouthAt(_clock - _lineAt);
      if (mouth == null) {
        _line = null;
        _changed();
      } else {
        // The line's shapes over the mouth's, the rest of it eased off.
        for (final k in want.keys.toList()) {
          if (k.startsWith('MTH_')) want[k] = want[k]! * 0.5;
        }
        for (final e in mouth.entries) {
          want[e.key] = math.max(want[e.key] ?? 0, e.value);
        }
      }
    }
    if (_face.glances && _clock >= _glanceNext) {
      _glanceX = (_random.nextDouble() - 0.5) * 0.9;
      _glanceY = (_random.nextDouble() - 0.5) * 0.5;
      _glanceNext = _clock + 1.5 + _random.nextDouble() * 2.5;
    }
    if (!_face.glances) _glanceX = _glanceY = 0;
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

  /// _repaint paints what is painted on the character, and the blush.
  void _repaint() {
    final a = _avatar;
    if (a == null) return;
    final b = _mixNow.blush;
    _blushed = b;
    a.paint([
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

  /// restAt is where bone [b] is with the body at rest, in the scene: what
  /// it is framed by, so the camera stays put as it jumps or crouches.
  vm.Vector3? restAt(VrmHumanBone b) =>
      identical(_poser?.avatar, _avatar) ? _poser?.restWorld(b) : null;

  /// pick is where a ray from [from] going [dir] first meets the
  /// character: see ShapedAvatar.pick.
  CharacterHit? pick(vm.Vector3 from, vm.Vector3 dir) =>
      _avatar?.pick(from, dir);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
