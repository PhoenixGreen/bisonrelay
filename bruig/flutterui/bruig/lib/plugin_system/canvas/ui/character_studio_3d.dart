import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/character_decal.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_look.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/character3d_painter.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_character.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_gpu.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_scene.dart';
import 'package:bruig/plugin_system/canvas/storage/character_designs.dart';
import 'package:bruig/plugin_system/canvas/storage/vroid_assets.dart';
import 'package:bruig/plugin_system/canvas/ui/character_decal_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/character_look_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/character_outfit_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/character_shape_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:vector_math/vector_math.dart' as vm;

// character_studio_3d.dart is the new Character Studio, laid out as its
// approved prototype: a bar of steps along the top (Character base, Face,
// Move, Test), the parts down the left, the character on a page in the
// middle with the views over it, and the open part's settings on the right.
// It takes the whole page, in place of the canvas, as the old Studio does.
//
// The character is drawn in 3D with Flutter GPU, from one of the four VRoid
// bodies (vroid_assets.dart), shaped (vrm_shape.dart) and dressed
// (vrm_wear.dart). Only the first step is built so far.

/// The bodies, by the names the page gives them.
const Map<String, String> studioBodyNames = {
  "Vivi": "Vivi",
  "Victoria_Rubin": "Victoria",
  "Vita": "Vita",
  "HairSample_Male": "Kai",
};

/// StudioView is which way round the character is seen.
enum StudioView {
  front("Front", 0),
  angled("Angled", 0.6),
  side("Side", math.pi / 2),
  back("Back", math.pi),
  turntable("Turntable", 0);

  final String label;
  final double yaw;
  const StudioView(this.label, this.yaw);
}

/// CharacterStudio3D is the whole page.
class CharacterStudio3D extends StatefulWidget {
  /// onDone goes back to the canvas, with the character as it was kept --
  /// or null where there was nothing to keep.
  final void Function(CharacterDesign? kept) onDone;

  /// design is the character to change, or null to make a new one.
  final CharacterDesign? design;

  /// gpuReady stands in for whether this app can draw in 3D, for tests,
  /// which run without Flutter GPU; designs for the library's characters.
  final Future<bool>? gpuReady;
  final Future<List<CharacterDesign>> Function()? designs;
  const CharacterStudio3D(
      {required this.onDone,
      this.design,
      this.gpuReady,
      this.designs,
      super.key});

  @override
  State<CharacterStudio3D> createState() => _CharacterStudio3DState();
}

class _CharacterStudio3DState extends State<CharacterStudio3D> {
  bool? _gpu;
  bool? _have;
  double? _progress;
  String? _error;

  String _id = vroidBodies.first.id;
  CharacterShape _shape = const CharacterShape();
  CharacterOutfit _outfit = CharacterOutfit.asDesigned;
  String _lookName = characterLooks.keys.first;
  CharacterLook _look = characterLooks.values.first;
  List<CharacterDecal> _decals = const [];
  String? _openDecal;
  String _part = startPartId;
  StudioView? _view = StudioView.front;

  /// _own are the clothes the body on the stage comes with, once it is
  /// there.
  Set<WearSlot> _own = const {};

  @override
  void initState() {
    super.initState();
    if (widget.design case final d?) _take(d);
    _check();
  }

  Future<void> _check() async {
    final gpu = await (widget.gpuReady ?? flutterGpuReady());
    final have = gpu && (await VroidAssets.missing(vroidBodies)).isEmpty;
    if (mounted) {
      setState(() {
        _gpu = gpu;
        _have = have;
      });
    }
  }

  Future<void> _download() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await VroidAssets.install(vroidBodies, progress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (mounted) {
        setState(() {
          _have = true;
          _progress = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "$e";
          _progress = null;
        });
      }
    }
  }

  /// _name is the body's name, for its own clothes ("Vivi's").
  String get _name => studioBodyNames[_id] ?? _id;

  /// _designId is the saved character being changed, or null for a new
  /// one; _title is what it is called.
  String? _designId;
  final TextEditingController _title = TextEditingController();

  /// _stageKey is the stage, for a picture of the character to keep.
  final GlobalKey<_StageState> _stageKey = GlobalKey();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// _design is the character as it is now.
  CharacterDesign _design() => CharacterDesign(
        id: _designId ?? CharacterDesigns.newId(),
        name: _title.text.trim().isEmpty ? _name : _title.text.trim(),
        body: _id,
        shape: _shape,
        outfit: _outfit,
        lookName: _lookName,
        look: _look,
        decals: _decals,
        updated: DateTime.now(),
      );

  /// _untouched is whether a new character is still as a body was made,
  /// so there is nothing to keep.
  bool get _untouched =>
      _designId == null &&
      _title.text.trim().isEmpty &&
      _shape == const CharacterShape() &&
      _outfit == CharacterOutfit.asDesigned &&
      _look == characterLooks[_lookName] &&
      _lookName == characterLooks.keys.first &&
      _decals.isEmpty;

  /// _done keeps the character in the library, and goes back to the canvas.
  Future<void> _done() async {
    if (_untouched) {
      widget.onDone(null);
      return;
    }
    final d = _design();
    // Its picture, for the list in Assets, before it is listed there.
    final png = await _stageKey.currentState?._character.picture(168, 224);
    if (png != null) await CharacterDesigns.savePicture(d.id, png);
    await CharacterDesigns.save(d);
    widget.onDone(d);
  }

  /// _openDesign opens a saved character to change it, or with null starts a new
  /// one.
  void _openDesign(CharacterDesign? d) => setState(() => _take(d));

  void _take(CharacterDesign? d) {
    // A character with no id is one read from a canvas that could not be:
    // kept, it is a new one.
    _designId = d == null || d.id.isEmpty ? null : d.id;
    _title.text = d?.name ?? "";
    if (d != null) _id = d.body;
    _shape = d?.shape ?? const CharacterShape();
    _outfit = d?.outfit ?? CharacterOutfit.asDesigned;
    _lookName = d?.lookName ?? characterLooks.keys.first;
    _look = d?.look ?? characterLooks.values.first;
    _decals = d?.decals ?? const [];
    _openDecal = null;
    _own = const {};
  }

  ShapePart? get _open =>
      characterShapeParts.where((p) => p.id == _part).firstOrNull;

  /// _frame is what the camera looks at for the open part: the feet for
  /// shoes and socks, the whole body for the rest of the clothes.
  ShapeFrame get _frame =>
      _open?.frame ??
      switch (wearSlotOf(_part)) {
        WearSlot.shoes || WearSlot.legwear => ShapeFrame.feet,
        _ => ShapeFrame.body,
      };

  void _pick(String id) {
    final was = _frame;
    setState(() {
      _part = id;
      // The bum is seen from behind, and the front again after.
      if (_frame == ShapeFrame.bum && was != ShapeFrame.bum) {
        _view = StudioView.back;
      } else if (was == ShapeFrame.bum && _frame != ShapeFrame.bum) {
        _view = StudioView.front;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    final ready = _gpu == true && _have == true;
    return Material(
      color: colors.surface,
      child: Column(children: [
        _TopBar(
          name: _name,
          title: _title,
          onStartAgain: () => setState(() {
            _shape = const CharacterShape();
            _outfit = CharacterOutfit.asDesigned;
            _lookName = characterLooks.keys.first;
            _look = characterLooks.values.first;
            _decals = const [];
            _openDecal = null;
          }),
          onDone: _done,
        ),
        Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 220,
              color: colors.surfaceContainerLow,
              child: CharacterShapeList(
                  shape: _shape,
                  outfit: _outfit,
                  styled: _look != characterLooks[_lookName],
                  decorated: _decals.isNotEmpty,
                  selected: _part,
                  onSelect: _pick),
            ),
            Expanded(child: _stageArea(ready)),
            Container(
              width: 330,
              color: colors.surfaceContainerLow,
              child: _panel(),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _stageArea(bool ready) => switch ((_gpu, _have)) {
        (null, _) ||
        (true, null) =>
          const Center(child: CircularProgressIndicator()),
        (false, _) => const _Notice(
            key: ValueKey("characterBaseNoGpu"),
            title: "3D characters need Flutter GPU",
            body: "Flutter GPU is switched on for Bison Relay on macOS. On "
                "this system it is not available, so the new characters "
                "cannot be drawn here yet.",
          ),
        (true, false) => _Notice(
            key: const ValueKey("characterBaseDownload"),
            title: "Fetch the characters",
            body: "The new characters are built from four of pixiv's VRoid "
                "sample characters, which are free to use (CC0). They are "
                "fetched once from GitHub, about "
                "${(vroidBodiesBytes / 1e6).round()} MB, and kept in your "
                "library.",
            progress: _progress,
            error: _error,
            action: _progress == null
                ? StudioPill(
                    key: const ValueKey("characterBaseFetch"),
                    label: _error == null ? "Fetch them" : "Try again",
                    filled: true,
                    onTap: _download,
                  )
                : null,
          ),
        (true, true) => _Stage(
            key: _stageKey,
            id: _id,
            shape: _shape,
            outfit: _outfit,
            look: _look,
            decals: _decals,
            frame: _frame,
            view: _view,
            onView: (v) => setState(() => _view = v),
            onLoaded: (own) => setState(() => _own = own),
          ),
      };

  Widget _panel() {
    final part = _open;
    if (part != null) {
      return CharacterShapeControls(
          part: part,
          shape: _shape,
          onChanged: (s) => setState(() => _shape = s));
    }
    if (_part == decalsPartId) {
      return CharacterDecalControls(
          decals: _decals,
          open: _openDecal,
          outfit: _outfit,
          onChanged: (d, open) => setState(() {
                _decals = d;
                _openDecal = open;
              }));
    }
    if (_part == stylePartId) {
      return CharacterLookControls(
          look: _look,
          name: _lookName,
          onChanged: (l, n) => setState(() {
                _look = l;
                _lookName = n;
              }));
    }
    if (_part == startPartId) {
      return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const StudioPanelHead(
                title: "Start from",
                says:
                    "Pick who to start from. Hair, clothes, face and body all "
                    "change from here, and everything you change stays yours. "
                    "Done keeps the character in your library."),
            ValueListenableBuilder<int>(
              valueListenable: CharacterDesigns.changed,
              builder: (context, _, __) => FutureBuilder<List<CharacterDesign>>(
                future: (widget.designs ?? CharacterDesigns.list)(),
                builder: (context, snap) {
                  final all = snap.data ?? const <CharacterDesign>[];
                  if (all.isEmpty) return const SizedBox.shrink();
                  return StudioPills<String>(
                    key: const ValueKey("studioDesigns"),
                    id: "design",
                    label: "Your characters",
                    value: _designId ?? "new",
                    options: [
                      ("new", "Start a new one"),
                      for (final d in all)
                        (d.id, d.name.isEmpty ? "Unnamed" : d.name),
                    ],
                    onChanged: (id) =>
                        _openDesign(all.where((d) => d.id == id).firstOrNull),
                  );
                },
              ),
            ),
            StudioPills<String>(
              key: const ValueKey("studioBodies"),
              id: "body",
              label: "Body",
              value: _id,
              options: [
                for (final m in vroidBodies)
                  (m.id, studioBodyNames[m.id] ?? m.id)
              ],
              onChanged: (id) => setState(() {
                _id = id;
                _own = const {};
              }),
            ),
          ]);
    }
    return CharacterOutfitControls(
      part: _part,
      outfit: _outfit,
      bodyName: _name,
      own: _own,
      male: _id == "HairSample_Male",
      onChanged: (o) => setState(() => _outfit = o),
    );
  }
}

/// _TopBar is the character's name, the Studio's steps, and the ways out.
class _TopBar extends StatelessWidget {
  final String name;

  /// title is the character's own name, typed here; [name], the body's,
  /// until one is.
  final TextEditingController title;
  final VoidCallback onStartAgain, onDone;
  const _TopBar(
      {required this.name,
      required this.title,
      required this.onStartAgain,
      required this.onDone});

  static const _steps = ["Character base", "Face", "Move", "Test"];

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        SizedBox(
          width: 150,
          child: TextField(
            key: const ValueKey("studioName"),
            controller: title,
            decoration: InputDecoration.collapsed(
                hintText: name,
                hintStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurfaceVariant)),
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colors.onSurface),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (i, s) in _steps.indexed) ...[
                StudioPill(
                  key: ValueKey("studioStep-$i"),
                  label: "${i + 1}   $s",
                  selected: i == 0,
                  tooltip: i == 0 ? "" : "Comes after the Character base",
                  onTap: i == 0 ? () {} : null,
                ),
                const SizedBox(width: 6),
              ],
            ]),
          ),
        ),
        StudioPill(
          key: const ValueKey("studioStartAgain"),
          label: "Start again",
          tooltip: "Put the body and clothes back as they were made",
          onTap: onStartAgain,
        ),
        const SizedBox(width: 8),
        StudioPill(
          key: const ValueKey("studioDone"),
          label: "Done",
          filled: true,
          onTap: onDone,
        ),
      ]),
    );
  }
}

/// _Notice is a card in the middle of the stage saying what is needed.
class _Notice extends StatelessWidget {
  final String title, body;
  final double? progress;
  final String? error;
  final Widget? action;
  const _Notice(
      {required this.title,
      required this.body,
      this.progress,
      this.error,
      this.action,
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface)),
              const SizedBox(height: 8),
              Text(body,
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: colors.onSurfaceVariant)),
              if (progress != null) ...[
                const SizedBox(height: 14),
                LinearProgressIndicator(
                    key: const ValueKey("characterBaseProgress"),
                    value: progress),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!,
                    key: const ValueKey("characterBaseError"),
                    style: TextStyle(fontSize: 12, color: colors.error)),
              ],
              if (action != null) ...[const SizedBox(height: 14), action!],
            ]),
      ),
    );
  }
}

/// _Stage is the character in 3D on its page, the views over it, and a
/// drag to turn it.
class _Stage extends StatefulWidget {
  final String id;
  final CharacterShape shape;
  final CharacterOutfit outfit;
  final CharacterLook look;
  final List<CharacterDecal> decals;
  final ShapeFrame frame;
  final StudioView? view;
  final ValueChanged<StudioView?> onView;
  final ValueChanged<Set<WearSlot>> onLoaded;
  const _Stage(
      {required this.id,
      required this.shape,
      required this.outfit,
      required this.look,
      required this.decals,
      required this.frame,
      required this.view,
      required this.onView,
      required this.onLoaded,
      super.key});

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  /// _character is the character, drawn by vrm_character.dart; this is its
  /// camera, its framing, and the gestures that turn, tilt, move and zoom
  /// it.
  late final CharacterScene _character =
      CharacterScene(loadDecal: loadDecalPicture)..addListener(_changed);
  final PerspectiveCamera _camera = PerspectiveCamera(
      fovRadiansY: 30 * vm.degrees2Radians, fovNear: 0.05, fovFar: 100);
  double _yaw = 0;
  vm.Vector3? _focus;
  double _distance = 3, _pitch = 0.06;

  /// _tilt and _zoom are the viewer's own: a tilt up or down added to the
  /// view's, and how much nearer or further, by dragging up and down and by
  /// scrolling or pinching. A double-click, or another part, puts them back.
  double _tilt = 0, _zoom = 1;
  double _zoomAtStart = 1;

  /// _pan is how far the view is moved across and up, in the world, by a
  /// shift-drag, a right- or middle-button drag, or two fingers.
  final vm.Vector3 _pan = vm.Vector3.zero();
  bool _panning = false;

  /// _panBy moves the view by [delta] on screen: the character follows the
  /// pointer, as far as the view is from it.
  void _panBy(Offset delta) {
    final forward = (_camera.target - _camera.position).normalized();
    final right = forward.cross(vm.Vector3(0, 1, 0)).normalized();
    final up = right.cross(forward).normalized();
    final k = _distance * 0.0012;
    _pan.add((right * -delta.dx + up * delta.dy) * k);
  }

  void _resetView() => setState(() {
        _tilt = 0;
        _zoom = 1;
        _pan.setZero();
      });

  Set<WearSlot> _own = const {};

  void _changed() {
    if (!mounted) return;
    final own = _character.own;
    if (!setEquals(own, _own)) {
      _own = own;
      widget.onLoaded(own);
    }
    setState(() {});
  }

  void _show() => _character.show(
      body: widget.id,
      shape: widget.shape,
      outfit: widget.outfit,
      look: widget.look,
      decals: widget.decals);

  @override
  void initState() {
    super.initState();
    _show();
  }

  @override
  void didUpdateWidget(_Stage old) {
    super.didUpdateWidget(old);
    if (widget.frame != old.frame) {
      _tilt = 0;
      _zoom = 1;
      _pan.setZero();
    }
    _show();
  }

  @override
  void dispose() {
    _character.removeListener(_changed);
    _character.dispose();
    super.dispose();
  }

  /// _framing is where the camera looks and from how far, for the open
  /// part.
  (vm.Vector3, double, double) _framing(ShapedAvatar? a) {
    vm.Vector3? at(VrmHumanBone b) => a?.avatar.humanoid.worldPosition(b);
    final head = at(VrmHumanBone.head) ?? vm.Vector3(0, 1.4, 0);
    final tall = head.y;
    switch (widget.frame) {
      case ShapeFrame.head:
        // The face: from the head bone up to the eyes, as far up as the
        // head is now drawn.
        final rig = a?.rig,
            face = rig?.face,
            bone = rig?.data.bindPos['J_Bip_C_Head'];
        final p = rig?.proportions(widget.shape);
        final grow = (p?.bones['J_Bip_C_Head']?.scale ?? 1) * (p?.height ?? 1);
        final up =
            face != null && bone != null ? (face.eyeY - bone.y) * grow : 0.06;
        final size = (face?.es ?? 0.09) * grow;
        return (head + vm.Vector3(0, up * 0.75, 0), size * 9, 0.04);
      case ShapeFrame.torso:
        return (
          at(VrmHumanBone.upperChest) ?? at(VrmHumanBone.chest) ?? head * 0.75,
          tall * 0.75,
          0.05
        );
      case ShapeFrame.bum:
        return (
          (at(VrmHumanBone.hips) ?? head * 0.55) -
              vm.Vector3(0, 0.04 * tall, 0),
          tall * 0.75,
          0.05
        );
      case ShapeFrame.feet:
        final foot = at(VrmHumanBone.leftFoot)?.y ?? 0.08;
        return (vm.Vector3(0, foot + 0.04 * tall, 0), tall * 0.7, 0.3);
      case ShapeFrame.body:
        return (vm.Vector3(0, tall * 0.55, 0), tall * 2.3, 0.06);
    }
  }

  void _tick(Duration elapsed, double dt) {
    final (focus, distance, pitch) = _framing(_character.avatar);
    final k = (dt * 7).clamp(0.0, 1.0);
    final f = _focus ??= focus.clone();
    f.add((focus - f) * k);
    _distance += (distance * _zoom - _distance) * k;
    _pitch += ((pitch + _tilt).clamp(-0.9, 1.3) - _pitch) * k;
    switch (widget.view) {
      case StudioView.turntable:
        _yaw += dt * 0.6;
      case final StudioView v:
        // The shortest way round to the view's side.
        var d = (v.yaw - _yaw) % (2 * math.pi);
        if (d > math.pi) d -= 2 * math.pi;
        _yaw += d * k;
      case null:
    }
    final at = f + _pan;
    final eye = at +
        vm.Vector3(math.sin(_yaw) * math.cos(_pitch), math.sin(_pitch),
                -math.cos(_yaw) * math.cos(_pitch)) *
            _distance;
    _camera
      ..position = eye
      ..target = at;
    _character.tick(dt, _camera,
        lookAt: eye, pixelRatio: MediaQuery.devicePixelRatioOf(context));
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Stack(children: [
      Positioned.fill(
        child: Listener(
          // A drag with shift held moves the view rather than turning it;
          // so does one with the right or middle button, which the gesture
          // below never sees.
          onPointerDown: (e) =>
              _panning = HardwareKeyboard.instance.isShiftPressed,
          onPointerMove: (e) {
            if (e.buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0) {
              _panBy(e.delta);
            }
          },
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              _zoom =
                  (_zoom * math.exp(e.scrollDelta.dy * 0.002)).clamp(0.25, 3.0);
            }
          },
          child: GestureDetector(
            key: const ValueKey("studioStageGestures"),
            onDoubleTap: _resetView,
            onScaleStart: (_) => _zoomAtStart = _zoom,
            onScaleUpdate: (d) {
              if (d.pointerCount > 1) {
                // Two fingers: pinched to zoom, slid to move the view.
                _zoom = (_zoomAtStart / d.scale).clamp(0.25, 3.0);
                _panBy(d.focalPointDelta);
                return;
              }
              if (_panning) {
                _panBy(d.focalPointDelta);
                return;
              }
              if (d.focalPointDelta.dx != 0 && widget.view != null) {
                widget.onView(null);
              }
              _yaw -= d.focalPointDelta.dx * 0.01;
              _tilt = (_tilt + d.focalPointDelta.dy * 0.006).clamp(-0.9, 1.2);
            },
            child: ColoredBox(
              color: Color(0xff000000 | widget.look.paperColour),
              child:
                  SceneView(_character.scene, camera: _camera, onTick: _tick),
            ),
          ),
        ),
      ),
      if (_character.error case final e?)
        Center(child: Text(e, style: TextStyle(color: colors.error))),
      if (_character.avatar == null && _character.error == null)
        const Center(child: CircularProgressIndicator()),
      if (_character.fetching != null)
        Positioned(
          left: 0,
          right: 0,
          bottom: 52,
          child: Center(
            child: Container(
              key: const ValueKey("studioHairFetching"),
              width: 260,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text("Fetching ${_character.fetching}, once",
                    style: TextStyle(fontSize: 12, color: colors.onSurface)),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: _character.fetched),
              ]),
            ),
          ),
        ),
      Positioned(
        top: 12,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final v in StudioView.values) ...[
                StudioPill(
                  key: ValueKey("studioView-${v.name}"),
                  label: v.label,
                  selected: widget.view == v,
                  onTap: () => widget.onView(v),
                ),
                if (v != StudioView.values.last) const SizedBox(width: 4),
              ],
            ]),
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 12,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
                "Drag to turn and tilt it; shift-drag to move it; scroll to zoom; double-click to reset",
                style: TextStyle(fontSize: 12, color: colors.onSurface)),
          ),
        ),
      ),
    ]);
  }
}
