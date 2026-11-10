import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart'
    show paintTransition;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/scene_transition_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/camera_section.dart'
    show CameraMove;
import 'package:bruig/plugin_system/canvas/ui/sidebar/transition_sound.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';

// scene_cards.dart is a scene's motion in the Chain, as the chain prototype
// has it (Ken, 2026-11-08: "the scene design hasn't been brought over"):
// its Transition -- how it gives way to the next, played on its screen --
// and its Camera, the slow move over it, each a studio device card like
// every other in the chain.

const sceneAccent = Color(0xFF5AB4C8);

/// SceneTransitionCard is how scene [scene] gives way to the next -- on the
/// master, the default every scene starts from: its kind, how long, how it
/// looks, its sound and where it comes from, with its screen playing it.
class SceneTransitionCard extends StatefulWidget {
  final CanvasController controller;
  final int scene;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const SceneTransitionCard(
      {required this.controller,
      required this.scene,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  State<SceneTransitionCard> createState() => _SceneTransitionCardState();
}

class _SceneTransitionCardState extends State<SceneTransitionCard>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);

  /// _through is how far through it the screen is, played while hovered.
  double? _through;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration d) {
    var t = _target.value;
    var rate = math.max(1, widget.controller.document.frameRate);
    var length = math.max(0.2, t.frames / rate);
    // Played, then a breath on the next scene, round again.
    var round = length + 0.8;
    var s = d.inMicroseconds / 1e6 % round;
    setState(() => _through = math.min(1.0, s / length));
  }

  SceneTransitionTarget get _target =>
      SceneTransitionTarget(widget.controller, widget.scene);

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    var c = widget.controller;
    var target = _target;
    var value = target.value;
    var kind = value.kind;
    var rate = math.max(1, c.document.frameRate);
    var scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    var doc = c.document;
    var scenes = doc.allScenes;
    String nameOf(int i) => i < 0 || i >= scenes.length
        ? ""
        : scenes[i].name.isEmpty
            ? "${doc.kind.one} ${i + 1}"
            : scenes[i].name;
    var from = target.master ? "A ${doc.kind.one}" : nameOf(widget.scene);
    var to = target.master
        ? "The next"
        : target.last
            ? "The end"
            : nameOf(widget.scene + 1);
    void write(SceneTransition next, {bool transient = false}) {
      c.beginInteraction();
      target.write(next, transient: true);
      if (!transient) c.endInteraction();
    }

    Widget knob(
            String key,
            String label,
            String text,
            double value,
            double min,
            double max,
            double initial,
            void Function(double v, {bool transient}) onChanged) =>
        DeviceKnob(
          key: ValueKey(key),
          label: label,
          text: text,
          value: value.clamp(min, max),
          initial: initial,
          min: min,
          max: max,
          accent: sceneAccent,
          ink: skin.ink,
          onChanged: onChanged,
          onCommit: c.endInteraction,
        );

    List<Widget> controls(DeviceTier tier) => [
          DevicePack(key: const ValueKey("sceneTransitionPack"), children: [
            if (value.on) ...[
              knob(
                  "transitionLength",
                  "Length",
                  "${(value.frames / rate).toStringAsFixed(2)}s",
                  value.frames / rate,
                  1 / rate,
                  5,
                  0.5,
                  (v, {transient = false}) => write(
                      value.copyWith(frames: math.max(1, (v * rate).round())),
                      transient: transient)),
              knob(
                  "transitionOverlap",
                  "Overlap",
                  "${(value.overlap / rate).toStringAsFixed(2)}s",
                  value.overlap / rate,
                  0,
                  5,
                  0.5,
                  (v, {transient = false}) => write(
                      value.copyWith(overlap: math.max(0, (v * rate).round())),
                      transient: transient)),
            ],
            StudioDrop<SceneTransitionFamily>(
              key: const ValueKey("transitionFamily"),
              label: "Kind",
              value: kind.familyOf,
              options: [
                for (var f in SceneTransitionFamily.values)
                  (f, f == SceneTransitionFamily.none ? "Cut" : f.label)
              ],
              onChanged: (f) => write(startedAs(
                  value,
                  f == SceneTransitionFamily.none
                      ? SceneTransitionKind.cut
                      : SceneTransitionKind.inFamily(f).first)),
            ),
            if (value.on)
              StudioDrop<SceneTransitionKind>(
                key: const ValueKey("transitionKind"),
                label: "Which",
                value: kind,
                options: [
                  for (var k in SceneTransitionKind.inFamily(kind.familyOf))
                    (k, k.label)
                ],
                onChanged: (k) => write(startedAs(value, k)),
              ),
            if (value.on)
              StudioDrop<SceneTransitionEase>(
                key: const ValueKey("transitionEase"),
                label: "Ease",
                value: value.ease,
                options: [
                  for (var e in SceneTransitionEase.values) (e, e.label)
                ],
                onChanged: (e) => write(value.copyWith(ease: e)),
              ),
            if (kind.takesWay)
              StudioDrop<SceneTransitionWay>(
                key: const ValueKey("transitionWay"),
                label: "Which way",
                value: SceneTransitionWay.waysFor(kind).contains(value.way)
                    ? value.way
                    : SceneTransitionWay.waysFor(kind).first,
                options: [
                  for (var w in SceneTransitionWay.waysFor(kind))
                    (w, w.saysFor(kind))
                ],
                onChanged: (w) => write(value.copyWith(way: w)),
              ),
            if (kind.takesShape)
              StudioDrop<ShapeKind>(
                key: const ValueKey("transitionShape"),
                label: "Shape",
                value: value.shape,
                options: [for (var k in ShapeKind.values) (k, k.label)],
                onChanged: (k) => write(value.copyWith(shape: k)),
              ),
            if (kind.takesColour)
              _ColourCell(
                  key: const ValueKey("transitionColour"),
                  label: kind.covers ? "Colour" : "Through",
                  colour: value.color,
                  onChanged: (col) => write(value.copyWith(color: col))),
            if (kind.takesCount)
              knob(
                  "transitionCount",
                  switch (kind) {
                    SceneTransitionKind.blinds => "Bars",
                    SceneTransitionKind.burst => "Rays",
                    SceneTransitionKind.brush => "Strokes",
                    SceneTransitionKind.splatter => "Splats",
                    SceneTransitionKind.tiles => "Across",
                    SceneTransitionKind.halftone => "Dots",
                    SceneTransitionKind.arrow => "Arrows",
                    _ => "How many",
                  },
                  "${value.count}",
                  value.count.toDouble(),
                  1,
                  40,
                  6,
                  (v, {transient = false}) => write(
                      value.copyWith(count: v.round()),
                      transient: transient)),
            if (kind.takesSpacing)
              knob(
                  "transitionSpacing",
                  "Apart",
                  "${(value.spacing * 100).round()}%",
                  value.spacing,
                  0,
                  2,
                  0.15,
                  (v, {transient = false}) =>
                      write(value.copyWith(spacing: v), transient: transient)),
            if (kind.takesRadius)
              knob(
                  "transitionRadius",
                  "Size",
                  "${(value.radius * 100).round()}%",
                  value.radius,
                  0.05,
                  1,
                  0.5,
                  (v, {transient = false}) =>
                      write(value.copyWith(radius: v), transient: transient)),
            if (kind.takesAngle)
              knob(
                  "transitionAngle",
                  "Angle",
                  "${value.angle.round()}°",
                  value.angle,
                  -180,
                  180,
                  0,
                  (v, {transient = false}) =>
                      write(value.copyWith(angle: v), transient: transient)),
            if (kind.takesSoftness)
              knob(
                  "transitionSoftness",
                  "Soft edge",
                  "${(value.softness * 100).round()}%",
                  value.softness,
                  0,
                  1,
                  0,
                  (v, {transient = false}) =>
                      write(value.copyWith(softness: v), transient: transient)),
            if (kind.takesCentre) ...[
              knob(
                  "transitionCentreX",
                  "Centre across",
                  "${(value.centreX * 100).round()}%",
                  value.centreX,
                  0,
                  1,
                  0.5,
                  (v, {transient = false}) =>
                      write(value.copyWith(centreX: v), transient: transient)),
              knob(
                  "transitionCentreY",
                  "Centre down",
                  "${(value.centreY * 100).round()}%",
                  value.centreY,
                  0,
                  1,
                  0.5,
                  (v, {transient = false}) =>
                      write(value.copyWith(centreY: v), transient: transient)),
            ],
            // Its own, or the master's: what every scene starts from.
            if (!target.master)
              StudioDrop<bool>(
                key: const ValueKey("transitionCustom"),
                label: "Comes from",
                value: doc.allScenes[widget.scene].custom,
                options: [
                  (false, "The master ${doc.kind.one}"),
                  (true, "This ${doc.kind.one}"),
                ],
                onChanged: (own) {
                  c.beginInteraction();
                  c.setSceneTransition(widget.scene,
                      own ? doc.transitionAfter(widget.scene) : null);
                  c.endInteraction();
                },
              ),
          ]),
          // Its sound: what plays as it does.
          if (value.on)
            PackWide(CanvasControlScope(
              maxWidth: 400,
              child: CanvasTransitionSound(
                key: const ValueKey("transitionSound"),
                value: value,
                onChanged: (t) => write(t),
                onEvery: (t) => c.soundEveryTransition(t),
                hearing: c.hearingSound(value.sound),
                onHear: () =>
                    c.hearSound(value.sound, volume: value.soundVolume),
              ),
            )),
        ];

    // Still, a third of the way: half way, a kind that covers the join
    // (blinds, shapes) is all its colour, and shows nothing of either.
    var through = _through ?? 0.35;
    return DeviceFrame(
      id: "sceneTransition",
      title: target.master ? "Transition · every scene" : "Transition",
      help: "How this ${doc.kind.one} gives way to the next: the kind, how "
          "long, how it looks and what it sounds like. Its screen plays it "
          "while the pointer is over it; Preview plays it on the canvas. On "
          "the master ${doc.kind.one}, the one every ${doc.kind.one} starts "
          "from.",
      skin: skin,
      folded: widget.folded,
      onFold: widget.onFold,
      width: 420 * scale,
      height: widget.height,
      icon: Icons.movie_filter_outlined,
      accent: sceneAccent,
      // Its screen down its left, the full height, as the prototype's wide
      // card: its settings are many, and would squeeze it to a strip.
      displayBeside: true,
      besideDisplay: 250,
      besideSettings: 340,
      onReset: () => write(SceneTransition.bestFor(kind)),
      summary: value.on
          ? "${kind.label} · ${(value.frames / rate).toStringAsFixed(2)}s"
          : "a cut",
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: controls,
      display: MouseRegion(
        onEnter: (_) {
          if (!_ticker.isActive && value.on) _ticker.start();
        },
        onExit: (_) {
          if (_ticker.isActive) _ticker.stop();
          setState(() => _through = null);
        },
        child: Stack(fit: StackFit.expand, children: [
          CustomPaint(
            key: const ValueKey("sceneTransitionScreen"),
            painter: _TransitionScreen(
                value, value.ease.apply(through), from, to, look.studio),
            child: const SizedBox.expand(),
          ),
          Positioned(
            top: 5,
            right: 5,
            child: CopyButtonLike(
              key: const ValueKey("previewTransition"),
              label: "Preview",
              onTap: target.last
                  ? null
                  : () => c.previewTransitionAfter(widget.scene,
                      exact: !c.transitionsAsDefault),
            ),
          ),
          Positioned(
            left: 7,
            bottom: 4,
            right: 7,
            child: Text(
                value.on
                    ? "${kind.label}${value.soundName.isEmpty ? "" : " · ${value.soundName}"}"
                        "${_through == null ? " · hover to play" : ""}"
                    : "A cut: straight to the next",
                key: const ValueKey("sceneTransitionSays"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xCCFFFFFF))),
          ),
        ]),
      ),
    );
  }
}

/// _TransitionScreen draws [transition] [t] of the way from one scene to
/// the next, each a panel with its name, as the canvas draws it.
class _TransitionScreen extends CustomPainter {
  final SceneTransition transition;
  final double t;
  final String from, to;
  final StudioColors studio;
  _TransitionScreen(this.transition, this.t, this.from, this.to, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    var page = Offset.zero & size;
    void panel(Color colour, String name, Alignment at) {
      canvas.drawRect(page, Paint()..color = colour);
      // A horizon and a sun, so a move or a zoom reads as one.
      canvas.drawRect(
          Rect.fromLTWH(0, size.height * 0.68, size.width, size.height * 0.32),
          Paint()..color = Color.lerp(colour, Colors.black, 0.25)!);
      canvas.drawCircle(Offset(size.width * 0.72, size.height * 0.32),
          size.shortestSide * 0.1, Paint()..color = const Color(0x55FFFFFF));
      var tp = TextPainter(
          text: TextSpan(
              text: name,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          maxLines: 1,
          ellipsis: "…",
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: size.width - 16);
      var x = at.x < 0 ? 8.0 : size.width - tp.width - 8;
      var y = at.y < 0 ? 8.0 : size.height - tp.height - 18;
      tp.paint(canvas, Offset(x, y));
    }

    canvas.save();
    canvas.clipRect(page);
    paintTransition(canvas, page, transition, t,
        from: () => panel(const Color(0xFF2B5E66), from, Alignment.topLeft),
        to: () => panel(const Color(0xFF5B3D99), to, Alignment.bottomRight));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TransitionScreen old) =>
      old.transition != transition ||
      old.t != t ||
      old.from != from ||
      old.to != to;
}

/// SceneCameraCard is scene [scene]'s slow move: still, a push in, a pull
/// out, a drift -- how far, and its screen showing the frame going from
/// where it starts to where it ends.
class SceneCameraCard extends StatelessWidget {
  final CanvasController controller;
  final int scene;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const SceneCameraCard(
      {required this.controller,
      required this.scene,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var skin = DeviceSkin.studio(look.studio);
    var c = controller;
    var doc = c.document;
    var camera = doc.allScenes[scene].camera;
    var move = CameraMove.of(camera);
    var strength = CameraMove.strengthOf(camera);
    var shake = camera?.shake ?? 0;
    var open = doc.at == scene;
    // A move, with the shake it had: still and shaking is a camera too.
    SceneCamera? moved(CameraMove m, double strength, double shake) {
      var next = m.camera(strength);
      if (shake <= 0) return next;
      return (next ?? const SceneCamera(toZoom: 1)).copyWith(shake: shake);
    }

    return DeviceFrame(
      id: "sceneCamera",
      title: "Camera",
      help: "A slow move over the ${doc.kind.one}: still, pushing in, pulling "
          "out or drifting across, as far as Closer by says. Look through it "
          "to see it on the canvas as you step and scrub.",
      skin: skin,
      folded: folded,
      onFold: onFold,
      width: 260 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5),
      height: height,
      icon: Icons.videocam_outlined,
      accent: sceneAccent,
      besideDisplay: 220,
      besideSettings: 200,
      onReset: () {
        c.beginInteraction();
        c.setSceneCamera(scene, null);
        c.endInteraction();
      },
      summary: shake > 0 ? "${move.label}, shaking" : move.label,
      foldedBody: const SizedBox(),
      body: const SizedBox.shrink(),
      controls: (tier) => [
        DevicePack(key: const ValueKey("sceneCameraPack"), children: [
          DeviceKnob(
            key: const ValueKey("cameraStrength"),
            label: "Closer by",
            text: "${(strength * 100).round()}%",
            value: strength,
            initial: 0.12,
            min: 0.02,
            max: 1,
            accent: sceneAccent,
            ink: skin.ink,
            onChanged: (v, {transient = false}) {
              if (move == CameraMove.still) return;
              c.beginInteraction();
              c.setSceneCamera(scene, moved(move, v, shake), transient: true);
              if (!transient) c.endInteraction();
            },
            onCommit: c.endInteraction,
          ),
          StudioDrop<CameraMove>(
            key: const ValueKey("cameraMove"),
            label: "Move",
            value: move,
            options: [for (var m in CameraMove.values) (m, m.label)],
            onChanged: (m) {
              c.beginInteraction();
              c.setSceneCamera(scene, moved(m, strength, shake));
              c.endInteraction();
            },
          ),
          DeviceKnob(
            key: const ValueKey("cameraShake"),
            label: "Shake",
            text: "${(shake * 100).round()}%",
            value: shake,
            initial: 0,
            min: 0,
            max: 1,
            accent: sceneAccent,
            ink: skin.ink,
            onChanged: (v, {transient = false}) {
              c.beginInteraction();
              c.setSceneCamera(
                  scene, moved(move, strength, (v * 100).roundToDouble() / 100),
                  transient: true);
              if (!transient) c.endInteraction();
            },
            onCommit: c.endInteraction,
          ),
          if (camera != null && open)
            StudioDrop<bool>(
              key: const ValueKey("cameraView"),
              label: "On the canvas",
              value: c.cameraView,
              options: const [(false, "The page"), (true, "Through it")],
              onChanged: (v) => c.cameraView = v,
            ),
        ]),
      ],
      display: CustomPaint(
        key: const ValueKey("sceneCameraScreen"),
        painter: _CameraScreen(camera, look.studio),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// _CameraScreen is the page, and the camera's frame where it starts
/// (faint) and where it ends.
class _CameraScreen extends CustomPainter {
  final SceneCamera? camera;
  final StudioColors studio;
  _CameraScreen(this.camera, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.display);
    var page = Rect.fromLTWH(12, 10, size.width - 24, size.height - 20);
    canvas.drawRect(
        page,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = studio.edge);
    var cam = camera;
    Rect frame(double t) {
      if (cam == null) return page;
      var (zoom, centre) = cam.at(t, page);
      return Rect.fromCenter(
          center: centre, width: page.width / zoom, height: page.height / zoom);
    }

    canvas.drawRect(
        frame(0),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = sceneAccent.withValues(alpha: 0.4));
    canvas.drawRect(
        frame(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = sceneAccent);
  }

  @override
  bool shouldRepaint(_CameraScreen old) => old.camera != camera;
}

/// _ColourCell is a colour picked from a few, labelled as a dropdown is.
class _ColourCell extends StatelessWidget {
  final String label;
  final Color colour;
  final ValueChanged<Color> onChanged;
  const _ColourCell(
      {required this.label,
      required this.colour,
      required this.onChanged,
      super.key});

  static const _choices = [
    Color(0xFF000000),
    Color(0xFFFFFFFF),
    Color(0xFFE2B04A),
    Color(0xFFE5534B),
    Color(0xFF3D7EFF),
    Color(0xFF3FB08D),
    Color(0xFF9A92EA),
  ];

  @override
  Widget build(BuildContext context) {
    var s = MixerLook.of(context).studio;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(label,
                maxLines: 1, style: TextStyle(fontSize: 10, color: s.muted)),
          ),
          Wrap(spacing: 3, runSpacing: 3, children: [
            for (var (i, c) in _choices.indexed)
              InkWell(
                key: ValueKey("transitionColour-$i"),
                onTap: () => onChanged(c),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color:
                            c.toARGB32() == colour.toARGB32() ? s.text : s.edge,
                        width: c.toARGB32() == colour.toARGB32() ? 2 : 1),
                  ),
                ),
              ),
          ]),
        ]);
  }
}

/// CopyButtonLike is a small chip on a card's screen.
class CopyButtonLike extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const CopyButtonLike({required this.label, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    var s = MixerLook.of(context).studio;
    return Material(
      color: s.raised.withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: s.edge)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(label,
              style: TextStyle(
                  fontSize: 10, color: onTap == null ? s.muted : s.text)),
        ),
      ),
    );
  }
}

/// sceneCameraOf is the Camera element framing scene [index] -- its first
/// shown one, as cameraOf has it -- or null with none.
CameraElement? sceneCameraOf(CanvasController c, int index) {
  var doc = c.document;
  if (index < 0 || index >= doc.allScenes.length) return null;
  var elements = doc.at == index ? doc.elements : doc.allScenes[index].elements;
  return elements
      .whereType<CameraElement>()
      .where((e) => e.visible)
      .firstOrNull;
}

/// _SceneRow is a card's label and what it is: the Output's rows.
Widget _sceneRow(MixerLook look, String label, String value, {Key? key}) =>
    Row(key: key, children: [
      Expanded(
          child: Text(label,
              style: TextStyle(fontSize: 10.5, color: look.studio.muted))),
      Flexible(
        child: Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 10.5, color: look.studio.text)),
      ),
    ]);

/// SceneAddCamera is a scene's Source with nothing in it yet: the chain
/// prototype's "+" -- a Camera put on the scene, whose clips key its zoom
/// and where it looks over the scene, are then the Source. A scene not
/// open is opened first: its elements are edited where they are.
class SceneAddCamera extends StatelessWidget {
  final CanvasController controller;
  final int scene;
  final double height;
  const SceneAddCamera(
      {required this.controller,
      required this.scene,
      required this.height,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var c = controller;
    var open = c.document.at == scene && !c.document.editingMaster;
    var name = c.document.allScenes[scene].name;
    return DeviceFrame(
      id: "sceneAddCamera",
      title: "Keyed camera",
      help: "Its own clips: put a Camera on the ${c.document.kind.one} and "
          "key how close it is and where it looks, over time. Its clips are "
          "then this chain's Source, and frame the ${c.document.kind.one} in "
          "place of the Camera card's slow move.",
      skin: DeviceSkin.studio(look.studio),
      folded: false,
      onFold: () {},
      width: 200,
      height: height,
      icon: Icons.add,
      accent: sceneAccent,
      summary: "none yet",
      foldedBody: const SizedBox(),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  open
                      ? "Key its zoom and where it looks: a Camera, its clips "
                          "the Source."
                      : "Open $name to give it a camera of its own.",
                  style: TextStyle(fontSize: 10.5, color: look.studio.muted)),
              const SizedBox(height: 8),
              CopyButtonLike(
                  key: const ValueKey("sceneAddCamera"),
                  label: open ? "+ Camera" : "Open $name",
                  onTap: () {
                    if (!open) {
                      c.goToScene(scene);
                      c.pickScene(scene);
                      return;
                    }
                    c.addElement(newElement(ElementKind.camera, c.document));
                    // Back on the scene's chain, its Source the new camera.
                    c.pickScene(scene);
                  }),
            ]),
      ),
    );
  }
}

/// SceneCameraNote stands in for the Camera card while a Camera element
/// frames the scene: its clips do, and the slow move is not used.
class SceneCameraNote extends StatelessWidget {
  final CameraElement camera;
  final double height;
  const SceneCameraNote(
      {required this.camera, required this.height, super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var name = camera.name.isEmpty ? "Camera" : camera.name;
    return DeviceFrame(
      id: "sceneCamera",
      title: "Camera",
      help: "",
      skin: DeviceSkin.studio(look.studio),
      folded: false,
      onFold: () {},
      width: 180,
      height: height,
      icon: Icons.videocam_outlined,
      accent: sceneAccent,
      summary: "by $name",
      foldedBody: const SizedBox(),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
            "Framed by $name: its clips move it. The slow move is kept for "
            "when it is gone or hidden.",
            style: TextStyle(fontSize: 10.5, color: look.studio.muted)),
      ),
    );
  }
}

/// SceneOutputCard is where a scene's chain ends, as an element's Output
/// is: which scenes it is shown in, how long it is, and what comes after.
class SceneOutputCard extends StatelessWidget {
  final CanvasController controller;
  final int scene;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  const SceneOutputCard(
      {required this.controller,
      required this.scene,
      required this.folded,
      required this.onFold,
      required this.height,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var doc = controller.document;
    var master = doc.editingMaster;
    var scenes = doc.allScenes;
    var me = scenes[scene];
    var seconds = me.frames / (doc.frameRate <= 0 ? 1 : doc.frameRate);
    var over = doc.transitionAfter(scene);
    var next = scene + 1 < scenes.length ? scenes[scene + 1] : null;
    String then() {
      if (me.holds) return "holds at its end";
      if (next == null) return "the end";
      var into = next.name.isEmpty ? "the next" : next.name;
      return over.on ? "$into, by ${over.kind.label.toLowerCase()}" : into;
    }

    var shown = master ? "every ${doc.kind.one}" : "${me.name} only";
    return DeviceFrame(
      id: "sceneOutput",
      title: "Output",
      help: "Where the ${doc.kind.one}'s chain ends: where it is shown, how "
          "long it is and what comes after it.",
      skin: DeviceSkin.studio(look.studio),
      folded: folded,
      onFold: onFold,
      width: 200,
      height: height,
      icon: Icons.output,
      accent: const Color(0xFFCFCBDF),
      summary: shown,
      foldedBody: const SizedBox(),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _sceneRow(look, "Shown", shown,
              key: const ValueKey("sceneOutputShown")),
          const SizedBox(height: 6),
          if (!master) ...[
            _sceneRow(look, "Length",
                me.frames <= 1 ? "a still" : "${seconds.toStringAsFixed(1)} s",
                key: const ValueKey("sceneOutputLength")),
            const SizedBox(height: 6),
            _sceneRow(look, "Then", then(),
                key: const ValueKey("sceneOutputThen")),
          ],
        ]),
      ),
    );
  }
}
