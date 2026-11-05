import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast3d.dart';

import 'package:bruig/plugin_system/canvas/model/elements/character_decal.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_face.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_look.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_move.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_performance.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_sculpt.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/character3d_painter.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_character.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_gpu.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_scene.dart';
import 'package:bruig/plugin_system/canvas/storage/character_designs.dart';
import 'package:bruig/plugin_system/canvas/storage/vroid_assets.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/character_decal_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/character_face_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/character_look_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/character_move_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/character_outfit_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/character_shape_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/character_touchup_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character3d_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_vrm/flutter_vrm.dart';
import 'package:vector_math/vector_math.dart' as vm;

// character_studio_3d.dart is the Character Studio: a bar of steps along the
// top (Character base, Face, Move, Test), the parts down the left, the
// character on a page in the middle with the views over it, and the open
// part's settings on the right. It takes the whole page, in place of the
// canvas.
//
// The character is drawn in 3D with Flutter GPU, from one of the VRoid
// bodies (vroid_assets.dart), shaped (vrm_shape.dart) and dressed
// (vrm_wear.dart). The Test step tries it in a scene, with the settings a
// 3D character has on the canvas (character3d_settings.dart) and a timeline
// to play them on.

/// studioBodyNames is the bodies, by the names the page gives them.
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
  /// onDone goes back to the canvas with the character as it was kept (null
  /// where there was nothing to keep) and what the Test step left
  /// [performance] as, where it was changed.
  final void Function(CharacterDesign? kept, CharacterPerformance? performance)
      onDone;

  /// design is the character to change, or null to make a new one.
  final CharacterDesign? design;

  /// performance is what the character the Studio was opened for does in
  /// its scene, for the Test step to try and change; null where it was
  /// opened for none, and the Test step's changes are not kept.
  final CharacterPerformance? performance;

  /// gpuReady stands in for whether this app can draw in 3D, and designs for
  /// the library's characters, for tests, which run without Flutter GPU.
  final Future<bool>? gpuReady;
  final Future<List<CharacterDesign>> Function()? designs;
  const CharacterStudio3D(
      {required this.onDone,
      this.design,
      this.performance,
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
  List<SculptStroke> _sculpt = const [];
  List<PaintStroke> _paint = const [];
  TouchBrush _brush = const TouchBrush();
  String _part = startPartId;

  /// _step is the step open: the Character base, the Face, Move or Test.
  int _step = 0;
  CharacterMove _move = const CharacterMove();
  String _movePart = moveParts.first.$1;

  /// _playing is whether the motion plays on the stage: the top bar's
  /// Play and Stop. Not kept with the character.
  bool _playing = true;
  CharacterFace _face = const CharacterFace();
  String _facePart = faceParts.first.$1;

  /// _line is the line last said, and how many have been, so saying the
  /// same again says it again.
  ({String text, int n})? _line;
  StudioView? _view = StudioView.front;

  /// _own are the clothes the body on the stage comes with, once it is
  /// there.
  Set<WearSlot> _own = const {};

  @override
  void initState() {
    super.initState();
    if (widget.design case final d?) _take(d);
    _testAt.addListener(_testAtChanged);
    _test.addListener(_testFrameChanged);
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

  // The Test step: what it does in the scene tried, and when.

  /// _perf is what it does in the scene being tried. _test holds the
  /// playhead, as a canvas would, for the settings; _testAt is the time,
  /// in seconds, as the stage plays it.
  late CharacterPerformance _perf =
      widget.performance ?? const CharacterPerformance();
  static const int _testFps = 24;
  final CanvasController _test = CanvasController(
      CanvasDocument(frames: _testFps * 600, frameRate: _testFps));
  final ValueNotifier<double> _testAt = ValueNotifier(0);
  bool _testPlaying = false;

  /// _testLength is how long the timeline is: ten seconds, or as long as
  /// what is on it and a second more.
  double get _testLength => [
        10.0,
        for (final c in _perf.clips) c.end + 1,
        for (final k in _perf.keys) k.t + 1,
        if (_perf.line.trim().isNotEmpty)
          _perf.lineAt +
              SpokenLine.of(_perf.line).total / SpokenLine.beatsPerSecond +
              1,
      ].reduce(math.max);

  /// _tried is the character in the scene being tried, as the canvas would
  /// have it: what the settings show and change.
  Character3dElement _tried() => Character3dElement(
      const ElementBase(id: "studioTest", width: 200, height: 400),
      design: _design(),
      performance: _perf);

  void _playTest() => setState(() {
        if (!_testPlaying && _testAt.value >= _testLength - 1e-3) {
          _testAt.value = 0;
        }
        _testPlaying = !_testPlaying;
      });

  // The playhead, kept in step both ways: as the stage plays it, and as
  // the settings move it.
  void _testAtChanged() {
    final f = (_testAt.value * _testFps).round();
    if (_test.frame != f) _test.frame = f;
  }

  void _testFrameChanged() {
    if ((_testAt.value * _testFps).round() != _test.frame) {
      _testAt.value = _test.frame / _testFps;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _testAt
      ..removeListener(_testAtChanged)
      ..dispose();
    _test
      ..removeListener(_testFrameChanged)
      ..dispose();
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
        sculpt: _sculpt,
        paint: _paint,
        face: _face,
        move: _move,
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
      _decals.isEmpty &&
      _sculpt.isEmpty &&
      _paint.isEmpty &&
      _face == const CharacterFace() &&
      _move == const CharacterMove();

  /// _done keeps the character in the library, and goes back to the canvas.
  Future<void> _done() async {
    // The scene's settings, kept where they were changed for a character on
    // the canvas.
    final perf = widget.performance != null && _perf != widget.performance
        ? _perf
        : null;
    if (_untouched) {
      widget.onDone(null, perf);
      return;
    }
    final d = _design();
    // Its picture, for the list in Assets, before it is listed there.
    final png = await _stageKey.currentState?._character.picture(168, 224);
    if (png != null) await CharacterDesigns.savePicture(d.id, png);
    await CharacterDesigns.save(d);
    widget.onDone(d, perf);
  }

  /// _openDesign opens a saved character to change it, or with null starts a
  /// new one.
  void _openDesign(CharacterDesign? d) => setState(() => _take(d));

  void _take(CharacterDesign? d) {
    // A character with no id (read from a canvas that could not give it one)
    // or an id that cannot name its files (a received canvas's, say) is kept
    // as a new one.
    _designId = d == null || !CharacterDesigns.isId(d.id) ? null : d.id;
    _title.text = d?.name ?? "";
    if (d != null) _id = d.body;
    _shape = d?.shape ?? const CharacterShape();
    _outfit = d?.outfit ?? CharacterOutfit.asDesigned;
    _lookName = d?.lookName ?? characterLooks.keys.first;
    _look = d?.look ?? characterLooks.values.first;
    _decals = d?.decals ?? const [];
    _openDecal = null;
    _sculpt = d?.sculpt ?? const [];
    _paint = d?.paint ?? const [];
    _face = d?.face ?? const CharacterFace();
    _move = d?.move ?? const CharacterMove();
    _own = const {};
  }

  /// _resetPart puts part [id] of the Character base back as the body was
  /// made: its mark in the list, clicked.
  void _resetPart(String id) => setState(() {
        final part = characterShapeParts.where((p) => p.id == id).firstOrNull;
        final slot = wearSlotOf(id);
        if (part != null) {
          _shape = _shape.reset(part);
        } else if (slot != null) {
          _outfit = _outfit.wear(slot, CharacterOutfit.defaults[slot]!);
        } else {
          switch (id) {
            case stylePartId:
              _look = characterLooks[_lookName] ?? _look;
            case outfitPartId:
              _outfit = CharacterOutfit.asDesigned;
            case decalsPartId:
              _decals = const [];
              _openDecal = null;
            case touchUpPartId:
              _sculpt = const [];
              _paint = const [];
          }
        }
      });

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
          step: _step,
          onStep: (i) => setState(() {
            _step = i;
            _testPlaying = false;
          }),
          playing: _step == 3 ? _testPlaying : _playing,
          onPlay: _step == 3
              ? _playTest
              : () => setState(() => _playing = !_playing),
          onDone: _done,
        ),
        Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 220,
              color: colors.surfaceContainerLow,
              child: _step == 3
                  ? _TestNotes(kept: widget.performance != null)
                  : _step == 2
                      ? CharacterMoveList(
                          move: _move,
                          selected: _movePart,
                          onSelect: (id) => setState(() => _movePart = id),
                          onReset: (m) => setState(() => _move = m))
                      : _step == 1
                          ? CharacterFaceList(
                              face: _face,
                              selected: _facePart,
                              onSelect: (id) => setState(() => _facePart = id),
                              onReset: (f) => setState(() => _face = f))
                          : CharacterShapeList(
                              shape: _shape,
                              outfit: _outfit,
                              styled: _look != characterLooks[_lookName],
                              decorated: _decals.isNotEmpty,
                              touched: _sculpt.isNotEmpty || _paint.isNotEmpty,
                              selected: _part,
                              onSelect: _pick,
                              onReset: _resetPart),
            ),
            Expanded(
                child: _step == 3
                    ? Column(children: [
                        Expanded(child: _stageArea(ready)),
                        _TestTimeline(
                          at: _testAt,
                          length: _testLength,
                          performance: _perf,
                          onSeek: (t) => _testAt.value = t,
                        ),
                      ])
                    : _stageArea(ready)),
            Container(
              width: 330,
              color: colors.surfaceContainerLow,
              child: _step == 3
                  ? ListenableBuilder(
                      listenable: _test,
                      builder: (context, _) => ListView(
                          key: const ValueKey("studioTestSettings"),
                          padding: const EdgeInsets.only(bottom: 24),
                          children: character3dSettings(
                              context,
                              _test,
                              _tried(),
                              (e) => setState(() => _perf =
                                  (e as Character3dElement).performance),
                              () {},
                              () {},
                              inStudio: true)))
                  : _step == 2
                      ? CharacterMoveControls(
                          part: _movePart,
                          move: _move,
                          onChanged: (m) => setState(() => _move = m))
                      : _step == 1
                          ? CharacterFaceControls(
                              key: ValueKey("faceControls-$_facePart"),
                              part: _facePart,
                              face: _face,
                              onChanged: (f) => setState(() => _face = f),
                              onSay: (text) => setState(() =>
                                  _line = (text: text, n: (_line?.n ?? 0) + 1)))
                          : _panel(),
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
            outfit: _step == 3 ? _tried().worn.outfit : _outfit,
            look: _look,
            decals: _decals,
            sculpt: _sculpt,
            paint: _paint,
            face: _face,
            move: _move,
            playing: _playing,
            performance: _step == 3 ? _perf : null,
            clock: _step == 3 ? _testAt : null,
            clockRuns: _step == 3 && _testPlaying,
            clockEnd: _testLength,
            onClockEnd: () => setState(() => _testPlaying = false),
            onMove: _step == 2 ? (m) => setState(() => _move = m) : null,
            line: _line,
            brush: _step == 0 && _part == touchUpPartId ? _brush : null,
            onSculpt: (s) => setState(() => _sculpt = s),
            onPaint: (s) => setState(() => _paint = s),
            frame: switch (_step) {
              1 => ShapeFrame.head,
              2 => _movePart == "feet" ? ShapeFrame.feet : ShapeFrame.body,
              3 => ShapeFrame.body,
              _ => _frame,
            },
            view: _view,
            onView: (v) => setState(() => _view = v),
            onLoaded: (own) => setState(() => _own = own),
          ),
      };

  /// _designsAt is the saved characters as listed at a revision of them:
  /// the panel is built again at every change in the Studio, and every
  /// design was read from disk each time.
  (int, Future<List<CharacterDesign>>)? _listed;

  Future<List<CharacterDesign>> _designsAt(int revision) {
    if (widget.designs case var read?) return read();
    if (_listed case (var at, var f) when at == revision) return f;
    var f = CharacterDesigns.list();
    _listed = (revision, f);
    return f;
  }

  Widget _panel() {
    final part = _open;
    if (part != null) {
      return CharacterShapeControls(
          part: part,
          shape: _shape,
          onChanged: (s) => setState(() => _shape = s));
    }
    if (_part == touchUpPartId) {
      return CharacterTouchUpControls(
          brush: _brush,
          strokes: _sculpt,
          paint: _paint,
          onPaint: (s) => setState(() => _paint = s),
          onBrush: (b) => setState(() => _brush = b),
          onStrokes: (s) => setState(() => _sculpt = s));
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
              builder: (context, revision, __) =>
                  FutureBuilder<List<CharacterDesign>>(
                future: _designsAt(revision),
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
            // The ready-made cast: started from, each is a new character.
            StudioPills<String>(
              key: const ValueKey("studioCast"),
              id: "cast",
              label: "Ready-made",
              value: "",
              options: [
                for (final m in readyMadeCast) (m.design.name, m.design.name)
              ],
              onChanged: (name) => _openDesign(readyMadeCast
                  .firstWhere((m) => m.design.name == name)
                  .design),
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

  /// step is the step open, and onStep opens another.
  final int step;
  final ValueChanged<int> onStep;

  /// playing is whether the motion plays, and onPlay plays or stops it:
  /// here, for every step.
  final bool playing;
  final VoidCallback onPlay;
  const _TopBar(
      {required this.name,
      required this.title,
      required this.step,
      required this.onStep,
      required this.playing,
      required this.onPlay,
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
                  selected: i == step,
                  onTap: () => onStep(i),
                ),
                const SizedBox(width: 6),
              ],
            ]),
          ),
        ),
        StudioPill(
          key: const ValueKey("studioPlay"),
          label: playing ? "Stop" : "Play",
          tooltip: step == 3
              ? (playing ? "Stop the scene" : "Play the scene")
              : playing
                  ? "Stop the motion: it stands in its stance"
                  : "Play the motion",
          onTap: onPlay,
        ),
        const SizedBox(width: 8),
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
  final List<SculptStroke> sculpt;

  /// brush is the brush a drag on the stage shapes the body with, while
  /// Touch up is open; onSculpt and onPaint are given the strokes as one
  /// is drawn.
  final TouchBrush? brush;
  final List<PaintStroke> paint;
  final ValueChanged<List<SculptStroke>> onSculpt;
  final ValueChanged<List<PaintStroke>> onPaint;

  /// face is the face's expression; line the line it was last asked to say.
  final CharacterFace face;
  final ({String text, int n})? line;

  /// move is how it stands; with [onMove], its dots are on the stage to drag
  /// (the hands, feet and hips moved, the head turned). [playing] is whether
  /// its motion plays.
  final CharacterMove move;
  final bool playing;
  final ValueChanged<CharacterMove>? onMove;

  /// performance is what it does in a scene, played to [clock]'s time in
  /// seconds (the Test step's), which runs on while [clockRuns] until
  /// [clockEnd], then calls [onClockEnd]. Null for as designed.
  final CharacterPerformance? performance;
  final ValueNotifier<double>? clock;
  final bool clockRuns;
  final double clockEnd;
  final VoidCallback? onClockEnd;
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
      this.sculpt = const [],
      this.brush,
      this.paint = const [],
      required this.onSculpt,
      required this.onPaint,
      this.face = const CharacterFace(),
      this.move = const CharacterMove(),
      this.playing = true,
      this.onMove,
      this.performance,
      this.clock,
      this.clockRuns = false,
      this.clockEnd = 10,
      this.onClockEnd,
      this.line,
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
    // forward × up is the screen's left in flutter_scene's view: see _view.
    // The view moves the other way to the pointer, so the character follows.
    final left = forward.cross(vm.Vector3(0, 1, 0)).normalized();
    final up = left.cross(forward).normalized();
    final k = _distance * 0.0012;
    _pan.add((left * delta.dx + up * delta.dy) * k);
  }

  // ---------------------------------------------------------------------
  // Touch up: a drag shapes the body under the pointer.

  /// _before is the strokes from before the one being drawn, [_stroke];
  /// _paintBefore and [_painted] the same for paint strokes.
  List<SculptStroke>? _before;
  SculptStroke? _stroke;
  List<PaintStroke>? _paintBefore;
  PaintStroke? _painted;

  /// _ring is the brush shown on the body under the pointer: where, and
  /// how big on screen.
  ({Offset at, double radius})? _ring;
  DateTime _ringAt = DateTime(0);

  bool get _sculpting =>
      widget.brush != null && !HardwareKeyboard.instance.isAltPressed;

  /// _tall is the body's height at rest, which the brush is sized by.
  double get _tall => _character.avatar?.rig.face?.headTop.y ?? 1.5;

  /// _hitAt is where on the body point [p] of the stage is, if on it.
  CharacterHit? _hitAt(Offset p) {
    final ray = _rayAt(p);
    return ray == null ? null : _character.pick(ray.$1, ray.$2);
  }

  /// _view is the camera's frame: which way it looks, the screen's left and
  /// up, how wide it sees, and the stage's size. forward × up is the screen's
  /// left in flutter_scene's view (a stroke aimed at one arm would otherwise
  /// land on the other).
  ({vm.Vector3 f, vm.Vector3 left, vm.Vector3 up, double t, Size size})?
      _view() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) return null;
    final f = (_camera.target - _camera.position).normalized();
    final left = f.cross(vm.Vector3(0, 1, 0)).normalized();
    return (
      f: f,
      left: left,
      up: left.cross(f).normalized(),
      t: math.tan(_camera.fovRadiansY / 2),
      size: box.size,
    );
  }

  /// _rayAt is the ray from the camera through [p] on the stage.
  (vm.Vector3, vm.Vector3)? _rayAt(Offset p) {
    final v = _view();
    if (v == null) return null;
    final x =
            (2 * p.dx / v.size.width - 1) * v.t * v.size.width / v.size.height,
        y = (1 - 2 * p.dy / v.size.height) * v.t;
    return (_camera.position, v.f - v.left * x + v.up * y);
  }

  /// _onStage is where [p], a point in the scene, is on the stage: the
  /// other way from [_rayAt].
  Offset? _onStage(vm.Vector3 p) {
    final v = _view();
    if (v == null) return null;
    final d = p - _camera.position, z = d.dot(v.f);
    if (z <= 1e-4) return null;
    final x = -d.dot(v.left) / (z * v.t * v.size.width / v.size.height),
        y = d.dot(v.up) / (z * v.t);
    return Offset((x + 1) / 2 * v.size.width, (1 - y) / 2 * v.size.height);
  }

  // ---------------------------------------------------------------------
  // The Move step's dots, dragged to move the hands, feet and hips, and to
  // turn the head.

  /// _dots are where they are on the stage, each frame.
  final ValueNotifier<Map<String, Offset>> _dots = ValueNotifier(const {});
  String? _dragging;
  vm.Vector3? _dragFrom;
  CharacterMove? _moveAtStart;

  void _placeDots() {
    if (widget.onMove == null) {
      if (_dots.value.isNotEmpty) _dots.value = const {};
      return;
    }
    _dots.value = {
      for (final e in _character.dotsAt().entries)
        if (_onStage(e.value) case final o?) e.key: o,
    };
  }

  void _dotFrom(String k, Offset global) {
    final at = _character.dotsAt()[k];
    if (at == null) return;
    _dragging = k;
    _dragFrom = at;
    _moveAtStart = widget.move;
  }

  /// _dotTo carries the dot being dragged to [global] on the screen, on a
  /// plane facing the camera through where it started. The hands, feet and
  /// hips move by as much, in the body's own space, and the pose keeps them
  /// where a body can be; the head turns toward it instead.
  void _dotTo(Offset global) {
    final k = _dragging, from = _dragFrom, m0 = _moveAtStart;
    final onMove = widget.onMove;
    final box = context.findRenderObject() as RenderBox?;
    if (k == null ||
        from == null ||
        m0 == null ||
        onMove == null ||
        box == null) {
      return;
    }
    final ray = _rayAt(box.globalToLocal(global));
    final v = _view();
    if (ray == null || v == null) return;
    final denom = ray.$2.dot(v.f);
    if (denom.abs() < 1e-6) return;
    final hit = ray.$1 + ray.$2 * ((from - ray.$1).dot(v.f) / denom);
    final a = _character.toBody(from), b = _character.toBody(hit);
    if (a == null || b == null) return;
    final d = b - a;
    if (k == "head") {
      // Toward its left (+x) turns it left; down nods it.
      onMove(m0
          .withBody(
              "headTurn", (m0.bodyOf("headTurn") + d.x / 0.15).clamp(-1.0, 1.0))
          .withBody(
              "headNod", (m0.bodyOf("headNod") - d.y / 0.15).clamp(-1.0, 1.0)));
      return;
    }
    final o = m0.offsetOf(k);
    onMove(m0.withOffset(k, [o[0] + d.x, o[1] + d.y, o[2] + d.z]));
  }

  /// _showRing puts the brush ring where [p] is on the body, or takes it
  /// away when it is off it.
  void _showRing(Offset p, {bool now = false}) {
    final brush = widget.brush;
    if (brush == null) {
      if (_ring != null) setState(() => _ring = null);
      return;
    }
    // Looked for at most every 30 milliseconds as the pointer moves.
    final at = DateTime.now();
    if (!now && at.difference(_ringAt).inMilliseconds < 30) return;
    _ringAt = at;
    final hit = _hitAt(p);
    final box = context.findRenderObject() as RenderBox?;
    setState(() => _ring = hit == null || box == null
        ? null
        : (
            at: p,
            radius: brush.size *
                _tall /
                (hit.distance * math.tan(_camera.fovRadiansY / 2)) *
                box.size.height /
                2,
          ));
  }

  /// _strokeFrom starts a stroke where [p] is on the body; false if it is
  /// off it, when the drag turns the character instead. A paint stroke
  /// starts only on the skin or the clothes.
  bool _strokeFrom(Offset p) {
    final brush = widget.brush;
    final hit = brush == null ? null : _hitAt(p);
    if (brush == null || hit == null) return false;
    if (brush.mode == TouchMode.paint) {
      final on = hit.surface;
      if (on == null) return false;
      _paintBefore = widget.paint;
      _painted = PaintStroke(
          on: on,
          tool: brush.paintTool,
          colour: brush.colour,
          radius: brush.size * _tall,
          opacity: brush.opacity,
          softness: brush.softness,
          mirror: brush.mirror,
          points: [_pointOf(hit, made: true)]);
      widget.onPaint([..._paintBefore!, _painted!]);
    } else {
      _before = widget.sculpt;
      _stroke = SculptStroke(
          tool: brush.tool,
          radius: brush.size * _tall,
          strength: brush.strength,
          mirror: brush.mirror,
          points: [_pointOf(hit)]);
      widget.onSculpt([..._before!, _stroke!]);
    }
    _showRing(p, now: true);
    return true;
  }

  bool get _stroking => _stroke != null || _painted != null;

  /// _strokeTo carries the stroke on to [p], a point at a time a little
  /// apart.
  void _strokeTo(Offset p) {
    _showRing(p);
    final hit = _hitAt(p);
    if (hit == null) return;
    bool far(SculptPoint last, vm.Vector3 at, double radius) =>
        (at - vm.Vector3(last.x, last.y, last.z)).length >= radius * 0.3;
    final stroke = _stroke, before = _before;
    if (stroke != null && before != null) {
      if (!far(stroke.points.last, hit.at, stroke.radius)) return;
      _stroke = stroke.withPoint(_pointOf(hit));
      widget.onSculpt([...before, _stroke!]);
    }
    final painted = _painted, paintBefore = _paintBefore;
    if (painted != null && paintBefore != null) {
      if (!far(painted.points.last, hit.made, painted.radius * 0.6)) return;
      _painted = painted.withPoint(_pointOf(hit, made: true));
      widget.onPaint([...paintBefore, _painted!]);
    }
  }

  void _strokeEnd() {
    _stroke = null;
    _before = null;
    _painted = null;
    _paintBefore = null;
  }

  /// _pointOf is [hit] as a stroke's point: where on the body as shaped,
  /// or as [made].
  static SculptPoint _pointOf(CharacterHit hit, {bool made = false}) {
    final at = made ? hit.made : hit.at;
    return SculptPoint(
        at.x, at.y, at.z, hit.normal.x, hit.normal.y, hit.normal.z);
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

  void _show() => (_character..playing = widget.playing).show(
      body: widget.id,
      shape: widget.shape,
      outfit: widget.outfit,
      look: widget.look,
      decals: widget.decals,
      sculpt: widget.sculpt,
      paint: widget.paint,
      face: widget.face,
      move: widget.move);

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
    if (widget.line case final l? when l != old.line) _character.say(l.text);
  }

  /// _ticks counts the stage's frames, for its shadow to be drawn again on
  /// each.
  final ValueNotifier<int> _ticks = ValueNotifier(0);

  @override
  void dispose() {
    _ticks.dispose();
    _dots.dispose();
    _character.removeListener(_changed);
    _character.dispose();
    super.dispose();
  }

  /// _framing is where the camera looks and from how far, for the open
  /// part.
  (vm.Vector3, double, double) _framing(ShapedAvatar? a) {
    vm.Vector3? at(VrmHumanBone b) =>
        _character.restAt(b) ?? a?.avatar.humanoid.worldPosition(b);
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
    // A scene being tried plays on to where the clock is.
    final clock = widget.clock;
    if (clock != null && widget.clockRuns) {
      final t = clock.value + dt;
      if (t >= widget.clockEnd) {
        clock.value = widget.clockEnd;
        widget.onClockEnd?.call();
      } else {
        clock.value = t;
      }
    }
    _character
      ..performance = clock == null ? null : widget.performance
      ..sceneTime = clock?.value;
    // Carried across by its walks and turned the way it goes: the view
    // moved and turned the other way, as the canvas does it.
    final go = _character.travel;
    final yaw = _yaw - go.turn * math.pi / 2;
    var at = f + _pan;
    var eye = at +
        vm.Vector3(math.sin(yaw) * math.cos(_pitch), math.sin(_pitch),
                -math.cos(yaw) * math.cos(_pitch)) *
            _distance;
    if (go.x != 0) {
      final right = vm.Vector3(0, 1, 0)
          .cross((at - eye).normalized())
          .normalized()
        ..scale(go.x);
      at -= right;
      eye -= right;
    }
    _camera
      ..position = eye
      ..target = at;
    _character.tick(dt, _camera,
        lookAt: eye, pixelRatio: MediaQuery.devicePixelRatioOf(context));
    _ticks.value++;
    _placeDots();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Stack(children: [
      Positioned.fill(
        child: Listener(
          // A drag with shift held moves the view rather than turning it; so does
          // one with the right or middle button, which the gesture below never
          // sees.
          onPointerDown: (e) =>
              _panning = HardwareKeyboard.instance.isShiftPressed,
          onPointerMove: (e) {
            if (e.buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0) {
              _panBy(e.delta);
            }
          },
          onPointerHover: (e) => _showRing(e.localPosition),
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              _zoom =
                  (_zoom * math.exp(e.scrollDelta.dy * 0.002)).clamp(0.25, 3.0);
            }
          },
          child: GestureDetector(
            key: const ValueKey("studioStageGestures"),
            onDoubleTap: _resetView,
            onScaleStart: (d) {
              _zoomAtStart = _zoom;
              if (d.pointerCount == 1 && !_panning && _sculpting) {
                _strokeFrom(d.localFocalPoint);
              }
            },
            onScaleEnd: (_) => _strokeEnd(),
            onScaleUpdate: (d) {
              if (_stroking && d.pointerCount == 1) {
                _strokeTo(d.localFocalPoint);
                return;
              }
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
              // Drawn once there is a body: an empty scene is a blank frame
              // flutter_scene warns of.
              child: _character.avatar == null
                  ? const SizedBox.expand()
                  // Its shadow on the ground under it, drawn before it.
                  : CustomPaint(
                      painter: _GroundShadow(_character, _camera, _ticks),
                      child: SceneView(_character.scene,
                          camera: _camera, onTick: _tick)),
            ),
          ),
        ),
      ),
      if (widget.onMove != null)
        Positioned.fill(
          child: ValueListenableBuilder<Map<String, Offset>>(
            valueListenable: _dots,
            builder: (context, dots, _) => Stack(children: [
              for (final MapEntry(key: k, value: at) in dots.entries)
                Positioned(
                  left: at.dx - 9,
                  top: at.dy - 9,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: GestureDetector(
                      key: ValueKey("moveDot-$k"),
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => _dotFrom(k, d.globalPosition),
                      onPanUpdate: (d) => _dotTo(d.globalPosition),
                      onPanEnd: (_) => _dragging = null,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: k == "hips"
                              ? colors.primary
                              : k == "head"
                                  // Not tertiary, which is a panel fill.
                                  ? const Color(0xff3aa66b)
                                  : colors.secondary,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(blurRadius: 4, color: Color(0x59000000))
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      if (_ring case final r? when widget.brush != null)
        Positioned(
          left: r.at.dx - r.radius,
          top: r.at.dy - r.radius,
          width: r.radius * 2,
          height: r.radius * 2,
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey("studioBrushRing"),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: colors.primary.withValues(alpha: 0.9), width: 1.5),
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
                widget.brush != null
                    ? "Drag over the body to shape it; Option-drag to turn it; shift-drag to move it; scroll to zoom"
                    : "Drag to turn and tilt it; shift-drag to move it; scroll to zoom; double-click to reset",
                style: TextStyle(fontSize: 12, color: colors.onSurface)),
          ),
        ),
      ),
    ]);
  }
}

/// _GroundShadow is the character's shadow on the ground under it on the
/// Studio's stage, as the stage's camera sees it.
class _GroundShadow extends CustomPainter {
  final CharacterScene character;
  final PerspectiveCamera camera;
  _GroundShadow(this.character, this.camera, Listenable ticks)
      : super(repaint: ticks);

  @override
  void paint(Canvas canvas, Size size) =>
      character.shadowOn(canvas, Offset.zero & size, camera);

  @override
  bool shouldRepaint(_GroundShadow old) => old.character != character;
}

/// _TestNotes is the Test step's side: what it is for, and whether what is
/// tried is kept.
class _TestNotes extends StatelessWidget {
  /// kept is whether the Studio was opened for a character on the canvas,
  /// whose scene Done keeps this in.
  final bool kept;
  const _TestNotes({required this.kept});

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        StudioPanelHead(
          key: const ValueKey("studioTestNotes"),
          title: "Try it in a scene",
          says: kept
              ? "The settings it has in its scene on the canvas: how it "
                  "stands, the motions it plays and when, its face and "
                  "what it says. Play to see them; Done keeps them there."
              : "The settings a character has in a scene on the canvas: "
                  "how it stands, the motions it plays and when, its face "
                  "and what it says. Play to see them. Nothing here is "
                  "kept -- each character's scene is set on the canvas.",
        ),
      ]);
}

/// _TestTimeline is the Test step's timeline: the motions as bars, the
/// keys as marks, and the playhead, dragged or clicked to move it.
class _TestTimeline extends StatelessWidget {
  final ValueNotifier<double> at;
  final double length;
  final CharacterPerformance performance;
  final ValueChanged<double> onSeek;
  const _TestTimeline(
      {required this.at,
      required this.length,
      required this.performance,
      required this.onSeek});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Container(
      key: const ValueKey("studioTestTimeline"),
      height: 64,
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        ValueListenableBuilder<double>(
          valueListenable: at,
          builder: (context, t, _) => SizedBox(
            width: 84,
            child: Text(
                "${t.toStringAsFixed(1)} / ${length.toStringAsFixed(0)} s",
                key: const ValueKey("studioTestTime"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: colors.onSurface)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            void seek(double x) =>
                onSeek((x / box.maxWidth).clamp(0.0, 1.0) * length);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => seek(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
              child: ValueListenableBuilder<double>(
                valueListenable: at,
                builder: (context, t, _) => CustomPaint(
                  size: Size(box.maxWidth, box.maxHeight),
                  painter: _TimelinePainter(
                    performance: performance,
                    length: length,
                    at: t,
                    clip: colors.primary,
                    onClip: colors.onPrimary,
                    key: colors.secondary,
                    ink: colors.onSurfaceVariant,
                    line: colors.outlineVariant,
                  ),
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final CharacterPerformance performance;
  final double length, at;
  final Color clip, onClip, key, ink, line;
  _TimelinePainter(
      {required this.performance,
      required this.length,
      required this.at,
      required this.clip,
      required this.onClip,
      required this.key,
      required this.ink,
      required this.line});

  @override
  void paint(Canvas canvas, Size size) {
    double x(double t) => t / length * size.width;
    // A tick a second, and the track the motions lie on.
    final tick = Paint()..color = line;
    for (var s = 0; s <= length; s++) {
      canvas.drawLine(Offset(x(s.toDouble()), size.height - 6),
          Offset(x(s.toDouble()), size.height), tick);
    }
    const top = 18.0, high = 18.0;
    for (final c in performance.clips) {
      final r = RRect.fromRectAndRadius(
          Rect.fromLTRB(
              x(c.start), top, math.max(x(c.end), x(c.start) + 3), top + high),
          const Radius.circular(4));
      canvas.drawRRect(r, Paint()..color = clip.withValues(alpha: 0.85));
      final tp = TextPainter(
        text: TextSpan(
            text: switch (c.dir) {
              -1 => "\u2190 ${c.kind}",
              1 => "${c.kind} \u2192",
              _ => c.kind,
            },
            style: TextStyle(fontSize: 10, color: onClip)),
        maxLines: 1,
        ellipsis: "",
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(0, r.width - 8));
      tp.paint(canvas, Offset(r.left + 4, top + (high - tp.height) / 2));
    }
    // The keys: a diamond at each, over the motions.
    for (final k in performance.keys) {
      final c = Offset(x(k.t), 8);
      canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - 6)
            ..lineTo(c.dx + 6, c.dy)
            ..lineTo(c.dx, c.dy + 6)
            ..lineTo(c.dx - 6, c.dy)
            ..close(),
          Paint()..color = key);
    }
    canvas.drawLine(
        Offset(x(at), 0),
        Offset(x(at), size.height),
        Paint()
          ..color = ink
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.at != at ||
      old.length != length ||
      old.performance != performance ||
      old.clip != clip ||
      old.key != key;
}
